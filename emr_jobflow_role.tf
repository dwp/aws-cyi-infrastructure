data "aws_iam_policy_document" "ec2_assume_role" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "aws_cyi_infrastructure" {
  name               = local.emr_cluster_name
  assume_role_policy = data.aws_iam_policy_document.ec2_assume_role.json
  tags = {
    Name = local.emr_cluster_name
  }
}

resource "aws_iam_instance_profile" "aws_cyi_infrastructure" {
  name = local.emr_cluster_name
  role = aws_iam_role.aws_cyi_infrastructure.id
  tags = {
    Name = local.emr_cluster_name
  }
}

resource "aws_iam_role_policy_attachment" "ec2_for_ssm_attachment" {
  role       = aws_iam_role.aws_cyi_infrastructure.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEC2RoleforSSM"
}

resource "aws_iam_role_policy_attachment" "aws_cyi_infrastructure_ebs_cmk" {
  role       = aws_iam_role.aws_cyi_infrastructure.name
  policy_arn = aws_iam_policy.aws_cyi_infrastructure_ebs_cmk_encrypt.arn
}

resource "aws_iam_role_policy_attachment" "aws_cyi_infrastructure_acm" {
  role       = aws_iam_role.aws_cyi_infrastructure.name
  policy_arn = aws_iam_policy.aws_cyi_infrastructure_acm.arn
}

data "aws_iam_policy_document" "aws_cyi_infrastructure_extra_ssm_properties" {
  statement {
    effect = "Allow"
    actions = [
      "cloudwatch:PutMetricData",
    ]

    resources = [
      "*",
    ]
  }
  statement {
    effect = "Allow"
    actions = [
      "ec2:DescribeInstanceStatus",
    ]

    resources = [
      "*",
    ]
  }
  statement {
    effect = "Allow"
    actions = [
      "ds:CreateComputer",
      "ds:DescribeDirectories",
    ]
    resources = [
      "*",
    ]
  }
  statement {
    effect = "Allow"
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:DescribeLogGroups",
      "logs:DescribeLogStreams",
      "logs:PutLogEvents",
    ]
    resources = [
      "*",
    ]
  }

  statement {
    effect = "Allow"

    actions = [
      "s3:GetBucketLocation",
      "s3:ListBucket",
    ]

    resources = [
      "arn:aws:s3:::eu-west-2.elasticmapreduce",
    ]
  }

  statement {
    effect = "Allow"

    actions = [
      "s3:Get*",
      "s3:List*",
    ]

    resources = [
      "arn:aws:s3:::eu-west-2.elasticmapreduce/libs/script-runner/*",
    ]
  }
}

resource "aws_iam_policy" "aws_cyi_infrastructure_extra_ssm_properties" {
  name        = "cyiAwsEmrTemplateRepositoryExtraSSM"
  description = "Additional properties to allow for SSM and writing logs"
  policy      = data.aws_iam_policy_document.aws_cyi_infrastructure_extra_ssm_properties.json
  tags = {
    Name = "aws_cyi_infrastructure_extra_ssm_properties"
  }
}

resource "aws_iam_role_policy_attachment" "aws_cyi_infrastructure_extra_ssm_properties" {
  role       = aws_iam_role.aws_cyi_infrastructure.name
  policy_arn = aws_iam_policy.aws_cyi_infrastructure_extra_ssm_properties.arn
}

resource "aws_iam_role_policy_attachment" "aws_cyi_infrastructure_certificates" {
  role       = aws_iam_role.aws_cyi_infrastructure.name
  policy_arn = aws_iam_policy.aws_cyi_infrastructure_certificates.arn
}

data "aws_iam_policy_document" "aws_cyi_infrastructure_write_logs" {
  statement {
    effect = "Allow"

    actions = [
      "s3:GetBucketLocation",
      "s3:ListBucket",
    ]

    resources = [
      data.terraform_remote_state.security-tools.outputs.logstore_bucket.arn,
    ]
  }

  statement {
    effect = "Allow"

    actions = [
      "s3:GetObject*",
      "s3:PutObject*",

    ]

    resources = [
      "${data.terraform_remote_state.security-tools.outputs.logstore_bucket.arn}/${local.s3_log_prefix}",
    ]
  }
}


resource "aws_iam_role_policy_attachment" "aws_cyi_infrastructure_publish_sns" {
  policy_arn = aws_iam_policy.aws_cyi_infrastructure_publish_sns.arn
  role       = aws_iam_role.aws_cyi_infrastructure.name
}

resource "aws_iam_policy" "aws_cyi_infrastructure_publish_sns" {
  name        = "aws-cyi-infrastructure-publish-sns"
  description = "allow cyi-infrastructure to publish to monitoring sns"
  policy      = data.aws_iam_policy_document.aws_cyi_infrastructure_publish_sns.json
  tags = {
    Name = "aws_cyi_infrastructure_publish_sns"
  }
}

