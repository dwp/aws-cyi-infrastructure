data "aws_iam_policy_document" "aws_cyi_infrastructure_write_data" {
  statement {
    effect = "Allow"

    actions = [
      "s3:GetBucketLocation",
      "s3:ListBucket",
    ]

    resources = [
      data.terraform_remote_state.common.outputs.published_bucket.arn,
    ]
  }

  statement {
    effect = "Allow"

    actions = [
      "s3:Get*",
      "s3:List*",
      "s3:Delete*",
      "s3:Put*",
    ]

    resources = [
      "${data.terraform_remote_state.common.outputs.published_bucket.arn}/metrics/*",
      "${data.terraform_remote_state.common.outputs.published_bucket.arn}/common-model-inputs/*",
      "${data.terraform_remote_state.common.outputs.published_bucket.arn}/data",
      "${data.terraform_remote_state.common.outputs.published_bucket.arn}/data/*",
      "${data.terraform_remote_state.common.outputs.published_bucket.arn}/cyi/external/",
      "${data.terraform_remote_state.common.outputs.published_bucket.arn}/cyi/external/*",
      "${data.terraform_remote_state.common.outputs.published_bucket.arn}/analytical-dataset/hive/external/cyi.db/*",
    ]
  }

  statement {
    effect = "Allow"

    actions = [
      "kms:Encrypt",
      "kms:Decrypt",
      "kms:ReEncrypt*",
      "kms:GenerateDataKey*",
      "kms:DescribeKey",
    ]

    resources = [
      data.terraform_remote_state.common.outputs.published_bucket_cmk.arn,
    ]
  }
}

resource "aws_iam_policy" "aws_cyi_infrastructure_write_data" {
  name        = "AwsCYIEMRWriteData"
  description = "Allow writing of aws-emr-template files and metrics"
  policy      = data.aws_iam_policy_document.aws_cyi_infrastructure_write_data.json
}

resource "aws_iam_role_policy_attachment" "aws_cyi_infrastructure_write_data" {
  role       = aws_iam_role.aws_cyi_infrastructure.name
  policy_arn = aws_iam_policy.aws_cyi_infrastructure_write_data.arn
}

data "aws_ec2_managed_prefix_list" "list" {
  name = "dwp-*-aws-cidrs-*"
}