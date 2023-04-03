---
Applications:
- Name: "Hive"
- Name: "Spark"
CustomAmiId: "${ami_id}"
EbsRootVolumeSize: 100
LogUri: "s3://${s3_log_bucket}/${s3_log_prefix}"
Name: "cyi"
ReleaseLabel: "emr-${emr_release}"
SecurityConfiguration: "${security_configuration}"
ScaleDownBehavior: "TERMINATE_AT_TASK_COMPLETION"
ServiceRole: "${service_role}"
JobFlowRole: "${instance_profile}"
VisibleToAllUsers: True
Tags:
- Key: "Persistence"
  Value: "Ignore"
- Key: "Owner"
  Value: "dataworks platform"
- Key: "AutoShutdown"
  Value: "False"
- Key: "CreatedBy"
  Value: "emr-launcher"
- Key: "SSMEnabled"
  Value: "True"
- Key: "Name"
  Value: "aws-cyi-infrastructure"
- Key: "Application"
  Value: "${application_tag_value}"
- Key: "Environment"
  Value: "${environment_tag_value}"
- key: "Function"
  Value: "function_tag_value"
- key: "Business-Project"
  Value: "business_project_tag_value"
- Key: "DWX_Environment"
  Value: "${dwx_environment_tag_value}"
- Key: "DWX_Application"
  Value: "aws-cyi-infrastructure"
- Key: "for-use-with-amazon-emr-managed-policies"
  Value: "true"
