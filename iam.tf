data "aws_caller_identity" "current" {}

locals {
  bedrock_region = coalesce(var.bedrock_region, var.aws_region)

  inference_profile_arn = "arn:aws:bedrock:${local.bedrock_region}:${data.aws_caller_identity.current.account_id}:inference-profile/${var.inference_profile_id}"

  # Any Region the profile routes to, but only through that profile (see the condition below).
  foundation_model_arn = "arn:aws:bedrock:*::foundation-model/${var.foundation_model_id}"
}

data "aws_iam_policy_document" "lambda_assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "lambda" {
  name               = "${var.project_name}-lambda-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}

data "aws_iam_policy_document" "lambda_permissions" {
  # Allow calling this one inference profile.
  statement {
    sid       = "InvokeInferenceProfile"
    actions   = ["bedrock:InvokeModel"]
    resources = [local.inference_profile_arn]
  }

  # Allow the underlying model only when the call comes through that profile.
  statement {
    sid       = "InvokeModelViaProfile"
    actions   = ["bedrock:InvokeModel"]
    resources = [local.foundation_model_arn]

    condition {
      test     = "StringEquals"
      variable = "bedrock:InferenceProfileArn"
      values   = [local.inference_profile_arn]
    }
  }

  # Write logs only to this function's log group.
  statement {
    sid       = "WriteLogs"
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["${aws_cloudwatch_log_group.lambda.arn}:*"]
  }
}

resource "aws_iam_role_policy" "lambda" {
  name   = "${var.project_name}-lambda-policy"
  role   = aws_iam_role.lambda.id
  policy = data.aws_iam_policy_document.lambda_permissions.json
}
