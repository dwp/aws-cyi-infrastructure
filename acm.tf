resource "aws_acm_certificate" "aws_cyi_infrastructure" {
  certificate_authority_arn = data.terraform_remote_state.aws_certificate_authority.outputs.root_ca.arn
  domain_name               = "aws-cyi-infrastructure.${local.env_prefix[local.environment]}${local.dataworks_domain_name}"

  options {
    certificate_transparency_logging_preference = "ENABLED"
  }
  tags = {
    Name = local.emr_cluster_name
  }
}

data "aws_iam_policy_document" "aws_cyi_infrastructure_acm" {
  statement {
    effect = "Allow"

    actions = [
      "acm:ExportCertificate",
    ]

    resources = [
      aws_acm_certificate.aws_cyi_infrastructure.arn
    ]
  }
}

resource "aws_iam_policy" "aws_cyi_infrastructure_acm" {
  name        = "ACMExport-aws-cyi-infrastructure-Cert"
  description = "Allow export of aws-cyi-infrastructure certificate"
  policy      = data.aws_iam_policy_document.aws_cyi_infrastructure_acm.json
  tags = {
    Name = "aws_cyi_infrastructure_acm"
  }
}

data "aws_iam_policy_document" "aws_cyi_infrastructure_certificates" {
  statement {
    effect = "Allow"

    actions = [
      "s3:Get*",
      "s3:List*",
    ]

    resources = [
      "arn:aws:s3:::${local.mgt_certificate_bucket}*",
      "arn:aws:s3:::${local.env_certificate_bucket}/*",
    ]
  }
}

resource "aws_iam_policy" "aws_cyi_infrastructure_certificates" {
  name        = "aws_cyi_infrastructureGetCertificates"
  description = "Allow read access to the Crown-specific subset of the aws_cyi_infrastructure"
  policy      = data.aws_iam_policy_document.aws_cyi_infrastructure_certificates.json
  tags = {
    Name = "aws_cyi_infrastructure_certificates"
  }
}


