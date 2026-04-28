#!/usr/bin/env bash
set -u

LOG_FILE="${1:-/var/log/tngs-bootstrap.log}"
TITLE="${2:-tNGS 安装日志}"

touch "${LOG_FILE}" 2>/dev/null || true

log_debug() {
  echo "[$(date '+%F %T')] [tngs-bootstrap] 终端启动器：$*" >> "${LOG_FILE}" 2>/dev/null || true
}

find_graphical_session() {
  loginctl list-sessions --no-legend 2>/dev/null | while read -r sid _user _seat; do
    [ -n "${sid}" ] || continue

    state="$(loginctl show-session "${sid}" -p State --value 2>/dev/null || true)"
    type="$(loginctl show-session "${sid}" -p Type --value 2>/dev/null || true)"
    remote="$(loginctl show-session "${sid}" -p Remote --value 2>/dev/null || true)"

    if [ "${state}" = "active" ] && [ "${remote}" = "no" ] && { [ "${type}" = "wayland" ] || [ "${type}" = "x11" ]; }; then
      echo "${sid}"
      return 0
    fi
  done
}

open_terminal_for_session() {
  local sid="$1"
  local user uid display runtime dbus wayland leader

  user="$(loginctl show-session "${sid}" -p Name --value 2>/dev/null || true)"
  uid="$(id -u "${user}" 2>/dev/null || true)"
  display="$(loginctl show-session "${sid}" -p Display --value 2>/dev/null || true)"
  leader="$(loginctl show-session "${sid}" -p Leader --value 2>/dev/null || true)"

  [ -n "${user}" ] || return 1
  [ -n "${uid}" ] || return 1

  runtime="/run/user/${uid}"
  dbus="unix:path=${runtime}/bus"
  wayland="wayland-0"

  if [ -n "${leader}" ] && [ -r "/proc/${leader}/environ" ]; then
    display="$(tr '\0' '\n' < "/proc/${leader}/environ" | sed -n 's/^DISPLAY=//p' | tail -n 1)"
    wayland="$(tr '\0' '\n' < "/proc/${leader}/environ" | sed -n 's/^WAYLAND_DISPLAY=//p' | tail -n 1)"
    dbus="$(tr '\0' '\n' < "/proc/${leader}/environ" | sed -n 's/^DBUS_SESSION_BUS_ADDRESS=//p' | tail -n 1)"
    runtime="$(tr '\0' '\n' < "/proc/${leader}/environ" | sed -n 's/^XDG_RUNTIME_DIR=//p' | tail -n 1)"
  fi

  [ -n "${runtime}" ] || runtime="/run/user/${uid}"
  [ -n "${dbus}" ] || dbus="unix:path=${runtime}/bus"
  [ -n "${wayland}" ] || wayland="wayland-0"

  if [ -z "${display}" ]; then
    display=":0"
  fi

  log_debug "正在为用户 ${user} 打开终端，session=${sid}，DISPLAY=${display}，WAYLAND_DISPLAY=${wayland}，XDG_RUNTIME_DIR=${runtime}"

  local command_text
  command_text="printf '%s\n' '${TITLE}'; printf '%s\n' '日志文件：${LOG_FILE}'; printf '%s\n' '正在等待安装/卸载输出...'; tail -n +1 -f '${LOG_FILE}'"

  if command -v gnome-terminal >/dev/null 2>&1 && runuser -u "${user}" -- env \
    DISPLAY="${display}" \
    WAYLAND_DISPLAY="${wayland}" \
    XDG_RUNTIME_DIR="${runtime}" \
    DBUS_SESSION_BUS_ADDRESS="${dbus}" \
    gnome-terminal -- bash -lc "${command_text}" >/dev/null 2>&1; then
    return 0
  fi

  if command -v kgx >/dev/null 2>&1 && runuser -u "${user}" -- env \
    DISPLAY="${display}" \
    WAYLAND_DISPLAY="${wayland}" \
    XDG_RUNTIME_DIR="${runtime}" \
    DBUS_SESSION_BUS_ADDRESS="${dbus}" \
    kgx -- bash -lc "${command_text}" >/dev/null 2>&1; then
    return 0
  fi

  if command -v konsole >/dev/null 2>&1 && runuser -u "${user}" -- env \
    DISPLAY="${display}" \
    WAYLAND_DISPLAY="${wayland}" \
    XDG_RUNTIME_DIR="${runtime}" \
    DBUS_SESSION_BUS_ADDRESS="${dbus}" \
    konsole -e bash -lc "${command_text}" >/dev/null 2>&1; then
    return 0
  fi

  if command -v xterm >/dev/null 2>&1 && runuser -u "${user}" -- env \
    DISPLAY="${display}" \
    XDG_RUNTIME_DIR="${runtime}" \
    DBUS_SESSION_BUS_ADDRESS="${dbus}" \
    xterm -hold -e "bash -lc ${command_text@Q}" >/dev/null 2>&1; then
    return 0
  fi

  log_debug "未能打开支持的终端程序"
  return 1
}

main() {
  if ! command -v loginctl >/dev/null 2>&1; then
    log_debug "未找到 loginctl"
    exit 0
  fi

  sid="$(find_graphical_session || true)"
  if [ -z "${sid:-}" ]; then
    log_debug "未找到活跃的图形桌面会话"
    exit 0
  fi

  open_terminal_for_session "${sid}" || true
}

main "$@"
