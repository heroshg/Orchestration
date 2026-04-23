# Builda as imagens de todos os serviços antes de executar o docker compose.
# Uso: .\build.ps1 [--no-cache]
#
# Após o build, suba o ambiente com:
#   docker compose up -d

param([switch]$NoCache)

$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

$services = @(
    @{ Image = "users-api";    Context = "..\UsersAPI" },
    @{ Image = "catalog-api";  Context = "..\CatalogAPI" },
    @{ Image = "payments-api"; Context = "..\PaymentsAPI" }
)

foreach ($svc in $services) {
    $context = Join-Path $ScriptDir $svc.Context
    Write-Host "Building $($svc.Image)..."
    $args = @("build", "-t", "$($svc.Image):latest", $context)
    if ($NoCache) { $args = @("build", "--no-cache", "-t", "$($svc.Image):latest", $context) }
    docker @args
}

Write-Host ""
Write-Host "Todas as imagens buildadas. Execute: docker compose up -d"
