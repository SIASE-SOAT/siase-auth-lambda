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

data "aws_ssm_parameter" "alb_dns" {
  count = var.alb_dns_override == "" ? 1 : 0
  name  = "/siase/${var.environment}/alb-dns"
}

data "aws_ssm_parameter" "db_client_sg_id" {
  name = "/siase/${var.environment}/db-client-sg-id"
}

locals {
  alb_dns             = var.alb_dns_override != "" ? var.alb_dns_override : data.aws_ssm_parameter.alb_dns[0].value
  lambda_security_ids = distinct([var.lambda_security_group_id, data.aws_ssm_parameter.db_client_sg_id.value])
}
