param(
    [Parameter(Mandatory)][string]$DdApiKey,
    [string]$SqsUserCreatedQueueUrl      = $env:SQS_USER_CREATED_QUEUE_URL,
    [string]$SqsPaymentProcessedQueueUrl = $env:SQS_PAYMENT_PROCESSED_QUEUE_URL
)

$ErrorActionPreference = "Stop"
$ScriptDir = $PSScriptRoot

function Info    ($msg) { Write-Host "[INFO] $msg" -ForegroundColor Cyan }
function Success ($msg) { Write-Host "[OK]   $msg" -ForegroundColor Green }
function Warn    ($msg) { Write-Host "[WARN] $msg" -ForegroundColor Yellow }

$context = kubectl config current-context
Write-Host ""
Write-Host "=================================================================" -ForegroundColor White
Write-Host "  FiapCloudGames — Bootstrap Kubernetes" -ForegroundColor White
Write-Host "  Cluster : $context" -ForegroundColor White
Write-Host "  SQS User: $(if ($SqsUserCreatedQueueUrl) { $SqsUserCreatedQueueUrl } else { '[vazio — notificacoes desabilitadas]' })" -ForegroundColor White
Write-Host "  SQS Pay : $(if ($SqsPaymentProcessedQueueUrl) { $SqsPaymentProcessedQueueUrl } else { '[vazio — notificacoes desabilitadas]' })" -ForegroundColor White
Write-Host "=================================================================" -ForegroundColor White
Write-Host ""

Info "Instalando nginx ingress controller..."
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.10.1/deploy/static/provider/cloud/deploy.yaml
Info "Aguardando nginx ingress controller ficar pronto (max 120s)..."
kubectl wait --namespace ingress-nginx `
    --for=condition=ready pod `
    --selector=app.kubernetes.io/component=controller `
    --timeout=120s
Success "nginx ingress controller pronto"

Info "Criando namespace..."
kubectl apply -f "$ScriptDir\namespace.yaml"
Success "Namespace 'fcg' pronto"

Info "Criando secret do Datadog..."
kubectl create secret generic datadog-secret `
    --from-literal=api-key="$DdApiKey" `
    --namespace fcg `
    --dry-run=client -o yaml | kubectl apply -f -
Success "datadog-secret criado"

Info "Criando secrets do PostgreSQL..."
kubectl apply -f "$ScriptDir\postgres-secrets.yaml"
Success "postgres-secret criado"

if ($SqsUserCreatedQueueUrl) {
    Info "Injetando SQS URL no users-api..."
    kubectl create secret generic users-api-sqs `
        --from-literal=AWS__SQS__UserCreatedQueueUrl="$SqsUserCreatedQueueUrl" `
        --namespace fcg `
        --dry-run=client -o yaml | kubectl apply -f -
    Success "users-api-sqs secret criado"
}

if ($SqsPaymentProcessedQueueUrl) {
    Info "Injetando SQS URL no payments-api..."
    kubectl create secret generic payments-api-sqs `
        --from-literal=AWS__SQS__PaymentProcessedQueueUrl="$SqsPaymentProcessedQueueUrl" `
        --namespace fcg `
        --dry-run=client -o yaml | kubectl apply -f -
    Success "payments-api-sqs secret criado"
}

Info "Deployando bancos de dados..."
kubectl apply -f "$ScriptDir\users-postgres.yaml"
kubectl apply -f "$ScriptDir\catalog-postgres.yaml"
kubectl apply -f "$ScriptDir\payments-postgres.yaml"
Success "PostgreSQL deployado"

Info "Deployando mensageria e cache..."
kubectl apply -f "$ScriptDir\rabbitmq.yaml"
kubectl apply -f "$ScriptDir\redis.yaml"
Success "RabbitMQ e Redis deployados"

Info "Deployando Datadog Agent..."
kubectl apply -f "$ScriptDir\datadog-agent.yaml"
Success "Datadog Agent deployado"

Info "Aplicando NetworkPolicies..."
kubectl apply -f "$ScriptDir\network-policies.yaml"
Success "NetworkPolicies aplicadas"

Info "Aguardando PostgreSQL ficar pronto (max 120s)..."
kubectl wait --for=condition=available deployment/users-postgres   -n fcg --timeout=120s 2>$null
kubectl wait --for=condition=available deployment/catalog-postgres -n fcg --timeout=120s 2>$null
kubectl wait --for=condition=available deployment/payments-postgres -n fcg --timeout=120s 2>$null

Info "Deployando APIs..."
kubectl apply -f "$ScriptDir\users-api.yaml"
kubectl apply -f "$ScriptDir\catalog-api.yaml"
kubectl apply -f "$ScriptDir\payments-api.yaml"
Success "APIs deployadas"

Info "Deployando Ingress..."
kubectl apply -f "$ScriptDir\ingress.yaml"
Success "Ingress fcg-ingress criado"

Write-Host ""
Info "Aguardando pods ficarem prontos (max 180s)..."
kubectl wait --for=condition=ready pod -l app=users-api    -n fcg --timeout=180s
kubectl wait --for=condition=ready pod -l app=catalog-api  -n fcg --timeout=180s
kubectl wait --for=condition=ready pod -l app=payments-api -n fcg --timeout=180s

Write-Host ""
Success "Bootstrap concluido!"
Write-Host ""
kubectl get pods -n fcg
Write-Host ""
Write-Host "Proximos passos:" -ForegroundColor White
Write-Host "  1. Verifique os pods acima — todos devem estar Running"
Write-Host "  2. O ingress esta disponivel em: http://localhost"
Write-Host "  3. Atualize o Terraform com as URLs e rode deploy.ps1"
