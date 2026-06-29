#!/usr/bin/env bash
#
# cleanup-disk.sh — Limpieza segura de disco para el host de Elestio
# (cesar-ia-gusto-u55406).
#
# Recupera espacio borrando SOLO recursos prescindibles:
#   - Imágenes Docker sin usar y build cache
#   - Logs del sistema (journald) más antiguos que RETENTION_DAYS
#   - Logs de contenedores Docker (*-json.log) que crecen sin límite
#   - Paquetes apt en caché
#
# NUNCA toca volúmenes Docker ni bases de datos: tus datos (n8n, Supabase,
# Postgres, etc.) están a salvo. No se ejecuta `docker volume prune` ni
# `docker system prune --volumes` a propósito.
#
# Pensado para correr por cron cada 15 días. Ver instrucciones en
# ops/README.md.

set -euo pipefail

RETENTION_DAYS="${RETENTION_DAYS:-7}"
LOG_FILE="${LOG_FILE:-/var/log/cleanup-disk.log}"
MAX_CONTAINER_LOG_MB="${MAX_CONTAINER_LOG_MB:-10}"

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

disk_usage() {
  df -h / | awk 'NR==2 {print $3" usados / "$2" ("$5")"}'
}

require_root() {
  if [ "$(id -u)" -ne 0 ]; then
    echo "Este script debe ejecutarse como root (usa sudo)." >&2
    exit 1
  fi
}

main() {
  require_root
  mkdir -p "$(dirname "$LOG_FILE")"

  log "===== Inicio limpieza ====="
  log "Disco antes: $(disk_usage)"

  if command -v docker >/dev/null 2>&1; then
    log "Docker: estado actual"
    docker system df 2>&1 | tee -a "$LOG_FILE" || true

    log "Docker: borrando imágenes sin usar (image prune -a)"
    docker image prune -a -f 2>&1 | tee -a "$LOG_FILE" || true

    log "Docker: borrando build cache"
    docker builder prune -a -f 2>&1 | tee -a "$LOG_FILE" || true

    log "Docker: truncando logs de contenedores > ${MAX_CONTAINER_LOG_MB}MB"
    find /var/lib/docker/containers/ -name '*-json.log' -type f \
      -size +"${MAX_CONTAINER_LOG_MB}"M -print 2>/dev/null | while read -r f; do
        log "  -> truncando $f ($(du -h "$f" | cut -f1))"
        : > "$f"
      done
  else
    log "Docker no instalado; se omite limpieza de Docker."
  fi

  if command -v journalctl >/dev/null 2>&1; then
    log "journald: conservando últimos ${RETENTION_DAYS} días"
    journalctl --vacuum-time="${RETENTION_DAYS}d" 2>&1 | tee -a "$LOG_FILE" || true
  fi

  if command -v apt-get >/dev/null 2>&1; then
    log "apt: limpiando caché de paquetes"
    apt-get clean 2>&1 | tee -a "$LOG_FILE" || true
  fi

  log "Disco después: $(disk_usage)"
  log "===== Fin limpieza ====="
  echo "" >> "$LOG_FILE"
}

main "$@"
