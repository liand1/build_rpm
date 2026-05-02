#!/usr/bin/env bash
set -euo pipefail

MYSQL_IMAGE="${MYSQL_IMAGE:-dockerpull.pw/mysql:latest}"
MYSQL_CONTAINER="${MYSQL_CONTAINER:-mysql-tngs}"
MYSQL_IMAGE_ARCHIVE_NAME="${MYSQL_IMAGE_ARCHIVE_NAME:-mysql_latest.tar}"
MYSQL_DATA_DIR="${MYSQL_DATA_DIR:-/tNGS/data/mysql}"
MYSQL_ROOT_PASSWORD="${MYSQL_ROOT_PASSWORD:-123456}"
MYSQL_SQL_WAIT_SECONDS="${MYSQL_SQL_WAIT_SECONDS:-15}"
MYSQL_SQL_INIT_MARKER="${MYSQL_SQL_INIT_MARKER:-${MYSQL_DATA_DIR}/.tngs_sql_initialized}"

REDIS_IMAGE="${REDIS_IMAGE:-dockerpull.pw/redis:latest}"
REDIS_CONTAINER="${REDIS_CONTAINER:-redis-tngs}"
REDIS_IMAGE_ARCHIVE_NAME="${REDIS_IMAGE_ARCHIVE_NAME:-redis_latest.tar}"
REDIS_DATA_DIR="${REDIS_DATA_DIR:-/tNGS/data/redis/data}"
REDIS_PASSWORD="${REDIS_PASSWORD:-123456}"

TNGS_SERVER_IMAGE="${TNGS_SERVER_IMAGE:-tngs-server-prod:1.0.0}"
TNGS_SERVER_CONTAINER="${TNGS_SERVER_CONTAINER:-tngs-server-prod}"
TNGS_SERVER_IMAGE_ARCHIVE_NAME="${TNGS_SERVER_IMAGE_ARCHIVE_NAME:-tngs-server-prod-1.0.0.tar}"
TNGS_PROJECT_PROD_DIR="${TNGS_PROJECT_PROD_DIR:-/tngs_project_prod}"
PROJECT_DIR="${PROJECT_DIR:-/project}"
TNGS_SERVER_LOG_DIR="${TNGS_SERVER_LOG_DIR:-/tNGS/server/logs}"

TZ_VALUE="${TZ_VALUE:-Asia/Shanghai}"
LOG_FILE="${LOG_FILE:-/var/log/tngs-bootstrap.log}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IMAGE_DIR="${IMAGE_DIR:-${SCRIPT_DIR}/../images}"
SQL_DIR="${SQL_DIR:-${SCRIPT_DIR}/../sql}"

mkdir -p "$(dirname "${LOG_FILE}")"
exec >>"${LOG_FILE}" 2>&1

log() {
  echo "[$(date '+%F %T')] [tngs-bootstrap] $*"
}

run_step() {
  local step_name="$1"
  shift

  log "===== 开始：${step_name} ====="
  "$@"
  log "===== 完成：${step_name} ====="
}

resolve_docker_user() {
  local session_user

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

  session_user="$(resolve_active_graphical_user)"
  if [[ -n "${session_user}" ]]; then
    echo "${session_user}"
    return
  fi

  echo ""
}

resolve_active_graphical_user() {
  local sid
  local state
  local type
  local remote
  local user

  if ! command -v loginctl >/dev/null 2>&1; then
    echo ""
    return
  fi

  while read -r sid _user _seat; do
    [[ -n "${sid}" ]] || continue

    state="$(loginctl show-session "${sid}" -p State --value 2>/dev/null || true)"
    type="$(loginctl show-session "${sid}" -p Type --value 2>/dev/null || true)"
    remote="$(loginctl show-session "${sid}" -p Remote --value 2>/dev/null || true)"

    if [[ "${state}" == "active" && "${remote}" == "no" && ( "${type}" == "wayland" || "${type}" == "x11" ) ]]; then
      user="$(loginctl show-session "${sid}" -p Name --value 2>/dev/null || true)"
      if [[ -n "${user}" && "${user}" != "root" ]]; then
        echo "${user}"
        return
      fi
    fi
  done < <(loginctl list-sessions --no-legend 2>/dev/null || true)

  echo ""
}

require_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    log "当前脚本必须使用 root 权限运行。"
    exit 1
  fi
}

