param(
    [string]$Environment  = "production",
    [string]$UsersApiUrl  = $env:USERS_API_URL,
    [string]$CatalogApiUrl = $env:CATALOG_API_URL,
    [string]$JwtKey       = $env:JWT_KEY,
    [string]$DdApiKey     = $env:DD_API_KEY,
    [string]$AwsRegion    = $env:AWS_REGION,
    [string]$DdSite       = $env:DD_SITE
)

$ErrorActionPreference = "Stop"
if (-not $AwsRegion) { $AwsRegion = "us-east-1" }
if (-not $DdSite)    { $DdSite    = "datadoghq.com" }
$ScriptDir  = $PSScriptRoot
$BuildDir   = "$ScriptDir\.build\notifications-lambda"
$ZipPath    = "$ScriptDir\.build\notifications-lambda.zip"
$LambdaSrc  = "$ScriptDir\..\..\..\NotificationsLambda\src\NotificationsLambda\NotificationsLambda.csproj"

if (-not $JwtKey)     { Write-Error "Defina JWT_KEY ou passe -JwtKey"; exit 1 }
if (-not $DdApiKey)   { Write-Error "Defina DD_API_KEY ou passe -DdApiKey"; exit 1 }

Write-Host "[INFO] Buildando NotificationsLambda..." -ForegroundColor Cyan
New-Item -ItemType Directory -Force -Path $BuildDir | Out-Null
dotnet publish $LambdaSrc `
    --configuration Release `
    --runtime linux-arm64 `
    --self-contained false `
    --output $BuildDir

Write-Host "[INFO] Compactando zip..." -ForegroundColor Cyan
Compress-Archive -Path "$BuildDir\*" -DestinationPath $ZipPath -Force

Write-Host "[INFO] Executando terraform apply..." -ForegroundColor Cyan
Set-Location $ScriptDir
terraform init -upgrade | Out-Null

$tfVars = @(
    "-var=environment=$Environment",
    "-var=aws_region=$AwsRegion",
    "-var=jwt_key=$JwtKey",
    "-var=jwt_issuer=FiapCloudGames",
    "-var=jwt_audience=FiapCloudGames",
    "-var=dd_api_key=$DdApiKey",
    "-var=dd_site=$DdSite"
)

if ($UsersApiUrl)   { $tfVars += "-var=users_api_url=$UsersApiUrl" }
if ($CatalogApiUrl) { $tfVars += "-var=catalog_api_url=$CatalogApiUrl" }

terraform apply @tfVars

Write-Host ""
Write-Host "[OK] Deploy concluído!" -ForegroundColor Green
terraform output
