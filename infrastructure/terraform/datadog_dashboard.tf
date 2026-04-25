resource "datadog_dashboard" "fcg_observability" {
  title       = "FiapCloudGames — Observabilidade (Fase 3)"
  description = "Trace distribuído, latência, erros e throughput de todos os microsserviços"
  layout_type = "ordered"
  reflow_type = "fixed"

  # ──────────────────────────────────────────────────────────────────────────
  # Cabeçalho — fluxo de compra
  # ──────────────────────────────────────────────────────────────────────────

  widget {
    note_definition {
      content          = "## Fluxo de Compra — Trace Distribuído\nAPI Gateway → **CatalogAPI** → RabbitMQ → **PaymentsAPI** → SQS → **Lambda Notifications** → DynamoDB"
      background_color = "blue"
      font_size        = "14"
      text_align       = "left"
      show_tick        = false
      tick_edge        = "left"
    }
    widget_layout {
      x      = 0
      y      = 0
      width  = 12
      height = 1
    }
  }

  # ──────────────────────────────────────────────────────────────────────────
  # Service Map + Trace service view (CatalogAPI)
  # ──────────────────────────────────────────────────────────────────────────

  widget {
    servicemap_definition {
      title   = "Service Map — FiapCloudGames"
      filters = ["env:production", "project:fiapcloudgames"]
      service = "catalog-api"
    }
    widget_layout {
      x      = 0
      y      = 1
      width  = 6
      height = 4
    }
  }

  widget {
    trace_service_definition {
      title              = "Traces — Fluxo de Compra (CatalogAPI)"
      env                = "production"
      service            = "catalog-api"
      span_name          = "aspnet_core.request"
      show_hits          = true
      show_errors        = true
      show_latency       = true
      show_breakdown     = true
      show_distribution  = true
      show_resource_list = true
      size_format        = "large"
      display_format     = "three_column"
    }
    widget_layout {
      x      = 6
      y      = 1
      width  = 6
      height = 4
    }
  }

  # ──────────────────────────────────────────────────────────────────────────
  # Throughput por serviço
  # ──────────────────────────────────────────────────────────────────────────

  widget {
    timeseries_definition {
      title         = "Throughput — Requisições/s por Serviço"
      show_legend   = true
      legend_layout = "horizontal"

      request {
        q            = "sum:trace.aspnet_core.request.hits{env:production,service:users-api}.as_rate()"
        display_type = "line"
        style {
          palette    = "blue"
          line_type  = "solid"
          line_width = "normal"
        }
        metadata {
          expression = "sum:trace.aspnet_core.request.hits{env:production,service:users-api}.as_rate()"
          alias_name = "UsersAPI"
        }
      }

      request {
        q            = "sum:trace.aspnet_core.request.hits{env:production,service:catalog-api}.as_rate()"
        display_type = "line"
        style {
          palette    = "green"
          line_type  = "solid"
          line_width = "normal"
        }
        metadata {
          expression = "sum:trace.aspnet_core.request.hits{env:production,service:catalog-api}.as_rate()"
          alias_name = "CatalogAPI"
        }
      }

      request {
        q            = "sum:trace.aspnet_core.request.hits{env:production,service:payments-api}.as_rate()"
        display_type = "line"
        style {
          palette    = "orange"
          line_type  = "solid"
          line_width = "normal"
        }
        metadata {
          expression = "sum:trace.aspnet_core.request.hits{env:production,service:payments-api}.as_rate()"
          alias_name = "PaymentsAPI"
        }
      }

      request {
        q            = "sum:aws.lambda.invocations{env:production,functionname:fcg-production-notifications}.as_rate()"
        display_type = "line"
        style {
          palette    = "purple"
          line_type  = "solid"
          line_width = "normal"
        }
        metadata {
          expression = "sum:aws.lambda.invocations{env:production,functionname:fcg-production-notifications}.as_rate()"
          alias_name = "Lambda Notifications"
        }
      }

      yaxis {
        include_zero = true
      }
    }
    widget_layout {
      x      = 0
      y      = 5
      width  = 6
      height = 3
    }
  }

  # ──────────────────────────────────────────────────────────────────────────
  # Latência p95 por serviço
  # ──────────────────────────────────────────────────────────────────────────

  widget {
    timeseries_definition {
      title         = "Latência p95 (ms) por Serviço"
      show_legend   = true
      legend_layout = "horizontal"

      request {
        q            = "p95:trace.aspnet_core.request{env:production,service:users-api}*1000"
        display_type = "line"
        style {
          palette    = "blue"
          line_type  = "solid"
          line_width = "normal"
        }
        metadata {
          expression = "p95:trace.aspnet_core.request{env:production,service:users-api}*1000"
          alias_name = "UsersAPI p95"
        }
      }

      request {
        q            = "p95:trace.aspnet_core.request{env:production,service:catalog-api}*1000"
        display_type = "line"
        style {
          palette    = "green"
          line_type  = "solid"
          line_width = "normal"
        }
        metadata {
          expression = "p95:trace.aspnet_core.request{env:production,service:catalog-api}*1000"
          alias_name = "CatalogAPI p95"
        }
      }

      request {
        q            = "p95:trace.aspnet_core.request{env:production,service:payments-api}*1000"
        display_type = "line"
        style {
          palette    = "orange"
          line_type  = "solid"
          line_width = "normal"
        }
        metadata {
          expression = "p95:trace.aspnet_core.request{env:production,service:payments-api}*1000"
          alias_name = "PaymentsAPI p95"
        }
      }

      yaxis {
        include_zero = true
      }
    }
    widget_layout {
      x      = 6
      y      = 5
      width  = 6
      height = 3
    }
  }

  # ──────────────────────────────────────────────────────────────────────────
  # Taxa de erros por serviço
  # ──────────────────────────────────────────────────────────────────────────

  widget {
    timeseries_definition {
      title         = "Taxa de Erros (%) por Serviço"
      show_legend   = true
      legend_layout = "horizontal"

      request {
        q            = "sum:trace.aspnet_core.request.errors{env:production,service:users-api}.as_rate() / sum:trace.aspnet_core.request.hits{env:production,service:users-api}.as_rate() * 100"
        display_type = "bars"
        style {
          palette    = "warm"
          line_type  = "solid"
          line_width = "normal"
        }
        metadata {
          expression = "sum:trace.aspnet_core.request.errors{env:production,service:users-api}.as_rate() / sum:trace.aspnet_core.request.hits{env:production,service:users-api}.as_rate() * 100"
          alias_name = "UsersAPI"
        }
      }

      request {
        q            = "sum:trace.aspnet_core.request.errors{env:production,service:catalog-api}.as_rate() / sum:trace.aspnet_core.request.hits{env:production,service:catalog-api}.as_rate() * 100"
        display_type = "bars"
        style {
          palette    = "warm"
          line_type  = "solid"
          line_width = "normal"
        }
        metadata {
          expression = "sum:trace.aspnet_core.request.errors{env:production,service:catalog-api}.as_rate() / sum:trace.aspnet_core.request.hits{env:production,service:catalog-api}.as_rate() * 100"
          alias_name = "CatalogAPI"
        }
      }

      request {
        q            = "sum:trace.aspnet_core.request.errors{env:production,service:payments-api}.as_rate() / sum:trace.aspnet_core.request.hits{env:production,service:payments-api}.as_rate() * 100"
        display_type = "bars"
        style {
          palette    = "warm"
          line_type  = "solid"
          line_width = "normal"
        }
        metadata {
          expression = "sum:trace.aspnet_core.request.errors{env:production,service:payments-api}.as_rate() / sum:trace.aspnet_core.request.hits{env:production,service:payments-api}.as_rate() * 100"
          alias_name = "PaymentsAPI"
        }
      }

      yaxis {
        include_zero = true
      }
    }
    widget_layout {
      x      = 0
      y      = 8
      width  = 6
      height = 3
    }
  }

  # ──────────────────────────────────────────────────────────────────────────
  # Lambda — erros e duração
  # ──────────────────────────────────────────────────────────────────────────

  widget {
    timeseries_definition {
      title         = "Lambda Notifications — Erros e Duração p95"
      show_legend   = true
      legend_layout = "horizontal"

      request {
        q            = "sum:aws.lambda.errors{env:production,functionname:fcg-production-notifications}.as_rate()"
        display_type = "bars"
        style {
          palette    = "red"
          line_type  = "solid"
          line_width = "normal"
        }
        metadata {
          expression = "sum:aws.lambda.errors{env:production,functionname:fcg-production-notifications}.as_rate()"
          alias_name = "Erros/s"
        }
      }

      request {
        q            = "avg:aws.lambda.duration.p95{env:production,functionname:fcg-production-notifications}"
        display_type = "line"
        style {
          palette    = "purple"
          line_type  = "solid"
          line_width = "normal"
        }
        metadata {
          expression = "avg:aws.lambda.duration.p95{env:production,functionname:fcg-production-notifications}"
          alias_name = "Duração p95 (ms)"
        }
      }

      yaxis {
        include_zero = true
      }
    }
    widget_layout {
      x      = 6
      y      = 8
      width  = 6
      height = 3
    }
  }

  # ──────────────────────────────────────────────────────────────────────────
  # Cache Redis e Mensageria SQS
  # ──────────────────────────────────────────────────────────────────────────

  widget {
    note_definition {
      content          = "## Cache Redis (cache-aside) e Mensageria SQS"
      background_color = "gray"
      font_size        = "14"
      text_align       = "left"
      show_tick        = false
      tick_edge        = "left"
    }
    widget_layout {
      x      = 0
      y      = 11
      width  = 12
      height = 1
    }
  }

  widget {
    timeseries_definition {
      title         = "Redis — Latência de Comandos p95 (ms)"
      show_legend   = true
      legend_layout = "horizontal"

      request {
        q            = "p95:trace.redis.command{env:production,service:users-api}*1000"
        display_type = "line"
        style {
          palette    = "blue"
          line_type  = "solid"
          line_width = "normal"
        }
        metadata {
          expression = "p95:trace.redis.command{env:production,service:users-api}*1000"
          alias_name = "UsersAPI → Redis"
        }
      }

      request {
        q            = "p95:trace.redis.command{env:production,service:catalog-api}*1000"
        display_type = "line"
        style {
          palette    = "green"
          line_type  = "solid"
          line_width = "normal"
        }
        metadata {
          expression = "p95:trace.redis.command{env:production,service:catalog-api}*1000"
          alias_name = "CatalogAPI → Redis"
        }
      }

      yaxis {
        include_zero = true
      }
    }
    widget_layout {
      x      = 0
      y      = 12
      width  = 6
      height = 3
    }
  }

  widget {
    timeseries_definition {
      title         = "SQS — Mensagens Visíveis nas Filas"
      show_legend   = true
      legend_layout = "horizontal"

      request {
        q            = "avg:aws.sqs.approximate_number_of_messages_visible{queuename:fcg-production-user-created-events}"
        display_type = "line"
        style {
          palette    = "blue"
          line_type  = "solid"
          line_width = "normal"
        }
        metadata {
          expression = "avg:aws.sqs.approximate_number_of_messages_visible{queuename:fcg-production-user-created-events}"
          alias_name = "UserCreatedEvents"
        }
      }

      request {
        q            = "avg:aws.sqs.approximate_number_of_messages_visible{queuename:fcg-production-payment-processed-events}"
        display_type = "line"
        style {
          palette    = "orange"
          line_type  = "solid"
          line_width = "normal"
        }
        metadata {
          expression = "avg:aws.sqs.approximate_number_of_messages_visible{queuename:fcg-production-payment-processed-events}"
          alias_name = "PaymentProcessedEvents"
        }
      }

      yaxis {
        include_zero = true
      }
    }
    widget_layout {
      x      = 6
      y      = 12
      width  = 6
      height = 3
    }
  }

  # ──────────────────────────────────────────────────────────────────────────
  # PostgreSQL (Npgsql spans)
  # ──────────────────────────────────────────────────────────────────────────

  widget {
    note_definition {
      content          = "## Banco de Dados — PostgreSQL"
      background_color = "gray"
      font_size        = "14"
      text_align       = "left"
      show_tick        = false
      tick_edge        = "left"
    }
    widget_layout {
      x      = 0
      y      = 15
      width  = 12
      height = 1
    }
  }

  widget {
    timeseries_definition {
      title         = "PostgreSQL — Latência de Queries p95 (ms)"
      show_legend   = true
      legend_layout = "horizontal"

      request {
        q            = "p95:trace.npgsql.command{env:production,service:users-api}*1000"
        display_type = "line"
        style {
          palette    = "blue"
          line_type  = "solid"
          line_width = "normal"
        }
        metadata {
          expression = "p95:trace.npgsql.command{env:production,service:users-api}*1000"
          alias_name = "UsersAPI → PG"
        }
      }

      request {
        q            = "p95:trace.npgsql.command{env:production,service:catalog-api}*1000"
        display_type = "line"
        style {
          palette    = "green"
          line_type  = "solid"
          line_width = "normal"
        }
        metadata {
          expression = "p95:trace.npgsql.command{env:production,service:catalog-api}*1000"
          alias_name = "CatalogAPI → PG"
        }
      }

      request {
        q            = "p95:trace.npgsql.command{env:production,service:payments-api}*1000"
        display_type = "line"
        style {
          palette    = "orange"
          line_type  = "solid"
          line_width = "normal"
        }
        metadata {
          expression = "p95:trace.npgsql.command{env:production,service:payments-api}*1000"
          alias_name = "PaymentsAPI → PG"
        }
      }

      yaxis {
        include_zero = true
      }
    }
    widget_layout {
      x      = 0
      y      = 16
      width  = 12
      height = 3
    }
  }

  # ──────────────────────────────────────────────────────────────────────────
  # SQS — DLQs e Throughput de Filas
  # ──────────────────────────────────────────────────────────────────────────

  widget {
    note_definition {
      content          = "## Filas SQS — DLQs e Throughput\nMensagens paradas nas dead letter queues e fluxo de entrada/saída das filas principais"
      background_color = "red"
      font_size        = "14"
      text_align       = "left"
      show_tick        = false
      tick_edge        = "left"
    }
    widget_layout {
      x      = 0
      y      = 19
      width  = 12
      height = 1
    }
  }

  widget {
    timeseries_definition {
      title         = "DLQ — Mensagens Paradas (visíveis)"
      show_legend   = true
      legend_layout = "horizontal"

      request {
        q            = "avg:aws.sqs.approximate_number_of_messages_visible{queuename:fcg-production-user-created-events-dlq}"
        display_type = "bars"
        style {
          palette    = "red"
          line_type  = "solid"
          line_width = "normal"
        }
        metadata {
          expression = "avg:aws.sqs.approximate_number_of_messages_visible{queuename:fcg-production-user-created-events-dlq}"
          alias_name = "DLQ UserCreated"
        }
      }

      request {
        q            = "avg:aws.sqs.approximate_number_of_messages_visible{queuename:fcg-production-payment-processed-events-dlq}"
        display_type = "bars"
        style {
          palette    = "orange"
          line_type  = "solid"
          line_width = "normal"
        }
        metadata {
          expression = "avg:aws.sqs.approximate_number_of_messages_visible{queuename:fcg-production-payment-processed-events-dlq}"
          alias_name = "DLQ PaymentProcessed"
        }
      }

      yaxis {
        include_zero = true
        min          = "0"
      }

      marker {
        value        = "y > 0"
        display_type = "error dashed"
        label        = "⚠ mensagens na DLQ"
      }
    }
    widget_layout {
      x      = 0
      y      = 20
      width  = 6
      height = 3
    }
  }

  widget {
    timeseries_definition {
      title         = "Filas Principais — Throughput (msg/min)"
      show_legend   = true
      legend_layout = "horizontal"

      request {
        q            = "sum:aws.sqs.number_of_messages_sent{queuename:fcg-production-user-created-events}.as_rate()*60"
        display_type = "line"
        style {
          palette    = "blue"
          line_type  = "solid"
          line_width = "normal"
        }
        metadata {
          expression = "sum:aws.sqs.number_of_messages_sent{queuename:fcg-production-user-created-events}.as_rate()*60"
          alias_name = "UserCreated — entrada"
        }
      }

      request {
        q            = "sum:aws.sqs.number_of_messages_deleted{queuename:fcg-production-user-created-events}.as_rate()*60"
        display_type = "line"
        style {
          palette    = "blue"
          line_type  = "dashed"
          line_width = "normal"
        }
        metadata {
          expression = "sum:aws.sqs.number_of_messages_deleted{queuename:fcg-production-user-created-events}.as_rate()*60"
          alias_name = "UserCreated — consumidas"
        }
      }

      request {
        q            = "sum:aws.sqs.number_of_messages_sent{queuename:fcg-production-payment-processed-events}.as_rate()*60"
        display_type = "line"
        style {
          palette    = "green"
          line_type  = "solid"
          line_width = "normal"
        }
        metadata {
          expression = "sum:aws.sqs.number_of_messages_sent{queuename:fcg-production-payment-processed-events}.as_rate()*60"
          alias_name = "PaymentProcessed — entrada"
        }
      }

      request {
        q            = "sum:aws.sqs.number_of_messages_deleted{queuename:fcg-production-payment-processed-events}.as_rate()*60"
        display_type = "line"
        style {
          palette    = "green"
          line_type  = "dashed"
          line_width = "normal"
        }
        metadata {
          expression = "sum:aws.sqs.number_of_messages_deleted{queuename:fcg-production-payment-processed-events}.as_rate()*60"
          alias_name = "PaymentProcessed — consumidas"
        }
      }

      yaxis {
        include_zero = true
      }
    }
    widget_layout {
      x      = 6
      y      = 20
      width  = 6
      height = 3
    }
  }

  widget {
    timeseries_definition {
      title         = "DLQ — Idade da Mensagem Mais Antiga (segundos)"
      show_legend   = true
      legend_layout = "horizontal"

      request {
        q            = "max:aws.sqs.approximate_age_of_oldest_message{queuename:fcg-production-user-created-events-dlq}"
        display_type = "line"
        style {
          palette    = "red"
          line_type  = "solid"
          line_width = "thick"
        }
        metadata {
          expression = "max:aws.sqs.approximate_age_of_oldest_message{queuename:fcg-production-user-created-events-dlq}"
          alias_name = "DLQ UserCreated"
        }
      }

      request {
        q            = "max:aws.sqs.approximate_age_of_oldest_message{queuename:fcg-production-payment-processed-events-dlq}"
        display_type = "line"
        style {
          palette    = "orange"
          line_type  = "solid"
          line_width = "thick"
        }
        metadata {
          expression = "max:aws.sqs.approximate_age_of_oldest_message{queuename:fcg-production-payment-processed-events-dlq}"
          alias_name = "DLQ PaymentProcessed"
        }
      }

      marker {
        value        = "y = 1800"
        display_type = "warning dashed"
        label        = "30 min"
      }

      marker {
        value        = "y = 3600"
        display_type = "error dashed"
        label        = "1 hora"
      }

      yaxis {
        include_zero = true
      }
    }
    widget_layout {
      x      = 0
      y      = 23
      width  = 6
      height = 3
    }
  }

  widget {
    timeseries_definition {
      title         = "Filas Principais — Mensagens em Processamento (in-flight)"
      show_legend   = true
      legend_layout = "horizontal"

      request {
        q            = "avg:aws.sqs.approximate_number_of_messages_not_visible{queuename:fcg-production-user-created-events}"
        display_type = "area"
        style {
          palette    = "blue"
          line_type  = "solid"
          line_width = "normal"
        }
        metadata {
          expression = "avg:aws.sqs.approximate_number_of_messages_not_visible{queuename:fcg-production-user-created-events}"
          alias_name = "UserCreated in-flight"
        }
      }

      request {
        q            = "avg:aws.sqs.approximate_number_of_messages_not_visible{queuename:fcg-production-payment-processed-events}"
        display_type = "area"
        style {
          palette    = "green"
          line_type  = "solid"
          line_width = "normal"
        }
        metadata {
          expression = "avg:aws.sqs.approximate_number_of_messages_not_visible{queuename:fcg-production-payment-processed-events}"
          alias_name = "PaymentProcessed in-flight"
        }
      }

      yaxis {
        include_zero = true
      }
    }
    widget_layout {
      x      = 6
      y      = 23
      width  = 6
      height = 3
    }
  }

}

output "datadog_dashboard_url" {
  value       = "https://app.${var.dd_site}/dashboard/${datadog_dashboard.fcg_observability.id}"
  description = "URL do dashboard de observabilidade no Datadog"
}
