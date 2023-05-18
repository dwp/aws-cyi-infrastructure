---
BootstrapActions:
- Name: "run-log4j-patch"
  ScriptBootstrapAction:
    Path: "s3://${s3_config_bucket}/component/cyi/patch-log4j-emr-6.3.1-v2.sh"
- Name: "download_scripts"
  ScriptBootstrapAction:
    Path: "s3://${s3_config_bucket}/component/cyi/download_scripts.sh"
- Name: "start_ssm"
  ScriptBootstrapAction:
    Path: "file:/var/ci/start_ssm.sh"
- Name: "metadata"
  ScriptBootstrapAction:
    Path: "file:/var/ci/metadata.sh"
- Name: "config_hcs"
  ScriptBootstrapAction:
    Path: "file:/var/ci/config_hcs.sh"
    Args: [
      "${environment}", 
      "${proxy_http_host}",
      "${proxy_http_port}"
    ]
- Name: "emr-setup"
  ScriptBootstrapAction:
    Path: "file:/var/ci/emr-setup.sh"
- Name: "metrics-setup"
  ScriptBootstrapAction:
    Path: "file:/var/ci/metrics-setup.sh"
- Name: "installer"
  ScriptBootstrapAction:
    Path: "file:/var/ci/installer.sh"
Steps:
- Name: "courtesy-flush"
  HadoopJarStep:
    Args:
    - "file:/var/ci/courtesy-flush.sh"
    Jar: "s3://eu-west-2.elasticmapreduce/libs/script-runner/script-runner.jar"
  ActionOnFailure: "CONTINUE"
- Name: "run-cyi"
  HadoopJarStep:
    Args:
    - "file:/var/ci/run-cyi.sh"
    Jar: "s3://eu-west-2.elasticmapreduce/libs/script-runner/script-runner.jar"
  ActionOnFailure: "${action_on_failure}"
- Name: "flush-pushgateway"
  HadoopJarStep:
    Args:
    - "file:/var/ci/flush-pushgateway.sh"
    Jar: "s3://eu-west-2.elasticmapreduce/libs/script-runner/script-runner.jar"
  ActionOnFailure: "CONTINUE"
