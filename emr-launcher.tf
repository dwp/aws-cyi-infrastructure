variable "emr_launcher_zip" {
  type = map(string)

  default = {
    base_path = ""
    version   = ""
  }
}

resource "aws_lambda_function" "aws_cyi_infrastructure_emr_launcher" {
  filename      = "${var.emr_launcher_zip["base_path"]}/emr-launcher-${var.emr_launcher_zip["version"]}.zip"
  function_name = "${local.emr_cluster_name}_emr_launcher"
  role          = aws_iam_role.aws_cyi_infrastructure_emr_launcher_lambda_role.arn
  handler       = "emr_launcher.handler.handler"
  runtime       = "python3.7"
  source_code_hash = filebase64sha256(
    format(
      "%s/emr-launcher-%s.zip",
      var.emr_launcher_zip["base_path"],
      var.emr_launcher_zip["version"]
    )
  )
  publish = false
  timeout = 60

  environment {
    variables = {
      EMR_LAUNCHER_CONFIG_S3_BUCKET = data.terraform_remote_state.common.outputs.config_bucket.id
      EMR_LAUNCHER_CONFIG_S3_FOLDER = "emr/aws_cyi_infrastructure"
      EMR_LAUNCHER_LOG_LEVEL        = "debug"
    }
  }

  tags = {
    Name = "${local.emr_cluster_name}_emr_launcher"
  }
}

resource "aws_iam_role" "aws_cyi_infrastructure_emr_launcher_lambda_role" {
  name               = "${local.emr_cluster_name}_emr_launcher_lambda_role"
  assume_role_policy = data.aws_iam_policy_document.aws_cyi_infrastructure_emr_launcher_assume_policy.json
  tags = {
    Name = "${local.emr_cluster_name}_emr_launcher_lambda_role"
  }
}

data "aws_iam_policy_document" "aws_cyi_infrastructure_emr_launcher_assume_policy" {
  statement {
    sid     = "cyiEMRLauncherLambdaAssumeRolePolicy"
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      identifiers = ["lambda.amazonaws.com"]
      type        = "Service"
    }
  }
}

data "aws_iam_policy_document" "aws_cyi_infrastructure_emr_launcher_read_s3_policy" {
  statement {
    effect = "Allow"
    actions = [
      "s3:GetObject",
    ]
    resources = [
      format("arn:aws:s3:::%s/emr/aws_cyi_infrastructure/*", data.terraform_remote_state.common.outputs.config_bucket.id)
    ]
  }
  statement {
    effect = "Allow"
    actions = [
      "kms:Decrypt",
    ]
    resources = [
      data.terraform_remote_state.common.outputs.config_bucket_cmk.arn
    ]
  }
}

data "aws_iam_policy_document" "aws_cyi_infrastructure_emr_launcher_receive_sqs_message_policy" {
  statement {
    effect = "Allow"
    actions = [
      "sqs:ReceiveMessage",
    ]
    resources = ["*"]
  }
}

data "aws_iam_policy_document" "aws_cyi_infrastructure_emr_launcher_runjobflow_policy" {
  statement {
    effect = "Allow"
    actions = [
      "elasticmapreduce:RunJobFlow",
      "elasticmapreduce:AddTags",
    ]
    resources = [
      "*"
    ]
  }
}

data "aws_iam_policy_document" "aws_cyi_infrastructure_emr_launcher_pass_role_document" {
  statement {
    effect = "Allow"
    actions = [
      "iam:PassRole"
    ]
    resources = [
      "arn:aws:iam::*:role/*"
    ]
  }
}

resource "aws_iam_policy" "aws_cyi_infrastructure_emr_launcher_read_s3_policy" {
  name        = "${local.emr_cluster_name}ReadS3"
  description = "Allow aws_cyi_infrastructure to read from S3 bucket"
  policy      = data.aws_iam_policy_document.aws_cyi_infrastructure_emr_launcher_read_s3_policy.json
  tags = {
    Name = "${local.emr_cluster_name}_emr_launcher_read_s3_policy"
  }
}

