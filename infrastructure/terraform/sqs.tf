resource "aws_sqs_queue" "user_created_dlq" {
  name                      = "${local.name_prefix}-user-created-events-dlq"
  message_retention_seconds = 1209600
  tags                      = local.common_tags
}

resource "aws_sqs_queue" "user_created" {
  name                       = "${local.name_prefix}-user-created-events"
  visibility_timeout_seconds = 90
  message_retention_seconds  = 86400
  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.user_created_dlq.arn
    maxReceiveCount     = 3
  })
  tags = local.common_tags
}

resource "aws_sqs_queue" "payment_processed_dlq" {
  name                      = "${local.name_prefix}-payment-processed-events-dlq"
  message_retention_seconds = 1209600
  tags                      = local.common_tags
}

resource "aws_sqs_queue" "payment_processed" {
  name                       = "${local.name_prefix}-payment-processed-events"
  visibility_timeout_seconds = 90
  message_retention_seconds  = 86400
  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.payment_processed_dlq.arn
    maxReceiveCount     = 3
  })
  tags = local.common_tags
}
