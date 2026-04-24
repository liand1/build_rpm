#!/usr/bin/env bash
set -u

LOG_FILE="${1:-/var/log/tngs-bootstrap.log}"
TITLE="${2:-tngs-bootstrap install log}"

touch "${LOG_FILE}" 2>/dev/null || true

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
  local user uid display type runtime dbus wayland

  user="$(loginctl show-session "${sid}" -p Name --value 2>/dev/null || true)"
  uid="$(id -u "${user}" 2>/dev/null || true)"
  display="$(loginctl show-session "${sid}" -p Display --value 2>/dev/null || true)"
  type="$(loginctl show-session "${sid}" -p Type --value 2>/dev/null || true)"

  [ -n "${user}" ] || return 1
  [ -n "${uid}" ] || return 1

  runtime="/run/user/${uid}"
  dbus="unix:path=${runtime}/bus"
  wayland="wayland-0"

  if [ "${type}" = "x11" ] && [ -z "${display}" ]; then
    display=":0"
  fi

  local command_text
  command_text="printf '%s\n' '${TITLE}'; printf '%s\n' 'log: ${LOG_FILE}'; printf '%s\n' 'waiting for installer output...'; tail -n +1 -f '${LOG_FILE}'"

  if runuser -u "${user}" -- env \
    DISPLAY="${display}" \
    WAYLAND_DISPLAY="${wayland}" \
    XDG_RUNTIME_DIR="${runtime}" \
    DBUS_SESSION_BUS_ADDRESS="${dbus}" \
    gnome-terminal -- bash -lc "${command_text}" >/dev/null 2>&1; then
    return 0
  fi

  if runuser -u "${user}" -- env \
    DISPLAY="${display}" \
    WAYLAND_DISPLAY="${wayland}" \
    XDG_RUNTIME_DIR="${runtime}" \
    DBUS_SESSION_BUS_ADDRESS="${dbus}" \
    konsole -e bash -lc "${command_text}" >/dev/null 2>&1; then
    return 0
  fi

  if runuser -u "${user}" -- env \
    DISPLAY="${display}" \
    XDG_RUNTIME_DIR="${runtime}" \
    DBUS_SESSION_BUS_ADDRESS="${dbus}" \
    xterm -hold -e "bash -lc ${command_text@Q}" >/dev/null 2>&1; then
    return 0
  fi

  return 1
}

main() {
  if ! command -v loginctl >/dev/null 2>&1; then
    exit 0
  fi

  sid="$(find_graphical_session || true)"
  [ -n "${sid:-}" ] || exit 0

  open_terminal_for_session "${sid}" || true
}

main "$@"
