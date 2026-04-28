#!/usr/bin/env bash
set -u

LOG_FILE="${LOG_FILE:-/var/log/tngs-bootstrap.log}"
INSTALL_UNIT="${INSTALL_UNIT:-tngs-bootstrap-install}"
MYSQL_CONTAINER="${MYSQL_CONTAINER:-mysql-tngs}"
REDIS_CONTAINER="${REDIS_CONTAINER:-redis-tngs}"

mkdir -p "$(dirname "${LOG_FILE}")"
exec >>"${LOG_FILE}" 2>&1

log() {
  echo "[$(date '+%F %T')] [tngs-bootstrap] $*"
}

stop_pending_install_unit() {
  if ! command -v systemctl >/dev/null 2>&1; then
    log "未找到 systemctl，跳过延迟安装任务清理。"
    return
  fi

  log "正在停止可能存在的延迟安装任务：${INSTALL_UNIT}"
  systemctl stop "${INSTALL_UNIT}.timer" >/dev/null 2>&1 || true
  systemctl stop "${INSTALL_UNIT}.service" >/dev/null 2>&1 || true
  systemctl reset-failed "${INSTALL_UNIT}.timer" >/dev/null 2>&1 || true
  systemctl reset-failed "${INSTALL_UNIT}.service" >/dev/null 2>&1 || true
}

stop_container_if_running() {
  local container="$1"
  local running

  if ! command -v docker >/dev/null 2>&1; then
    log "未找到 Docker 命令，无需停止容器。"
    return
  fi

  running="$(docker ps --filter "name=^/${container}$" --format '{{.Names}}' 2>/dev/null || true)"
  if [[ "${running}" != "${container}" ]]; then
    log "容器未运行，跳过：${container}"
    return
  fi

  log "正在停止容器：${container}"
  docker stop "${container}" >/dev/null 2>&1 || {
    log "停止容器失败：${container}"
    return 1
  }
  log "容器已停止：${container}"
}

main() {
  log "正在停止服务"
  stop_pending_install_unit
  stop_container_if_running "${MYSQL_CONTAINER}"
  stop_container_if_running "${REDIS_CONTAINER}"
  log "卸载流程执行完成。"
}

main "$@"
