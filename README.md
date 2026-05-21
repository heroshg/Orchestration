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
[NotificationsLambda](https://github.com/heroshg/NotificationsAPI)

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

## Rodando local — Kubernetes

**Pré-requisitos:** Docker Desktop com **Kubernetes habilitado**
(Settings → Kubernetes → Enable). `kubectl` no contexto `docker-desktop`.

```bash
# 1. Build das 4 imagens (a partir de Orchestration/)
docker build -t users-api:latest    ../UsersAPI
docker build -t catalog-api:latest  ../CatalogAPI
docker build -t payments-api:latest ../PaymentsAPI
docker build -t fcg-localstack:local infrastructure/localstack/

# 2. Aplicar o overlay local (cria namespace, secrets, bancos, mensageria,
#    LocalStack, APIs e o gateway Kong — tudo em um comando)
kubectl apply -k k8s/overlays/local --load-restrictor=LoadRestrictionsNone

# 3. Esperar tudo subir
kubectl wait --for=condition=available deployment --all -n fcg --timeout=300s
kubectl get pods -n fcg

# 4. Expor o gateway Kong em http://localhost:8080
kubectl port-forward -n fcg svc/api-gateway 8080:8000
```

A flag `--load-restrictor=LoadRestrictionsNone` é necessária porque o
`configMapGenerator` do `base/` lê `infrastructure/kong/` (mesma fonte da
verdade do Compose).

**Acesso via port-forward do Kong** — `http://localhost:8080/swagger/`,
mesmas rotas do Compose.

**Debug — port-forward direto nas APIs (bypass gateway):**

```bash
kubectl port-forward -n fcg svc/users-api  5001:8080
kubectl port-forward -n fcg svc/localstack 4566:4566   # awslocal a partir do host
kubectl logs -n fcg deploy/users-api -f
```

**Após rebuildar uma imagem** (tag `:latest` não muda — precisa forçar restart):

```bash
docker build -t users-api:latest ../UsersAPI
kubectl rollout restart deployment/users-api -n fcg
```

**Derrubar:**

```bash
kubectl delete namespace fcg
```

> **Lambda não roda em K8s.** A `NotificationsLambda` exige container-in-container,
> topologia que LocalStack não suporta dentro de cluster. Filas SQS são criadas
> normalmente, só o consumer Lambda fica off. Para testar o fluxo
> `SQS → Lambda → DynamoDB` end-to-end, use o Compose.

> **Datadog mora só em prod.** O overlay `local/` não inclui o agent. As APIs
> exportam as env vars `DD_*` (vêm do base), mas como ninguém escuta em
> `DD_AGENT_HOST`, o tracer silenciosamente desiste. Zero configuração extra.

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
├── docker-compose.yml              # stack local Compose
├── infrastructure/
│   ├── kong/                       # config do API Gateway Kong
│   ├── localstack/                 # Dockerfile + init-aws.sh + Lambda zip
│   ├── datadog/                    # checks customizados (só prod)
│   ├── scripts/                    # generate-jwt-keys, smoke-test, ...
│   └── terraform/                  # IaC AWS (ECS, API GW, SQS, Lambda, ...)
└── k8s/
    ├── base/                       # manifests canônicos (Kustomize)
    └── overlays/
        ├── local/                  # base + LocalStack + SQS endpoints fake
        └── prod/                   # base + SQS reais (Terraform) + Datadog
```
