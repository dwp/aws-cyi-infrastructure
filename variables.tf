variable "emr_release" {
  default = {
    development = "6.3.0"
    qa          = "6.3.0"
    integration = "6.3.0"
    preprod     = "6.3.0"
    production  = "6.3.0"
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
    preprod     = "m5.12xlarge"
    production  = "m5.12xlarge"
  }
}

variable "emr_ami_id" {
  description = "AMI ID to use for the EMR nodes"
}

variable "region" {
  description = "AWS Region name"
  default     = "eu-west-2"
}

# Count of instances
variable "emr_core_instance_count" {
  default = {
    development = "1"
    qa          = "1"
    integration = "1"
    preprod     = "2"
    production  = "8"
  }
}

variable "emr_instance_type_master_one" {
  default = {
    development = "r5.2xlarge"
    qa          = "r5.2xlarge"
    integration = "r5.2xlarge"
    preprod     = "r5.8xlarge"
    production  = "r5.8xlarge"
  }
}

variable "emr_instance_type_master_two" {
  default = {
    development = "m5.4xlarge"
    qa          = "m5.4xlarge"
    integration = "m5.4xlarge"
    preprod     = "m5.16xlarge"
    production  = "m5.16xlarge"
  }
}

variable "emr_instance_type_core_one" {
  default = {
    development = "r5.2xlarge"
    qa          = "r5.2xlarge"
    integration = "r5.2xlarge"
    preprod     = "r5.8xlarge"
    production  = "r5.8xlarge"
  }
}

variable "emr_instance_type_core_two" {
  default = {
    development = "r4.2xlarge"
    qa          = "r4.2xlarge"
    integration = "r4.2xlarge"
    preprod     = "r4.8xlarge"
    production  = "r4.8xlarge"
  }
}

variable "emr_instance_type_core_three" {
  default = {
    development = "m5.4xlarge"
    qa          = "m5.4xlarge"
    integration = "m5.4xlarge"
    preprod     = "m5.16xlarge"
    production  = "m5.16xlarge"
  }
}

variable "spark_kyro_buffer" {
  default = {
    development = "128m"
    qa          = "128m"
    integration = "128m"
    preprod     = "2047m"
    production  = "2047m" # Max amount allowed
  }
}

variable "spark_executor_instances" {
  default = {
    development = 50
    qa          = 50
    integration = 50
    preprod     = 600
    production  = 600 # More than possible as it won't create them if no core or memory available
  }
}
