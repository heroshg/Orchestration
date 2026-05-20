# FiapCloudGames — Orquestração

Repositório central de orquestração da plataforma **FiapCloudGames**: Docker Compose para desenvolvimento local, manifests Kubernetes (Kustomize + script imperativo) e infraestrutura AWS como código (Terraform).

---

## Sumário

- [Quick Start (local)](#quick-start-local)
- [Arquitetura Local](#arquitetura-local)
- [Arquitetura AWS (Fase 3)](#arquitetura-aws-fase-3)
- [Stack de Tecnologias](#stack-de-tecnologias)
- [Como testar a aplicação](#como-testar-a-aplicação)
- [Deploy no Kubernetes local](#deploy-no-kubernetes-local)
- [Deploy AWS (Terraform)](#deploy-aws-terraform)
- [Observabilidade — Datadog APM](#observabilidade--datadog-apm)
- [Taskfile — referência das tasks](#taskfile--referência-das-tasks)
- [Repositórios dos microsserviços](#repositórios-dos-microsserviços)

---

## Quick Start (local)

**Pré-requisitos** — instale uma vez por máquina:
- [Docker Desktop](https://docs.docker.com/desktop/) com Compose v2
- [go-task](https://taskfile.dev/installation/) — `winget install Task.Task` · `brew install go-task` · `curl -sL https://taskfile.dev/install.sh | sh`
- (opcional, só para o caminho K8s) [kind](https://kind.sigs.k8s.io/) + `kubectl`

**Subir o ambiente:**

```bash
task up        # init (chaves, lambda, .env) + docker compose up. ~2min na 1ª vez
task test      # smoke test 6/6 contra http://localhost:8080
```

Pronto. Entrypoint único em **http://localhost:8080/swagger/** — mesma URL, rotas e validação JWT que o AWS API Gateway em produção. `task up` é idempotente: re-rodar pula etapas já feitas (chaves geradas, Lambda já buildada, etc).

### O que sobe no Compose

11 containers, ~3 GB de RAM: `users-postgres`, `catalog-postgres`, `payments-postgres`, `redis`, `rabbitmq`, `localstack`, `users-api`, `catalog-api`, `payments-api`, `api-gateway` (Kong), `swagger-ui` — mais `datadog-agent` (opcional se você setar `DD_API_KEY`).

### Comandos mais usados

```bash
task                            # lista as 32 tasks
task watch                      # hot-reload: rebuild auto ao editar .cs nas APIs
task logs svc=api-gateway       # tail dos logs de um serviço
task rebuild svc=users-api      # rebuild + recreate uma API após mudar código
task test                       # smoke test local (6 checagens)
task test:aws                   # smoke test contra o API Gateway de produção
task k8s:up                     # mesma stack, mas em Kubernetes (kind)
task aws:deploy svc=users-api   # build + push ECR + redeploy ECS de uma API
task aws:status                 # tabela com runningCount de cada service ECS
task down                       # para tudo
task clean                      # fresh start (apaga volumes + .keys + lambda zip)
```

> **Setup manual** (se não quiser instalar go-task): `cp .env.example .env` → `bash infrastructure/scripts/generate-jwt-keys.sh --inject-env` → `bash infrastructure/localstack/build-lambda.sh` → `docker compose up -d --build`. O Taskfile só encapsula esses passos com idempotência e cross-platform.

---

## Arquitetura Local

```
                                  ┌───────────────────────────────────┐
                                  │           Cliente / curl           │
                                  │       http://localhost:8080        │
                                  └────────────────┬───────────────────┘
                                                   │
                                                   ▼
                         ┌─────────────────────────────────────────────┐
                         │           Kong API Gateway (3.7)            │
                         │       DB-less · plugin JWT (RS256)          │
                         │  Rotas + CORS + Rate-limit (50 rps)         │
                         │  Espelha api_gateway.tf (HTTP API v2)       │
                         └──┬──────────────────┬──────────────────┬────┘
                            │                  │                  │
              ┌─────────────▼──┐  ┌────────────▼────┐  ┌──────────▼─────┐
              │   UsersAPI     │  │   CatalogAPI     │  │  Swagger UI    │
              │   :5001        │  │   :5002          │  │  spec curado   │
              │ JWT signing    │  │ JWT validation   │  └────────────────┘
              │ JWKS endpoint  │  │                  │
              └──┬──────────┬──┘  └──┬──────────┬────┘
                 │          │        │          │
                 ▼          ▼        ▼          ▼
        ┌──────────────┐  ┌──────────────┐  ┌──────────────┐
        │ users-       │  │ Redis 7.2    │  │ catalog-     │
        │ postgres     │  │ (cache)      │  │ postgres     │
        └──────────────┘  └──────────────┘  └──────────────┘
                                                  │ publica OrderPlaced
                                                  ▼
                              ┌────────────────────────────────────────┐
                              │            RabbitMQ 3.13               │
                              └───────────────┬────────────────────────┘
                                              │ consome
                                              ▼
                            ┌────────────────────────────────┐
                            │         PaymentsAPI :5003      │
                            │   simula pagamento (90% ok)    │
                            └──┬───────────────────┬─────────┘
                               │                   │
                               ▼                   │ publica
                       ┌──────────────┐            │ PaymentProcessed
                       │ payments-    │            ▼
                       │ postgres     │   ┌──────────────────────────────┐
                       └──────────────┘   │       LocalStack 3.8         │
                                          │  emula AWS: SQS, DynamoDB,   │
                                          │  Lambda, S3, CloudWatch      │
                                          │  ┌────────────────────────┐  │
                                          │  │ Lambda Notifications   │  │
                                          │  │ (.NET 8 do .zip local) │  │
                                          │  └───────────┬────────────┘  │
                                          │              ▼               │
                                          │  ┌────────────────────────┐  │
                                          │  │  DynamoDB              │  │
                                          │  │  fcg-local-            │  │
                                          │  │  notifications         │  │
                                          │  └────────────────────────┘  │
                                          └──────────────────────────────┘

                          ┌─────────────────────────────────────────────┐
                          │   Datadog Agent (DD_API_KEY) — opcional     │
                          │   APM + logs + métricas de todos containers │
                          └─────────────────────────────────────────────┘
```

**Pontos-chave:**
- **Kong** substitui o AWS API Gateway HTTP API v2 localmente — mesmas rotas, CORS, throttling e validação JWT (RS256) usando a chave pública RSA exposta pela UsersAPI.
- **LocalStack** emula SQS + DynamoDB + Lambda + S3 + CloudWatch Logs. O fluxo `SQS → Lambda → DynamoDB` roda end-to-end sem AWS.
- **JWT** é assinado pela UsersAPI (chave privada) e validado em três pontos: Kong (no gateway), Catalog/Payments API ([Authorize]), e em produção pelo AWS API Gateway via JWKS.

---

## Arquitetura AWS (Fase 3)

```
              ┌─────────────────────────────────┐
              │       AWS API Gateway v2         │
              │   CORS + Throttling + JWT auth   │
              └────────────┬────────────┬────────┘
                           │            │
        ┌──────────────────▼──┐    ┌────▼─────────────────┐
        │   UsersAPI (ECS)    │    │   CatalogAPI (ECS)   │
        │  ┌───────────────┐  │    │  ┌────────────────┐  │
        │  │ PostgreSQL    │  │    │  │ PostgreSQL     │  │
        │  └───────────────┘  │    │  └────────────────┘  │
        │  ┌───────────────┐  │    │  ┌────────────────┐  │
        │  │ Redis Cache   │◄─┼────┼─►│ Redis Cache    │  │
        │  └───────────────┘  │    │  └────────────────┘  │
        └──────────┬──────────┘    └────────┬─────────────┘
                   │ publica                │
                   ▼                        ▼
        ┌─────────────────┐      ┌─────────────────────────┐
        │ SQS Queue       │      │ PaymentsAPI (ECS)       │
        │ UserCreated     │      │   └─► SQS Queue         │
        └────────┬────────┘      │       PaymentProcessed  │
                 │               └────────────┬────────────┘
                 └──────────┬─────────────────┘
                            │ trigger
                            ▼
              ┌─────────────────────────────────┐
              │  AWS Lambda — Notifications     │
              │  (.NET 8 arm64) → DynamoDB      │
              └─────────────────────────────────┘
```

| Fase | Descrição |
|------|-----------|
| Fase 1 | Monolito .NET 8, banco único |
| Fase 2 | Microsserviços + RabbitMQ + Kustomize |
| **Fase 3** | **AWS API Gateway v2, ECS, Lambda, SQS, DynamoDB, Redis, Datadog** |

---

## Stack de Tecnologias

### API Gateway
| Ambiente | Implementação | Auth |
|---|---|---|
| Local (compose / k8s) | **Kong 3.7 OSS** (DB-less, `infrastructure/kong/kong.yml`) | Plugin `jwt` (RS256, chave estática) |
| AWS | **API Gateway HTTP API v2** (`infrastructure/terraform/api_gateway.tf`) | Authorizer JWT nativo (via JWKS endpoint da UsersAPI) |

Ambos espelham as mesmas rotas:

| Rota | Auth |
|---|---|
| `POST /api/users` | público (cadastro) |
| `POST /api/users/login` | público (autenticação) |
| `GET /.well-known/*` | público (JWKS / OIDC discovery) |
| `GET /swagger/*` | público (somente local) |
| `ANY /api/users/{path}` | JWT |
| `GET\|POST /api/games` | JWT |
| `ANY /api/games/{path}` | JWT |

### Serverless — NotificationsLambda
- **AWS Lambda** (.NET 8 arm64) — trigger Amazon SQS (EventSourceMapping)
- **DynamoDB** para log de notificações (persistência poliglota)
- IaC: `infrastructure/terraform/lambda.tf`
- Local: emulada via LocalStack (`infrastructure/localstack/`)

### Mensageria
| Ambiente | Broker |
|----------|--------|
| Local | RabbitMQ 3.13 (entre APIs) + LocalStack SQS (para Lambda) |
| AWS | Amazon SQS para tudo |

### Cache
- **Redis 7.2** via `StackExchange.Redis` / `IDistributedCache`
- Local: container · AWS: ElastiCache

### Persistência poliglota
| Serviço | Banco |
|---------|-------|
| UsersAPI, CatalogAPI, PaymentsAPI | PostgreSQL |
| NotificationsLambda | DynamoDB |

### Observabilidade — Datadog APM
- Datadog Agent (DaemonSet K8s / container Compose) + .NET Tracer + Lambda Extension
- 3 pilares cobertos: métricas, logs (com `dd.trace_id` injetado), traces distribuídos
- Toda configuração em `k8s/base/datadog-agent.yaml` e `infrastructure/terraform/datadog.tf`

---

## Como testar a aplicação

Todos os exemplos usam o entrypoint do **Kong** local (`http://localhost:8080`), que é a mesma forma usada em produção via AWS API Gateway.

### 1. Smoke test — gateway está validando JWT?

```bash
curl -i http://localhost:8080/api/games        # → 401 Unauthorized (sem token)
curl -i http://localhost:8080/.well-known/jwks.json  # → 200 OK (público)
```

### 2. Cadastrar usuário (público)

```bash
curl -X POST http://localhost:8080/api/users \
  -H "Content-Type: application/json" \
  -d '{"name":"Demo","email":"demo@fgc.com","password":"Demo@123"}'
```

### 3. Login e captura do token

```bash
TOKEN=$(curl -s -X POST http://localhost:8080/api/users/login \
  -H "Content-Type: application/json" \
  -d '{"email":"admin@fgc.com","password":"Admin@123"}' | jq -r .token)
echo "$TOKEN"
```

> **Credencial seed:** `admin@fgc.com` / `Admin@123` (role `Admin`) — criado automaticamente pela UsersAPI no startup.

> **Validade do token:** 15 minutos (configurável via env `Jwt__ExpirationMinutes`).

### 4. Listar e criar jogos (autenticado)

```bash
# GET — qualquer usuário autenticado
curl http://localhost:8080/api/games -H "Authorization: Bearer $TOKEN"

# POST — só Admin
curl -X POST http://localhost:8080/api/games \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"name":"Stellar Odyssey","description":"Space RPG","price":59.90}'
```

### 5. Fluxo de compra (assíncrono, dispara Lambda)

```bash
# Listar jogos para pegar um gameId
GAME_ID=$(curl -s http://localhost:8080/api/games -H "Authorization: Bearer $TOKEN" | jq -r '.[0].id')

# Disparar compra — responde 202 Accepted, processamento é async via RabbitMQ → SQS → Lambda
curl -X POST http://localhost:8080/api/games/purchase \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d "{\"gameId\":\"$GAME_ID\"}"

# Após ~5s, ver a notificação registrada no DynamoDB (via LocalStack)
docker exec fcg-localstack awslocal dynamodb scan \
  --table-name fcg-local-notifications --query 'Items[*].message.S'

# Logs da Lambda
docker exec fcg-localstack awslocal logs filter-log-events \
  --log-group-name /aws/lambda/fcg-local-notifications --limit 20 \
  --query 'events[].message' --output text
```

### 6. Swagger UI

http://localhost:8080/swagger/ — spec único curado descrevendo só o contrato exposto pelo gateway (sem detalhes internos).

### Outras URLs úteis

| URL | Uso |
|---|---|
| http://localhost:8080 | **Entrypoint Kong** (use este!) |
| http://localhost:5001/swagger | UsersAPI direta (debug) |
| http://localhost:5002/swagger | CatalogAPI direta (debug) |
| http://localhost:5003/health | PaymentsAPI direta (debug) |
| http://localhost:15672 | RabbitMQ Management (`$RABBITMQ_USER` / `$RABBITMQ_PASSWORD`) |
| http://localhost:4566 | LocalStack edge port |

### Inspecionar recursos AWS locais

```bash
docker exec fcg-localstack awslocal sqs list-queues
docker exec fcg-localstack awslocal sqs receive-message \
  --queue-url http://localhost:4566/000000000000/fcg-local-user-created-events
docker exec fcg-localstack awslocal dynamodb scan --table-name fcg-local-notifications
```

---

## Deploy no Kubernetes local

Roda a mesma stack do Compose dentro de um cluster Kubernetes — UsersAPI + CatalogAPI + PaymentsAPI atrás do Kong, com Postgres, Redis, RabbitMQ e LocalStack (SQS/DynamoDB/S3) dentro do cluster.

> **Limitação conhecida:** a NotificationsLambda **não roda no K8s** (LocalStack não consegue emular Lambda dentro de cluster por causa de container-in-container). Para validar o fluxo SQS → Lambda → DynamoDB end-to-end, use Docker Compose. No K8s as filas SQS são criadas e populadas normalmente — só o consumer Lambda fica off.

### Pré-requisitos

- **Cluster K8s local** — use uma das opções:
  - [`kind`](https://kind.sigs.k8s.io/) (recomendado — config pronta em `k8s/kind-config.yaml`)
  - `minikube`
  - Kubernetes do Docker Desktop (Settings → Kubernetes → Enable)
- `kubectl` no PATH
- Docker (para buildar as imagens das APIs)

### Passo 1 — criar o cluster (kind)

```bash
kind create cluster --name fcg --config k8s/kind-config.yaml
kubectl config use-context kind-fcg
kubectl get nodes                  # deve mostrar o node fcg-control-plane Ready
```

> Pulando: se você já usa Docker Desktop K8s ou minikube, só garanta que o contexto correto está ativo com `kubectl config current-context`.

### Passo 2 — buildar as imagens locais

```bash
# A partir de Orchestration/
docker build -t users-api:latest    ../UsersAPI
docker build -t catalog-api:latest  ../CatalogAPI
docker build -t payments-api:latest ../PaymentsAPI
docker build -t fcg-localstack:local infrastructure/localstack/

# Empacotar a Lambda (mesmo que o K8s não rode, o LocalStack tenta carregar
# o .zip no startup — sem ele o init falha)
bash infrastructure/localstack/build-lambda.sh   # Windows: pwsh build-lambda.ps1
```

**Carregar as imagens no cluster:**

```bash
# kind — única opção que precisa do load explícito
kind load docker-image users-api:latest catalog-api:latest payments-api:latest \
                       fcg-localstack:local --name fcg

# minikube
minikube image load users-api:latest && minikube image load catalog-api:latest && \
minikube image load payments-api:latest && minikube image load fcg-localstack:local

# Docker Desktop K8s — não precisa, já compartilha o daemon
```

### Passo 3 — preparar os secrets

```bash
# Gerar par RSA (mesmo do .env do Compose — pode reutilizar se já gerou)
bash infrastructure/scripts/generate-jwt-keys.sh

# Copiar cada template e editar com os valores reais
for f in postgres-secrets rabbitmq-secret redis-secret datadog-secret \
         users-api-secret catalog-api-secret payments-api-secret; do
  cp "k8s/base/$f.yaml.example" "k8s/base/$f.yaml"
done

# Edite k8s/base/users-api-secret.yaml, catalog-api-secret.yaml e
# payments-api-secret.yaml colando JWT_RSA_PUBLIC_KEY (base64) — UsersAPI
# também precisa de JWT_RSA_PRIVATE_KEY.
```

### Passo 4 — instalar o ingress controller (uma vez por cluster)

```bash
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.10.1/deploy/static/provider/cloud/deploy.yaml
kubectl wait --namespace ingress-nginx \
    --for=condition=ready pod \
    --selector=app.kubernetes.io/component=controller \
    --timeout=180s
```

### Passo 5 — aplicar o overlay local

```bash
kubectl apply -k k8s/overlays/local --load-restrictor=LoadRestrictionsNone
```

A flag `--load-restrictor=LoadRestrictionsNone` é necessária porque o `configMapGenerator` do `base/` referencia arquivos em `infrastructure/nginx/` (compartilhados com o Compose — fonte única da verdade). O overlay cria o namespace `fcg`, todos os Secrets/ConfigMaps, Postgres × 3, RabbitMQ, Redis, LocalStack, as 3 APIs, o api-gateway (Nginx), o Swagger UI e o Ingress.

> **Datadog mora só em prod.** O overlay `local/` não inclui agent nem `DD_API_KEY` — as APIs continuam exportando as env vars `DD_*` (vêm do base), mas como não há agent escutando em `DD_AGENT_HOST` o tracer silenciosamente desiste. Zero configuração extra para dev.

### Passo 6 — esperar os pods + acessar

```bash
kubectl get pods -n fcg -w
# Aguarde até todos ficarem Running. UsersAPI/CatalogAPI/PaymentsAPI podem
# levar ~30s no primeiro start (rodam migrations do Entity Framework).

# Acesso via Ingress (já publica em http://localhost)
#   http://localhost/                Swagger UI agregado
#   http://localhost/users/          UsersAPI
#   http://localhost/catalog/        CatalogAPI
#   http://localhost/payments/       PaymentsAPI
```

### Passo 7 — testar

```bash
# Smoke
curl -i http://localhost/catalog/api/games            # → 401 (sem token)
curl -i http://localhost/users/.well-known/jwks.json  # → 200

# Login com a credencial seed
TOKEN=$(curl -s -X POST http://localhost/users/api/users/login \
  -H "Content-Type: application/json" \
  -d '{"email":"admin@fgc.com","password":"Admin@123"}' | jq -r .token)

curl http://localhost/catalog/api/games -H "Authorization: Bearer $TOKEN"
```

Demais exemplos (criar jogo, fluxo de compra) na seção [Como testar a aplicação](#como-testar-a-aplicação) — basta trocar `http://localhost:8080` por `http://localhost`.

### Acessos diretos (debug)

```bash
kubectl port-forward svc/users-api    5001:8080 -n fcg
kubectl port-forward svc/catalog-api  5002:8080 -n fcg
kubectl port-forward svc/payments-api 5003:8080 -n fcg
kubectl port-forward svc/localstack   4566:4566 -n fcg

# Logs
kubectl logs -f -n fcg deploy/api-gateway
kubectl logs -f -n fcg deploy/users-api
```

### Atualizar uma API após mudança de código

```bash
docker build -t users-api:latest ../UsersAPI
kind load docker-image users-api:latest --name fcg          # se for kind
kubectl rollout restart deploy/users-api -n fcg
```

### Cleanup

```bash
# Deletar só o namespace (mantém o cluster)
kubectl delete namespace fcg

# Ou destruir o cluster inteiro (kind)
kind delete cluster --name fcg
```

### Estrutura do diretório `k8s/`

```
k8s/
├── base/                          # manifests canônicos (Kustomize)
│   ├── kustomization.yaml         # gera kong-config + swagger-spec + datadog-checks
│   ├── namespace.yaml · network-policies.yaml
│   ├── *-postgres.yaml + secrets · rabbitmq.yaml + secret · redis.yaml + secret
│   ├── users-api.yaml · catalog-api.yaml · payments-api.yaml (+ secrets)
│   ├── api-gateway.yaml           # Kong 3.7 (Deployment + Service + ConfigMap entrypoint)
│   ├── swagger-ui.yaml            # mount do openapi.yaml via ConfigMap
│   └── datadog-agent.yaml + secret
├── overlays/
│   ├── local/                     # base + LocalStack + sqs-secrets
│   └── prod/                      # template — usa AWS gerenciado
├── *.yaml                         # manifests equivalentes para bootstrap.sh
├── bootstrap.sh / bootstrap.ps1   # caminho imperativo (sem Kustomize)
└── kind-config.yaml               # config exemplo para o cluster kind
```

> **EKS na AWS não é usado** — em produção as APIs rodam em ECS sobre EC2 (Terraform). O cluster K8s só serve para dev local.

---

## Deploy AWS (Terraform)

Infraestrutura em `infrastructure/terraform/` — provider AWS + Datadog, modularizada por recurso.

### O que é provisionado

| Recurso | Descrição |
|---|---|
| `aws_apigatewayv2_api` + routes + JWT authorizer | API Gateway HTTP API v2 com CORS, throttling e validação JWT |
| `aws_ecs_cluster` + services | UsersAPI, CatalogAPI, PaymentsAPI rodando em ECS sobre EC2 |
| `aws_ecr_repository` (×3) | Imagens das APIs |
| `aws_sqs_queue` + DLQ (×2) | Filas `user-created-events` e `payment-processed-events` |
| `aws_lambda_function` + event_source_mapping | NotificationsLambda + Datadog Extension |
| `aws_dynamodb_table` | `fcg-{env}-notifications` (TTL + GSI) |
| `aws_s3_bucket` | Bucket de deploy da Lambda |
| `aws_iam_role` / policies | Least privilege para Lambda + ECS |
| `datadog_dashboard` / `datadog_monitor` | Dashboards e monitores |

### Deploy completo

```bash
cd infrastructure/terraform

cp terraform.tfvars.example terraform.tfvars
# preencha: jwt_rsa_private_key, jwt_rsa_public_key, db_password,
#          rmq_password, dd_api_key, etc.

# Script automatizado — faz dotnet publish da Lambda + terraform apply
export DD_API_KEY=xxxxxxxxxxxx
export AWS_REGION=us-east-1
bash deploy.sh                # Windows: pwsh deploy.ps1
```

### Deploy só do API Gateway / ECS task def (após mudança de env var)

```bash
# Quando muda só task def da UsersAPI (ex: env var nova)
terraform apply \
  -target=aws_ecs_task_definition.users_api \
  -target=aws_ecs_service.users_api

# Quando muda código (rebuild + push da imagem)
aws ecr get-login-password --region us-east-1 | docker login --username AWS \
  --password-stdin <accountId>.dkr.ecr.us-east-1.amazonaws.com
docker build -t <accountId>.dkr.ecr.us-east-1.amazonaws.com/users-api:latest ../../UsersAPI
docker push <accountId>.dkr.ecr.us-east-1.amazonaws.com/users-api:latest
aws ecs update-service --cluster fcg-production-cluster \
  --service fcg-production-users-api --force-new-deployment
```

### Outputs úteis

```bash
terraform output -raw api_gateway_url               # entrypoint público
terraform output -raw users_api_url                 # acesso direto (debug)
terraform output -raw user_created_queue_url        # input para users-api
terraform output -raw payment_processed_queue_url   # input para payments-api
```

---

## Observabilidade — Datadog APM

### Stack
| Componente | Função |
|---|---|
| Datadog Agent 7.58 (DaemonSet/container) | Recebe traces APM (8126), DogStatsD (8125), coleta logs por autodiscovery |
| Datadog .NET Tracer (`Datadog.Trace.Bundle`) | Auto-instrumentation: ASP.NET Core, EF Core, Npgsql, Redis, MassTransit, HttpClient |
| Datadog Lambda Extension (layer ARM64) | Envia traces/logs/métricas direto da Lambda (sem CloudWatch) |

### API key — onde configurar

| Ambiente | Onde |
|---|---|
| Docker Compose | `.env` — `DD_API_KEY=` e `DD_SITE=` (ex.: `us5.datadoghq.com`) |
| Kubernetes | `cp k8s/base/datadog-secret.yaml.example k8s/base/datadog-secret.yaml` + edite |
| AWS Lambda | `export TF_VAR_dd_api_key=...` antes do `terraform apply` |

Para rodar **sem Datadog** localmente, comente o serviço `datadog-agent` no `docker-compose.yml` e remova as envs `DD_*` das APIs.

### Dashboards
- https://app.\<seu-site\>.datadoghq.com/
- APM → Services: `users-api`, `catalog-api`, `payments-api`, `fcg-local-notifications`
- APM → Service Map: topologia completa (Postgres, Redis, RabbitMQ, SQS, DynamoDB)
- Trace de compra: `service:catalog-api resource_name:POST /api/games/purchase`

---

## Taskfile — referência das tasks

`task` (go-task) é o orquestrador. Todas as tasks são definidas em `Taskfile.yml`, idempotentes, e listáveis com `task --list-all`.

### Setup (one-shot, idempotente)

| Task | Descrição |
|---|---|
| `task init` | Roda init:env + init:keys + init:lambda (skip do que já está pronto) |
| `task init:env` | `cp .env.example .env` se não existir |
| `task init:keys` | Gera par RSA e injeta `JWT_RSA_*` no `.env` (skip se já preenchido) |
| `task init:lambda` | Empacota NotificationsLambda; reroda só se `.cs` mudou |

### Dev local (Compose)

| Task | Descrição |
|---|---|
| `task up` | Sobe a stack inteira (com init automático antes) |
| `task watch` | Hot-reload — rebuild automático ao editar código das APIs |
| `task ps` / `task logs svc=…` | Status / tail de logs |
| `task rebuild svc=…` | Rebuild + recreate de um serviço (`users-api`, `catalog-api`, `payments-api`) |
| `task restart svc=…` / `task shell svc=…` | Restart simples / shell num container |
| `task test` | Smoke test (10 checagens contra http://localhost:8080) |
| `task down` / `task clean` | Para containers / fresh start (remove volumes + .keys + lambda zip) |

### Kubernetes local (kind)

| Task | Descrição |
|---|---|
| `task k8s:up` | Cluster kind + build/load imagens + secrets do .env + apply Kustomize |
| `task k8s:cluster` | Cria cluster kind 'fcg' (skip se existe) |
| `task k8s:images` | Build das 4 imagens + `kind load` |
| `task k8s:secrets` | Cria os 7 Secrets do namespace a partir do `.env` |
| `task k8s:forward` | Port-forward do Kong em `:8080` |
| `task k8s:rollout svc=…` | Rebuild + load + rollout restart de uma API |
| `task k8s:pods` / `task k8s:logs app=…` | Status / logs |
| `task k8s:down` / `task k8s:nuke` | Remove namespace / destrói cluster |

### AWS — dia-a-dia de produção

| Task | Descrição |
|---|---|
| `task aws:deploy svc=users-api` | ECR login + build + push + ECS force-new-deployment + wait stable |
| `task aws:status` | Tabela com desiredCount/runningCount dos 3 services ECS |
| `task aws:logs svc=…` | `aws logs tail` do CloudWatch group da API |
| `task aws:url` | Imprime o URL do API Gateway |
| `task aws:plan -- -target=…` | `terraform plan` com argumentos passados |
| `task aws:terraform -- -target=…` | `terraform apply` com argumentos passados |
| `task test:aws` | Smoke test contra a URL real do API Gateway AWS |

### Scripts (chamados pelas tasks, mas podem rodar diretos)

| Script | Quando usar diretamente |
|---|---|
| `infrastructure/scripts/generate-jwt-keys.sh [--inject-env] [--force]` | Regerar chaves RSA |
| `infrastructure/scripts/k8s-secrets-from-env.sh` | Reaplicar secrets k8s após mudar `.env` |
| `infrastructure/scripts/smoke-test.sh <URL>` | Testar qualquer endpoint do gateway |
| `infrastructure/localstack/build-lambda.{sh,ps1}` | Recompilar Lambda manualmente |
| `infrastructure/localstack/init-aws.sh` | (auto — init do container LocalStack) |
| `infrastructure/kong/entrypoint.sh` | (auto — entrypoint do Kong) |
| `infrastructure/terraform/deploy.{sh,ps1}` | Deploy AWS completo (Lambda + Terraform) |
| `k8s/bootstrap.{sh,ps1}` | Deploy K8s imperativo (alternativa ao `task k8s:up`) |

---

## Contratos de Eventos

| Evento | Produtor | Consumidores |
|---|---|---|
| `UserCreatedEvent(UserId, Name, Email)` | UsersAPI | Lambda (via SQS) |
| `OrderPlacedEvent(OrderId, UserId, UserEmail, GameId, GameName, Price)` | CatalogAPI | PaymentsAPI (via RabbitMQ/SQS) |
| `PaymentProcessedEvent(OrderId, UserId, …, Status)` | PaymentsAPI | CatalogAPI, Lambda (via SQS) |

---

## Repositórios dos microsserviços

| Serviço | Repositório |
|---|---|
| UsersAPI | [heroshg/UsersAPI](https://github.com/heroshg/UsersAPI) |
| CatalogAPI | [heroshg/CatalogAPI](https://github.com/heroshg/CatalogAPI) |
| PaymentsAPI | [heroshg/PaymentsAPI](https://github.com/heroshg/PaymentsAPI) |
| NotificationsLambda | [heroshg/NotificationsAPI](https://github.com/heroshg/NotificationsAPI) |
