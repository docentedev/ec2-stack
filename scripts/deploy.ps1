# =====================================================================
# Despliegue completo del stack Docker en el EC2 (partir de cero).
# Version Windows (PowerShell) de deploy.sh.
#
#   1. Limpieza del stack anterior (omitir con -SkipCleanup)
#   2. Verificacion/instalacion de Docker + Compose + buildx en el EC2
#   3. Swap de emergencia si la instancia es chica (build de Gradle)
#   4. Empaquetado del proyecto con tar + scp (equivalente a rsync)
#   5. docker compose up -d --build
#   6. Health checks de todos los servicios
#
# Uso:
#   .\scripts\deploy.ps1               # limpia el stack viejo + despliega
#   .\scripts\deploy.ps1 -SkipCleanup  # solo despliega
#
# Nota: en vez de rsync (no existe en Windows) se empaqueta con tar
# (incluido en Windows 10 1803+) y se sube con scp.
# =====================================================================
#Requires -Version 5.1
[CmdletBinding()]
param(
    [switch]$SkipCleanup
)
$ErrorActionPreference = "Stop"

. "$PSScriptRoot\config.ps1"
Assert-Config

Write-Host "== Despliegue del stack en ${EC2_USER}@${EC2_HOST} =="

# ------------------------------------------------------------------ 1. limpieza
if (-not $SkipCleanup) {
    & "$PSScriptRoot\cleanup.ps1"
} else {
    Write-Host "-- (limpieza omitida con -SkipCleanup) --"
}

# ------------------------------------------------------------------ 2. conectividad
Write-Host "-- Verificando conexion SSH --"
& ssh @script:SSH_BASE "${EC2_USER}@${EC2_HOST}" "true"
if ($LASTEXITCODE -ne 0) { throw "no se pudo conectar a ${EC2_USER}@${EC2_HOST} con $KEY_PATH" }
Write-Host "   OK"

# ------------------------------------------------------------------ 3. docker en el EC2
# Mismo payload bash que deploy.sh (se ejecuta EN el EC2)
$dockerSetup = @'
set -euo pipefail
if ! command -v docker >/dev/null 2>&1; then
  if [ -f /etc/os-release ] && grep -q 'ID="amzn"' /etc/os-release; then
    # Amazon Linux (2/2023): get.docker.com NO soporta "amzn"; usar repos de AWS
    echo "   Docker no esta instalado: instalando desde repos de Amazon Linux..."
    if command -v dnf >/dev/null 2>&1; then PKG=dnf; else PKG=yum; fi
    sudo "$PKG" install -y docker
    sudo systemctl enable --now docker
  else
    echo "   Docker no esta instalado: instalando (get.docker.com)..."
    curl -fsSL https://get.docker.com | sudo sh
    sudo systemctl enable --now docker || true
  fi
  sudo usermod -aG docker "$USER" || true
fi
if ! sudo docker compose version >/dev/null 2>&1; then
  echo "   Plugin docker compose no encontrado en repos: descargando de GitHub..."
  case "$(uname -m)" in
    x86_64) compose_arch=x86_64 ;;
    aarch64|arm64) compose_arch=aarch64 ;;
    *) echo "ERROR: arquitectura no soportada para compose: $(uname -m)" >&2; exit 1 ;;
  esac
  sudo mkdir -p /usr/local/lib/docker/cli-plugins
  sudo curl -fsSL "https://github.com/docker/compose/releases/latest/download/docker-compose-linux-${compose_arch}" \
    -o /usr/local/lib/docker/cli-plugins/docker-compose
  sudo chmod +x /usr/local/lib/docker/cli-plugins/docker-compose
fi
if ! sudo docker compose version >/dev/null 2>&1; then
  echo "ERROR: el plugin docker compose no esta disponible en el EC2" >&2
  exit 1
fi

# compose v5 exige buildx >= 0.17.0 (el docker de Amazon Linux trae 0.12.1 viejo)
buildx_version_ok() {
  v=$(sudo docker buildx version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
  [ -n "$v" ] && [ "$(printf '%s\n' "0.17.0" "$v" | sort -V | head -1)" = "0.17.0" ]
}
if ! buildx_version_ok; then
  echo "   buildx ausente o viejo (<0.17.0): descargando version reciente de GitHub..."
  case "$(uname -m)" in
    x86_64) buildx_arch=amd64 ;;   # los assets de buildx usan amd64/arm64, no x86_64/aarch64
    aarch64|arm64) buildx_arch=arm64 ;;
    *) echo "ERROR: arquitectura no soportada para buildx: $(uname -m)" >&2; exit 1 ;;
  esac
  buildx_version=$(curl -fsSL https://api.github.com/repos/docker/buildx/releases/latest \
    | grep -oE '"tag_name": *"v[0-9.]+"' | head -1 | grep -oE 'v[0-9.]+')
  # fallback si la API de GitHub falla (rate limit): version fijada que cumple >= 0.17.0
  [ -z "$buildx_version" ] && buildx_version="v0.21.1"
  sudo mkdir -p /usr/local/lib/docker/cli-plugins
  sudo curl -fsSL "https://github.com/docker/buildx/releases/download/${buildx_version}/buildx-${buildx_version}.linux-${buildx_arch}" \
    -o /usr/local/lib/docker/cli-plugins/docker-buildx
  sudo chmod +x /usr/local/lib/docker/cli-plugins/docker-buildx
