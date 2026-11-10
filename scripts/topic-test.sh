#!/usr/bin/env bash
# =====================================================================
# Prueba end-to-end del flujo kafka:
#   1. Publica un mensaje via el endpoint de la api: /topic-test?msj=<MSJ>
#   2. Espera unos segundos a que los consumers lo procesen
#   3. Verifica en los LOGS de los 3 consumers que cada grupo recibio el mensaje
#
# Uso:
#   ./scripts/topic-test.sh              # mensaje "test"
#   ./scripts/topic-test.sh "hola123"   # mensaje personalizado
# =====================================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=config.sh
source "${SCRIPT_DIR}/config.sh"

if [[ -z "$EC2_HOST" ]]; then
  echo "ERROR: definí EC2_HOST en scripts/config.sh (o pasalo como variable de entorno)" >&2
  exit 1
fi
if [[ ! -f "$KEY_PATH" ]]; then
  echo "ERROR: no existe la llave en $KEY_PATH" >&2
  exit 1
fi

MSJ="${1:-test}"

echo "== Prueba del flujo kafka: /topic-test?msj=${MSJ} =="

# ------------------------------------------------------------------ 1. publicar
echo "-- 1. Publicando via la api --"
RESPONSE=$(curl -fsS -m 15 "http://${EC2_HOST}:8080/topic-test?msj=${MSJ}") || {
  echo "ERROR: la api no respondio en http://${EC2_HOST}:8080/topic-test" >&2
  exit 1
}
echo "   respuesta de la api: $RESPONSE"

# ------------------------------------------------------------------ 2. esperar proceso
echo "-- 2. Esperando 6s a que los 3 grupos procesen el mensaje --"
sleep 6

# ------------------------------------------------------------------ 3. verificar en logs
echo "-- 3. Verificando recepcion en los consumers (via ssh) --"
SSH_BASE=(ssh -i "$KEY_PATH" -o BatchMode=yes -o StrictHostKeyChecking=accept-new "${EC2_USER}@${EC2_HOST}")

"${SSH_BASE[@]}" bash -s -- "$REMOTE_DIR" "$MSJ" <<'REMOTE'
set -uo pipefail
REMOTE_DIR="$1"; MSJ="$2"
cd "$HOME/$REMOTE_DIR"

FAILS=0
for consumer in consumer-analiticas consumer-notificaciones consumer-pagos; do
  if sudo docker compose logs --tail 30 "$consumer" 2>/dev/null | grep -F "\"mensaje\":\"${MSJ}\"" | tail -1; then
    echo "   OK    $consumer recibio el mensaje"
  else
    echo "   FALLO $consumer NO recibio el mensaje"
    FAILS=$((FAILS+1))
  fi
done

if [ "$FAILS" -gt 0 ]; then
  echo ""
  echo "   $FAILS consumer(s) sin el mensaje. Ver estado con:"
  echo "     sudo docker compose ps"
  echo "     sudo docker compose logs consumer-analiticas consumer-notificaciones consumer-pagos"
  exit 1
fi
REMOTE
RC=$?

if [ $RC -ne 0 ]; then
  echo "== Prueba FALLIDA =="
  exit 1
fi

echo "== Prueba OK: el mensaje llego a los 3 grupos (analiticas, notificaciones, pagos) =="