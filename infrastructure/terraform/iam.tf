data "aws_iam_policy_document" "lambda_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "sqs_consumer" {
  statement {
    effect = "Allow"
    actions = [
      "sqs:ReceiveMessage",
      "sqs:DeleteMessage",
      "sqs:GetQueueAttributes",
      "sqs:ChangeMessageVisibility",
    ]
    resources = [
      aws_sqs_queue.user_created.arn,
      aws_sqs_queue.payment_processed.arn,
    ]
  }
}

data "aws_iam_policy_document" "dynamodb_crud" {
  statement {
    effect = "Allow"
    actions = [
      "dynamodb:PutItem",
      "dynamodb:GetItem",
      "dynamodb:Query",
      "dynamodb:UpdateItem",
      "dynamodb:DeleteItem",
    ]
    resources = [
      aws_dynamodb_table.notifications.arn,
      "${aws_dynamodb_table.notifications.arn}/index/*",
    ]
  }
}

data "aws_iam_policy_document" "cloudwatch_logs" {
  statement {
    effect = "Allow"
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]
    resources = ["arn:aws:logs:${var.aws_region}:${data.aws_caller_identity.current.account_id}:*"]
  }
}

resource "aws_iam_role" "lambda" {
  name               = "${local.name_prefix}-notifications-lambda-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json
  tags               = local.common_tags
}

resource "aws_iam_role_policy_attachment" "basic_execution" {
  role       = aws_iam_role.lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "sqs_consumer" {
  name   = "SQSConsumerPolicy"
  role   = aws_iam_role.lambda.id
  policy = data.aws_iam_policy_document.sqs_consumer.json
}

resource "aws_iam_role_policy" "dynamodb_crud" {
  name   = "DynamoDBPolicy"
  role   = aws_iam_role.lambda.id
  policy = data.aws_iam_policy_document.dynamodb_crud.json
}

resource "aws_iam_role_policy" "cloudwatch_logs" {
  name   = "CloudWatchPolicy"
  role   = aws_iam_role.lambda.id
  policy = data.aws_iam_policy_document.cloudwatch_logs.json
}