ensure_rocky_like() {
  log "正在检查操作系统兼容性..."
  if [[ ! -f /etc/os-release ]]; then
    log "未找到 /etc/os-release。"
    exit 1
  fi

  # shellcheck disable=SC1091
  source /etc/os-release
  case "${ID:-}" in
    rocky|rhel|almalinux|centos)
      ;;
    *)
      log "不支持的系统发行版：${ID:-unknown}。需要 Rocky/RHEL 兼容系统。"
      exit 1
      ;;
  esac
}

ensure_docker() {
  local docker_user

  log "正在检查 Docker 安装状态..."
  if command -v docker >/dev/null 2>&1; then
    log "Docker 已安装。"
  else
    log "未检测到 Docker，正在安装 Docker CE..."
    dnf install -y dnf-plugins-core
    dnf config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
    dnf install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  fi

  log "正在启用并启动 Docker 服务..."
  systemctl enable --now docker

  docker_user="$(resolve_docker_user)"
  configure_docker_permissions "${docker_user}"
}

configure_docker_permissions() {
  local docker_user="${1:-}"

  log "正在配置 Docker 用户权限..."
  if getent group docker >/dev/null 2>&1; then
    log "用户组已存在：docker"
  else
    log "正在创建用户组：docker"
    groupadd docker
  fi

  if [[ -z "${docker_user}" || "${docker_user}" == "root" ]]; then
    log "未识别到需要授权的普通用户。如需指定用户，请设置 DOCKER_USER。"
    return
  fi

  if ! id "${docker_user}" >/dev/null 2>&1; then
    log "用户不存在，无法授予 Docker 权限：${docker_user}"
    exit 1
  fi

  if id -nG "${docker_user}" | tr ' ' '\n' | grep -Fxq docker; then
    log "用户已经拥有 Docker 权限：${docker_user}"
  else
    log "正在给用户授予 Docker 权限：${docker_user}"
    usermod -aG docker "${docker_user}"
    log "用户 ${docker_user} 已加入 docker 用户组。"
  fi

  log "Docker 权限提示：用户 ${docker_user} 需要注销后重新登录，或执行 'newgrp docker'，当前会话才能免 sudo 使用 docker。"
}

ensure_image() {
  local image="$1"
  local archive="$2"
  local load_output=""
  local loaded_image=""
  local loaded_image_id=""

  log "正在检查镜像是否存在：${image}"
  if docker image inspect "${image}" >/dev/null 2>&1; then
    log "镜像已存在：${image}"
  else
    if [[ ! -f "${archive}" ]]; then
      log "本地没有镜像，并且 RPM 内置镜像文件缺失：${archive}"
      exit 1
    fi

    log "本地没有镜像，正在从 RPM 内置文件导入：${archive}"
    load_output="$(docker load -i "${archive}" 2>&1)"
    while IFS= read -r line; do
      [[ -n "${line}" ]] && log "docker load: ${line}"
    done <<< "${load_output}"

    loaded_image="$(printf '%s\n' "${load_output}" | sed -n 's/^Loaded image: //p' | tail -n 1)"
    loaded_image_id="$(printf '%s\n' "${load_output}" | sed -n 's/^Loaded image ID: //p' | tail -n 1)"

    if [[ -n "${loaded_image}" && "${loaded_image}" != "${image}" ]]; then
      log "正在给导入的镜像重新打标签：${loaded_image} -> ${image}"
      docker tag "${loaded_image}" "${image}"
    elif [[ -n "${loaded_image_id}" ]]; then
      log "正在给导入的镜像 ID 重新打标签：${loaded_image_id} -> ${image}"
      docker tag "${loaded_image_id}" "${image}"
    fi

    if docker image inspect "${image}" >/dev/null 2>&1; then
      log "镜像导入成功：${image}"
    else
      log "镜像文件已导入，但仍无法找到目标镜像：${image}"
      exit 1
    fi
  fi
}

