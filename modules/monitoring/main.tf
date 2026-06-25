locals {
  topic_name         = "${var.project}-alerts"
  backend_image_name = "${var.parameter_path_prefix}/BACKEND_IMAGE"
}

# --- Alerts topic + email subscription -------------------------------------

resource "aws_sns_topic" "alerts" {
  name = local.topic_name
}

resource "aws_sns_topic_subscription" "email" {
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

# Allow CloudWatch alarms and EventBridge to publish to the topic.
data "aws_iam_policy_document" "topic" {
  statement {
    sid       = "AllowServicesPublish"
    actions   = ["sns:Publish"]
    resources = [aws_sns_topic.alerts.arn]
    principals {
      type        = "Service"
      identifiers = ["cloudwatch.amazonaws.com", "events.amazonaws.com"]
    }
  }
}

resource "aws_sns_topic_policy" "alerts" {
  arn    = aws_sns_topic.alerts.arn
  policy = data.aws_iam_policy_document.topic.json
}

# --- Layer 1b: real-time deploy/SSM failure -> email -----------------------
# Any SSM Run Command (the deploy mechanism) that fails or times out fires this.

resource "aws_cloudwatch_event_rule" "ssm_command_failed" {
  name        = "${var.project}-ssm-command-failed"
  description = "SSM Run Command failed/timed-out (deploy rollout visibility)"
  event_pattern = jsonencode({
    source = ["aws.ssm"]
    detail-type = [
      "EC2 Command Status-change Notification",
      "EC2 Command Invocation Status-change Notification",
    ]
    detail = {
      status = ["Failed", "TimedOut"]
    }
  })
}

resource "aws_cloudwatch_event_target" "ssm_failed_to_sns" {
  rule      = aws_cloudwatch_event_rule.ssm_command_failed.name
  target_id = "sns"
  arn       = aws_sns_topic.alerts.arn

  input_transformer {
    input_paths = {
      cmd    = "$.detail.command-id"
      doc    = "$.detail.document-name"
      status = "$.detail.status"
      time   = "$.time"
    }
    input_template = "\"Enviable SSM command <cmd> (<doc>) changed to <status> at <time>. A deploy likely failed to roll out. Check GitHub Actions and SSM Run Command history.\""
  }
}

# --- Layer 4: root disk >=80% -> email -------------------------------------
# Fed by the CloudWatch agent (installed live via SSM) which publishes
# disk_used_percent aggregated to InstanceId. Config lives in an
# AmazonCloudWatch-* SSM param so CloudWatchAgentServerPolicy can read it.

resource "aws_ssm_parameter" "cwagent_config" {
  name = "AmazonCloudWatch-${var.project}-prod"
  type = "String"
  value = jsonencode({
    agent = {
      metrics_collection_interval = 60
      run_as_user                 = "root"
    }
    metrics = {
      namespace              = "CWAgent"
      append_dimensions      = { InstanceId = "$${aws:InstanceId}" }
      aggregation_dimensions = [["InstanceId"]]
      metrics_collected = {
        disk = {
          measurement                 = ["used_percent"]
          resources                   = ["/"]
          metrics_collection_interval = 60
          ignore_file_system_types    = ["sysfs", "devtmpfs", "tmpfs"]
        }
      }
    }
  })
}

resource "aws_cloudwatch_metric_alarm" "disk_high" {
  alarm_name          = "${var.project}-root-disk-high"
  namespace           = "CWAgent"
  metric_name         = "disk_used_percent"
  dimensions          = { InstanceId = var.instance_id }
  statistic           = "Maximum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 80
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"
  alarm_description   = "Root volume >=80% used on ${var.project} backend box. Prune/clean before a deploy fails with ENOSPC."
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]
}

# --- Layer 1c: daily image-drift sanity check -> email ---------------------
# Runs on the box daily; publishes to SNS only when the running backend image
# tag differs from the recorded BACKEND_IMAGE (the "deployed but not really"
# state). Uses the instance role's scoped sns:Publish (granted in modules/iam).

resource "aws_ssm_document" "image_drift_check" {
  name            = "${var.project}-image-drift-check"
  document_type   = "Command"
  document_format = "JSON"
  content = jsonencode({
    schemaVersion = "2.2"
    description   = "Alert if the running backend image tag differs from the recorded BACKEND_IMAGE"
    mainSteps = [{
      action = "aws:runShellScript"
      name   = "checkDrift"
      inputs = {
        runCommand = [
          "set -u",
          "REGION='${var.region}'",
          "PARAM='${local.backend_image_name}'",
          "CONTAINER='${var.backend_container_name}'",
          "TOPIC='${aws_sns_topic.alerts.arn}'",
          "INSTANCE='${var.instance_id}'",
          "EXPECTED=$(aws ssm get-parameter --region \"$REGION\" --name \"$PARAM\" --query Parameter.Value --output text 2>/dev/null)",
          "RUNNING=$(docker inspect \"$CONTAINER\" --format '{{.Config.Image}}' 2>/dev/null)",
          "exp_tag=$${EXPECTED##*:}; run_tag=$${RUNNING##*:}",
          "if [ -z \"$RUNNING\" ]; then aws sns publish --region \"$REGION\" --topic-arn \"$TOPIC\" --subject 'Enviable drift: backend not running' --message \"Instance $INSTANCE: no running $CONTAINER. Expected image $EXPECTED.\"; exit 0; fi",
          "if [ \"$exp_tag\" != \"$run_tag\" ]; then aws sns publish --region \"$REGION\" --topic-arn \"$TOPIC\" --subject 'Enviable deploy drift detected' --message \"Instance $INSTANCE: running backend tag ($run_tag) != recorded tag ($exp_tag). A deploy likely failed to roll out. Expected=$EXPECTED Running=$RUNNING.\"; else echo 'no drift'; fi",
        ]
      }
    }]
  })
}

resource "aws_ssm_association" "image_drift_check" {
  association_name    = "${var.project}-image-drift-check"
  name                = aws_ssm_document.image_drift_check.name
  schedule_expression = "rate(1 day)"

  targets {
    key    = "InstanceIds"
    values = [var.instance_id]
  }
}
