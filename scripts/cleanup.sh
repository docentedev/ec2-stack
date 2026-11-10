#!/usr/bin/env bash
# =====================================================================
# Limpieza del stack anterior (Java + Spring Boot sin Docker) en el EC2.
#
# Qué hace:
#   1. Detecta servicios systemd que ejecutan java/.jar y los detiene
#      y deshabilita (no borra los unit files, solo los apaga).
#   2. Detecta por PUERTO (8080-8083) los procesos que hoy escuchan y
#      los mata (cubre nohup/java -jar y pm2; pm2 se apaga entero).
#   3. Mueve los jars / artefactos del despliegue anterior a
#      ~/backup-pre-docker/<fecha>/ (recuperable, no se borra definitivo).
#
# Qué NO toca:
#   - El stack nuevo de Docker (ignora procesos dentro de contenedores)
#   - Paquetes del sistema (Java queda instalado; el stack nuevo corre
#     Java dentro de contenedores)
#
# Uso:
#   ./scripts/cleanup.sh
# =====================================================================
set -euo pipefail

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

SSH_BASE=(ssh -i "$KEY_PATH" -o BatchMode=yes -o StrictHostKeyChecking=accept-new "${EC2_USER}@${EC2_HOST}")

echo "== Limpieza del stack anterior en ${EC2_USER}@${EC2_HOST} =="

"${SSH_BASE[@]}" bash -s -- "$REMOTE_DIR" <<'REMOTE'
set -uo pipefail
REMOTE_DIR="$1"

is_docker_pid() {
  # true si el pid pertenece a un contenedor (cgroup lo indica)
  grep -qsE 'docker|containerd|kubepods' "/proc/$1/cgroup" 2>/dev/null
}

echo "-- 1. Servicios systemd que ejecutan java/.jar --"
SYSTEMD_FOUND=0
if command -v systemctl >/dev/null 2>&1; then
  for unit in $(systemctl list-units --type=service --state=running --no-pager --no-legend 2>/dev/null | awk '{print $1}'); do
    exec_start=$(systemctl show "$unit" -p ExecStart --value 2>/dev/null || true)
    if echo "$exec_start" | grep -qiE 'java|\.jar'; then
      echo "   deteniendo y deshabilitando: $unit"
      sudo systemctl stop "$unit" 2>/dev/null || true
      sudo systemctl disable "$unit" 2>/dev/null || true
      SYSTEMD_FOUND=1
    fi
  done
fi
[[ "$SYSTEMD_FOUND" -eq 0 ]] && echo "   (ninguno)"

echo "-- 2. Procesos escuchando en 8080-8083 --"
PORTS_FOUND=0
for port in 8080 8081 8082 8083; do
  pids=$(sudo ss -ltnp 2>/dev/null | grep -E ":${port}\b" | grep -oE 'pid=[0-9]+' | cut -d= -f2 | sort -u)
  for pid in $pids; do
    [ -z "$pid" ] && continue
    cmd=$(tr '\0' ' ' < "/proc/$pid/cmdline" 2>/dev/null || echo "?")
    if is_docker_pid "$pid"; then
      echo "   puerto $port pid $pid pertenece a un contenedor docker: se ignora"
      continue
    fi
    echo "   puerto $port -> pid $pid ($cmd): matando"
    sudo kill "$pid" 2>/dev/null || true
    PORTS_FOUND=1
  done
done
[[ "$PORTS_FOUND" -eq 0 ]] && echo "   (ninguno)"

# pm2 revive procesos muertos: si existe y administraba algo, se apaga entero
if command -v pm2 >/dev/null 2>&1 && pm2 ping >/dev/null 2>&1; then
  echo "   pm2 activo: se apaga (pm2 kill)"
  pm2 kill >/dev/null 2>&1 || true
fi

# verificación final de puertos
sleep 2
STILL_BUSY=""
for port in 8080 8081 8082 8083; do
  if sudo ss -ltn 2>/dev/null | grep -qE ":${port}\b"; then
    STILL_BUSY="$STILL_BUSY $port"
  fi
done
if [[ -n "$STILL_BUSY" ]]; then
  echo "   ATENCION: puertos todavia ocupados:$STILL_BUSY (revisar manualmente con: ss -ltnp)"
else
  echo "   OK: 8080-8083 libres"
fi

echo "-- 3. Artefactos del despliegue anterior (jars) -> backup --"
BACKUP_DIR="$HOME/backup-pre-docker/$(date +%Y%m%d-%H%M%S)"
mkdir -p "$BACKUP_DIR"
MOVED=0
while IFS= read -r jar; do
  case "$jar" in
    "$HOME/$REMOTE_DIR"*) continue ;; # nunca tocar el proyecto nuevo
  esac
  echo "   moviendo: $jar"
  mv "$jar" "$BACKUP_DIR/" 2>/dev/null || sudo mv "$jar" "$BACKUP_DIR/" 2>/dev/null || echo "   (no se pudo mover: $jar)"
  MOVED=1
done < <(find "$HOME" /opt /srv -maxdepth 3 -name "*.jar" -type f -not -path "*/backup-pre-docker/*" 2>/dev/null)
[[ "$MOVED" -eq 0 ]] && echo "   (no se encontraron jars sueltos)"

echo "-- Resumen --"
echo "   backup en: $BACKUP_DIR"
echo "   (Java queda instalado en el SO; el stack nuevo lo usa dentro de contenedores)"
REMOTE

echo "== Limpieza terminada =="