ensure_bundled_archives() {
  local mysql_archive="${IMAGE_DIR}/${MYSQL_IMAGE_ARCHIVE_NAME}"
  local redis_archive="${IMAGE_DIR}/${REDIS_IMAGE_ARCHIVE_NAME}"
  local tngs_server_archive="${IMAGE_DIR}/${TNGS_SERVER_IMAGE_ARCHIVE_NAME}"

  log "正在检查 RPM 内置 Docker 镜像文件目录：${IMAGE_DIR}"
  if [[ ! -f "${mysql_archive}" ]]; then
    log "缺少 RPM 内置 MySQL 镜像文件：${mysql_archive}"
    exit 1
  fi

  if [[ ! -f "${redis_archive}" ]]; then
    log "Missing bundled Redis image archive: ${redis_archive}"
    exit 1
  fi

  if [[ ! -f "${tngs_server_archive}" ]]; then
    log "Missing bundled tngs-server-prod image archive: ${tngs_server_archive}"
    exit 1
  fi

  log "已找到 RPM 内置 MySQL 镜像文件：${mysql_archive}"
  log "已找到 RPM 内置 Redis 镜像文件：${redis_archive}"
}

ensure_data_dirs() {
  log "Creating service data directories."
  mkdir -p "${MYSQL_DATA_DIR}" "${REDIS_DATA_DIR}" "${TNGS_PROJECT_PROD_DIR}" "${PROJECT_DIR}" "${TNGS_SERVER_LOG_DIR}"
}

ensure_mysql_container() {
  local running
  local exists

  running="$(docker ps --filter "name=^/${MYSQL_CONTAINER}$" --format '{{.Names}}' || true)"
  if [[ "${running}" == "${MYSQL_CONTAINER}" ]]; then
    log "MySQL 容器已在运行：${MYSQL_CONTAINER}"
    return
  fi

  exists="$(docker ps -a --filter "name=^/${MYSQL_CONTAINER}$" --format '{{.Names}}' || true)"
  if [[ "${exists}" == "${MYSQL_CONTAINER}" ]]; then
    log "正在启动已存在的 MySQL 容器：${MYSQL_CONTAINER}"
    docker start "${MYSQL_CONTAINER}" >/dev/null
    return
  fi

  log "正在创建并启动 MySQL 容器：${MYSQL_CONTAINER}"
  docker run \
    -v "${MYSQL_DATA_DIR}:/var/lib/mysql" \
    -v /etc/localtime:/etc/localtime:ro \
    -p 3306:3306 \
    -e MYSQL_ROOT_PASSWORD="${MYSQL_ROOT_PASSWORD}" \
    -e TZ="${TZ_VALUE}" \
    --restart=always \
    --name "${MYSQL_CONTAINER}" \
    -d "${MYSQL_IMAGE}" \
    --lower_case_table_names=1 >/dev/null
}

ensure_redis_container() {
  local running
  local exists

  running="$(docker ps --filter "name=^/${REDIS_CONTAINER}$" --format '{{.Names}}' || true)"
  if [[ "${running}" == "${REDIS_CONTAINER}" ]]; then
    log "Redis 容器已在运行：${REDIS_CONTAINER}"
    return
  fi

  exists="$(docker ps -a --filter "name=^/${REDIS_CONTAINER}$" --format '{{.Names}}' || true)"
  if [[ "${exists}" == "${REDIS_CONTAINER}" ]]; then
    log "正在启动已存在的 Redis 容器：${REDIS_CONTAINER}"
    docker start "${REDIS_CONTAINER}" >/dev/null
    return
  fi

  log "正在创建并启动 Redis 容器：${REDIS_CONTAINER}"
  docker run \
    -d \
    --name "${REDIS_CONTAINER}" \
    --restart=always \
    -p 6380:6379 \
    -v "${REDIS_DATA_DIR}:/data" \
    -v /etc/localtime:/etc/localtime:ro \
    "${REDIS_IMAGE}" \
    --requirepass "${REDIS_PASSWORD}" >/dev/null
}

