Name:           tngs-bootstrap
Version:        0.3.7
Release:        1%{?dist}
Summary:        安装TNGS和其相关的服务

License:        Proprietary
URL:            https://example.local/tngs
BuildArch:      noarch
Source0:        %{name}-%{version}.tar.gz
Source1:        mysql_latest.tar
Source2:        redis_latest.tar
Source3:        tngs-server-prod-1.0.0.tar

Requires(post): /usr/bin/bash
Requires(post): /usr/bin/systemctl
Requires(post): /usr/bin/systemd-run
Requires(preun): /usr/bin/bash

%description
tngs-bootstrap installs Docker when missing, loads bundled MySQL, Redis,
and tngs-server-prod images, and starts the related containers.

%prep
%autosetup

%build
# no build step

%install
install -d %{buildroot}/usr/local/libexec/tngs-bootstrap
cp -a scripts %{buildroot}/usr/local/libexec/tngs-bootstrap/
cp -a sql %{buildroot}/usr/local/libexec/tngs-bootstrap/
cp -a rpm %{buildroot}/usr/local/libexec/tngs-bootstrap/
install -d %{buildroot}/usr/local/libexec/tngs-bootstrap/images
install -m 0644 %{SOURCE1} %{buildroot}/usr/local/libexec/tngs-bootstrap/images/mysql_latest.tar
install -m 0644 %{SOURCE2} %{buildroot}/usr/local/libexec/tngs-bootstrap/images/redis_latest.tar
install -m 0644 %{SOURCE3} %{buildroot}/usr/local/libexec/tngs-bootstrap/images/tngs-server-prod-1.0.0.tar
install -m 0755 build-rpm.sh %{buildroot}/usr/local/libexec/tngs-bootstrap/build-rpm.sh
install -m 0644 README.md %{buildroot}/usr/local/libexec/tngs-bootstrap/README.md

%post
LOG_FILE=/var/log/tngs-bootstrap.log
UNIT_NAME=tngs-bootstrap-install
mkdir -p /var/log || :
touch "${LOG_FILE}" || :
{
  echo "[$(date '+%F %T')] [tngs-bootstrap] RPM 安装后流程已启动。"
  echo "[$(date '+%F %T')] [tngs-bootstrap] 安装程序将在约 20 秒后开始执行。"
} >> "${LOG_FILE}" 2>&1 || :

# Best effort: open a terminal in the active graphical user session.
/usr/local/libexec/tngs-bootstrap/scripts/open-log-terminal.sh "${LOG_FILE}" "正在安装 tNGS 服务" >/dev/null 2>&1 || :

# Run asynchronously after install to avoid package-manager lock conflicts.
SYSTEMD_RUN_OUTPUT="$(
  /usr/bin/systemd-run \
    --unit="${UNIT_NAME}" \
    --description="tngs bootstrap installer" \
    --on-active=20s \
    /usr/local/libexec/tngs-bootstrap/scripts/tngs-bootstrap.sh 2>&1
)"
SYSTEMD_RUN_RC=$?
{
  if [ ${SYSTEMD_RUN_RC} -eq 0 ]; then
    echo "[$(date '+%F %T')] [tngs-bootstrap] 已成功创建延迟安装任务：${UNIT_NAME}。"
    echo "[$(date '+%F %T')] [tngs-bootstrap] systemd-run 输出：${SYSTEMD_RUN_OUTPUT}"
  else
    echo "[$(date '+%F %T')] [tngs-bootstrap] 创建延迟安装任务失败：${UNIT_NAME}，退出码：${SYSTEMD_RUN_RC}。"
    echo "[$(date '+%F %T')] [tngs-bootstrap] systemd-run 输出：${SYSTEMD_RUN_OUTPUT}"
  fi
} >> "${LOG_FILE}" 2>&1 || :

%preun
if [ "$1" -eq 0 ]; then
  LOG_FILE=/var/log/tngs-bootstrap.log
  mkdir -p /var/log || :
  touch "${LOG_FILE}" || :
  {
    echo "[$(date '+%F %T')] [tngs-bootstrap] 正在停止服务"
  } >> "${LOG_FILE}" 2>&1 || :

  /usr/local/libexec/tngs-bootstrap/scripts/open-log-terminal.sh "${LOG_FILE}" "正在停止服务" >/dev/null 2>&1 || :
  /usr/local/libexec/tngs-bootstrap/scripts/tngs-uninstall.sh || :
fi

%files
/usr/local/libexec/tngs-bootstrap

%changelog
* Thu Apr 30 2026 Codex <codex@example.local> - 0.3.7-1
- Start Redis before MySQL and add bundled tngs-server-prod startup

* Wed Apr 29 2026 Codex <codex@example.local> - 0.3.6-1
- Run SQL initialization with MySQL binary mode enabled

* Wed Apr 29 2026 Codex <codex@example.local> - 0.3.5-1
- Package SQL files and run database initialization after MySQL starts

* Tue Apr 28 2026 Codex <codex@example.local> - 0.3.4-1
- Localize install and uninstall console output to Chinese

* Tue Apr 28 2026 Codex <codex@example.local> - 0.3.3-1
- Package MySQL and Redis image archives as explicit RPM sources

* Tue Apr 28 2026 Codex <codex@example.local> - 0.3.2-1
- Package only bundled MySQL and Redis image tar archives
- Improve GUI terminal launcher by reading active session environment

* Tue Apr 28 2026 Codex <codex@example.local> - 0.3.1-1
- Add active graphical user to docker group for non-sudo Docker usage

* Tue Apr 28 2026 Codex <codex@example.local> - 0.3.0-1
- Replace hello-world with bundled MySQL and Redis service startup
- Stop only mysql-tngs and redis-tngs during package uninstall

* Tue Apr 28 2026 Codex <codex@example.local> - 0.2.5-1
- Show Chinese stopping-service message in uninstall log terminal

* Sat Apr 25 2026 Codex <codex@example.local> - 0.2.4-1
- Stop all running Docker containers during package uninstall

* Fri Apr 24 2026 Codex <codex@example.local> - 0.2.3-1
- Launch log terminal through active graphical user session

* Thu Apr 24 2026 Codex <codex@example.local> - 0.2.2-1
- Best-effort popup terminal window to display install log in GUI installs

* Fri Apr 24 2026 Codex <codex@example.local> - 0.2.1-1
- Run bootstrap script asynchronously via systemd-run to avoid dnf lock issue

* Fri Apr 24 2026 Codex <codex@example.local> - 0.2.0-1
- Switch first-stage flow to Docker + hello-world

* Tue Apr 21 2026 Codex <codex@example.local> - 0.1.0-1
- Initial package: install Docker and ensure Redis container is running
