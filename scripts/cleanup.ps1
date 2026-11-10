# =====================================================================
# Limpieza del stack anterior (Java + Spring Boot sin Docker) en el EC2.
# Version Windows (PowerShell) de cleanup.sh. La logica remota (bash) es
# identica a la de la version bash.
#
# Que hace:
#   1. Detecta servicios systemd que ejecutan java/.jar y los detiene.
#   2. Detecta por PUERTO (8080-8083) los procesos que hoy escuchan y
#      los mata (cubre nohup/java -jar y pm2; pm2 se apaga entero).
#   3. Mueve los jars del despliegue anterior a ~/backup-pre-docker/<fecha>/.
#
# Uso:
#   .\scripts\cleanup.ps1
# =====================================================================
#Requires -Version 5.1
$ErrorActionPreference = "Stop"

. "$PSScriptRoot\config.ps1"
Assert-Config

Write-Host "== Limpieza del stack anterior en ${EC2_USER}@${EC2_HOST} =="

# Mismo payload bash que cleanup.sh (se ejecuta EN el EC2)
$remote = @'
set -uo pipefail
REMOTE_DIR="$1"

is_docker_pid() {
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

sleep 2
STILL_BUSY=""
for port in 8080 8081 8082 8083; do
  if sudo ss -ltn 2>/dev/null | grep -qE ":${port}\b"; then
    STILL_BUSY="$STILL_BUSY $port"
  fi
done
if [[ -n "$STILL_BUSY" ]]; then
  echo "   ATENCION: puertos todavia ocupados:$STILL_BUSY (revisar con: ss -ltnp)"
else
  echo "   OK: 8080-8083 libres"
fi

echo "-- 3. Artefactos del despliegue anterior (jars) -> backup --"
BACKUP_DIR="$HOME/backup-pre-docker/$(date +%Y%m%d-%H%M%S)"
mkdir -p "$BACKUP_DIR"
MOVED=0
while IFS= read -r jar; do
  case "$jar" in
    "$HOME/$REMOTE_DIR"*) continue ;;          # nunca tocar el proyecto nuevo
    */backup-pre-docker/*) continue ;;          # ni backups ya hechos
  esac
  echo "   moviendo: $jar"
  mv "$jar" "$BACKUP_DIR/" 2>/dev/null || sudo mv "$jar" "$BACKUP_DIR/" 2>/dev/null || echo "   (no se pudo mover: $jar)"
  MOVED=1
done < <(find "$HOME" /opt /srv -maxdepth 3 -name "*.jar" -type f -not -path "*/backup-pre-docker/*" 2>/dev/null)
[[ "$MOVED" -eq 0 ]] && echo "   (no se encontraron jars sueltos)"

echo "-- Resumen --"
echo "   backup en: $BACKUP_DIR"
echo "   (Java queda instalado en el SO; el stack nuevo lo usa dentro de contenedores)"
'@

Invoke-Remote -ScriptBody $remote -ScriptArgs @($REMOTE_DIR)

Write-Host "== Limpieza terminada =="
