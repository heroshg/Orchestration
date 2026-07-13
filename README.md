# FiapCloudGames — Orquestração (Plataforma)

Repo **plataforma mínimo** da solução cloud-native FiapCloudGames — provisiona o substrato
compartilhado (EKS, ECR, API Gateway, SSM) **uma única vez**; cada microsserviço é dono da própria
infra e do próprio deploy (ver `specs/phase2/` para o plano completo).

> **Sem Docker Compose, sem cluster local (kind), sem LocalStack.** Local = `dotnet run` de cada
> serviço contra os recursos reais do ambiente `dev` na AWS (ver README de cada repo, spec 06).
> Todos os recursos (DynamoDB, SQS/SNS, RDS, ElastiCache, OpenSearch) são reais na conta AWS —
> não há mais emulação local.

---

## Arquitetura

```
Internet
   │
   ▼
AWS API Gateway (HTTP API, gerenciado) ──▶ VPC Link ──▶ NLB interno ── por serviço
   │
   ▼
┌──────────── EKS (1 cluster fcg-eks, namespaces fcg-dev / fcg-prd) ──────────────────┐
│   ├─ users-api / catalog-api / payments-api  (Deployment + Service interno)        │
│   └─ External Secrets Operator ── sincroniza AWS Secrets Manager (fcg/<env>/*)      │
└───────────────────────────────────────────────────────────────────────────────────┘
   │              │              │              │                 │
   ▼              ▼              ▼              ▼                 ▼
DynamoDB     RDS Postgres   Amazon SQS/SNS  ElastiCache(Redis)  OpenSearch
(Catalog)    (Users/Paym.)  (saga msgs)     (cache do Catalog)  (busca fuzzy)
```

**Eventos:**

| Evento | Produtor | Consumidor |
|---|---|---|
| `UserCreatedEvent` | UsersAPI | Notifications λ (via SQS) |
| `OrderPlacedEvent` | CatalogAPI | PaymentsAPI (via SQS/SNS) |
| `PaymentProcessedEvent` | PaymentsAPI | CatalogAPI, Notifications λ |

