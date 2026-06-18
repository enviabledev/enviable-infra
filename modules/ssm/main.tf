locals {
  prefix = "/${var.project}/prod"

  # Non-secret app config written as plain String params.
  plain_params = merge(
    {
      REDIS_URL                 = var.redis_url
      SESSION_STORE             = "redis"
      NODE_ENV                  = "production"
      PORT                      = "3000"
      PUPPETEER_EXECUTABLE_PATH = "/usr/bin/chromium"
      AWS_REGION                = var.region
      S3_BUCKET                 = var.s3_bucket
    },
    var.invoice_config,
  )
}

resource "random_password" "session_secret" {
  length  = 64
  special = false
}

resource "aws_ssm_parameter" "session_secret" {
  name  = "${local.prefix}/SESSION_SECRET"
  type  = "SecureString"
  value = random_password.session_secret.result
}

resource "aws_ssm_parameter" "default_initial_password" {
  name  = "${local.prefix}/DEFAULT_INITIAL_PASSWORD"
  type  = "SecureString"
  value = var.default_initial_password
}

resource "aws_ssm_parameter" "database_url" {
  name  = "${local.prefix}/DATABASE_URL"
  type  = "SecureString"
  value = var.database_url
}

resource "aws_ssm_parameter" "plain" {
  for_each = local.plain_params
  name     = "${local.prefix}/${each.key}"
  type     = "String"
  value    = each.value
}

# Image tag updated by CI on every deploy; seeded here so the param exists.
resource "aws_ssm_parameter" "backend_image" {
  name  = "${local.prefix}/BACKEND_IMAGE"
  type  = "String"
  value = "PENDING_FIRST_DEPLOY"

  lifecycle {
    ignore_changes = [value] # CI owns this value after first deploy
  }
}
