data "archive_file" "lambda" {
  type        = "zip"
  source_dir  = path.module == "" ? "." : "${path.module}/.."
  output_path = "${path.module}/.terraform/siase-auth-lambda.zip"
  excludes = [
    ".git",
    ".github",
    ".terraform",
    "docs",
    "infra",
    "test",
    "README.md",
    "package-lock.json"
  ]
}

resource "aws_lambda_function" "token" {
  function_name    = "siase-auth-token-${var.environment}"
  role             = var.lab_role_arn
  handler          = "src/token-handler.handler"
  runtime          = "nodejs20.x"
  filename         = data.archive_file.lambda.output_path
  source_code_hash = data.archive_file.lambda.output_base64sha256
  timeout          = var.lambda_timeout
  memory_size      = var.lambda_memory_size

  vpc_config {
    subnet_ids         = var.private_subnet_ids
    security_group_ids = local.lambda_security_ids
  }

  environment {
    variables = {
      JWT_SECRET_ARN = data.aws_secretsmanager_secret.jwt.arn
      DB_SECRET_ARN  = data.aws_ssm_parameter.db_secret_arn.value
      DB_HOST        = data.aws_ssm_parameter.db_endpoint.value
      DB_NAME        = data.aws_ssm_parameter.db_name.value
      JWT_ISSUER     = var.jwt_issuer
      JWT_EXPIRATION = var.jwt_expiration
    }
  }
}

resource "aws_lambda_function" "authorizer" {
  function_name    = "siase-auth-authorizer-${var.environment}"
  role             = var.lab_role_arn
  handler          = "src/authorizer.handler"
  runtime          = "nodejs20.x"
  filename         = data.archive_file.lambda.output_path
  source_code_hash = data.archive_file.lambda.output_base64sha256
  timeout          = var.lambda_timeout
  memory_size      = var.lambda_memory_size

  vpc_config {
    subnet_ids         = var.private_subnet_ids
    security_group_ids = local.lambda_security_ids
  }

  environment {
    variables = {
      JWT_SECRET_ARN = data.aws_secretsmanager_secret.jwt.arn
      JWT_ISSUER     = var.jwt_issuer
    }
  }
}

resource "aws_lambda_function" "notification" {
  function_name    = "siase-auth-notification-${var.environment}"
  role             = var.lab_role_arn
  handler          = "src/notification.handler"
  runtime          = "nodejs20.x"
  filename         = data.archive_file.lambda.output_path
  source_code_hash = data.archive_file.lambda.output_base64sha256
  timeout          = var.lambda_timeout
  memory_size      = var.lambda_memory_size

  vpc_config {
    subnet_ids         = var.private_subnet_ids
    security_group_ids = local.lambda_security_ids
  }
}

resource "aws_apigatewayv2_api" "http" {
  name          = "siase-${var.environment}"
  protocol_type = "HTTP"
}

resource "aws_apigatewayv2_authorizer" "client" {
  api_id                            = aws_apigatewayv2_api.http.id
  authorizer_type                   = "REQUEST"
  authorizer_uri                    = aws_lambda_function.authorizer.invoke_arn
  authorizer_payload_format_version = "2.0"
  authorizer_result_ttl_in_seconds  = 300
  enable_simple_responses           = true
  identity_sources                  = ["$request.header.Authorization"]
  name                              = "siase-client-authorizer"
}

resource "aws_lambda_permission" "authorizer" {
  statement_id  = "AllowApiGatewayInvokeAuthorizer"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.authorizer.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.http.execution_arn}/*"
}

resource "aws_apigatewayv2_integration" "token" {
  api_id                 = aws_apigatewayv2_api.http.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.token.invoke_arn
  integration_method     = "POST"
  payload_format_version = "2.0"
}

resource "aws_lambda_permission" "token" {
  statement_id  = "AllowApiGatewayInvokeToken"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.token.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.http.execution_arn}/*/*"
}

resource "aws_apigatewayv2_integration" "application" {
  api_id             = aws_apigatewayv2_api.http.id
  integration_type   = "HTTP_PROXY"
  integration_method = "ANY"
  integration_uri    = "http://${local.lb_dns}"
  request_parameters = {
    "overwrite:path" = "$request.path.proxy"
  }
}

resource "aws_apigatewayv2_route" "token" {
  api_id    = aws_apigatewayv2_api.http.id
  route_key = "POST /auth/token"
  target    = "integrations/${aws_apigatewayv2_integration.token.id}"
}

resource "aws_apigatewayv2_route" "application" {
  api_id             = aws_apigatewayv2_api.http.id
  route_key          = "ANY /{proxy+}"
  target             = "integrations/${aws_apigatewayv2_integration.application.id}"
  authorization_type = "CUSTOM"
  authorizer_id      = aws_apigatewayv2_authorizer.client.id
}

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.http.id
  name        = "$default"
  auto_deploy = true
}

resource "aws_sqs_queue" "notification_dlq" {
  name                      = "siase-notification-dlq-${var.environment}"
  message_retention_seconds = 1209600
}

resource "aws_sns_topic" "notification" {
  name = "siase-notification-${var.environment}"
}

resource "aws_sns_topic_subscription" "notification" {
  topic_arn = aws_sns_topic.notification.arn
  protocol  = "lambda"
  endpoint  = aws_lambda_function.notification.arn
  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.notification_dlq.arn
  })
}

resource "aws_lambda_permission" "notification" {
  statement_id  = "AllowSnsInvokeNotification"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.notification.function_name
  principal     = "sns.amazonaws.com"
  source_arn    = aws_sns_topic.notification.arn
}