fi
if ! buildx_version_ok; then
  echo "ERROR: no se pudo obtener buildx >= 0.17.0" >&2
  exit 1
fi
sudo docker buildx version
sudo docker --version
sudo docker compose version

# swap de emergencia: el build de Gradle (api) necesita ~2GB
total_mb=$(free -m | awk '/^Mem:/{print $2}')
swap_mb=$(free -m | awk '/^Swap:/{print $2}')
if [ "${total_mb:-0}" -lt 2000 ] && [ "${swap_mb:-0}" -lt 1000 ] && [ ! -f /swapfile ]; then
  echo "   Instancia con poca RAM y sin swap: creando swap de 2G para el build..."
  sudo fallocate -l 2G /swapfile || sudo dd if=/dev/zero of=/swapfile bs=1M count=2048
  sudo chmod 600 /swapfile
  sudo mkswap /swapfile
  sudo swapon /swapfile
  echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab >/dev/null
fi
'@

Write-Host "-- Verificando Docker en el EC2 --"
Invoke-Remote -ScriptBody $dockerSetup

# ------------------------------------------------------------------ 4. empaquetar y subir proyecto
if (-not (Get-Command tar -ErrorAction SilentlyContinue)) {
    throw "tar no esta disponible (incluido en Windows 10 1803+)"
}
Write-Host "-- Empaquetando proyecto (tar) y subiendo al EC2 (~/$REMOTE_DIR/) --"
$tarFile = Join-Path ([IO.Path]::GetTempPath()) "proyectoFinal-deploy.tar.gz"
if (Test-Path $tarFile) { Remove-Item $tarFile -Force }

# Excludes equivalentes a los del rsync de deploy.sh.
# En bsdtar de Windows, un patron sin "/" coincide con cualquier componente de la ruta.
& tar -czf $tarFile -C $PROJECT_ROOT `
    --exclude node_modules `
    --exclude .gradle `
    --exclude build `
    --exclude .git `
    --exclude "*.pem" `
    --exclude .DS_Store `
    .
if ($LASTEXITCODE -ne 0) { throw "tar fallo al empaquetar el proyecto" }

& scp @script:SSH_BASE -q $tarFile "${EC2_USER}@${EC2_HOST}:proyectoFinal-deploy.tar.gz"
if ($LASTEXITCODE -ne 0) { throw "fallo scp del paquete del proyecto" }
Remove-Item $tarFile -Force

$extract = @'
set -euo pipefail
REMOTE_DIR="$1"
[ -n "$REMOTE_DIR" ] || { echo "ERROR: REMOTE_DIR vacio" >&2; exit 1; }
cd "$HOME"
rm -rf "$REMOTE_DIR"
mkdir "$REMOTE_DIR"
tar -xzf proyectoFinal-deploy.tar.gz -C "$REMOTE_DIR"
rm -f proyectoFinal-deploy.tar.gz
rm -f "$REMOTE_DIR"/*.pem 2>/dev/null || true   # doble seguridad: nunca dejar la llave en el EC2
echo "   proyecto extraido en ~/$REMOTE_DIR"
'@
Invoke-Remote -ScriptBody $extract -ScriptArgs @($REMOTE_DIR)

# ------------------------------------------------------------------ 5. build + up
Write-Host "-- Levantando stack (docker compose up -d --build) --"
Write-Host "   (la primera build de la api descarga Gradle y demora varios minutos)"
$composeUp = @'
set -euo pipefail
REMOTE_DIR="$1"
cd "$HOME/$REMOTE_DIR"
sudo docker compose up -d --build
'@
Invoke-Remote -ScriptBody $composeUp -ScriptArgs @($REMOTE_DIR)

# ------------------------------------------------------------------ 6. health checks
# Mismo payload bash que deploy.sh (se ejecuta EN el EC2)
$healthChecks = @'
set -uo pipefail
FAILS=0

check() {
  name="$1"; url="$2"; attempts="${3:-20}"
  for _ in $(seq 1 "$attempts"); do
    if curl -fsS "$url" >/dev/null 2>&1; then
      echo "   OK    $name  ($url)"
      return 0
    fi
    sleep 5
  done
  echo "   FALLO $name  ($url)"
  FAILS=$((FAILS+1))
  return 1
}

# la api demora mas la primera vez (build de Gradle + arranque de Spring)
check api                  http://localhost:8080/health 60
check consumer-analiticas  http://localhost:8081/health 20
check consumer-notificaciones http://localhost:8082/health 20
check consumer-pagos       http://localhost:8083/health 20
check kafka-ui             http://localhost:8084        20

if [ "$FAILS" -gt 0 ]; then
  echo ""
  echo "   $FAILS servicio(s) sin responder. Ver logs con:"
  echo "     ${USER}@$(hostname):~/proyectoFinal$ sudo docker compose logs"
  exit 1
fi
echo "   Todos los servicios responden."
'@

Write-Host "-- Health checks --"
Invoke-Remote -ScriptBody $healthChecks

Write-Host ""
Write-Host "== Despliegue terminado =="
Write-Host "   health api:             http://${EC2_HOST}:8080/health"
Write-Host "   health analiticas:      http://${EC2_HOST}:8081/health"
Write-Host "   health notificaciones:  http://${EC2_HOST}:8082/health"
Write-Host "   health pagos:           http://${EC2_HOST}:8083/health"
Write-Host "   kafka-ui:               http://${EC2_HOST}:8084"
Write-Host "   (requiere puertos abiertos: .\scripts\security-group.ps1)"
