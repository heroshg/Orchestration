# FiapCloudGames — Arquitetura AWS

Reflete o que está em `infrastructure/terraform/`.

## Diagrama

```mermaid
flowchart LR
    client([Cliente])

    subgraph entry[Entrada]
        apigw[API Gateway v2<br/>HTTP + JWT authorizer]
    end

    subgraph compute[Compute — 1 EC2 t2.small com ECS]
        users[UsersAPI]
        catalog[CatalogAPI]
        payments[PaymentsAPI]
        rabbit[(RabbitMQ)]
        pg[(PostgreSQL<br/>+ EBS gp3)]
    end

    subgraph async[Notificações assíncronas]
        sqsUser[SQS<br/>user-created]
        sqsPay[SQS<br/>payment-processed]
        lambda[Lambda Notifications<br/>.NET 8 arm64]
        ddb[(DynamoDB)]
    end

    client --> apigw
    apigw --> users
    apigw --> catalog

    users --> pg
    catalog --> pg
    payments --> pg

    catalog <-->|OrderPlaced / PaymentProcessed| rabbit
    payments <--> rabbit

    users -->|UserCreated| sqsUser
    payments -->|PaymentProcessed| sqsPay
    sqsUser --> lambda
    sqsPay --> lambda
    lambda --> ddb
```

Cada fila SQS tem uma DLQ. ECR guarda as imagens das 3 APIs.
CloudWatch Logs recebe logs de ECS e Lambda; Datadog (agent em ECS + AWS
integration role) cobre métricas/traces.

## Recursos AWS usados

| Serviço | Para quê |
|---|---|
| API Gateway v2 (HTTP) | Entrada única, autoriza JWT (RS256), faz proxy HTTP para o EIP da EC2 |
| ECS em **uma** EC2 t2.small | Roda 6 tasks: 3 APIs + Postgres + RabbitMQ + Datadog agent |
| ECR | Imagens Docker das 3 APIs |
| EBS gp3 | Volume persistente do Postgres |
| Elastic IP | IP estável da EC2, usado pelo API Gateway |
| SQS (+ DLQ) | `user-created-events` e `payment-processed-events`, consumidos pela Lambda |
| Lambda + S3 | Notifications λ (zip no S3); event source mapping em ambas as filas |
| DynamoDB | Tabela `notifications` (log de envios, TTL ativo) |
| CloudWatch Logs | Logs de todas as tasks ECS e da Lambda |
| Datadog | Agent em ECS + role AWS integration |
| IAM | Permissões: ECS publica em SQS; Lambda lê SQS e escreve DynamoDB; Datadog lê métricas |

## Fluxo de compra

```mermaid
sequenceDiagram
    actor C as Cliente
    participant GW as API Gateway
    participant Cat as CatalogAPI
    participant RMQ as RabbitMQ
    participant Pay as PaymentsAPI
    participant SQS
    participant L as Lambda
    participant DDB as DynamoDB

    C->>GW: POST /api/games/purchase
    GW->>Cat: proxy (JWT validado)
    Cat->>Cat: cria Order (Pending) + OutboxMessage
    Cat-->>C: 202 Accepted

    Note over Cat,RMQ: BusOutbox publica eventualmente
    Cat->>RMQ: OrderPlacedEvent
    RMQ->>Pay: OrderPlacedEvent
    Pay->>RMQ: PaymentProcessedEvent
    Pay->>SQS: PaymentProcessedEvent

    RMQ->>Cat: PaymentProcessedEvent (saga)
    alt Aprovado
        Cat->>Cat: cria GameLicense + Order.Complete
    else Rejeitado
        Cat->>Cat: Order.Fail
        Cat->>RMQ: OrderCancelledEvent
    end

    SQS->>L: trigger
    L->>DDB: salva notificação
```

O cadastro de usuário segue o mesmo padrão simplificado: `POST /api/users`
→ UsersAPI grava no Postgres → envia `UserCreatedEvent` pro SQS → Lambda
grava no DynamoDB.