resource "aws_iam_policy" "aws_cyi_infrastructure_emr_launcher_receive_sqs_message_policy" {
  name        = "${local.emr_cluster_name}ReadSQS"
  description = "Allow aws_cyi_infrastructure to receive SQS messages"
  policy      = data.aws_iam_policy_document.aws_cyi_infrastructure_emr_launcher_receive_sqs_message_policy.json
  tags = {
    Name = "${local.emr_cluster_name}_emr_launcher_receive_sqs_message_policy"
  }
}

resource "aws_iam_policy" "aws_cyi_infrastructure_emr_launcher_runjobflow_policy" {
  name        = "aws_cyi_infrastructureRunJobFlow"
  description = "Allow aws_cyi_infrastructure to run job flow"
  policy      = data.aws_iam_policy_document.aws_cyi_infrastructure_emr_launcher_runjobflow_policy.json
  tags = {
    Name = "aws_cyi_infrastructure_emr_launcher_runjobflow_policy"
  }
}

resource "aws_iam_policy" "aws_cyi_infrastructure_emr_launcher_pass_role_policy" {
  name        = "aws_cyi_infrastructurePassRole"
  description = "Allow aws_cyi_infrastructure to pass role"
  policy      = data.aws_iam_policy_document.aws_cyi_infrastructure_emr_launcher_pass_role_document.json
  tags = {
    Name = "aws_cyi_infrastructure_emr_launcher_pass_role_policy"
  }
}

resource "aws_iam_role_policy_attachment" "aws_cyi_infrastructure_emr_launcher_read_s3_attachment" {
  role       = aws_iam_role.aws_cyi_infrastructure_emr_launcher_lambda_role.name
  policy_arn = aws_iam_policy.aws_cyi_infrastructure_emr_launcher_read_s3_policy.arn
}

resource "aws_iam_role_policy_attachment" "aws_cyi_infrastructure_emr_launcher_runjobflow_attachment" {
  role       = aws_iam_role.aws_cyi_infrastructure_emr_launcher_lambda_role.name
  policy_arn = aws_iam_policy.aws_cyi_infrastructure_emr_launcher_runjobflow_policy.arn
}

resource "aws_iam_role_policy_attachment" "aws_cyi_infrastructure_emr_launcher_pass_role_attachment" {
  role       = aws_iam_role.aws_cyi_infrastructure_emr_launcher_lambda_role.name
  policy_arn = aws_iam_policy.aws_cyi_infrastructure_emr_launcher_pass_role_policy.arn
}

resource "aws_iam_role_policy_attachment" "aws_cyi_infrastructure_emr_launcher_policy_execution" {
  role       = aws_iam_role.aws_cyi_infrastructure_emr_launcher_lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

resource "aws_sns_topic_subscription" "aws_cyi_infrastructure_trigger_sns" {
  topic_arn = aws_sns_topic.aws_cyi_infrastructure_cw_trigger_sns.arn
  protocol  = "lambda"
  endpoint  = aws_lambda_function.aws_cyi_infrastructure_emr_launcher.arn
}

resource "aws_lambda_permission" "aws_cyi_infrastructure_emr_launcher_subscription" {
  statement_id  = "CWTriggeraws_cyi_infrastructureSNS"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.aws_cyi_infrastructure_emr_launcher.function_name
  principal     = "sns.amazonaws.com"
  source_arn    = aws_sns_topic.aws_cyi_infrastructure_cw_trigger_sns.arn
}

resource "aws_iam_policy" "aws_cyi_infrastructure_emr_launcher_getsecrets" {
  name        = "aws_cyi_infrastructureGetSecrets"
  description = "Allow aws_cyi_infrastructure function to get secrets"
  policy      = data.aws_iam_policy_document.aws_cyi_infrastructure_emr_launcher_getsecrets.json
}

data "aws_iam_policy_document" "aws_cyi_infrastructure_emr_launcher_getsecrets" {
  statement {
    effect = "Allow"

    actions = [
      "secretsmanager:GetSecretValue",
    ]

    resources = [
      data.terraform_remote_state.internal_compute.outputs.metadata_store_users.cyi_writer.secret_arn,
    ]
  }
}

resource "aws_iam_role_policy_attachment" "aws_cyi_infrastructure_emr_launcher_getsecrets" {
  role       = aws_iam_role.aws_cyi_infrastructure_emr_launcher_lambda_role.name
  policy_arn = aws_iam_policy.aws_cyi_infrastructure_emr_launcher_getsecrets.arn
}