ensure_tngs_server_container() {
  local running
  local exists

  running="$(docker ps --filter "name=^/${TNGS_SERVER_CONTAINER}$" --format '{{.Names}}' || true)"
  if [[ "${running}" == "${TNGS_SERVER_CONTAINER}" ]]; then
    log "tngs-server-prod container is already running: ${TNGS_SERVER_CONTAINER}"
    return
  fi

  exists="$(docker ps -a --filter "name=^/${TNGS_SERVER_CONTAINER}$" --format '{{.Names}}' || true)"
  if [[ "${exists}" == "${TNGS_SERVER_CONTAINER}" ]]; then
    log "Starting existing tngs-server-prod container: ${TNGS_SERVER_CONTAINER}"
    docker start "${TNGS_SERVER_CONTAINER}" >/dev/null
    return
  fi

  log "Creating and starting tngs-server-prod container: ${TNGS_SERVER_CONTAINER}"
  docker run \
    -d \
    -e spring_env=prod \
    -p 58081:8080 \
    --name "${TNGS_SERVER_CONTAINER}" \
    -v /var/run/docker.sock:/var/run/docker.sock \
    -v "${TNGS_PROJECT_PROD_DIR}:/tngs_project_prod" \
    -v "${PROJECT_DIR}:/project" \
    -v "${TNGS_SERVER_LOG_DIR}:/tNGS/server/logs" \
    "${TNGS_SERVER_IMAGE}" >/dev/null
}

wait_for_mysql_before_sql() {
  log "MySQL 容器启动后等待 ${MYSQL_SQL_WAIT_SECONDS} 秒，再执行 SQL 初始化。"
  sleep "${MYSQL_SQL_WAIT_SECONDS}"

  log "正在检查 MySQL 服务是否可连接..."
  for attempt in $(seq 1 30); do
    if docker exec "${MYSQL_CONTAINER}" mysqladmin ping -uroot -p"${MYSQL_ROOT_PASSWORD}" --silent >/dev/null 2>&1; then
      log "MySQL 服务已可连接。"
      return
    fi

    log "MySQL 暂不可连接，继续等待（第 ${attempt}/30 次）..."
    sleep 2
  done

  log "等待 MySQL 可连接超时，停止执行 SQL 初始化。"
  exit 1
}

execute_sql_files() {
  local sql_files=()
  local sql_file

  if [[ -f "${MYSQL_SQL_INIT_MARKER}" ]]; then
    log "检测到 SQL 初始化标记文件，跳过重复初始化：${MYSQL_SQL_INIT_MARKER}"
    return
  fi

  if [[ ! -d "${SQL_DIR}" ]]; then
    log "SQL 目录不存在，跳过数据库初始化：${SQL_DIR}"
    return
  fi

  mapfile -t sql_files < <(find "${SQL_DIR}" -maxdepth 1 -type f -name '*.sql' | sort)
  if [[ "${#sql_files[@]}" -eq 0 ]]; then
    log "SQL 目录中没有 .sql 文件，跳过数据库初始化：${SQL_DIR}"
    return
  fi

  wait_for_mysql_before_sql

  log "开始执行 SQL 初始化文件，目录：${SQL_DIR}"
  for sql_file in "${sql_files[@]}"; do
    log "正在执行 SQL 文件：${sql_file}"
    log "SQL 文件大小：$(du -h "${sql_file}" | awk '{print $1}')"
    docker exec -i "${MYSQL_CONTAINER}" mysql \
      --binary-mode=1 \
      --default-character-set=utf8mb4 \
      -uroot \
      -p"${MYSQL_ROOT_PASSWORD}" < "${sql_file}"
    log "SQL 文件执行完成：${sql_file}"
  done

  touch "${MYSQL_SQL_INIT_MARKER}"
  log "SQL 初始化完成，已写入标记文件：${MYSQL_SQL_INIT_MARKER}"
}

main() {
  run_step "Check root privileges" require_root
  run_step "Check operating system" ensure_rocky_like
  run_step "Check and install Docker" ensure_docker
  run_step "Check bundled image archives" ensure_bundled_archives
  run_step "Create data directories" ensure_data_dirs
  run_step "Import Redis image" ensure_image "${REDIS_IMAGE}" "${IMAGE_DIR}/${REDIS_IMAGE_ARCHIVE_NAME}"
  run_step "Import MySQL image" ensure_image "${MYSQL_IMAGE}" "${IMAGE_DIR}/${MYSQL_IMAGE_ARCHIVE_NAME}"
  run_step "Import tngs-server-prod image" ensure_image "${TNGS_SERVER_IMAGE}" "${IMAGE_DIR}/${TNGS_SERVER_IMAGE_ARCHIVE_NAME}"
  run_step "Start Redis container" ensure_redis_container
  run_step "Start MySQL container" ensure_mysql_container
  run_step "Execute SQL initialization" execute_sql_files
  run_step "Start tngs-server-prod container" ensure_tngs_server_container
  log "Install flow completed."
}

main "$@"
