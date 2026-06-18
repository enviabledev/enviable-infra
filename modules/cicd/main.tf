# The GitHub Actions OIDC provider already exists in this AWS account
# (shared across projects), so reference it rather than create it — avoids a
# 409 EntityAlreadyExists and prevents Terraform from deleting a shared
# provider on destroy.
data "aws_iam_openid_connect_provider" "github" {
  url = "https://token.actions.githubusercontent.com"
}

# ---------- Backend deploy role ----------
data "aws_iam_policy_document" "backend_assume" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [data.aws_iam_openid_connect_provider.github.arn]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }
    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${var.github_org}/${var.github_repo_backend}:ref:refs/heads/main"]
    }
  }
}

resource "aws_iam_role" "backend_deploy" {
  name               = "${var.project}-gha-backend-deploy"
  assume_role_policy = data.aws_iam_policy_document.backend_assume.json
}

data "aws_iam_policy_document" "backend_deploy" {
  statement {
    sid       = "EcrAuth"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }
  statement {
    sid = "EcrPush"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:CompleteLayerUpload",
      "ecr:InitiateLayerUpload",
      "ecr:PutImage",
      "ecr:UploadLayerPart",
      "ecr:BatchGetImage",
      "ecr:GetDownloadUrlForLayer",
    ]
    resources = [var.ecr_repository_arn]
  }
  statement {
    sid       = "PutImageTagParam"
    actions   = ["ssm:PutParameter", "ssm:GetParameter"]
    resources = ["arn:aws:ssm:${var.region}:${var.account_id}:parameter${var.parameter_path_prefix}/BACKEND_IMAGE"]
  }
  statement {
    sid       = "UploadDeployArtifacts"
    actions   = ["s3:PutObject"]
    resources = ["${var.bucket_arn}/_deploy/*"]
  }
  statement {
    sid     = "TriggerDeploy"
    actions = ["ssm:SendCommand"]
    resources = [
      "arn:aws:ec2:${var.region}:${var.account_id}:instance/${var.instance_id}",
      "arn:aws:ssm:${var.region}::document/AWS-RunShellScript",
    ]
  }
  statement {
    sid       = "ReadCommandResult"
    actions   = ["ssm:GetCommandInvocation", "ssm:ListCommandInvocations"]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "backend_deploy" {
  name   = "${var.project}-gha-backend-deploy"
  role   = aws_iam_role.backend_deploy.id
  policy = data.aws_iam_policy_document.backend_deploy.json
}

# ---------- Infra (terraform) role ----------
data "aws_iam_policy_document" "infra_assume" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [data.aws_iam_openid_connect_provider.github.arn]
    }
    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }
    condition {
      test     = "StringLike"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${var.github_org}/${var.github_repo_infra}:*"]
    }
  }
}

resource "aws_iam_role" "infra" {
  name               = "${var.project}-gha-infra"
  assume_role_policy = data.aws_iam_policy_document.infra_assume.json
}

# Terraform needs broad provisioning rights; PowerUser + IAM management.
resource "aws_iam_role_policy_attachment" "infra_power" {
  role       = aws_iam_role.infra.name
  policy_arn = "arn:aws:iam::aws:policy/PowerUserAccess"
}

resource "aws_iam_role_policy_attachment" "infra_iam" {
  role       = aws_iam_role.infra.name
  policy_arn = "arn:aws:iam::aws:policy/IAMFullAccess"
}
