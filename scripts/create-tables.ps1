# =====================================================================
# Crea las 3 tablas DynamoDB para los consumers (fase 3) - version Windows (PowerShell).
#   - pagos           -> consumer del grupo "pagos"           (guarda mensajes de pagos)
#   - notificaciones -> consumer del grupo "notificaciones"
#   - analiticas     -> consumer del grupo "analiticas"
# Billing: PAY_PER_REQUEST (lo mas economico; la cuenta tiene 1 ano gratis).
#
# Requiere AWS CLI configurado (aws configure).
#
# Uso:
#   .\scripts\create-tables.ps1
# =====================================================================
#Requires -Version 5.1
$ErrorActionPreference = "Stop"

. "$PSScriptRoot\config.ps1"

function New-Table {
    param([string]$TableName)
    Write-Host "-- Creando tabla DynamoDB: $TableName ..."
    $describe = & aws dynamodb describe-table --region $AWS_REGION --table-name $TableName 2>$null
    if ($LASTEXITCODE -eq 0) {
        Write-Host "   tabla ya existe: $TableName (OK, no se crea otra vez)"
    } else {
        & aws dynamodb create-table `
            --region $AWS_REGION `
            --table-name $TableName `
            --attribute-definitions AttributeName=PK,AttributeType=S `
            --key-schema AttributeName=PK,KeyType=HASH `
            --billing-mode PAY_PER_REQUEST
        Write-Host "   tabla creada: $TableName"
    }
}

New-Table pagos
New-Table notificaciones
New-Table analiticas

Write-Host "== Tablas DynamoDB listas =="
foreach ($t in @("pagos", "notificaciones", "analiticas")) {
    & aws dynamodb describe-table --region $AWS_REGION --table-name $t `
        --query "Table.{Nombre:TableName, BillingMode:BillingMode, Clave:KeySchema}" --output json
}
