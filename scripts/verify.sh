#!/usr/bin/env bash
# =====================================================================
# Verifica el estado del stack contra la IP/DNS pública del EC2.
# Asume que el Security Group ya tiene 8080-8084 abiertos
# (ver scripts/security-group.sh).
#
# Uso:
#   ./scripts/verify.sh          # desde la máquina local
# =====================================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=config.sh
source "${SCRIPT_DIR}/config.sh"

if [[ -z "$EC2_HOST" ]]; then
  echo "ERROR: definí EC2_HOST en scripts/config.sh (o pasalo como variable de entorno)" >&2
  exit 1
fi

FAILS=0

check() {
  name="$1"; url="$2"
  if body=$(curl -fsS -m 10 "$url" 2>/dev/null); then
    echo "OK    $name  ($url) -> $body"
  else
    echo "FALLO $name  ($url)"
    FAILS=$((FAILS+1))
  fi
}

echo "== Verificación contra http://${EC2_HOST} =="

check "api"                 "http://${EC2_HOST}:8080/health"
check "consumer-analiticas" "http://${EC2_HOST}:8081/health"
check "consumer-notificaciones" "http://${EC2_HOST}:8082/health"
check "consumer-pagos"      "http://${EC2_HOST}:8083/health"
check "kafka-ui"            "http://${EC2_HOST}:8084"

if [ "$FAILS" -gt 0 ]; then
  echo ""
  echo "$FAILS servicio(s) sin responder. Posibles causas:"
  echo "  - Security Group sin puertos abiertos -> ./scripts/security-group.sh"
  echo "  - servicios caidos -> ssh y revisar: sudo docker compose ps / logs"
  exit 1
fi
echo "Todos los servicios responden."
