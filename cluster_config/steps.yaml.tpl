---
BootstrapActions:
- Name: "download_scripts"
  ScriptBootstrapAction:
    Path: "s3://${s3_config_bucket}/component/cyi/download_scripts.sh"
- Name: "start_ssm"
  ScriptBootstrapAction:
    Path: "file:/var/ci/start_ssm.sh"
- Name: "metadata"
  ScriptBootstrapAction:
    Path: "file:/var/ci/metadata.sh"
- Name: "emr-setup"
  ScriptBootstrapAction:
    Path: "file:/var/ci/emr-setup.sh"
- Name: "metrics-setup"
  ScriptBootstrapAction:
    Path: "file:/var/ci/metrics-setup.sh"
Steps:
- Name: "courtesy-flush"
  HadoopJarStep:
    Args:
    - "file:/var/ci/courtesy-flush.sh"
    Jar: "s3://eu-west-2.elasticmapreduce/libs/script-runner/script-runner.jar"
- Name: "create-cyi-database"
  HadoopJarStep:
    Args:
    - "file:/var/ci/create-cyi-database.sh"
    Jar: "s3://eu-west-2.elasticmapreduce/libs/script-runner/script-runner.jar"
  ActionOnFailure: "${action_on_failure}"
- Name: "flush-pushgateway"
  HadoopJarStep:
    Args:
    - "file:/var/ci/flush-pushgateway.sh"
    Jar: "s3://eu-west-2.elasticmapreduce/libs/script-runner/script-runner.jar"
  ActionOnFailure: "CONTINUE"
