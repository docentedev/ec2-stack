# =====================================================================
# Verifica el estado del stack contra la IP/DNS publica del EC2.
# Version Windows (PowerShell) de verify.sh. Usa curl.exe (incluido
# en Windows 10 1803+). Asume que el Security Group ya tiene 8080-8084
# abiertos (ver .\scripts\security-group.ps1).
#
# Uso:
#   .\scripts\verify.ps1
# =====================================================================
#Requires -Version 5.1
$ErrorActionPreference = "Stop"

. "$PSScriptRoot\config.ps1"
if (-not $EC2_HOST) { throw "defini EC2_HOST en scripts\config.ps1 (o con `$env:EC2_HOST)" }

# En Windows PowerShell 5.1 "curl" es un alias de Invoke-WebRequest: usar curl.exe.
# En pwsh (Windows/Linux/macOS) existe curl a secas. Fallback nativo si no hay ninguno.
$curlCmd = if (Get-Command curl.exe -ErrorAction SilentlyContinue) { "curl.exe" }
           elseif (Get-Command curl -ErrorAction SilentlyContinue) { "curl" }
           else { $null }

# GET HTTP nativo de PowerShell (para cuando no hay curl en el sistema)
function Get-Http {
    param([string]$Url, [switch]$StatusCodeOnly)
    try {
        # sin proxy, timeout 10s, no cachea errores de SSL en sesion
        $resp = Invoke-WebRequest -Uri $Url -TimeoutSec 10 -UseBasicParsing -Proxy $null
        if ($StatusCodeOnly) { return [string]$resp.StatusCode }
        return $resp.Content
    } catch [Exception] { return $null }
}

$checks = @(
    @{ Name = "api";                  Url = "http://${EC2_HOST}:8080/health" },
    @{ Name = "consumer-analiticas";  Url = "http://${EC2_HOST}:8081/health" },
    @{ Name = "consumer-notificaciones"; Url = "http://${EC2_HOST}:8082/health" },
    @{ Name = "consumer-pagos";       Url = "http://${EC2_HOST}:8083/health" },
    @{ Name = "kafka-ui";            Url = "http://${EC2_HOST}:8084" }
)

Write-Host "== Verificacion contra http://$EC2_HOST =="

$failed = 0
foreach ($c in $checks) {
    if ($c.Name -eq "kafka-ui") {
        # solo el codigo HTTP (el body es HTML grande)
        if ($curlCmd) {
            $code = & $curlCmd -fsS -m 10 -o NUL -w "%{http_code}" $c.Url
            $ok = ($LASTEXITCODE -eq 0 -and "$code" -match "^2\d\d$")
        } else {
            $code = Get-Http -Url $c.Url -StatusCodeOnly
            $ok = ("$code" -match "^2\d\d$")
        }
        if ($ok) {
            Write-Host ("OK    {0}  ({1}) -> HTTP {2}" -f $c.Name, $c.Url, $code)
        } else {
            Write-Host ("FALLO {0}  ({1})" -f $c.Name, $c.Url)
            $failed++
        }
    } else {
        if ($curlCmd) {
            $body = & $curlCmd -fsS -m 10 $c.Url
            $ok = ($LASTEXITCODE -eq 0)
        } else {
            $body = Get-Http -Url $c.Url
            $ok = ($null -ne $body)
        }
        if ($ok) {
            Write-Host ("OK    {0}  ({1}) -> {2}" -f $c.Name, $c.Url, ($body -join ""))
        } else {
            Write-Host ("FALLO {0}  ({1})" -f $c.Name, $c.Url)
            $failed++
        }
    }
}

if ($failed -gt 0) {
    Write-Host ""
    Write-Host "$failed servicio(s) sin responder. Posibles causas:"
    Write-Host "  - Security Group sin puertos abiertos -> .\scripts\security-group.ps1"
    Write-Host "  - servicios caidos -> ssh y revisar: sudo docker compose ps / logs"
    exit 1
}
Write-Host "Todos los servicios responden."
