resource "aws_s3_bucket" "lambda_deploy" {
  bucket        = "fcg-${var.environment}-lambda-deploy-${data.aws_caller_identity.current.account_id}"
  force_destroy = true
  tags          = local.common_tags
}

resource "aws_s3_object" "notifications_zip" {
  bucket = aws_s3_bucket.lambda_deploy.id
  key    = "notifications-lambda.zip"
  source = "${path.module}/.build/notifications-lambda.zip"
  etag   = filemd5("${path.module}/.build/notifications-lambda.zip")
}

resource "aws_cloudwatch_log_group" "notifications" {
  name              = "/aws/lambda/${local.name_prefix}-notifications"
  retention_in_days = 14
  tags              = local.common_tags
}

resource "aws_lambda_function" "notifications" {
  function_name    = "${local.name_prefix}-notifications"
  description      = "Processa UserCreatedEvent e PaymentProcessedEvent via SQS"
  s3_bucket        = aws_s3_bucket.lambda_deploy.id
  s3_key           = aws_s3_object.notifications_zip.key
  source_code_hash = filebase64sha256("${path.module}/.build/notifications-lambda.zip")
  handler          = "NotificationsLambda::NotificationsLambda.Function::FunctionHandler"
  runtime          = "dotnet8"
  architectures    = ["arm64"]
  role             = aws_iam_role.lambda.arn
  memory_size      = 512
  timeout          = 30

  layers = [
    "arn:aws:lambda:${var.aws_region}:464622532012:layer:Datadog-Extension-ARM:${var.dd_extension_version}"
  ]

  environment {
    variables = {
      ASPNETCORE_ENVIRONMENT     = var.environment
      DynamoDB__TableName        = aws_dynamodb_table.notifications.name
      DynamoDB__Region           = var.aws_region
      DD_API_KEY                 = var.dd_api_key
      DD_SITE                    = var.dd_site
      DD_SERVICE                 = "${local.name_prefix}-notifications"
      DD_ENV                     = var.environment
      DD_VERSION                 = "1.0.0"
      DD_TAGS                    = "project:fiapcloudgames phase:3 component:lambda"
      DD_TRACE_ENABLED           = "false"
      DD_LOGS_INJECTION          = "true"
      DD_SERVERLESS_LOGS_ENABLED = "true"
      DD_CAPTURE_LAMBDA_PAYLOAD  = "true"
      DD_RUNTIME_METRICS_ENABLED = "true"
      CORECLR_ENABLE_PROFILING   = "0"
    }
  }

  depends_on = [aws_cloudwatch_log_group.notifications, aws_s3_object.notifications_zip]

  tags = local.common_tags
}

resource "aws_lambda_event_source_mapping" "user_created" {
  event_source_arn                   = aws_sqs_queue.user_created.arn
  function_name                      = aws_lambda_function.notifications.arn
  batch_size                         = 10
  maximum_batching_window_in_seconds = 5
  function_response_types            = ["ReportBatchItemFailures"]
}

resource "aws_lambda_event_source_mapping" "payment_processed" {
  event_source_arn                   = aws_sqs_queue.payment_processed.arn
  function_name                      = aws_lambda_function.notifications.arn
  batch_size                         = 10
  maximum_batching_window_in_seconds = 5
  function_response_types            = ["ReportBatchItemFailures"]
}
