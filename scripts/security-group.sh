#!/usr/bin/env bash
# =====================================================================
# Abre en el Security Group de la instancia los puertos acordados:
#   - 22         (SSH):   solo a la IP pública desde donde ejecutas esto
#   - 8080-8084  (stack): público (api, consumers y kafka-ui)
#
# Requiere AWS CLI configurado (aws configure).
# Si SG_ID está vacío en config.sh, intenta autodetectar el Security
# Group buscando la instancia por su IP pública.
#
# Uso:
#   ./scripts/security-group.sh
# =====================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=config.sh
source "${SCRIPT_DIR}/config.sh"

if ! command -v aws >/dev/null 2>&1; then
  echo "ERROR: AWS CLI no está instalado/configurado (aws configure)" >&2
  exit 1
fi
if [[ -z "$EC2_HOST" ]]; then
  echo "ERROR: definí EC2_HOST en scripts/config.sh (o pasalo como variable de entorno)" >&2
  exit 1
fi

MY_IP=$(curl -fsS https://checkip.amazonaws.com | tr -d '[:space:]')
if [[ -z "$MY_IP" ]]; then
  echo "ERROR: no se pudo determinar tu IP pública" >&2
  exit 1
fi

SG="$SG_ID"
if [[ -z "$SG" ]]; then
  echo "-- Autodetectando Security Group de la instancia ${EC2_HOST} --"
  SG=$(aws ec2 describe-instances --region "$AWS_REGION" \
    --filters "Name=ip-address,Values=${EC2_HOST}" "Name=instance-state-name,Values=running" \
    --query 'Reservations[].Instances[0].SecurityGroups[0].GroupId' --output text 2>/dev/null | head -1)
  if [[ -z "$SG" || "$SG" == "None" ]]; then
    echo "ERROR: no se pudo autodetectar el Security Group." >&2
    echo "  - Verifica AWS_REGION en scripts/config.sh" >&2
    echo "  - O define SG_ID manualmente en scripts/config.sh" >&2
    exit 1
  fi
  echo "   detectado: $SG (si la instancia tiene varios SG, solo se usa el primero;"
  echo "   define SG_ID en config.sh para elegir otro)"
fi

echo "== Configurando Security Group $SG =="

add_rule() {
  if aws ec2 authorize-security-group-ingress --region "$AWS_REGION" --group-id "$SG" "$@" >/dev/null 2>&1; then
    echo "   regla agregada: $*"
  else
    echo "   regla ya existente (ok): $*"
  fi
}

echo "   tu IP pública: $MY_IP (SSH quedará restringido a ella)"
add_rule --protocol tcp --port 22 --cidr "${MY_IP}/32"
add_rule --protocol tcp --port 8080-8084 --cidr 0.0.0.0/0

echo "== Listo =="
echo "   SSH:        puerto 22 solo desde ${MY_IP}"
echo "   Stack:      8080-8084 abiertos a todo internet"
echo "   kafka 9092: queda interno (no se abre)"
