locals {
  db_host      = "172.17.0.1"
  db_user      = "postgres"
  db_password  = "uK9$pM4!rL7@qN2#Ws"
  rmq_host     = "172.17.0.1"
  rmq_user     = "fcg"
  rmq_password = "rQ5$$bT8!xW3@kM6#Yx"
  dd_agent_host = "172.17.0.1"

  pg_dd_instances = jsonencode([{
    host                          = "%%host%%"
    port                          = 5432
    username                      = "postgres"
    password                      = "uK9$pM4!rL7@qN2#Ws"
    dbname                        = "postgres"
    collect_activity_metrics      = true
    collect_database_size_metrics = true
  }])

  rmq_dd_instances = jsonencode([{
    rabbitmq_api_endpoint = "http://%%host%%:15672/api/"
    username              = "fcg"
    password              = "rQ5$bT8!xW3@kM6#Yx"
    queues = [
      "fcg-production-user-created-events",
      "fcg-production-payment-processed-events",
    ]
  }])
}

# ── PostgreSQL ────────────────────────────────────────────────────────────────

resource "aws_cloudwatch_log_group" "postgres" {
  name              = "/ecs/${local.name_prefix}-postgres"
  retention_in_days = 7
  tags              = local.common_tags
}

resource "aws_ecs_task_definition" "postgres" {
  family       = "${local.name_prefix}-postgres"
  network_mode = "bridge"

  volume {
    name      = "postgres-data"
    host_path = "/data/postgres/pgdata"
  }

  container_definitions = jsonencode([{
    name      = "postgres"
    image     = "postgres:16-alpine"
    essential = true
    memoryReservation = 128
    portMappings = [{
      containerPort = 5432
      hostPort      = 5432
      protocol      = "tcp"
    }]
    mountPoints = [{
      sourceVolume  = "postgres-data"
      containerPath = "/var/lib/postgresql/data"
      readOnly      = false
    }]
    environment = [
      { name = "POSTGRES_USER",     value = local.db_user },
      { name = "POSTGRES_PASSWORD", value = local.db_password },
      { name = "POSTGRES_DB",       value = "postgres" }
    ]
    dockerLabels = {
      "com.datadoghq.ad.check_names"  = "[\"postgres\"]"
      "com.datadoghq.ad.init_configs" = "[{}]"
      "com.datadoghq.ad.instances"    = local.pg_dd_instances
      "com.datadoghq.ad.logs"         = "[{\"source\":\"postgresql\",\"service\":\"postgres\"}]"
    }
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        awslogs-group         = "/ecs/${local.name_prefix}-postgres"
        awslogs-region        = var.aws_region
        awslogs-stream-prefix = "ecs"
      }
    }
  }])

  tags = local.common_tags
}

resource "aws_ecs_service" "postgres" {
  name                               = "${local.name_prefix}-postgres"
  cluster                            = aws_ecs_cluster.fcg.id
  task_definition                    = aws_ecs_task_definition.postgres.arn
  desired_count                      = 1
  deployment_minimum_healthy_percent = 0
  deployment_maximum_percent         = 100
  tags                               = local.common_tags
}

# ── RabbitMQ ──────────────────────────────────────────────────────────────────

resource "aws_cloudwatch_log_group" "rabbitmq" {
  name              = "/ecs/${local.name_prefix}-rabbitmq"
  retention_in_days = 7
  tags              = local.common_tags
}

resource "aws_ecs_task_definition" "rabbitmq" {
  family       = "${local.name_prefix}-rabbitmq"
  network_mode = "bridge"

  container_definitions = jsonencode([{
    name      = "rabbitmq"
    image     = "rabbitmq:3-management-alpine"
    essential = true
    memoryReservation = 128
    portMappings = [
      { containerPort = 5672,  hostPort = 5672,  protocol = "tcp" },
      { containerPort = 15672, hostPort = 15672, protocol = "tcp" },
    ]
    environment = [
      { name = "RABBITMQ_DEFAULT_USER", value = local.rmq_user },
      { name = "RABBITMQ_DEFAULT_PASS", value = local.rmq_password }
    ]
    dockerLabels = {
      "com.datadoghq.ad.check_names"  = "[\"rabbitmq\"]"
      "com.datadoghq.ad.init_configs" = "[{}]"
      "com.datadoghq.ad.instances"    = local.rmq_dd_instances
      "com.datadoghq.ad.logs"         = "[{\"source\":\"rabbitmq\",\"service\":\"rabbitmq\"}]"
    }
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        awslogs-group         = "/ecs/${local.name_prefix}-rabbitmq"
        awslogs-region        = var.aws_region
        awslogs-stream-prefix = "ecs"
      }
    }
  }])

  tags = local.common_tags
}

resource "aws_ecs_service" "rabbitmq" {
  name                               = "${local.name_prefix}-rabbitmq"
  cluster                            = aws_ecs_cluster.fcg.id
  task_definition                    = aws_ecs_task_definition.rabbitmq.arn
  desired_count                      = 1
  deployment_minimum_healthy_percent = 0
  deployment_maximum_percent         = 100
  tags                               = local.common_tags
}

# ── UsersAPI ──────────────────────────────────────────────────────────────────

resource "aws_cloudwatch_log_group" "users_api" {
  name              = "/ecs/${local.name_prefix}-users-api"
  retention_in_days = 7
  tags              = local.common_tags
}

