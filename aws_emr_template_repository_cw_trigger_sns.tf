resource "aws_sns_topic" "aws_cyi_infrastructure_cw_trigger_sns" {
  name = "${local.emr_cluster_name}_cw_trigger_sns"

  tags = {
    "Name" = "${local.emr_cluster_name}_cw_trigger_sns"
  }
}

output "aws_cyi_infrastructure_cw_trigger_sns_topic" {
  value = aws_sns_topic.aws_cyi_infrastructure_cw_trigger_sns
}
