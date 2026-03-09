# FiapCloudGames — Orquestração

Repositório central de orquestração da plataforma FiapCloudGames com microsserviços.

## Arquitetura

```
┌──────────────┐    UserCreatedEvent      ┌──────────────────────┐
│  UsersAPI    │ ─────────────────────── ▶│  NotificationsAPI    │
│  :5001       │                          │  :5004               │
└──────────────┘                          │                      │
                                          │  PaymentProcessed    │
┌──────────────┐   OrderPlacedEvent       │  Event (Approved)    │
│  CatalogAPI  │ ─────────────────────── ▶│                      │
│  :5002       │◀────────────────────────┤                      │
└──────────────┘  PaymentProcessedEvent   └──────────────────────┘
        │                                          ▲
        │          OrderPlacedEvent                │
        └────────────────────────────▶─────────────┘
                                   PaymentsAPI
                                    :5003
```

## Pré-requisitos
- Docker Desktop com Compose
- kubectl + cluster local (Docker Desktop / Minikube / Kind)

## Executando com Docker Compose

```bash
cd Orchestration
docker-compose up --build
```

| Serviço | URL |
|---------|-----|
| UsersAPI (Swagger) | http://localhost:5001/swagger |
| CatalogAPI (Swagger) | http://localhost:5002/swagger |
| PaymentsAPI (health) | http://localhost:5003/health |
| NotificationsAPI (health) | http://localhost:5004/health |
| RabbitMQ Management | http://localhost:15672 (guest/guest) |

## Deploy no Kubernetes

### 1. Build das imagens locais

```bash
docker build -t users-api:latest ../UsersAPI
docker build -t catalog-api:latest ../CatalogAPI
docker build -t payments-api:latest ../PaymentsAPI
docker build -t notifications-api:latest ../NotificationsAPI
```

### 2. Criar namespace e aplicar todos os manifests

```bash
kubectl apply -f k8s/namespace.yaml
kubectl apply -f k8s/ -n fcg
```

### 3. Verificar os pods

```bash
kubectl get pods -n fcg
kubectl get services -n fcg
```

### 4. Acessar os serviços localmente

```bash
# UsersAPI
kubectl port-forward svc/users-api 5001:80 -n fcg

# CatalogAPI
kubectl port-forward svc/catalog-api 5002:80 -n fcg

# RabbitMQ Management
kubectl port-forward svc/rabbitmq 15672:15672 -n fcg
```

## Fluxos de Eventos

### Cadastro de Usuário
```
POST /api/users (UsersAPI)
  → UserCreatedEvent publicado no RabbitMQ
  → NotificationsAPI consome → loga e-mail de boas-vindas
```

### Compra de Jogo
```
POST /api/games/purchase (CatalogAPI)
  → OrderPlacedEvent publicado
  → PaymentsAPI consome → simula pagamento → publica PaymentProcessedEvent
  → CatalogAPI consome → se Approved, cria GameLicense
  → NotificationsAPI consome → se Approved, loga confirmação de compra
```

## Repositórios dos Microsserviços

| Serviço | Repositório |
|---------|-------------|
| UsersAPI | [UsersAPI](../UsersAPI) |
| CatalogAPI | [CatalogAPI](../CatalogAPI) |
| PaymentsAPI | [PaymentsAPI](../PaymentsAPI) |
| NotificationsAPI | [NotificationsAPI](../NotificationsAPI) |
