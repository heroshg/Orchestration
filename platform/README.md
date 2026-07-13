# Plataforma (Estágio 1 — spec `01-platform.md`)

Root Terraform da **plataforma** (VPC + EKS `fcg-eks` + SSM), adaptado ao **AWS Academy Learner Lab**.
State remoto no S3 (`fcg-tfstate-667079134782`, key `platform/terraform.tfstate`).

> ⚠️ **Learner Lab:** reusa o `LabRole` (sem criar roles/OIDC/IRSA). Credenciais expiram a cada sessão →
> reautenticar antes de rodar. Ver `../../specs/phase2/00-overview.md` e `memory/project_aws_learner_lab.md`.

## Pré-requisitos
- `aws sts get-caller-identity` OK, região `us-east-1`.
- `terraform`, `kubectl`, `helm` instalados.

## Aplicar (o `apply` gera custo — ~US$7/dia; destrua quando ocioso)
```bash
cd Orchestration/platform
terraform init
terraform plan -out tfplan
terraform apply tfplan          # cria VPC + EKS + SSM (~15-20 min)
```

## Pós-apply (namespaces, gateway, secrets)
```bash
# 1. kubeconfig
aws eks update-kubeconfig --name fcg-eks --region us-east-1
kubectl get nodes                       # nós devem ficar Ready

# 2. Namespaces por ambiente
kubectl create namespace fcg-dev
kubectl create namespace fcg-prd

# 3. Gateway = AWS API Gateway (HTTP API) — MUDANÇA DE ESCOPO (2026-07-11): não é mais Kong.
#    É criado pela TERRAFORM da plataforma (falta adicionar `apigateway.tf`: aws_apigatewayv2_api +
#    aws_apigatewayv2_vpc_link + stage; publicar api_id/api_endpoint/vpc_link_id no SSM). Ver spec 01.
#    Cada serviço adiciona sua rota/integração (aws_apigatewayv2_route/_integration) na Terraform dele.

# 4. Secrets: no lab, usar Secrets do K8s (sem ESO/IRSA) — ver spec 05.
```

> **Nota:** na 1ª validação (2026-07-11) o gateway foi testado com Kong via helm; o escopo mudou para
> **AWS API Gateway** (cloud-native). Não usar mais `helm install kong`.

## Riscos a observar no apply (Learner Lab)
- **Access entries / join dos nós:** o node group reusa o `LabRole`. Se os nós não ficarem `Ready`,
  pode faltar uma *access entry* EC2 para o `LabRole` ou uma policy de CNI — ajustar em `eks.tf`.
- **KMS/log group desativados** de propósito (`create_kms_key=false`, sem CloudWatch log group) para evitar
  chamadas que o lab nega. Se precisar de logs, reavaliar.
- **`iam:CreateRole` negado:** garantir que nenhum recurso tente criar role (por isso `create_iam_role=false`
  em cluster e node group, `enable_irsa=false`).

## Destruir (economizar budget)
```bash
terraform destroy
```

## Publicado no SSM (`/fcg/platform/*`) para os serviços consumirem
`eks/cluster_name`, `eks/cluster_endpoint`, `vpc/id`, `vpc/private_subnets`, `iam/lab_role_arn`,
`ecr/<svc>_url`. (Sem `oidc_provider_arn` — não há IRSA no lab.)
