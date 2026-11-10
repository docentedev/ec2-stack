#!/usr/bin/env bash
# =====================================================================
# Prueba end-to-end: API (producer) -> Kafka -> 3 consumers -> DynamoDB.
# Solo usa curl + AWS CLI local (sin ssh). Compara el conteo de items
# antes/despues y verifica que el item nuevo exista en las 3 tablas.
#
# Uso:  ./scripts/e2e-dynamo.sh [mensaje]
# =====================================================================
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=config.sh
source "${SCRIPT_DIR}/config.sh"
export AWS_PAGER=""
R="${AWS_REGION:-us-east-2}"
TABLES=(pagos notificaciones analiticas)

cnt() { aws dynamodb scan --region "$R" --table-name "$1" --select COUNT --query Count --output text; }

BEFORE=()
echo "-- ANTES --"
i=0; for t in "${TABLES[@]}"; do BEFORE[$i]=$(cnt "$t"); echo "   $t=${BEFORE[$i]}"; i=$((i+1)); done

MSJ="${1:-e2e-$(date +%s)}"
echo "-- Publicando '${MSJ}' via la api --"
RESP=$(curl -fsS -m 15 "http://${EC2_HOST}:8080/topic-test?msj=${MSJ}") || { echo "ERROR: la api no respondio" >&2; exit 1; }
echo "   $RESP"
P=$(echo "$RESP" | grep -oE '"particion":[0-9]+' | cut -d: -f2)
O=$(echo "$RESP" | grep -oE '"offset":[0-9]+' | cut -d: -f2)
PK="pagos-${P}-${O}"

echo "-- Esperando 6s a los consumers --"; sleep 6

echo "-- DESPUES (pk=${PK}) --"
FAILS=0; i=0
for t in "${TABLES[@]}"; do
  v=$(aws dynamodb get-item --region "$R" --table-name "$t" --key "{\"PK\":{\"S\":\"${PK}\"}}" \
        --query 'Item.mensaje.S' --output text 2>/dev/null)
  after=$(cnt "$t")
  if echo "$v" | grep -qF "$MSJ"; then ok=SI; else ok=NO; FAILS=$((FAILS+1)); fi
  echo "   $t: items ${BEFORE[$i]} -> ${after}  contiene_mensaje=${ok}"
  i=$((i+1))
done

if [ "$FAILS" -gt 0 ]; then echo "== FALLO: $FAILS tabla(s) sin el item =="; exit 1; fi
echo "== OK: el mensaje paso por producer, kafka y los 3 consumers hasta DynamoDB =="
