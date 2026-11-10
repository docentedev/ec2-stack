# =====================================================================
# Prueba end-to-end del flujo kafka (version Windows de topic-test.sh):
#   1. Publica un mensaje via el endpoint de la api: /topic-test?msj=<MSJ>
#   2. Espera unos segundos a que los consumers lo procesen
#   3. Verifica en los LOGS de los 3 consumers que cada grupo recibio el mensaje
#
# Uso:
#   .\scripts\topic-test.ps1               # mensaje "test"
#   .\scripts\topic-test.ps1 -Mensaje "hola123"
# =====================================================================
#Requires -Version 5.1
[CmdletBinding()]
param(
    [string]$Mensaje = "test"
)
$ErrorActionPreference = "Stop"

. "$PSScriptRoot\config.ps1"
Assert-Config

Write-Host "== Prueba del flujo kafka: /topic-test?msj=$Mensaje =="

# ------------------------------------------------------------------ 1. publicar
Write-Host "-- 1. Publicando via la api --"
$curlCmd = if (Get-Command curl.exe -ErrorAction SilentlyContinue) { "curl.exe" } else { "curl" }
$response = & $curlCmd -fsS -m 15 "http://${EC2_HOST}:8080/topic-test?msj=$Mensaje"
if ($LASTEXITCODE -ne 0) {
    throw "la api no respondio en http://${EC2_HOST}:8080/topic-test"
}
Write-Host "   respuesta de la api: $response"

# ------------------------------------------------------------------ 2. esperar proceso
Write-Host "-- 2. Esperando 6s a que los 3 grupos procesen el mensaje --"
Start-Sleep -Seconds 6

# ------------------------------------------------------------------ 3. verificar en logs
Write-Host "-- 3. Verificando recepcion en los consumers (via ssh) --"
# Here-string con comilla simple: los $ pasan literales al script bash remoto
$remote = 'set -uo pipefail
REMOTE_DIR="$1"
MSJ="$2"
cd "$HOME/$REMOTE_DIR"

FAILS=0
for consumer in consumer-analiticas consumer-notificaciones consumer-pagos; do
  if sudo docker compose logs --tail 30 "$consumer" 2>/dev/null | grep -F "\"mensaje\":\"$MSJ\"" | tail -1; then
    echo "   OK    $consumer recibio el mensaje"
  else
    echo "   FALLO $consumer NO recibio el mensaje"
    FAILS=$((FAILS+1))
  fi
done

if [ "$FAILS" -gt 0 ]; then
  echo ""
  echo "   $FAILS consumer(s) sin el mensaje."
  exit 1
fi'

Invoke-Remote -ScriptBody $remote -ScriptArgs @($REMOTE_DIR, $Mensaje)

Write-Host "== Prueba OK: el mensaje llego a los 3 grupos (analiticas, notificaciones, pagos) =="
