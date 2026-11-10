# =====================================================================
# Abre en el Security Group de la instancia los puertos acordados:
#   - 22         (SSH):   solo a la IP publica desde donde ejecutas esto
#   - 8080-8084  (stack): publico (api, consumers y kafka-ui)
#
# Version Windows (PowerShell) de security-group.sh. Requiere AWS CLI
# configurado (aws configure).
#
# Uso:
#   .\scripts\security-group.ps1
# =====================================================================
#Requires -Version 5.1
$ErrorActionPreference = "Stop"

. "$PSScriptRoot\config.ps1"

if (-not (Get-Command aws -ErrorAction SilentlyContinue)) {
    throw "AWS CLI no esta instalado/configurado (aws configure)"
}
if (-not $EC2_HOST) { throw "defini EC2_HOST en scripts\config.ps1 (o con `$env:EC2_HOST)" }

# IP publica propia
$myIp = (Invoke-RestMethod -Uri "https://checkip.amazonaws.com").ToString().Trim()
if (-not $myIp) { throw "no se pudo determinar tu IP publica" }

$sg = $SG_ID
if (-not $sg) {
    Write-Host "-- Autodetectando Security Group de la instancia $EC2_HOST --"
    $json = & aws ec2 describe-instances --region $AWS_REGION `
        --filters "Name=ip-address,Values=$EC2_HOST" "Name=instance-state-name,Values=running" `
        --query "Reservations[].Instances[0].SecurityGroups[0].GroupId" --output json
    if ($LASTEXITCODE -ne 0) { throw "no se pudo consultar la instancia (region correcta en config.ps1?)" }
    $sg = ($json | ConvertFrom-Json)
    if ($sg -is [array]) { $sg = $sg[0] }
    if (-not $sg) {
        throw "no se pudo autodetectar el Security Group. Define SG_ID en scripts\config.ps1"
    }
    Write-Host "   detectado: $sg (si la instancia tiene varios SG, solo se usa el primero;"
    Write-Host "   define SG_ID en config.ps1 para elegir otro)"
}

Write-Host "== Configurando Security Group $sg =="
Write-Host "   tu IP publica: $myIp (SSH quedara restringido a ella)"

function Add-Rule {
    param([string]$Description, [string[]]$RuleArgs)
    & aws ec2 authorize-security-group-ingress --region $AWS_REGION --group-id $sg @RuleArgs
    if ($LASTEXITCODE -eq 0) {
        Write-Host "   regla agregada: $Description"
    } else {
        # aws devuelve error si la regla ya existe (InvalidPermission.Duplicate)
        Write-Host "   regla ya existente (ok): $Description"
    }
}

Add-Rule "SSH 22 solo desde $myIp"        @("--protocol", "tcp", "--port", "22", "--cidr", "$myIp/32")
Add-Rule "stack 8080-8084 a todo internet" @("--protocol", "tcp", "--port", "8080-8084", "--cidr", "0.0.0.0/0")

Write-Host "== Listo =="
Write-Host "   SSH:        puerto 22 solo desde $myIp"
Write-Host "   Stack:      8080-8084 abiertos a todo internet"
Write-Host "   kafka 9092: queda interno (no se abre)"
