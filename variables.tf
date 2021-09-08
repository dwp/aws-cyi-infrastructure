variable "emr_release" {
  default = {
    development = "6.2.0"
    qa          = "6.2.0"
    integration = "6.2.0"
    preprod     = "6.2.0"
    production  = "6.2.0"
  }
}

variable "truststore_aliases" {
  description = "comma seperated truststore aliases"
  type        = list(string)
  default     = ["dataworks_root_ca", "dataworks_mgt_root_ca"]
}

variable "emr_instance_type_master" {
  default = {
    development = "m5.xlarge"
    qa          = "m5.xlarge"
    integration = "m5.xlarge"
    preprod     = "m5.4xlarge"
    production  = "m5.4xlarge"
  }
}

variable "emr_instance_type_core_one" {
  default = {
    development = "m5.xlarge"
    qa          = "m5.xlarge"
    integration = "m5.xlarge"
    preprod     = "m5.4xlarge"
    production  = "m5.4xlarge"
  }
}

# Count of instances
variable "emr_core_instance_count" {
  default = {
    development = "1"
    qa          = "1"
    integration = "1"
    preprod     = "1"
    production  = "1"
  }
}

variable "emr_ami_id" {
  description = "AMI ID to use for the HBase EMR nodes"
}

variable "hive_tez_container_size" {}

variable "hive_tez_java_opts" {}

variable "tez_grouping_min_size" {}

variable "tez_grouping_max_size" {}

variable "tez_am_resource_memory_mb" {}

variable "tez_am_launch_cmd_opts" {}

variable "tez_runtime_io_sort_mb" {}

variable "hive_auto_convert_join_noconditionaltask_size" {}
