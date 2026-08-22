resource "aws_secretsmanager_secret" "jwt" {
  name                    = var.jwt_secret_name
  recovery_window_in_days = 7
}

resource "aws_secretsmanager_secret" "db" {
  name                    = var.db_secret_name
  recovery_window_in_days = 7
}

resource "aws_iam_role" "token" {
  name = "siase-auth-token-${var.environment}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "token_vpc" {
  role       = aws_iam_role.token.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

resource "aws_iam_role_policy" "token_secrets" {
  role = aws_iam_role.token.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["secretsmanager:GetSecretValue"]
      Resource = [aws_secretsmanager_secret.jwt.arn, aws_secretsmanager_secret.db.arn]
    }]
  })
}

resource "aws_iam_role" "authorizer" {
  name = "siase-auth-authorizer-${var.environment}"

  assume_role_policy = aws_iam_role.token.assume_role_policy
}

resource "aws_iam_role_policy_attachment" "authorizer_logs" {
  role       = aws_iam_role.authorizer.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy_attachment" "authorizer_vpc" {
  role       = aws_iam_role.authorizer.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

resource "aws_iam_role_policy" "authorizer_secrets" {
  role = aws_iam_role.authorizer.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["secretsmanager:GetSecretValue"]
      Resource = aws_secretsmanager_secret.jwt.arn
    }]
  })
}

resource "aws_iam_role" "notification" {
  name = "siase-auth-notification-${var.environment}"

  assume_role_policy = aws_iam_role.token.assume_role_policy
}

resource "aws_iam_role_policy_attachment" "notification_logs" {
  role       = aws_iam_role.notification.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy_attachment" "notification_vpc" {
  role       = aws_iam_role.notification.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

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
  role             = aws_iam_role.token.arn
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
      JWT_SECRET_ARN = aws_secretsmanager_secret.jwt.arn
      DB_SECRET_ARN  = aws_secretsmanager_secret.db.arn
      JWT_ISSUER     = var.jwt_issuer
      JWT_EXPIRATION = var.jwt_expiration
    }
  }
}

resource "aws_lambda_function" "authorizer" {
  function_name    = "siase-auth-authorizer-${var.environment}"
  role             = aws_iam_role.authorizer.arn
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
      JWT_SECRET_ARN = aws_secretsmanager_secret.jwt.arn
      JWT_ISSUER     = var.jwt_issuer
    }
  }
}

resource "aws_lambda_function" "notification" {
  function_name    = "siase-auth-notification-${var.environment}"
  role             = aws_iam_role.notification.arn
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
  integration_uri    = "http://${local.alb_dns}"
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
