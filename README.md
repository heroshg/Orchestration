# FiapCloudGames — Orquestração

Plataforma de microsserviços .NET 8 com Postgres, RabbitMQ, Redis e LocalStack
(SQS + Lambda + DynamoDB + S3). Roda local em **Docker Compose** ou
**Kubernetes**. Produção em AWS (ECS + API Gateway v2 + SQS + Lambda).

---

## Arquitetura

```
                          ┌────────────────────────────────┐
                          │     Cliente (http://localhost) │
                          └───────────────┬────────────────┘
                                          ▼
                          ┌────────────────────────────────┐
                          │      API Gateway (Kong 3.7)    │
                          │   CORS + JWT (RS256) + rotas   │
                          └──┬──────────────┬──────────────┘
                             │              │
                  ┌──────────▼───┐   ┌──────▼───────┐    ┌──────────────┐
                  │   UsersAPI   │   │  CatalogAPI  │◄──►│ PaymentsAPI  │
                  │  Postgres    │   │  Postgres    │    │  Postgres    │
                  │  + Redis     │   │  + Redis     │    │  (eventos    │
                  │  + JWKS      │   │              │    │   RabbitMQ)  │
                  └──────┬───────┘   └──────┬───────┘    └──────┬───────┘
                         │ UserCreated     │ OrderPlaced       │ PaymentProcessed
                         │                 │                   │
                         ▼                 ▼                   ▼
                  ┌──────────────────────────────────────────────────┐
                  │      LocalStack (SQS + DynamoDB + Lambda + S3)   │
                  │   ┌────────────────────┐  ┌──────────────────┐   │
                  │   │ Notifications λ    │─►│  fcg-notifications│   │
                  │   │ (.NET 8 arm64)     │  │  (DynamoDB)       │   │
                  │   └────────────────────┘  └──────────────────┘   │
                  └──────────────────────────────────────────────────┘
```

**Eventos:**

| Evento | Produtor | Consumidor |
|---|---|---|
| `UserCreatedEvent` | UsersAPI | Notifications λ (via SQS) |
| `OrderPlacedEvent` | CatalogAPI | PaymentsAPI (via RabbitMQ) |
| `PaymentProcessedEvent` | PaymentsAPI | CatalogAPI, Notifications λ |

