#!/usr/bin/env bash
# =====================================================================
# Despliegue completo del stack Docker en el EC2 (partir de cero):
#   1. Limpieza del stack anterior (omitir con --skip-cleanup)
#   2. Verificación/instalación de Docker + Compose en el EC2
#   3. Swap de emergencia si la instancia es chica (el build de Gradle
#      de la api necesita memoria)
#   4. rsync del proyecto (sin node_modules/build/.gradle/.git/*.pem)
#   5. docker compose up -d --build
#   6. Health checks de todos los servicios
#
# Uso:
#   ./scripts/deploy.sh                  # limpia el stack viejo + despliega
#   ./scripts/deploy.sh --skip-cleanup   # solo despliega
# =====================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=config.sh
source "${SCRIPT_DIR}/config.sh"

SKIP_CLEANUP=0
if [[ "${1:-}" == "--skip-cleanup" ]]; then
  SKIP_CLEANUP=1
fi

if [[ -z "$EC2_HOST" ]]; then
  echo "ERROR: definí EC2_HOST en scripts/config.sh (o pasalo como variable de entorno)" >&2
  exit 1
fi
if [[ ! -f "$KEY_PATH" ]]; then
  echo "ERROR: no existe la llave en $KEY_PATH" >&2
  exit 1
fi
# ssh rechaza llaves demasiado abiertas
chmod 600 "$KEY_PATH" 2>/dev/null || true

SSH_BASE=(ssh -i "$KEY_PATH" -o BatchMode=yes -o StrictHostKeyChecking=accept-new "${EC2_USER}@${EC2_HOST}")

echo "== Despliegue del stack en ${EC2_USER}@${EC2_HOST} =="

# ------------------------------------------------------------------ 1. limpieza
if [[ "$SKIP_CLEANUP" -eq 0 ]]; then
  bash "${SCRIPT_DIR}/cleanup.sh"
else
  echo "-- (limpieza omitida con --skip-cleanup) --"
fi

# ------------------------------------------------------------------ 2. conectividad
echo "-- Verificando conexión SSH --"
if ! "${SSH_BASE[@]}" true 2>/dev/null; then
  echo "ERROR: no se pudo conectar a ${EC2_USER}@${EC2_HOST} con $KEY_PATH" >&2
  exit 1
fi
echo "   OK"

# ------------------------------------------------------------------ 3. docker en el EC2
echo "-- Verificando Docker en el EC2 --"
"${SSH_BASE[@]}" bash -s <<'REMOTE'
set -euo pipefail
if ! command -v docker >/dev/null 2>&1; then
  if [ -f /etc/os-release ] && grep -q 'ID="amzn"' /etc/os-release; then
    # Amazon Linux (2/2023): get.docker.com NO soporta "amzn"; usar repos de AWS
    echo "   Docker no está instalado: instalando desde repos de Amazon Linux..."
    if command -v dnf >/dev/null 2>&1; then PKG=dnf; else PKG=yum; fi
    sudo "$PKG" install -y docker
    sudo systemctl enable --now docker
  else
    echo "   Docker no está instalado: instalando (get.docker.com)..."
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
  echo "ERROR: el plugin docker compose no está disponible en el EC2" >&2
  exit 1
fi
# compose v5 exige buildx >= 0.17.0 (el docker de Amazon Linux trae 0.12.1 viejo)
buildx_version_ok() {
  v=$(sudo docker buildx version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
  [ -n "$v" ] && [ "$(printf '%s\n' "0.17.0" "$v" | sort -V | head -1)" = "0.17.0" ]
}
if ! buildx_version_ok; then
  echo "   buildx ausente o viejo (<0.17.0): descargando versión reciente de GitHub..."
  case "$(uname -m)" in
    x86_64) buildx_arch=amd64 ;;   # los assets de buildx usan amd64/arm64, no x86_64/aarch64
    aarch64|arm64) buildx_arch=arm64 ;;
    *) echo "ERROR: arquitectura no soportada para buildx: $(uname -m)" >&2; exit 1 ;;
  esac
  buildx_version=$(curl -fsSL https://api.github.com/repos/docker/buildx/releases/latest \
    | grep -oE '"tag_name": *"v[0-9.]+"' | head -1 | grep -oE 'v[0-9.]+')
  # fallback si la API de GitHub falla (rate limit): versión fijada que cumple >= 0.17.0
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
REMOTE

# ------------------------------------------------------------------ 4. rsync del proyecto
echo "-- Sincronizando proyecto al EC2 (${REMOTE_DIR}/) --"
rsync -az --delete \
  --exclude 'node_modules/' \
  --exclude '.gradle/' \
  --exclude 'build/' \
  --exclude '.git/' \
  --exclude '*.pem' \
  --exclude '.DS_Store' \
  -e "ssh -i ${KEY_PATH} -o StrictHostKeyChecking=accept-new" \
  "${PROJECT_ROOT}/" "${EC2_USER}@${EC2_HOST}:${REMOTE_DIR}/"
echo "   OK"

# ------------------------------------------------------------------ 5. build + up
echo "-- Levantando stack (docker compose up -d --build) --"
echo "   (la primera build de la api descarta Gradle y demora varios minutos)"
"${SSH_BASE[@]}" bash -s -- "$REMOTE_DIR" <<'REMOTE'
set -euo pipefail
cd "$HOME/$1"
sudo docker compose up -d --build
REMOTE

# ------------------------------------------------------------------ 6. health checks
echo "-- Health checks --"
"${SSH_BASE[@]}" bash -s <<'REMOTE'
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

# la api demora más la primera vez (build de Gradle + arranque de Spring)
check api                  http://localhost:8080/health 60
check consumer-analiticas  http://localhost:8081/health 20
check consumer-notificaciones http://localhost:8082/health 20
check consumer-pagos       http://localhost:8083/health 20
check kafka-ui             http://localhost:8084        20

if [ "$FAILS" -gt 0 ]; then
  echo ""
  echo "   $FAILS servicio(s) sin responder. Ver logs con:"
  echo "     ${USER}@\$(hostname):~/proyectoFinal\$ sudo docker compose logs"
  exit 1
fi
echo "   Todos los servicios responden."
REMOTE

echo ""
echo "== Despliegue terminado =="
echo "   health api:             http://${EC2_HOST}:8080/health"
echo "   health analiticas:      http://${EC2_HOST}:8081/health"
echo "   health notificaciones:  http://${EC2_HOST}:8082/health"
echo "   health pagos:           http://${EC2_HOST}:8083/health"
echo "   kafka-ui:               http://${EC2_HOST}:8084"
echo "   (requiere puertos abiertos: ./scripts/security-group.sh)"
