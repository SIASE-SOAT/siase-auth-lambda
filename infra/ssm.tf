resource "aws_ssm_parameter" "api_endpoint" {
  name      = "/siase/${var.environment}/api-endpoint"
  type      = "String"
  overwrite = true
  value     = aws_apigatewayv2_api.http.api_endpoint

  tags = {
    Project     = "siase"
    Component   = "auth-lambda"
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}
