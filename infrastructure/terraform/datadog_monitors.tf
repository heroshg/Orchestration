# ── DLQ Monitors ──────────────────────────────────────────────────────────────
# Alerta quando mensagens aparecem na DLQ — indica falhas no processamento
# Warning: 1+ mensagem (atenção), Critical: 5+ mensagens (intervenção imediata)

locals {
  dlq_alert_message = <<-EOT
    {{#is_warning}}
    ⚠️ A DLQ **{{queuename}}** recebeu mensagens. Verifique logs da Lambda Notifications / PaymentsAPI.
    {{/is_warning}}
    {{#is_alert}}
    🚨 A DLQ **{{queuename}}** está acumulando mensagens ({{value}}). Processamento com falha persistente!
    {{/is_alert}}
    {{#is_recovery}}
    ✅ DLQ **{{queuename}}** esvaziada — processamento normalizado.
    {{/is_recovery}}

    **Runbook:**
    1. Verificar logs no Datadog APM → serviço afetado
    2. Inspecionar mensagens via AWS Console → SQS → {{queuename}}
    3. Corrigir a causa raiz e usar "Start DLQ Redrive" para reprocessar

    @pagerduty @slack-fcg-alerts
  EOT
}

resource "datadog_monitor" "dlq_user_created" {
  name    = "[FCG] DLQ user-created-events com mensagens paradas"
  type    = "metric alert"
  message = local.dlq_alert_message

  query = "avg(last_5m):max:aws.sqs.approximate_number_of_messages_visible{queuename:${local.name_prefix}-user-created-events-dlq} > 5"

  monitor_thresholds {
    warning  = 1
    critical = 5
  }

  notify_no_data    = false
  renotify_interval = 30
  require_full_window = false

  tags = [
    "env:${var.environment}",
    "project:fiapcloudgames",
    "queue:user-created-events-dlq",
    "team:fcg",
  ]
}

resource "datadog_monitor" "dlq_payment_processed" {
  name    = "[FCG] DLQ payment-processed-events com mensagens paradas"
  type    = "metric alert"
  message = local.dlq_alert_message

  query = "avg(last_5m):max:aws.sqs.approximate_number_of_messages_visible{queuename:${local.name_prefix}-payment-processed-events-dlq} > 5"

  monitor_thresholds {
    warning  = 1
    critical = 5
  }

  notify_no_data    = false
  renotify_interval = 30
  require_full_window = false

  tags = [
    "env:${var.environment}",
    "project:fiapcloudgames",
    "queue:payment-processed-events-dlq",
    "team:fcg",
  ]
}

# Alerta na idade da mensagem mais antiga nas DLQs (mensagem "presa" há muito tempo)
resource "datadog_monitor" "dlq_message_age" {
  name    = "[FCG] DLQ com mensagem parada há mais de 1 hora"
  type    = "metric alert"
  message = <<-EOT
    {{#is_alert}}
    🚨 Mensagem na DLQ **{{queuename}}** sem ser processada há {{value}}s (> 1h).
    Verifique se a infraestrutura de reprocessamento está ativa.
    {{/is_alert}}
    {{#is_recovery}}
    ✅ DLQ **{{queuename}}** — mensagens antigas removidas.
    {{/is_recovery}}

    @pagerduty @slack-fcg-alerts
  EOT

  query = "avg(last_10m):max:aws.sqs.approximate_age_of_oldest_message{queuename:${local.name_prefix}-user-created-events-dlq,queuename:${local.name_prefix}-payment-processed-events-dlq} > 3600"

  monitor_thresholds {
    warning  = 1800
    critical = 3600
  }

  notify_no_data    = false
  renotify_interval = 60
  require_full_window = false

  tags = [
    "env:${var.environment}",
    "project:fiapcloudgames",
    "team:fcg",
  ]
}