data "aws_iam_policy_document" "aws_cyi_infrastructure_publish_sns" {
  statement {
    effect = "Allow"

    actions = [
      "sns:Publish"
    ]

    resources = [
      data.terraform_remote_state.security-tools.outputs.sns_topic_london_monitoring["arn"]
    ]

  }
}


resource "aws_iam_policy" "aws_cyi_infrastructure_write_logs" {
  name        = "aws-cyi-infrastructure-WriteLogs"
  description = "Allow writing of aws_cyi_infrastructure logs"
  policy      = data.aws_iam_policy_document.aws_cyi_infrastructure_write_logs.json
  tags = {
    Name = "aws_cyi_infrastructure_write_logs"
  }
}

resource "aws_iam_role_policy_attachment" "aws_cyi_infrastructure_write_logs" {
  role       = aws_iam_role.aws_cyi_infrastructure.name
  policy_arn = aws_iam_policy.aws_cyi_infrastructure_write_logs.arn
}

data "aws_iam_policy_document" "aws_cyi_infrastructure_read_config" {
  statement {
    effect = "Allow"

    actions = [
      "s3:GetBucketLocation",
      "s3:ListBucket",
    ]

    resources = [
      data.terraform_remote_state.common.outputs.config_bucket.arn,
    ]
  }

  statement {
    effect = "Allow"

    actions = [
      "s3:GetObject*",
    ]

    resources = [
      "${data.terraform_remote_state.common.outputs.config_bucket.arn}/*",
    ]
  }

  statement {
    effect = "Allow"

    actions = [
      "kms:Decrypt",
      "kms:DescribeKey",
    ]

    resources = [
      data.terraform_remote_state.common.outputs.config_bucket_cmk.arn,
    ]
  }
}

resource "aws_iam_policy" "aws_cyi_infrastructure_read_config" {
  name        = "aws-cyi-infrastructure-ReadConfig"
  description = "Allow reading of aws_cyi_infrastructure config files"
  policy      = data.aws_iam_policy_document.aws_cyi_infrastructure_read_config.json
  tags = {
    Name = "aws_cyi_infrastructure_read_config"
  }
}

resource "aws_iam_role_policy_attachment" "aws_cyi_infrastructure_read_config" {
  role       = aws_iam_role.aws_cyi_infrastructure.name
  policy_arn = aws_iam_policy.aws_cyi_infrastructure_read_config.arn
}

data "aws_iam_policy_document" "aws_cyi_infrastructure_read_artefacts" {
  statement {
    effect = "Allow"

    actions = [
      "s3:GetBucketLocation",
      "s3:ListBucket",
    ]

    resources = [
      data.terraform_remote_state.management_artefact.outputs.artefact_bucket.arn,
    ]
  }

  statement {
    effect = "Allow"

    actions = [
      "s3:GetObject*",
    ]

    resources = [
      "${data.terraform_remote_state.management_artefact.outputs.artefact_bucket.arn}/*",
    ]
  }

  statement {
    effect = "Allow"

    actions = [
      "kms:Decrypt",
      "kms:DescribeKey",
    ]

    resources = [
      data.terraform_remote_state.management_artefact.outputs.artefact_bucket.cmk_arn,
    ]
  }
}

resource "aws_iam_policy" "aws_cyi_infrastructure_read_artefacts" {
  name        = "aws-cyi-infrastructure-ReadArtefacts"
  description = "Allow reading of aws_cyi_infrastructure software artefacts"
  policy      = data.aws_iam_policy_document.aws_cyi_infrastructure_read_artefacts.json
  tags = {
    Name = "aws_cyi_infrastructure_read_artefacts"
  }
}

resource "aws_iam_role_policy_attachment" "aws_cyi_infrastructure_read_artefacts" {
  role       = aws_iam_role.aws_cyi_infrastructure.name
  policy_arn = aws_iam_policy.aws_cyi_infrastructure_read_artefacts.arn
}

data "aws_iam_policy_document" "aws_cyi_infrastructure_write_dynamodb" {
  statement {
    effect = "Allow"

    actions = [
      "dynamodb:*",
    ]

    resources = [
      "arn:aws:dynamodb:${var.region}:${local.account[local.environment]}:table/${local.data_pipeline_metadata}"
    ]
  }
}

resource "aws_iam_policy" "aws_cyi_infrastructure_write_dynamodb" {
  name        = "cyiAwsEmrTemplateRepositoryDynamoDB"
  description = "Allows read and write access toaws_cyi_infrastructure's EMRFS DynamoDB table"
  policy      = data.aws_iam_policy_document.aws_cyi_infrastructure_write_dynamodb.json
  tags = {
    Name = "aws_cyi_infrastructure_write_dynamodb"
  }
}

resource "aws_iam_role_policy_attachment" "analytical_dataset_generator_dynamodb" {
  role       = aws_iam_role.aws_cyi_infrastructure.name
  policy_arn = aws_iam_policy.aws_cyi_infrastructure_write_dynamodb.arn
}

