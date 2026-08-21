provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "siase"
      Component   = "auth-lambda"
      Environment = var.environment
      ManagedBy   = "terraform"
    }
  }
}

data "aws_region" "current" {}

data "aws_ssm_parameter" "lb_dns" {
  count = var.lb_dns_override == "" ? 1 : 0
  name  = "/siase/production/lb-dns"
}

data "aws_ssm_parameter" "db_client_sg_id" {
  name = "/siase/production/db-client-sg-id"
}

data "aws_ssm_parameter" "db_endpoint" {
  name = "/siase/production/db-endpoint"
}

data "aws_ssm_parameter" "db_name" {
  name = "/siase/production/db-name"
}

data "aws_ssm_parameter" "db_secret_arn" {
  name = "/siase/production/db-secret-arn"
}

data "aws_secretsmanager_secret" "jwt" {
  name = var.jwt_secret_name
}

locals {
  lb_dns              = var.lb_dns_override != "" ? var.lb_dns_override : data.aws_ssm_parameter.lb_dns[0].value
  lambda_security_ids = distinct([var.lambda_security_group_id, data.aws_ssm_parameter.db_client_sg_id.value])
}
