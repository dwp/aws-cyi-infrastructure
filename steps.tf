#uploading of step files to s3 go here
resource "aws_s3_bucket_object" "run_cyi" {
  bucket     = data.terraform_remote_state.common.outputs.config_bucket.id
  kms_key_id = data.terraform_remote_state.common.outputs.config_bucket_cmk.arn
  key        = "component/cyi/run-cyi.sh"
  content = templatefile("${path.module}/steps/run-cyi.sh",
    {
      serde                = local.serde
      published_bucket     = format("s3://%s", data.terraform_remote_state.common.outputs.published_bucket.id)
      cyi_processes        = local.cyi_processes[local.environment]
      cyi_scripts_location = local.cyi_scripts_location
    }
  )
}

resource "aws_s3_bucket_object" "generate_external_table" {
  bucket     = data.terraform_remote_state.common.outputs.config_bucket.id
  kms_key_id = data.terraform_remote_state.common.outputs.config_bucket_cmk.arn
  key        = "component/cyi/generate_external_table.py"
  content = templatefile("${path.module}/steps/generate_external_table.py",
    {
      database_name       = local.cyi_db
      managed_table_name  = "cyi_managed"
      external_table_name = "cyi_external"
      table_prefix        = "cyi"
      published_bucket    = data.terraform_remote_state.common.outputs.published_bucket.id
      src_bucket          = data.terraform_remote_state.ingestion.outputs.s3_buckets.input_bucket
      src_s3_prefix       = "cyi"
      log_level           = "INFO"
    }
  )
}

resource "aws_s3_bucket_object" "flush_pushgateway" {
  bucket     = data.terraform_remote_state.common.outputs.config_bucket.id
  kms_key_id = data.terraform_remote_state.common.outputs.config_bucket_cmk.arn
  key        = "component/cyi/flush-pushgateway.sh"
  content = templatefile("${path.module}/steps/flush-pushgateway.sh",
    {
      cyi_pushgateway_hostname = local.aws_cyi_infrastructure_pushgateway_hostname
    }
  )
}

resource "aws_s3_bucket_object" "courtesy_flush" {
  bucket     = data.terraform_remote_state.common.outputs.config_bucket.id
  kms_key_id = data.terraform_remote_state.common.outputs.config_bucket_cmk.arn
  key        = "component/cyi/courtesy-flush.sh"
  content = templatefile("${path.module}/steps/courtesy-flush.sh",
    {
      cyi_pushgateway_hostname = local.aws_cyi_infrastructure_pushgateway_hostname
    }
  )
}