data "aws_iam_policy_document" "aws_cyi_infrastructure_metadata_change" {
  statement {
    effect = "Allow"

    actions = [
      "ec2:ModifyInstanceMetadataOptions",
      "ec2:*Tags",
    ]

    resources = [
      "arn:aws:ec2:${var.region}:${local.account[local.environment]}:instance/*",
    ]
  }
}

resource "aws_iam_policy" "aws_cyi_infrastructure_metadata_change" {
  name        = "aws-cyi-infrastructure-MetadataOptions"
  description = "Allow editing of Metadata Options"
  policy      = data.aws_iam_policy_document.aws_cyi_infrastructure_metadata_change.json
  tags = {
    Name = "aws_cyi_infrastructure_metadata_change"
  }
}

resource "aws_iam_role_policy_attachment" "aws_cyi_infrastructure_metadata_change" {
  role       = aws_iam_role.aws_cyi_infrastructure.name
  policy_arn = aws_iam_policy.aws_cyi_infrastructure_metadata_change.arn
}

data "aws_iam_policy_document" "aws_cyi_infrastructure_get_ingest" {
  statement {
    sid    = "allowToFindIngest"
    effect = "Allow"

    actions = [
      "s3:ListBucket",
      "s3:GetBucketLocation",
    ]

    resources = [
      "arn:aws:s3:::${data.terraform_remote_state.ingestion.outputs.s3_buckets.input_bucket}",
    ]
  }

  statement {
    sid    = "allowToGetFromIngest"
    effect = "Allow"

    actions = [
      "s3:GetObject",
      "s3:ListObjects",
    ]

    resources = [
      "arn:aws:s3:::${data.terraform_remote_state.ingestion.outputs.s3_buckets.input_bucket}/cyi/*",
      "arn:aws:s3:::${data.terraform_remote_state.ingestion.outputs.s3_buckets.input_bucket}/cyi",
    ]
  }

  statement {
    sid    = "allowToDecryptObjectsIngest"
    effect = "Allow"

    actions = [
      "kms:Decrypt",
      "kms:DescribeKey"
    ]

    resources = [
      data.terraform_remote_state.ingestion.outputs.input_bucket_cmk.arn,
    ]
  }
}

resource "aws_iam_policy" "aws_cyi_infrastructure_get_ingest" {
  name        = "aws-cyi-infrastructure-get-ingest"
  description = "Allow get from ingest bucket"
  policy      = data.aws_iam_policy_document.aws_cyi_infrastructure_get_ingest.json
  tags = {
    Name = "aws-cyi-infrastructure-get-ingest"
  }
}

resource "aws_iam_role_policy_attachment" "aws_cyi_infrastructure_get_ingest" {
  role       = aws_iam_role.aws_cyi_infrastructure.name
  policy_arn = aws_iam_policy.aws_cyi_infrastructure_get_ingest.arn
}

data "aws_iam_policy_document" "aws_cyi_infrastructure_write_published" {
  statement {
    sid    = "allowToFindPublished"
    effect = "Allow"

    actions = [
      "s3:ListBucket",
      "s3:GetBucketLocation",
    ]

    resources = [
      "arn:aws:s3:::${data.terraform_remote_state.common.outputs.published_bucket.id}",
    ]
  }

  statement {
    sid    = "allowTowriteFromPublished"
    effect = "Allow"

    actions = [
      "s3:Get*",
      "s3:List*",
      "s3:Delete*",
      "s3:Put*",
    ]

    resources = [
      "arn:aws:s3:::${data.terraform_remote_state.common.outputs.published_bucket.id}/cyi/*",
      "arn:aws:s3:::${data.terraform_remote_state.common.outputs.published_bucket.id}/cyi",
      "arn:aws:s3:::${data.terraform_remote_state.common.outputs.published_bucket.id}/analytical-dataset/hive/external/cyi.db/*",
    ]
  }

  statement {
    sid    = "allowToDecryptObjectsPublished"
    effect = "Allow"

    actions = [
      "kms:Decrypt",
      "kms:DescribeKey"
    ]

    resources = [
      data.terraform_remote_state.common.outputs.published_bucket_cmk.arn,
    ]
  }
}

resource "aws_iam_policy" "aws_cyi_infrastructure_write_published" {
  name        = "aws-cyi-infrastructure-write-published"
  description = "Allow write to published bucket"
  policy      = data.aws_iam_policy_document.aws_cyi_infrastructure_write_published.json
  tags = {
    Name = "aws-cyi-infrastructure-write-published"
  }
}

resource "aws_iam_role_policy_attachment" "aws_cyi_infrastructure_write_published" {
  role       = aws_iam_role.aws_cyi_infrastructure.name
  policy_arn = aws_iam_policy.aws_cyi_infrastructure_write_published.arn
}
