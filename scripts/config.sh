#!/usr/bin/env bash
# =====================================================================
# Configuración de despliegue del proyecto final (EC2 único).
# EDITAR estos valores antes de ejecutar cualquier script.
# Todos pueden sobrescribirse como variable de entorno:
#   EC2_HOST=1.2.3.4 ./scripts/deploy.sh
# =====================================================================

# IP pública o DNS público de la instancia EC2. OBLIGATORIO.
# Ej: ec2-3-141-XX-XX.us-east-1.compute.amazonaws.com
EC2_HOST="${EC2_HOST:-ec2-77-113-69-25.us-east-2.compute.amazonaws.com}"

# Usuario SSH según la AMI: "ubuntu" (Ubuntu) | "ec2-user" (Amazon Linux)
EC2_USER="${EC2_USER:-ec2-user}"

# Llave privada SSH (vive en la raíz del proyecto; NO se sube al EC2)
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
KEY_PATH="${KEY_PATH:-${PROJECT_ROOT}/mi-llave-privada.pem}"

# Directorio (relativo al home del usuario) donde vive el proyecto en el EC2
REMOTE_DIR="${REMOTE_DIR:-proyectoFinal}"

# ---- Solo para scripts que usan AWS CLI (security-group.sh) ----
AWS_REGION="${AWS_REGION:-us-east-2}"

# ID del Security Group de la instancia (ej: sg-0abc123...).
# Si queda vacío, security-group.sh intenta autodetectarlo con AWS CLI
# a partir de la IP pública de la instancia.
SG_ID="${SG_ID:-sg-0dac330c25b8c2240}"
