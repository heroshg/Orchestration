output "datadog_integration_role_arn" {
  value       = aws_iam_role.datadog_aws.arn
  description = "Cole este ARN no Datadog → Integrations → AWS → Role ARN"
}

output "datadog_external_id" {
  value       = datadog_integration_aws.fcg.external_id
  description = "External ID gerado pelo Datadog (auto-managed pela integration)"
}

output "user_created_queue_url" {
  value       = aws_sqs_queue.user_created.url
  description = "URL da fila SQS UserCreatedEvent — configurar em UsersAPI"
}

output "user_created_queue_arn" {
  value = aws_sqs_queue.user_created.arn
}

output "payment_processed_queue_url" {
  value       = aws_sqs_queue.payment_processed.url
  description = "URL da fila SQS PaymentProcessedEvent — configurar em PaymentsAPI"
}

output "payment_processed_queue_arn" {
  value = aws_sqs_queue.payment_processed.arn
}

output "notifications_table_name" {
  value = aws_dynamodb_table.notifications.name
}

output "notifications_function_arn" {
  value = aws_lambda_function.notifications.arn
}

output "ecr_users_api_url" {
  value       = aws_ecr_repository.users_api.repository_url
  description = "URL do repositório ECR — users-api"
}

output "ecr_catalog_api_url" {
  value       = aws_ecr_repository.catalog_api.repository_url
  description = "URL do repositório ECR — catalog-api"
}

output "ecr_payments_api_url" {
  value       = aws_ecr_repository.payments_api.repository_url
  description = "URL do repositório ECR — payments-api"
}
