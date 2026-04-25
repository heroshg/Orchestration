#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
log_info()    { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[OK]${NC}   $1"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }

DD_API_KEY="${DD_API_KEY:-}"
SQS_USER_CREATED_QUEUE_URL="${SQS_USER_CREATED_QUEUE_URL:-}"
SQS_PAYMENT_PROCESSED_QUEUE_URL="${SQS_PAYMENT_PROCESSED_QUEUE_URL:-}"

[ -z "$DD_API_KEY" ] && log_error "Defina DD_API_KEY antes de rodar (export DD_API_KEY=...)"

echo ""
echo "================================================================="
echo "  FiapCloudGames — Bootstrap Kubernetes"
echo "================================================================="
echo "  Cluster : $(kubectl config current-context)"
echo "  SQS User: ${SQS_USER_CREATED_QUEUE_URL:-'[vazio — notificações desabilitadas]'}"
echo "  SQS Pay : ${SQS_PAYMENT_PROCESSED_QUEUE_URL:-'[vazio — notificações desabilitadas]'}"
echo "================================================================="
echo ""

log_info "Instalando nginx ingress controller..."
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.10.1/deploy/static/provider/cloud/deploy.yaml
kubectl wait --namespace ingress-nginx \
  --for=condition=ready pod \
  --selector=app.kubernetes.io/component=controller \
  --timeout=120s
log_success "nginx ingress controller pronto"

log_info "Criando namespace..."
kubectl apply -f "$SCRIPT_DIR/namespace.yaml"
log_success "Namespace 'fcg' pronto"

log_info "Criando secret do Datadog..."
kubectl create secret generic datadog-secret \
  --from-literal=api-key="$DD_API_KEY" \
  --namespace fcg \
  --dry-run=client -o yaml | kubectl apply -f -
log_success "datadog-secret criado"

log_info "Criando secrets do PostgreSQL..."
kubectl apply -f "$SCRIPT_DIR/postgres-secrets.yaml"
log_success "postgres-secret criado"

log_info "Aplicando secrets das APIs e serviços..."
for secret_file in rabbitmq-secret.yaml redis-secret.yaml users-api-secret.yaml catalog-api-secret.yaml payments-api-secret.yaml; do
  if [[ -f "$SCRIPT_DIR/$secret_file" ]]; then
    kubectl apply -f "$SCRIPT_DIR/$secret_file"
  else
    log_error "$secret_file não encontrado — copie o .example e preencha os valores: cp $SCRIPT_DIR/$secret_file.example $SCRIPT_DIR/$secret_file"
  fi
done
log_success "Secrets das APIs aplicados"

if [ -n "$SQS_USER_CREATED_QUEUE_URL" ]; then
  log_info "Injetando SQS URL no users-api..."
  kubectl create secret generic users-api-sqs \
    --from-literal=AWS__SQS__UserCreatedQueueUrl="$SQS_USER_CREATED_QUEUE_URL" \
    --namespace fcg \
    --dry-run=client -o yaml | kubectl apply -f -
  log_success "users-api-sqs secret criado"
fi

if [ -n "$SQS_PAYMENT_PROCESSED_QUEUE_URL" ]; then
  log_info "Injetando SQS URL no payments-api..."
  kubectl create secret generic payments-api-sqs \
    --from-literal=AWS__SQS__PaymentProcessedQueueUrl="$SQS_PAYMENT_PROCESSED_QUEUE_URL" \
    --namespace fcg \
    --dry-run=client -o yaml | kubectl apply -f -
  log_success "payments-api-sqs secret criado"
fi

log_info "Deployando bancos de dados..."
kubectl apply -f "$SCRIPT_DIR/users-postgres.yaml"
kubectl apply -f "$SCRIPT_DIR/catalog-postgres.yaml"
kubectl apply -f "$SCRIPT_DIR/payments-postgres.yaml"
log_success "PostgreSQL deployado"

log_info "Deployando mensageria e cache..."
kubectl apply -f "$SCRIPT_DIR/rabbitmq.yaml"
kubectl apply -f "$SCRIPT_DIR/redis.yaml"
log_success "RabbitMQ e Redis deployados"

log_info "Deployando Datadog Agent..."
kubectl apply -f "$SCRIPT_DIR/datadog-agent.yaml"
log_success "Datadog Agent deployado"

log_info "Aplicando NetworkPolicies..."
kubectl apply -f "$SCRIPT_DIR/network-policies.yaml"
log_success "NetworkPolicies aplicadas"

log_info "Aguardando PostgreSQL ficar pronto (máx 120s)..."
kubectl wait --for=condition=available deployment/users-postgres   -n fcg --timeout=120s 2>/dev/null || true
kubectl wait --for=condition=available deployment/catalog-postgres -n fcg --timeout=120s 2>/dev/null || true
kubectl wait --for=condition=available deployment/payments-postgres -n fcg --timeout=120s 2>/dev/null || true

log_info "Deployando APIs..."
kubectl apply -f "$SCRIPT_DIR/users-api.yaml"
kubectl apply -f "$SCRIPT_DIR/catalog-api.yaml"
kubectl apply -f "$SCRIPT_DIR/payments-api.yaml"
log_success "APIs deployadas"

log_info "Deployando Ingress..."
kubectl apply -f "$SCRIPT_DIR/ingress.yaml"
log_success "Ingress fcg-ingress criado"

echo ""
log_info "Aguardando pods ficarem prontos (máx 180s)..."
kubectl wait --for=condition=ready pod -l app=users-api   -n fcg --timeout=180s || log_warn "users-api ainda não pronto"
kubectl wait --for=condition=ready pod -l app=catalog-api -n fcg --timeout=180s || log_warn "catalog-api ainda não pronto"
kubectl wait --for=condition=ready pod -l app=payments-api -n fcg --timeout=180s || log_warn "payments-api ainda não pronto"

echo ""
log_success "Bootstrap concluído!"
echo ""
kubectl get pods -n fcg
echo ""
echo "Próximos passos:"
echo "  1. Verifique os pods acima — todos devem estar Running"
echo "  2. Obtenha o IP externo do ingress:"
echo "     kubectl get ingress fcg-ingress -n fcg"
echo "  3. Use esse IP como users_api_url e catalog_api_url no Terraform:"
echo "     cd ../infrastructure/terraform && cp terraform.tfvars.example terraform.tfvars"
echo "  4. Preencha terraform.tfvars e execute: ./deploy.sh"
echo ""
