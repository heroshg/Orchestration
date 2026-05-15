# FiapCloudGames - Arquitetura AWS

Este desenho reflete a infraestrutura declarada hoje em `Orchestration/infrastructure/terraform`.

## Desenho geral

```mermaid
flowchart TB
    client[Cliente / App / Swagger]

    subgraph aws[AWS Account]
        apigw[API Gateway HTTP API]

        subgraph compute[ECS em EC2]
            eip[Elastic IP]
            ec2[EC2 t2.small<br/>ECS container instance]
            ecs[ECS Cluster]

            users[UsersAPI<br/>.NET 8 container<br/>porta 8080]
            catalog[CatalogAPI<br/>.NET 8 container<br/>porta 8081]
            payments[PaymentsAPI<br/>.NET 8 container<br/>porta 8082]
            postgres[(PostgreSQL container<br/>users_db / catalog_db / payments_db)]
            rabbit[(RabbitMQ container<br/>event bus interno)]
            ddagent[Datadog Agent<br/>ECS task]
            ebs[(EBS gp3<br/>dados do PostgreSQL)]
        end

        subgraph registries[ECR]
            ecrUsers[users-api image]
            ecrCatalog[catalog-api image]
            ecrPayments[payments-api image]
        end

        subgraph messaging[SQS]
            userQ[fcg-env-user-created-events]
            userDlq[DLQ user-created]
            paymentQ[fcg-env-payment-processed-events]
            paymentDlq[DLQ payment-processed]
        end

        subgraph serverless[Serverless]
            lambda[Lambda Notifications<br/>.NET 8 arm64]
            deployBucket[S3 bucket<br/>lambda deploy zip]
            ddb[(DynamoDB<br/>fcg-env-notifications)]
        end

        subgraph obs[Observabilidade]
            cwl[CloudWatch Logs]
            dd[Datadog<br/>dashboard, monitors, AWS integration]
        end

        iam[IAM Roles / Policies]
    end

    client -->|HTTP| apigw
    apigw -->|HTTP proxy para EIP:8080 / EIP:8081| eip
    eip -->|porta 8080| users
    eip -->|porta 8081| catalog
    eip --- ec2
    ec2 --- ecs
    ecs --- users
    ecs --- catalog
    ecs --- payments
    ecs --- postgres
    ecs --- rabbit
    ecs --- ddagent
    postgres --- ebs

    ecrUsers --> users
    ecrCatalog --> catalog
    ecrPayments --> payments

    users -->|EF Core / Npgsql| postgres
    catalog -->|EF Core / Npgsql| postgres
    payments -->|EF Core / Npgsql| postgres

    users -->|UserCreatedEvent dev/internal| rabbit
    catalog -->|OrderPlacedEvent| rabbit
    rabbit -->|OrderPlacedEvent| payments
    payments -->|PaymentProcessedEvent| rabbit
    rabbit -->|PaymentProcessedEvent| catalog

    users -->|SendMessage UserCreatedEvent| userQ
    payments -->|SendMessage PaymentProcessedEvent| paymentQ
    userQ -->|redrive after failures| userDlq
    paymentQ -->|redrive after failures| paymentDlq
    userQ -->|event source mapping| lambda
    paymentQ -->|event source mapping| lambda
    deployBucket -->|zip package| lambda
    lambda -->|PutItem notification log| ddb

    users --> cwl
    catalog --> cwl
    payments --> cwl
    postgres --> cwl
    rabbit --> cwl
    lambda --> cwl
    ddagent --> dd
    cwl --> dd
    dd -->|reads metrics via role| iam
    iam --> users
    iam --> payments
    iam --> lambda
```

## Como a AWS esta sendo usada

