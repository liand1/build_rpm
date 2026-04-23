#!/usr/bin/env bash
set -euo pipefail

HELLO_IMAGE="${HELLO_IMAGE:-hello-world:latest}"
HELLO_CONTAINER="${HELLO_CONTAINER:-tngs-hello-world}"

log() {
  echo "[tngs-bootstrap] $*"
}

require_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    log "This script must run as root."
    exit 1
  fi
}

ensure_rocky_like() {
  if [[ ! -f /etc/os-release ]]; then
    log "/etc/os-release not found."
    exit 1
  fi

  # shellcheck disable=SC1091
  source /etc/os-release
  case "${ID:-}" in
    rocky|rhel|almalinux|centos)
      ;;
    *)
      log "Unsupported distro ID: ${ID:-unknown}. Expected Rocky/RHEL-like."
      exit 1
      ;;
  esac
}

ensure_docker() {
  if command -v docker >/dev/null 2>&1; then
    log "Docker already installed."
  else
    log "Docker not found. Installing Docker CE..."
    dnf install -y dnf-plugins-core
    dnf config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
    dnf install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  fi

  log "Enabling and starting Docker service..."
  systemctl enable --now docker
}

ensure_hello_image() {
  if docker image inspect "${HELLO_IMAGE}" >/dev/null 2>&1; then
    log "Image exists: ${HELLO_IMAGE}"
  else
    log "Pulling image: ${HELLO_IMAGE}"
    docker pull "${HELLO_IMAGE}"
  fi
}

stop_all_containers() {
  local running_ids
  running_ids="$(docker ps -q || true)"
  if [[ -n "${running_ids}" ]]; then
    log "Stopping all running containers..."
    docker stop ${running_ids} >/dev/null
  else
    log "No running containers to stop."
  fi
}

clear_docker_cache() {
  log "Clearing Docker cache (unused data)..."
  docker system prune -f >/dev/null
}

start_hello_world() {
  local exists
  exists="$(docker ps -a --filter "name=^/${HELLO_CONTAINER}$" --format '{{.Names}}' || true)"
  if [[ "${exists}" == "${HELLO_CONTAINER}" ]]; then
    log "Removing existing container: ${HELLO_CONTAINER}"
    docker rm -f "${HELLO_CONTAINER}" >/dev/null || true
  fi

  log "Starting hello-world container: ${HELLO_CONTAINER}"
  # hello-world prints a verification message and exits immediately.
  docker run --name "${HELLO_CONTAINER}" "${HELLO_IMAGE}" >/dev/null
}

main() {
  require_root
  ensure_rocky_like
  ensure_docker
  ensure_hello_image
  stop_all_containers
  clear_docker_cache
  start_hello_world
  log "Done."
}

main "$@"
