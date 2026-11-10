#!/usr/bin/env bash
# =====================================================================
# Crea las 3 tablas DynamoDB para los consumers (fase 3).
#   - pagos           -> consumer del grupo "pagos"           (guarda mensajes de pagos)
#   - notificaciones -> consumer del grupo "notificaciones"
#   - analiticas     -> consumer del grupo "analiticas"
# Billing: PAY_PER_REQUEST (lo mas economico; la cuenta tiene 1 ano gratis).
#
# Requiere AWS CLI configurado (aws configure) y region en scripts/config.sh.
#
# Uso:
#   ./scripts/create-tables.sh
# =====================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=config.sh
source "${SCRIPT_DIR}/config.sh"

if ! command -v aws >/dev/null 2>&1; then
  echo "ERROR: AWS CLI no instalado/configurado (aws configure)" >&2
  exit 1
fi
if [[ -z "$EC2_HOST" ]]; then
  echo "ERROR: definí EC2_HOST en scripts/config.sh" >&2
  exit 1
fi

create_table() {
  local TABLE_NAME="$1"
  echo "-- Creando tabla DynamoDB: $TABLE_NAME ..."
  if aws dynamodb describe-table --region "$AWS_REGION" --table-name "$TABLE_NAME" >/dev/null 2>&1; then
    echo "   tabla ya existe: $TABLE_NAME (OK, no se crea otra vez)"
  else
    aws dynamodb create-table \
      --region "$AWS_REGION" \
      --table-name "$TABLE_NAME" \
      --attribute-definitions AttributeName=PK,AttributeType=S \
      --key-schema AttributeName=PK,KeyType=HASH \
      --billing-mode PAY_PER_REQUEST
    echo "   tabla creada: $TABLE_NAME"
  fi
}

create_table pagos
create_table notificaciones
create_table analiticas

echo "== Tablas DynamoDB listas =="
for t in pagos notificaciones analiticas; do
  aws dynamodb describe-table --region "$AWS_REGION" --table-name "$t" \
    --query "Table.{Nombre:TableName, BillingMode:BillingMode, Clave:KeySchema}" --output json
done
