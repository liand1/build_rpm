#!/usr/bin/env bash
set -u

LOG_FILE="${LOG_FILE:-/var/log/tngs-bootstrap.log}"
INSTALL_UNIT="${INSTALL_UNIT:-tngs-bootstrap-install}"

mkdir -p "$(dirname "${LOG_FILE}")"
exec >>"${LOG_FILE}" 2>&1

log() {
  echo "[$(date '+%F %T')] [tngs-bootstrap] $*"
}

stop_pending_install_unit() {
  if ! command -v systemctl >/dev/null 2>&1; then
    log "systemctl not found. Skipping pending install unit cleanup."
    return
  fi

  log "Stopping pending install unit if present: ${INSTALL_UNIT}"
  systemctl stop "${INSTALL_UNIT}.timer" >/dev/null 2>&1 || true
  systemctl stop "${INSTALL_UNIT}.service" >/dev/null 2>&1 || true
  systemctl reset-failed "${INSTALL_UNIT}.timer" >/dev/null 2>&1 || true
  systemctl reset-failed "${INSTALL_UNIT}.service" >/dev/null 2>&1 || true
}

stop_all_containers() {
  local running_ids

  if ! command -v docker >/dev/null 2>&1; then
    log "Docker command not found. No containers to stop."
    return
  fi

  running_ids="$(docker ps -q 2>/dev/null || true)"
  if [[ -z "${running_ids}" ]]; then
    log "No running Docker containers to stop."
    return
  fi

  log "Stopping all running Docker containers..."
  docker stop ${running_ids} >/dev/null 2>&1 || {
    log "Failed to stop one or more Docker containers."
    return 1
  }
  log "All running Docker containers stopped."
}

main() {
  log "RPM uninstall started."
  stop_pending_install_unit
  stop_all_containers
  log "RPM uninstall finished."
}

main "$@"