resource "aws_ecs_task_definition" "users_api" {
  family       = "${local.name_prefix}-users-api"
  network_mode = "bridge"

  container_definitions = jsonencode([{
    name      = "users-api"
    image     = "${aws_ecr_repository.users_api.repository_url}:latest"
    essential = true
    memoryReservation = 192
    portMappings = [{
      containerPort = 8080
      hostPort      = 8080
      protocol      = "tcp"
    }]
    environment = [
      { name = "ASPNETCORE_ENVIRONMENT",   value = "Production" },
      { name = "ConnectionStrings__Users", value = "Host=${local.db_host};Port=5432;Database=users_db;Username=${local.db_user};Password=${local.db_password}" },
      { name = "DD_AGENT_HOST",            value = local.dd_agent_host },
      { name = "DD_TRACE_AGENT_PORT",      value = "8126" },
      { name = "DD_TRACE_ENABLED",         value = "true" },
      { name = "DD_SERVICE",               value = "users-api" },
      { name = "DD_ENV",                   value = var.environment },
      { name = "DD_VERSION",               value = "1.0.0" },
      { name = "DD_LOGS_INJECTION",        value = "true" },
      { name = "DD_RUNTIME_METRICS_ENABLED", value = "true" },
      { name = "CORECLR_ENABLE_PROFILING", value = "1" },
      { name = "CORECLR_PROFILER",         value = "{846F5F1C-F9AE-4B07-969E-05C26BC060D8}" },
      { name = "CORECLR_PROFILER_PATH",    value = "/opt/datadog/linux-musl-x64/Datadog.Trace.ClrProfiler.Native.so" },
      { name = "DD_DOTNET_TRACER_HOME",    value = "/opt/datadog" },
      { name = "LD_PRELOAD",               value = "/opt/datadog/linux-musl-x64/Datadog.Linux.ApiWrapper.x64.so" },
      { name = "RabbitMQ__Host",           value = local.rmq_host },
      { name = "RabbitMQ__Username",       value = local.rmq_user },
      { name = "RabbitMQ__Password",       value = local.rmq_password },
      { name = "Jwt__Key",                 value = var.jwt_key },
      { name = "Jwt__Issuer",              value = "FiapCloudGames" },
      { name = "Jwt__Audience",            value = "FiapCloudGames" }
    ]
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        awslogs-group         = "/ecs/${local.name_prefix}-users-api"
        awslogs-region        = var.aws_region
        awslogs-stream-prefix = "ecs"
      }
    }
  }])

  tags = local.common_tags
}

resource "aws_ecs_service" "users_api" {
  name                               = "${local.name_prefix}-users-api"
  cluster                            = aws_ecs_cluster.fcg.id
  task_definition                    = aws_ecs_task_definition.users_api.arn
  desired_count                      = 1
  deployment_minimum_healthy_percent = 0
  deployment_maximum_percent         = 100
  tags                               = local.common_tags
}

# ── CatalogAPI ────────────────────────────────────────────────────────────────

resource "aws_cloudwatch_log_group" "catalog_api" {
  name              = "/ecs/${local.name_prefix}-catalog-api"
  retention_in_days = 7
  tags              = local.common_tags
}

resource "aws_ecs_task_definition" "catalog_api" {
  family       = "${local.name_prefix}-catalog-api"
  network_mode = "bridge"

  container_definitions = jsonencode([{
    name      = "catalog-api"
    image     = "${aws_ecr_repository.catalog_api.repository_url}:latest"
    essential = true
    memoryReservation = 192
    portMappings = [{
      containerPort = 8080
      hostPort      = 8081
      protocol      = "tcp"
    }]
    environment = [
      { name = "ASPNETCORE_ENVIRONMENT",     value = "Production" },
      { name = "ConnectionStrings__Catalog", value = "Host=${local.db_host};Port=5432;Database=catalog_db;Username=${local.db_user};Password=${local.db_password}" },
      { name = "DD_AGENT_HOST",              value = local.dd_agent_host },
      { name = "DD_TRACE_AGENT_PORT",        value = "8126" },
      { name = "DD_TRACE_ENABLED",           value = "true" },
      { name = "DD_SERVICE",                 value = "catalog-api" },
      { name = "DD_ENV",                     value = var.environment },
      { name = "DD_VERSION",                 value = "1.0.0" },
      { name = "DD_LOGS_INJECTION",          value = "true" },
      { name = "DD_RUNTIME_METRICS_ENABLED", value = "true" },
      { name = "CORECLR_ENABLE_PROFILING",   value = "1" },
      { name = "CORECLR_PROFILER",           value = "{846F5F1C-F9AE-4B07-969E-05C26BC060D8}" },
      { name = "CORECLR_PROFILER_PATH",      value = "/opt/datadog/linux-musl-x64/Datadog.Trace.ClrProfiler.Native.so" },
      { name = "DD_DOTNET_TRACER_HOME",      value = "/opt/datadog" },
      { name = "LD_PRELOAD",                 value = "/opt/datadog/linux-musl-x64/Datadog.Linux.ApiWrapper.x64.so" },
      { name = "RabbitMQ__Host",             value = local.rmq_host },
      { name = "RabbitMQ__Username",         value = local.rmq_user },
      { name = "RabbitMQ__Password",         value = local.rmq_password },
      { name = "Jwt__Key",                   value = var.jwt_key },
      { name = "Jwt__Issuer",                value = "FiapCloudGames" },
      { name = "Jwt__Audience",              value = "FiapCloudGames" }
    ]
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        awslogs-group         = "/ecs/${local.name_prefix}-catalog-api"
        awslogs-region        = var.aws_region
        awslogs-stream-prefix = "ecs"
      }
    }
  }])

  tags = local.common_tags
}

resource "aws_ecs_service" "catalog_api" {
  name                               = "${local.name_prefix}-catalog-api"
  cluster                            = aws_ecs_cluster.fcg.id
  task_definition                    = aws_ecs_task_definition.catalog_api.arn
  desired_count                      = 1
  deployment_minimum_healthy_percent = 0
  deployment_maximum_percent         = 100
  tags                               = local.common_tags
}
