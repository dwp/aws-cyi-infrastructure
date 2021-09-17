locals {
  cyi_active = {
    development = true
    qa          = true
    integration = true
    preprod     = true
    production  = true
  }

  persistence_tag_value = {
    development = "Ignore"
    qa          = "Ignore"
    integration = "Ignore"
    preprod     = "Ignore"
    production  = "Ignore"
  }

  auto_shutdown_tag_value = {
    development = "True"
    qa          = "False"
    integration = "True"
    preprod     = "False"
    production  = "False"
  }

  overridden_tags = {
    Role         = "cyi"
    Owner        = "aws-cyi-infrastructure"
    Persistence  = local.persistence_tag_value[local.environment]
    AutoShutdown = local.auto_shutdown_tag_value[local.environment]
  }

  common_repo_tags = merge(module.dataworks_common.common_tags, local.overridden_tags)
  common_emr_tags = {
    for-use-with-amazon-emr-managed-policies = "true"
  }

  emr_cluster_name       = "cyi"
  env_certificate_bucket = "dw-${local.environment}-public-certificates"
  mgt_certificate_bucket = "dw-${local.management_account[local.environment]}-public-certificates"
  dks_endpoint           = data.terraform_remote_state.crypto.outputs.dks_endpoint[local.environment]

  crypto_workspace = {
    management-dev = "management-dev"
    management     = "management"
  }

  management_workspace = {
    management-dev = "default"
    management     = "management"
  }

  management_account = {
    development = "management-dev"
    qa          = "management-dev"
    integration = "management-dev"
    preprod     = "management"
    production  = "management"
  }

  root_dns_name = {
    development = "dev.dataworks.dwp.gov.uk"
    qa          = "qa.dataworks.dwp.gov.uk"
    integration = "int.dataworks.dwp.gov.uk"
    preprod     = "pre.dataworks.dwp.gov.uk"
    production  = "dataworks.dwp.gov.uk"
  }

  aws_cyi_infrastructure_log_level = {
    development = "INFO"
    qa          = "INFO"
    integration = "INFO"
    preprod     = "INFO"
    production  = "INFO"
  }

  aws_cyi_infrastructure_version = {
    development = "0.0.1"
    qa          = "0.0.1"
    integration = "0.0.1"
    preprod     = "0.0.1"
    production  = "0.0.1"
  }

  cyi_alerts = {
    development = false
    qa          = false
    integration = false
    preprod     = false
    production  = true
  }

  data_pipeline_metadata = data.terraform_remote_state.internal_compute.outputs.data_pipeline_metadata_dynamo.name


  cyi_db                  = "cyi"
  hive_metastore_location = "data/cyi"
  serde                   = "org.openx.data.jsonserde.JsonSerDe"
  cyi_scripts_location    = "/opt/emr/dataworks-cyi"

  cyi_processes = {
    development = "10"
    qa          = "10"
    integration = "10"
    preprod     = "20"
    production  = "20"
  }

  amazon_region_domain = "${data.aws_region.current.name}.amazonaws.com"
  endpoint_services    = ["dynamodb", "ec2", "ec2messages", "glue", "kms", "logs", "monitoring", ".s3", "s3", "secretsmanager", "ssm", "ssmmessages"]
  no_proxy             = "169.254.169.254,${join(",", formatlist("%s.%s", local.endpoint_services, local.amazon_region_domain))},${local.aws_cyi_infrastructure_pushgateway_hostname}"
  ebs_emrfs_em = {
    EncryptionConfiguration = {
      EnableInTransitEncryption = false
      EnableAtRestEncryption    = true
      AtRestEncryptionConfiguration = {

        S3EncryptionConfiguration = {
          EncryptionMode             = "CSE-Custom"
          S3Object                   = "s3://${data.terraform_remote_state.management_artefact.outputs.artefact_bucket.id}/emr-encryption-materials-provider/encryption-materials-provider-all.jar"
          EncryptionKeyProviderClass = "uk.gov.dwp.dataworks.dks.encryptionmaterialsprovider.DKSEncryptionMaterialsProvider"
        }
        LocalDiskEncryptionConfiguration = {
          EnableEbsEncryption       = true
          EncryptionKeyProviderType = "AwsKms"
          AwsKmsKey                 = aws_kms_key.aws_cyi_infrastructure_ebs_cmk.arn
        }
      }
    }
  }

  keep_cluster_alive = {
    development = true
    qa          = false
    integration = false
    preprod     = false
    production  = false
  }

  step_fail_action = {
    development = "CONTINUE"
    qa          = "TERMINATE_CLUSTER"
    integration = "TERMINATE_CLUSTER"
    preprod     = "TERMINATE_CLUSTER"
    production  = "CONTINUE"
  }

  cw_agent_namespace                   = "/app/cyi"
  cw_agent_log_group_name              = "/app/cyi"
  cw_agent_bootstrap_loggrp_name       = "/app/cyi/bootstrap_actions"
  cw_agent_steps_loggrp_name           = "/app/cyi/step_logs"
  cw_agent_metrics_collection_interval = 60

  s3_log_prefix = "emr/cyi"

  dynamodb_final_step = {
    development = "run-cyi"
    qa          = "run-cyi"
    integration = "run-cyi"
    preprod     = "run-cyi"
    production  = "run-cyi"
  }

  # These should be `false` unless we have agreed this data product is to use the capacity reservations so as not to interfere with existing data products running
  use_capacity_reservation = {
    development = false
    qa          = false
    integration = false
    preprod     = false
    production  = false
  }

  emr_capacity_reservation_preference = local.use_capacity_reservation[local.environment] == true ? "open" : "none"

  emr_capacity_reservation_usage_strategy = local.use_capacity_reservation[local.environment] == true ? "use-capacity-reservations-first" : ""

  emr_subnet_region = "eu-west-2c"

  aws_cyi_infrastructure_pushgateway_hostname = "${aws_service_discovery_service.aws_cyi_infrastructure_services.name}.${aws_service_discovery_private_dns_namespace.aws_cyi_infrastructure_services.name}"

  aws_cyi_infrastructure_max_retry_count = {
    development = "0"
    qa          = "0"
    integration = "0"
    preprod     = "0"
    production  = "2"
  }

  hive_tez_container_size = {
    development = "2688"
    qa          = "2688"
    integration = "2688"
    preprod     = "15360"
    production  = "15360"
  }

  # 0.8 of hive_tez_container_size
  hive_tez_java_opts = {
    development = "-Xmx2150m"
    qa          = "-Xmx2150m"
    integration = "-Xmx2150m"
    preprod     = "-Xmx12288m"
    production  = "-Xmx12288m"
  }

  # 0.33 of hive_tez_container_size
  hive_auto_convert_join_noconditionaltask_size = {
    development = "896"
    qa          = "896"
    integration = "896"
    preprod     = "5068"
    production  = "5068"
  }

  # 0.4 of hive_tez_container_size
  tez_runtime_io_sort_mb = {
    development = "1075"
    qa          = "1075"
    integration = "1075"
    preprod     = "6144"
    production  = "6144"
  }

  tez_runtime_unordered_output_buffer_size_mb = {
    development = "268"
    qa          = "268"
    integration = "268"
    preprod     = "2148"
    production  = "2148"
  }

  tez_grouping_min_size = {
    development = "1342177"
    qa          = "1342177"
    integration = "1342177"
    preprod     = "52428800"
    production  = "52428800"
  }

  tez_grouping_max_size = {
    development = "268435456"
    qa          = "268435456"
    integration = "268435456"
    preprod     = "1073741824"
    production  = "1073741824"
  }

  tez_am_resource_memory_mb = {
    development = "1024"
    qa          = "1024"
    integration = "1024"
    preprod     = "12288"
    production  = "12288"
  }

  # 0.8 of tez_am_resource_memory_mb
  tez_am_launch_cmd_opts = {
    development = "-Xmx819m"
    qa          = "-Xmx819m"
    integration = "-Xmx819m"
    preprod     = "-Xmx6556m"
    production  = "-Xmx6556m"
  }

  hive_tez_sessions_per_queue = {
    development = "5"
    qa          = "5"
    integration = "5"
    preprod     = "10"
    production  = "10"
  }

  # See https://aws.amazon.com/blogs/big-data/best-practices-for-successfully-managing-memory-for-apache-spark-applications-on-amazon-emr/
  spark_executor_cores = {
    development = 1
    qa          = 1
    integration = 1
    preprod     = 1
    production  = 1
  }

  spark_executor_memory = {
    development = 10
    qa          = 10
    integration = 10
    preprod     = 35
    production  = 35 # At least 20 or more per executor core
  }

  spark_yarn_executor_memory_overhead = {
    development = 2
    qa          = 2
    integration = 2
    preprod     = 7
    production  = 7
  }

  spark_driver_memory = {
    development = 5
    qa          = 5
    integration = 5
    preprod     = 10
    production  = 10 # Doesn't need as much as executors
  }

  spark_driver_cores = {
    development = 1
    qa          = 1
    integration = 1
    preprod     = 1
    production  = 1
  }

  spark_executor_instances  = var.spark_executor_instances[local.environment]
  spark_default_parallelism = local.spark_executor_instances * local.spark_executor_cores[local.environment] * 2
  spark_kyro_buffer         = var.spark_kyro_buffer[local.environment]
}
