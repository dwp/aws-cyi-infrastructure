#uploading of step files to s3 go here

resource "aws_s3_bucket_object" "example_step_name_sh" {
  bucket     = data.terraform_remote_state.common.outputs.config_bucket.id
  kms_key_id = data.terraform_remote_state.common.outputs.config_bucket_cmk.arn
  key        = "component/aws-cyi-infrastructure/example-step-name.sh"
  content = templatefile("${path.module}/steps/example-step-name.sh",
    {
      example_var = "Hello World"
    }
  )
  tags = {
    Name = "example_step_name_sh"
  }
}

resource "aws_s3_bucket_object" "create_databases_sh" {
  bucket     = data.terraform_remote_state.common.outputs.config_bucket.id
  kms_key_id = data.terraform_remote_state.common.outputs.config_bucket_cmk.arn
  key        = "component/aws-cyi/create-cyi-databases.sh"
  content = templatefile("${path.module}/steps/create-cyi-databases.sh",
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
  key        = "component/aws-cyi/run-cyi.sh"
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
