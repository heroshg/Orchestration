# =============================================================================
# Empacota a NotificationsLambda em um .zip para o LocalStack carregar (Windows).
# =============================================================================
$ErrorActionPreference = "Stop"

$ScriptDir   = Split-Path -Parent $MyInvocation.MyCommand.Path
$LambdaSrc   = Join-Path $ScriptDir "..\..\..\NotificationsLambda\src\NotificationsLambda"
$BuildDir    = Join-Path $ScriptDir ".build"
$PublishDir  = Join-Path $BuildDir  "notifications-lambda"
$ZipPath     = Join-Path $BuildDir  "notifications-lambda.zip"

if (Test-Path $PublishDir) { Remove-Item -Recurse -Force $PublishDir }
if (Test-Path $ZipPath)    { Remove-Item -Force $ZipPath }
New-Item -ItemType Directory -Path $PublishDir | Out-Null

dotnet publish (Join-Path $LambdaSrc "NotificationsLambda.csproj") `
  --configuration Release `
  --runtime linux-x64 `
  --self-contained false `
  --output $PublishDir

Compress-Archive -Path (Join-Path $PublishDir "*") -DestinationPath $ZipPath -Force
Write-Host "Lambda empacotada em: $ZipPath"
