#uploading of step files to s3 go here
resource "aws_s3_bucket_object" "create_cyi_database" {
  bucket     = data.terraform_remote_state.common.outputs.config_bucket.id
  kms_key_id = data.terraform_remote_state.common.outputs.config_bucket_cmk.arn
  key        = "component/cyi/create-cyi-database.sh"
  content = templatefile("${path.module}/steps/create-cyi-database.sh",
    {
      cyi_db                  = local.cyi_db
      hive_metastore_location = local.hive_metastore_location
      published_bucket        = format("s3://%s", data.terraform_remote_state.common.outputs.published_bucket.id)
    }
  )
}

resource "aws_s3_bucket_object" "run_cyi" {
  bucket     = data.terraform_remote_state.common.outputs.config_bucket.id
  kms_key_id = data.terraform_remote_state.common.outputs.config_bucket_cmk.arn
  key        = "component/cyi/run-cyi.sh"
  content = templatefile("${path.module}/steps/run-cyi.sh",
    {
      target_db            = local.cyi_db
      serde                = local.serde
      data_path            = local.data_path
      published_bucket     = format("s3://%s", data.terraform_remote_state.common.outputs.published_bucket.id)
      cyi_processes        = local.cyi_processes[local.environment]
      cyi_scripts_location = local.cyi_scripts_location
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
