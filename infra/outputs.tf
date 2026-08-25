output "api_endpoint" {
  description = "Endpoint gerenciado do API Gateway; o valor só existe após o apply."
  value       = aws_apigatewayv2_api.http.api_endpoint
}

output "jwt_secret_arn" {
  value = data.aws_secretsmanager_secret.jwt.arn
}

output "db_secret_arn" {
  value     = data.aws_ssm_parameter.db_secret_arn.value
  sensitive = true
}

output "notification_topic_arn" {
  value = aws_sns_topic.notification.arn
}