| Area | AWS usada | Uso no projeto |
|---|---|---|
| Entrada HTTP | API Gateway HTTP API | Ponto unico de entrada para rotas de `UsersAPI` e `CatalogAPI`, usando o Elastic IP da EC2 como destino HTTP proxy. |
| Containers | ECS em EC2 | Roda `UsersAPI`, `CatalogAPI`, `PaymentsAPI`, `PostgreSQL`, `RabbitMQ` e `Datadog Agent`. |
| Imagens | ECR | Armazena as imagens Docker das tres APIs. |
| IP publico | Elastic IP | Expoe a instancia EC2 usada pelo API Gateway como destino HTTP proxy. |
| Persistencia relacional | PostgreSQL em container + EBS | Um container PostgreSQL guarda `users_db`, `catalog_db` e `payments_db`; o volume EBS preserva os dados. |
| Mensageria interna | RabbitMQ em container no ECS | Orquestra o fluxo de compra entre `CatalogAPI` e `PaymentsAPI`, e alimenta a saga do catalogo. |
| Mensageria gerenciada | SQS + DLQ | Recebe eventos assicronos para notificacoes: `UserCreatedEvent` e `PaymentProcessedEvent`. |
| Serverless | Lambda .NET 8 arm64 | Processa eventos do SQS e cria logs de notificacao. |
| NoSQL | DynamoDB | Armazena registros de notificacoes, com GSI por `userId/createdAt`, TTL e PITR. |
| Deploy Lambda | S3 | Guarda o pacote `.zip` usado pela Lambda. |
| Logs | CloudWatch Logs | Recebe logs de ECS e Lambda. |
| Observabilidade | Datadog + IAM integration | Coleta metricas AWS, traces, logs, dashboards e monitores. |
| Permissoes | IAM | Permite ECS publicar no SQS, Lambda consumir SQS/escrever DynamoDB e Datadog ler metricas. |

`PaymentsAPI` esta no ECS, mas nao aparece como rota do API Gateway no Terraform atual; ela consome `OrderPlacedEvent` pelo RabbitMQ e publica `PaymentProcessedEvent`.

## Fluxo 1 - Cadastro de usuario

```mermaid
sequenceDiagram
    actor Cliente
    participant APIGW as API Gateway
    participant Users as UsersAPI no ECS
    participant PG as PostgreSQL
    participant RMQ as RabbitMQ
    participant SQS as SQS UserCreated
    participant L as Lambda Notifications
    participant DDB as DynamoDB

    Cliente->>APIGW: POST /api/users
    APIGW->>Users: HTTP proxy
    Users->>PG: grava usuario
    Users->>RMQ: publica UserCreatedEvent para ambiente interno/dev
    Users->>SQS: envia UserCreatedEvent
    Users-->>APIGW: resposta HTTP
    APIGW-->>Cliente: resposta HTTP
    SQS->>L: trigger por EventSourceMapping
    L->>DDB: salva notification log
```

## Fluxo 2 - Compra de jogo

```mermaid
sequenceDiagram
    actor Cliente
    participant APIGW as API Gateway
    participant Catalog as CatalogAPI no ECS
    participant PG as PostgreSQL
    participant RMQ as RabbitMQ
    participant Payments as PaymentsAPI no ECS
    participant SQS as SQS PaymentProcessed
    participant L as Lambda Notifications
    participant DDB as DynamoDB

    Cliente->>APIGW: POST /api/games/purchase
    APIGW->>Catalog: HTTP proxy
    Catalog->>PG: valida jogo, licenca e cria pedido
    Catalog->>RMQ: publica OrderPlacedEvent
    Catalog-->>APIGW: pedido iniciado
    APIGW-->>Cliente: pedido iniciado

    RMQ->>Payments: entrega OrderPlacedEvent
    Payments->>PG: grava pagamento
    Payments->>RMQ: publica PaymentProcessedEvent
    Payments->>SQS: envia PaymentProcessedEvent

    RMQ->>Catalog: saga recebe PaymentProcessedEvent
    Catalog->>PG: aprova pedido e cria licenca, ou cancela pedido

    SQS->>L: trigger por EventSourceMapping
    L->>DDB: salva notification log
```

## Observacao importante

O README menciona EKS, RDS e ElastiCache como evolucao/arquitetura alvo em alguns pontos. Ja o Terraform atual deste repositorio provisiona ECS em EC2, PostgreSQL e RabbitMQ como containers, SQS, Lambda, DynamoDB, API Gateway, ECR, S3, CloudWatch e Datadog. Este desenho segue o que esta declarado no Terraform.
