variable "aws_region" {
  type        = string
  description = "Região AWS."
}

variable "environment" {
  type        = string
  default     = "production"
  description = "Ambiente fixo da entrega."
}

variable "vpc_id" {
  type        = string
  description = "VPC onde a Lambda de token acessará o RDS."
}

variable "private_subnet_ids" {
  type        = list(string)
  description = "Subnets privadas para a Lambda de token."
}

variable "lambda_security_group_id" {
  type        = string
  description = "Security Group com acesso de saída ao RDS."
}

variable "lab_role_arn" {
  type        = string
  description = "ARN da role pré-criada LabRole do AWS Academy Learner Lab."
}

variable "lb_dns_override" {
  type        = string
  default     = ""
  description = "Override do DNS do Load Balancer; vazio lê o parâmetro SSM."
}

variable "jwt_secret_name" {
  type        = string
  description = "Nome do segredo existente no Secrets Manager com o segredo HS256."
}

variable "jwt_issuer" {
  type    = string
  default = "siase-auth"
}

variable "jwt_expiration" {
  type    = string
  default = "1h"
}

variable "lambda_memory_size" {
  type    = number
  default = 256
}

variable "lambda_timeout" {
  type    = number
  default = 10
}
