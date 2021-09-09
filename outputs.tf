output "aws_cyi_infrastructure_common_sg" {
  value = aws_security_group.aws_cyi_infrastructure_common
}

output "aws_cyi_infrastructure_emr_launcher_lambda" {
  value = aws_lambda_function.aws_cyi_infrastructure_emr_launcher
}

output "private_dns" {
  value = {
    cyi_service_discovery_dns = aws_service_discovery_private_dns_namespace.aws_cyi_infrastructure_services
    cyi_service_discovery     = aws_service_discovery_service.aws_cyi_infrastructure_services
  }
}