**Microsserviços** — cada um em seu próprio repositório:
[UsersAPI](https://github.com/heroshg/UsersAPI) ·
[CatalogAPI](https://github.com/heroshg/CatalogAPI) ·
[PaymentsAPI](https://github.com/heroshg/PaymentsAPI) ·
[NotificationsLambda](https://github.com/heroshg/NotificationsLambda) (função serverless)

---

## Stack escolhida

| Camada | Tecnologia | Onde / por quê |
|---|---|---|
| Runtime | .NET 8 | APIs e Lambda |
| API Gateway | Kong 3.7 (local) / AWS API Gateway v2 (prod) | Roteamento + JWT RS256 |
| Persistência relacional | PostgreSQL — **um banco por serviço** | Isolamento de dados |
| Cache | Redis (`IDistributedCache`) | Cache-aside em `UsersAPI.GetUserById` e `CatalogAPI.GetAllGames` |
| Mensageria síncrona do domínio | RabbitMQ + MassTransit (Saga + EF Outbox) | `OrderPlacedEvent`, `PaymentProcessedEvent`, `OrderCancelledEvent` |
| Mensageria assíncrona p/ notificações | AWS SQS (+ DLQ) | `UserCreatedEvent`, `PaymentProcessedEvent` |
| NoSQL | AWS DynamoDB | Log de notificações enviadas (TTL 90d) |
| Função serverless | AWS Lambda (.NET 8 arm64) | Consome SQS → grava no DynamoDB |
| Observabilidade | **Datadog** (APM + Logs + AWS integration) | Stack escolhida da Fase 3. Tracer .NET injetado via Dockerfile (`/opt/datadog`); agent rodando em ECS / k8s sidecar; dashboards + monitors versionados via Terraform (`infrastructure/terraform/datadog*.tf`) |
| Infra-as-code | Terraform | `infrastructure/terraform/` |
| Orquestração local | Docker Compose + LocalStack | SQS / Lambda / DynamoDB / S3 emulados |
| Orquestração k8s | Manifesto flat por ambiente (`k8s-dev.yaml` / `k8s-prod.yaml`) | Um arquivo por ambiente; `kubectl apply -f` direto |

---

## Rodando local — Docker Compose

**Pré-requisitos:** Docker Desktop com Compose v2.

```bash
cp .env.example .env
bash infrastructure/scripts/generate-jwt-keys.sh --inject-env
bash infrastructure/localstack/build-lambda.sh        # Windows: .\build-lambda.ps1
docker compose up -d --build
```

Pronto — entrypoint em **http://localhost:8080/swagger/**.

**Credencial seed:** `admin@fgc.com` / `Admin@123` (role `Admin`).

**Smoke test:**

```bash
curl -i http://localhost:8080/api/games                # → 401 sem token

TOKEN=$(curl -s -X POST http://localhost:8080/api/users/login \
  -H "Content-Type: application/json" \
  -d '{"email":"admin@fgc.com","password":"Admin@123"}' | jq -r .token)

curl http://localhost:8080/api/games -H "Authorization: Bearer $TOKEN"
```

**Outras URLs úteis:**

| URL | Uso |
|---|---|
| http://localhost:8080/swagger/ | Swagger UI agregado |
| http://localhost:5001/swagger | UsersAPI direta (debug) |
| http://localhost:5002/swagger | CatalogAPI direta (debug) |
| http://localhost:15672 | RabbitMQ Management |
| http://localhost:4566 | LocalStack edge port |

**Derrubar:**

```bash
docker compose down -v
```

---

## Kubernetes — DEV (cluster local)

**Pré-requisitos:** kind + kubectl instalados.

### 1. Criar o cluster

```bash
kind create cluster --config kind-cluster.yaml
```

### 2. Build e carga das imagens no cluster

```bash
# A partir de Orchestration/
docker build -t users-api:dev    ../UsersAPI
docker build -t catalog-api:dev  ../CatalogAPI
docker build -t payments-api:dev ../PaymentsAPI
docker build -t fcg-localstack:local infrastructure/localstack/

kind load docker-image users-api:dev catalog-api:dev payments-api:dev fcg-localstack:local
```

### 3. Preencher os segredos

Edite `k8s-dev.yaml` e substitua todos os `CHANGE_ME` antes de aplicar:

| Campo | Como obter |
|---|---|
| `Jwt__RsaPrivateKey` / `Jwt__RsaPublicKey` | `bash infrastructure/scripts/generate-jwt-keys.sh` |
| `postgres-secret.password` | senha local à sua escolha |
| `rabbitmq-secret.RABBITMQ_DEFAULT_PASS` | senha local à sua escolha |
| `redis-secret.REDIS_PASSWORD` | senha local à sua escolha |
| `users-api-secret` / `catalog-api-secret` / `payments-api-secret` | preencher com as senhas acima |

Os secrets SQS (`users-api-sqs`, `payments-api-sqs`) já apontam para o LocalStack — não precisa alterar.

### 4. Aplicar

`k8s-dev.yaml` usa `${VAR}` para todos os segredos — os valores vêm do `.env`:

```bash
# Linux / macOS / Git Bash
set -a && source .env && set +a
envsubst < k8s-dev.yaml | kubectl apply -f -
```

```powershell
# PowerShell
Get-Content .env | ForEach-Object {
    if ($_ -match '^([^#][^=]+)=(.+)$') { [System.Environment]::SetEnvironmentVariable($Matches[1], $Matches[2]) }
}
(Get-Content k8s-dev.yaml -Raw) -replace '\$\{(\w+)\}', { [System.Environment]::GetEnvironmentVariable($_.Groups[1].Value) } |
    kubectl apply -f -
```

### 5. Aguardar e acessar

```bash
kubectl wait --for=condition=available deployment --all -n fcg --timeout=300s
kubectl get pods -n fcg

# Expõe o gateway em http://localhost:8080
kubectl port-forward -n fcg svc/api-gateway 8080:8000
```

Entrypoint: **http://localhost:8080/swagger/**

### Comandos úteis em dev

```bash
# Logs de um microsserviço
kubectl logs -n fcg deploy/users-api -f

# Port-forward direto (bypass gateway)
kubectl port-forward -n fcg svc/users-api   5001:8080
kubectl port-forward -n fcg svc/catalog-api 5002:8080
kubectl port-forward -n fcg svc/localstack  4566:4566

# Após rebuildar uma imagem
docker build -t users-api:dev ../UsersAPI
kind load docker-image users-api:dev
kubectl rollout restart deployment/users-api -n fcg
```

### Derrubar

```bash
kubectl delete namespace fcg
# ou para destruir o cluster inteiro
kind delete cluster
```

> **Lambda não roda em K8s.** O LocalStack no cluster omite a Lambda
> (`SKIP_LAMBDA=true`) por limitação de container-in-container. Filas SQS e
> DynamoDB funcionam normalmente. Para testar `SQS → Lambda → DynamoDB`
> end-to-end use o Docker Compose.

> **Datadog não roda em dev.** `k8s-dev.yaml` não inclui o agent nem as
> variáveis `DD_*` / `CORECLR_*`. Elas estão somente em `k8s-prod.yaml`.

---

## Kubernetes — PROD (EKS)

`k8s-prod.yaml` contém todos os recursos de produção: namespace, network
policies, bancos, mensageria, três microsserviços com imagens ECR versionadas,
Datadog Agent DaemonSet e o API Gateway Kong.

### 1. Preencher os segredos e imagens

Edite `k8s-prod.yaml` e substitua todos os marcadores:

| Marcador | Valor |
|---|---|
| `000000000000` (account ID nas imagens) | `aws sts get-caller-identity --query Account --output text` |
| `1.0.0` (tag das imagens) | tag da versão a ser implantada |
| `CHANGE_ME` nos secrets | valores reais (JWT keys, senhas, API key do Datadog) |
| `CHANGE_ME_terraform_output` | `terraform -chdir=infrastructure/terraform output -raw sqs_user_created_queue_url` |

**JWT keys:**

```bash
bash infrastructure/scripts/generate-jwt-keys.sh
```

**URLs SQS (após `terraform apply`):**

```bash
terraform -chdir=infrastructure/terraform output -raw sqs_user_created_queue_url
terraform -chdir=infrastructure/terraform output -raw sqs_payment_processed_queue_url
```

**ECR URLs:**

```bash
terraform -chdir=infrastructure/terraform output ecr_users_api_url
terraform -chdir=infrastructure/terraform output ecr_catalog_api_url
terraform -chdir=infrastructure/terraform output ecr_payments_api_url
```

### 2. Build e push das imagens para o ECR

```bash
AWS_REGION=us-east-1
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
TAG=1.0.0

aws ecr get-login-password --region $AWS_REGION | \
  docker login --username AWS --password-stdin $ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com

for svc in users-api catalog-api payments-api; do
  docker build -t $ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/fcg-$svc:$TAG ../${svc//-/}API
  docker push    $ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/fcg-$svc:$TAG
done
```

### 3. Aplicar

```bash
kubectl apply -f k8s-prod.yaml
```

### 4. Verificar

```bash
kubectl wait --for=condition=available deployment --all -n fcg --timeout=300s
kubectl get pods -n fcg
kubectl get daemonset datadog-agent -n fcg
```

### Atualizar um microsserviço (novo deploy)

```bash
TAG=1.0.1
docker build -t $ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/fcg-users-api:$TAG ../UsersAPI
docker push    $ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/fcg-users-api:$TAG

# Edite k8s-prod.yaml: troque a tag da imagem users-api para 1.0.1
kubectl apply -f k8s-prod.yaml
```

### Derrubar

```bash
kubectl delete namespace fcg
# RBAC é cluster-scoped — remover separadamente se necessário:
kubectl delete clusterrole datadog-agent
kubectl delete clusterrolebinding datadog-agent
```

---

## Deploy em AWS (produção)

**Pré-requisitos:** `aws` CLI configurado (`aws sts get-caller-identity` deve
funcionar), Docker rodando, ECR repos e cluster ECS já provisionados via
Terraform (`infrastructure/terraform/`).

### Com [go-task](https://taskfile.dev/) — atalho

```bash
task aws:deploy svc=users-api
task aws:deploy svc=catalog-api
task aws:deploy svc=payments-api
```

### Manualmente — sem task runner

Substitua `<svc>` por `users-api`, `catalog-api` ou `payments-api`.
Substitua `<CONTEXT_DIR>` pelo path do repo correspondente (`../UsersAPI`,
`../CatalogAPI` ou `../PaymentsAPI`).

```bash
AWS_REGION=us-east-1
ECS_CLUSTER=fcg-production-cluster
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
ECR_URI=$ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/<svc>

# 1. Login no ECR
aws ecr get-login-password --region $AWS_REGION | \
  docker login --username AWS --password-stdin $ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com

# 2. Build + push da imagem
docker build -t $ECR_URI:latest <CONTEXT_DIR>
docker push  $ECR_URI:latest

# 3. Force redeploy do service (ECS puxa a nova :latest)
aws ecs update-service \
  --cluster $ECS_CLUSTER \
  --service fcg-production-<svc> \
  --force-new-deployment \
  --region $AWS_REGION \
  --no-cli-pager > /dev/null

# 4. Aguardar estabilizar
aws ecs wait services-stable \
  --cluster $ECS_CLUSTER \
  --services fcg-production-<svc> \
  --region $AWS_REGION
```

**PowerShell** — mesmo fluxo, trocando `$VAR` por `$env:VAR` e `\` por
backtick. Ou rode em bash via Git Bash / WSL.

**URL pública** do API Gateway de prod:

```bash
terraform -chdir=infrastructure/terraform output -raw api_gateway_url
```

**Smoke test em prod:** `bash infrastructure/scripts/smoke-test.sh <url>`.

**Logs CloudWatch:**

```bash
aws logs tail /ecs/fcg-production-<svc> --follow --region us-east-1
```

> **Provisionamento inicial** (criar ECR/ECS/RDS/SQS/Lambda do zero) é via
> `infrastructure/terraform/deploy.ps1` (ou `deploy.sh`) — esse passo só é
> necessário uma vez por ambiente. O fluxo acima cobre apenas o ciclo
> normal de **redeploy de aplicação**.

---

## Estrutura do repositório

```
Orchestration/
├── docker-compose.yml              # stack local (Docker)
├── k8s-dev.yaml                    # todos os manifests Kubernetes para DEV
├── k8s-prod.yaml                   # todos os manifests Kubernetes para PROD
├── kind-cluster.yaml               # config do cluster kind (dev local)
├── .env / .env.example             # variáveis de ambiente do Compose
├── Taskfile.yml                    # atalhos de build e deploy
└── infrastructure/
    ├── kong/                       # config declarativa do API Gateway Kong
    │   ├── kong.yml                # rotas, plugins, rate-limit, CORS
    │   ├── entrypoint.sh           # injeta JWT public key em runtime
    │   └── openapi.yaml            # spec OpenAPI exposta pelo Swagger UI
    ├── localstack/                 # emulação AWS local
    │   ├── Dockerfile              # imagem com init-aws.sh pré-copiado
    │   ├── init-aws.sh             # cria filas SQS, tabelas DynamoDB, Lambda
    │   ├── build-lambda.sh / .ps1  # compila a NotificationsLambda
    │   └── .build/                 # artefatos compilados (zip + DLLs)
    ├── scripts/
    │   ├── generate-jwt-keys.sh    # gera par RSA e injeta no .env
    │   └── smoke-test.sh           # testes de fumaça end-to-end
    └── terraform/                  # IaC AWS (ECS, ECR, API GW, SQS, Lambda,
        │                           #           DynamoDB, Datadog monitors)
        ├── *.tf                    # recursos AWS
        ├── datadog*.tf             # monitors e dashboard do Datadog
        ├── deploy.sh / .ps1        # build → push ECR → force redeploy ECS
        ├── terraform.tfvars.example
        └── terraform.tfstate       # state local (usar backend S3 em prod real)
```
