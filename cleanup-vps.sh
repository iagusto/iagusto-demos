#!/usr/bin/env bash
#
# cleanup-vps.sh — Mantenimiento y limpieza de disco para VPS de Elestio (basado en Docker).
#
# Uso:
#   ./cleanup-vps.sh            Diagnóstico + limpieza segura (NO borra volúmenes)
#   ./cleanup-vps.sh --check    Solo diagnóstico, no borra nada
#   ./cleanup-vps.sh --deep     Limpieza profunda: TAMBIÉN borra volúmenes Docker sin usar
#                               (¡puede borrar datos de bases de datos huérfanas! usar con cuidado)
#
# Pensado para ejecutarse como root (o con sudo).

set -euo pipefail

MODE="${1:-clean}"

log()  { printf '\n\033[1;34m==> %s\033[0m\n' "$*"; }
warn() { printf '\033[1;33m[!] %s\033[0m\n' "$*"; }

require_root() {
  if [ "$(id -u)" -ne 0 ]; then
    warn "Este script necesita privilegios de root. Reejecuta con: sudo $0 $MODE"
    exit 1
  fi
}

diagnose() {
  log "Uso de disco del sistema"
  df -h /

  log "Carpetas más grandes en / (top 15)"
  du -sh /* 2>/dev/null | sort -rh | head -15 || true

  if command -v docker >/dev/null 2>&1; then
    log "Uso de disco de Docker"
    docker system df || true
  fi

  log "Tamaño de logs de journald"
  journalctl --disk-usage 2>/dev/null || true
}

clean_docker() {
  command -v docker >/dev/null 2>&1 || { warn "Docker no instalado, se omite."; return; }

  log "Eliminando imágenes, contenedores y redes Docker sin usar"
  docker system prune -af

  if [ "$MODE" = "--deep" ]; then
    warn "Modo --deep: eliminando también volúmenes Docker sin usar"
    docker volume prune -af
  fi

  log "Truncando logs de contenedores Docker"
  find /var/lib/docker/containers/ -name '*-json.log' -exec truncate -s 0 {} \; 2>/dev/null || true
}

ensure_docker_log_rotation() {
  command -v docker >/dev/null 2>&1 || return 0
  local cfg=/etc/docker/daemon.json
  if [ -f "$cfg" ] && grep -q '"max-size"' "$cfg" 2>/dev/null; then
    log "Rotación de logs de Docker ya configurada en $cfg"
    return 0
  fi
  warn "No hay rotación de logs de Docker configurada."
  warn "Añade esto a $cfg y reinicia Docker (systemctl restart docker):"
  cat <<'EOF'
  { "log-driver": "json-file", "log-opts": { "max-size": "10m", "max-file": "3" } }
EOF
}

clean_system() {
  log "Limpiando logs de journald (se conservan ~200M)"
  journalctl --vacuum-size=200M 2>/dev/null || true

  if command -v apt-get >/dev/null 2>&1; then
    log "Limpiando caché de paquetes apt"
    apt-get clean
    apt-get autoremove --purge -y
  fi

  log "Limpiando /tmp (archivos de más de 7 días)"
  find /tmp -type f -mtime +7 -delete 2>/dev/null || true
}

main() {
  if [ "$MODE" = "--check" ]; then
    diagnose
    exit 0
  fi

  require_root

  log "ESTADO ANTES DE LA LIMPIEZA"
  diagnose

  clean_docker
  clean_system
  ensure_docker_log_rotation

  log "ESTADO DESPUÉS DE LA LIMPIEZA"
  df -h /
  command -v docker >/dev/null 2>&1 && docker system df || true

  log "Limpieza completada."
}

main