**Microsserviços** — cada um em seu próprio repositório, com infra e deploy independentes:
[UsersAPI](https://github.com/heroshg/UsersAPI) ·
[CatalogAPI](https://github.com/heroshg/CatalogAPI) ·
[PaymentsAPI](https://github.com/heroshg/PaymentsAPI) ·
[NotificationsLambda](https://github.com/heroshg/NotificationsLambda) (função serverless)

---

## Stack

| Camada | Tecnologia | Onde / por quê |
|---|---|---|
| Runtime | .NET 8 | APIs e Lambda |
| Orquestração | **AWS EKS** (`fcg-eks`, 1 cluster, namespaces por ambiente) | Kubernetes gerenciado |
| API Gateway | **AWS API Gateway (HTTP API)** + VPC Link | Roteamento, CORS, throttling; rota declarada por serviço |
| Registry | **Amazon ECR** | Imagens versionadas por serviço |
| NoSQL | **DynamoDB** (Catalog) | Alta volumetria / dados flexíveis |
| Relacional | **RDS Postgres** (Users/Payments) | Um banco por serviço |
| Cache | **ElastiCache Redis** (Catalog) — `IDistributedCache` | Cache-aside; cai p/ memória se ausente |
| Busca | **Amazon OpenSearch** | Fuzzy search + relevância (`/api/games/search`) |
| Mensageria | **Amazon SQS/SNS** + MassTransit (Saga) | `OrderPlacedEvent`, `PaymentProcessedEvent`, `OrderCancelledEvent` |
| Segredos | **AWS Secrets Manager** + External Secrets Operator | Zero hardcoded; injeção em runtime |
| CI/CD | **GitHub Actions** por repo | Build/test → ECR → deploy EKS (spec 09) |
| Observabilidade | **Datadog** (APM + Logs) | Stack da Fase 3 |
| Infra-as-code | **Terraform** — `platform/` (plataforma) + `infra/` por serviço | State próprio por repo (S3 + lock); refs via SSM |

---

## Provisionar a plataforma

Pré-requisitos: `aws` CLI configurado (`aws sts get-caller-identity` deve funcionar), `terraform`
>= 1.5, `kubectl`.

```bash
cd platform
terraform init
terraform apply
```

Cria: VPC, cluster EKS `fcg-eks` + node group, 3 repositórios ECR, API Gateway (HTTP API) + VPC
Link, e publica as referências compartilhadas no SSM (`/fcg/platform/...`) para os serviços lerem.

```bash
aws eks update-kubeconfig --name fcg-eks --region us-east-1
kubectl apply -f k8s-dev.yaml     # namespace fcg-dev, NetworkPolicy, ClusterSecretStore (ESO)
kubectl apply -f k8s-prd.yaml     # namespace fcg-prd, idem
```

> **Learner Lab (AWS Academy):** EKS reusa o `LabRole` (sem IRSA/OIDC — `enable_irsa=false`);
> apenas `dev` + `prd` são provisionados (`homolog` fica documentado). Ver
> `specs/phase2/00-overview.md`, seção "Ambiente AWS = Academy Learner Lab".

---

## Deploy de um serviço (dev)

Cada serviço é autônomo: traz sua própria infra (`infra/*.tf`, lendo o SSM da plataforma) e seus
próprios manifests (`k8s-dev.yaml` / `k8s-homolog.yaml` / `k8s-prd.yaml`). Nenhum passo aqui edita
este repo.

```bash
# No repo do serviço, ex.: CatalogAPI/
cd infra && terraform init && terraform apply   # DynamoDB/Redis/OpenSearch/Secrets + rota no API Gateway

docker build -t <account_id>.dkr.ecr.us-east-1.amazonaws.com/catalog-api:latest .
docker push  <account_id>.dkr.ecr.us-east-1.amazonaws.com/catalog-api:latest

kubectl apply -f k8s-dev.yaml -n fcg-dev
kubectl rollout status deployment/catalog-api -n fcg-dev
```

Automatizado via GitHub Actions (push em `master` → build/test/scan/push/deploy) — ver
`.github/workflows/ci-cd.yml` em cada repo (spec 09).

---

## Rodando local (sem containers)

**Não há Docker Compose.** Cada API sobe com `dotnet run` apontando para os recursos reais do
ambiente `dev` (DynamoDB, SQS/SNS, RDS público, OpenSearch público); o cache cai para memória se
`Redis:ConnectionString` estiver vazio (ElastiCache é somente-VPC). Ver o README de cada serviço e
`specs/phase2/06-local-dev.md`.

```bash
# Em cada repo de serviço
dotnet run --project src/<Servico>.API
```

---

## Estrutura do repositório

```
Orchestration/
├── platform/                       # Terraform da plataforma (Estágio 1 — spec 01)
│   ├── vpc.tf / eks.tf / ecr.tf / apigateway.tf / ssm.tf / outputs.tf / variables.tf
│   └── versions.tf                 # backend S3 + lock DynamoDB
├── k8s-dev.yaml                    # Namespace fcg-dev + NetworkPolicy + ClusterSecretStore (ESO)
├── k8s-prd.yaml                    # idem para fcg-prd
└── infrastructure/
    ├── scripts/
    │   ├── generate-jwt-keys.sh    # gera par RSA (usado localmente e para popular secrets)
    │   └── smoke-test.sh           # testes de fumaça end-to-end
    └── terraform/                  # IaC restante: Lambda de notificações, Datadog (integração
        │                           #   AWS + monitors/dashboard), DynamoDB (tabela de notificações),
        │                           #   SQS. ECS/EC2/API-Gateway-v1 e Kong foram removidos (specs
        │                           #   01/13) — EKS + AWS API Gateway já validados no ar.
        ├── lambda.tf / datadog*.tf / dynamodb.tf / sqs.tf / iam*.tf / ecr.tf
        └── terraform.tfvars.example
```

> Não há mais `Taskfile.yml` (removido — spec 13). Os comandos de cada fluxo (build/push/deploy,
> `terraform apply`, `kubectl`) estão documentados neste README e no README de cada serviço.

> Os Deployments/Services de cada API (`k8s-dev.yaml`/`k8s-homolog.yaml`/`k8s-prd.yaml`), os
> `Dockerfile` e a infra própria (`infra/*.tf`) vivem nos repos dos serviços — spec 07/01.
