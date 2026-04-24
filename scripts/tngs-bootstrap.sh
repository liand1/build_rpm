#!/usr/bin/env bash
set -euo pipefail

HELLO_IMAGE="${HELLO_IMAGE:-hello-world:latest}"
HELLO_CONTAINER="${HELLO_CONTAINER:-tngs-hello-world}"
LOG_FILE="${LOG_FILE:-/var/log/tngs-bootstrap.log}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HELLO_IMAGE_ARCHIVE="${HELLO_IMAGE_ARCHIVE:-${SCRIPT_DIR}/../images/hello-world_latest.tar}"

mkdir -p "$(dirname "${LOG_FILE}")"
exec >>"${LOG_FILE}" 2>&1

log() {
  echo "[$(date '+%F %T')] [tngs-bootstrap] $*"
}

run_step() {
  local step_name="$1"
  shift

  log "===== START: ${step_name} ====="
  "$@"
  log "===== END: ${step_name} ====="
}

resolve_docker_user() {
  if [[ -n "${DOCKER_USER:-}" ]]; then
    echo "${DOCKER_USER}"
    return
  fi

  if [[ -n "${SUDO_USER:-}" ]]; then
    echo "${SUDO_USER}"
    return
  fi

  if logname >/dev/null 2>&1; then
    logname
    return
  fi

  echo ""
}

require_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    log "This script must run as root."
    exit 1
  fi
}

ensure_rocky_like() {
  log "Checking operating system compatibility..."
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
  local docker_user

  log "Checking Docker installation status..."
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

  docker_user="$(resolve_docker_user)"
  configure_docker_permissions "${docker_user}"
}

configure_docker_permissions() {
  local docker_user="${1:-}"

  log "Configuring Docker permissions..."
  if getent group docker >/dev/null 2>&1; then
    log "Group exists: docker"
  else
    log "Creating group: docker"
    groupadd docker
  fi

  if [[ -z "${docker_user}" || "${docker_user}" == "root" ]]; then
    log "No non-root Docker user resolved. Set DOCKER_USER explicitly if you want to grant Docker access."
    return
  fi

  if ! id "${docker_user}" >/dev/null 2>&1; then
    log "User does not exist, cannot grant Docker access: ${docker_user}"
    exit 1
  fi

  if id -nG "${docker_user}" | tr ' ' '\n' | grep -Fxq docker; then
    log "User already has Docker access: ${docker_user}"
  else
    log "Granting Docker access to user: ${docker_user}"
    usermod -aG docker "${docker_user}"
    log "User ${docker_user} added to docker group. Re-login or run 'newgrp docker' for the change to take effect."
  fi
}

ensure_hello_image() {
  local load_output=""
  local loaded_image=""
  local loaded_image_id=""

  log "Checking hello image availability: ${HELLO_IMAGE}"
  if docker image inspect "${HELLO_IMAGE}" >/dev/null 2>&1; then
    log "Image exists: ${HELLO_IMAGE}"
  else
    if [[ ! -f "${HELLO_IMAGE_ARCHIVE}" ]]; then
      log "Image not found locally and archive is missing: ${HELLO_IMAGE_ARCHIVE}"
      exit 1
    fi

    log "Image not found locally. Loading from archive: ${HELLO_IMAGE_ARCHIVE}"
    load_output="$(docker load -i "${HELLO_IMAGE_ARCHIVE}" 2>&1)"
    while IFS= read -r line; do
      [[ -n "${line}" ]] && log "docker load: ${line}"
    done <<< "${load_output}"

    loaded_image="$(printf '%s\n' "${load_output}" | sed -n 's/^Loaded image: //p' | tail -n 1)"
    loaded_image_id="$(printf '%s\n' "${load_output}" | sed -n 's/^Loaded image ID: //p' | tail -n 1)"

    if [[ -n "${loaded_image}" && "${loaded_image}" != "${HELLO_IMAGE}" ]]; then
      log "Retagging loaded image from ${loaded_image} to ${HELLO_IMAGE}"
      docker tag "${loaded_image}" "${HELLO_IMAGE}"
    elif [[ -n "${loaded_image_id}" ]]; then
      log "Retagging loaded image ID ${loaded_image_id} to ${HELLO_IMAGE}"
      docker tag "${loaded_image_id}" "${HELLO_IMAGE}"
    fi

    log "Current hello-related images after load:"
    docker images --format '{{.Repository}}:{{.Tag}} {{.ID}}' | grep 'hello-world' || log "No hello-world images found in docker images output."

    if docker image inspect "${HELLO_IMAGE}" >/dev/null 2>&1; then
      log "Image loaded successfully: ${HELLO_IMAGE}"
    else
      log "Image archive loaded, but ${HELLO_IMAGE} is still unavailable."
      exit 1
    fi
  fi
}

stop_all_containers() {
  local running_ids

  log "Checking for running containers..."
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

  log "Preparing hello-world container startup..."
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
  run_step "Require root" require_root
  run_step "Check Rocky-like OS" ensure_rocky_like
  run_step "Ensure Docker" ensure_docker
  run_step "Ensure hello image" ensure_hello_image
  run_step "Stop all containers" stop_all_containers
  run_step "Clear Docker cache" clear_docker_cache
  run_step "Start hello-world container" start_hello_world
  log "Done."
}

main "$@"
