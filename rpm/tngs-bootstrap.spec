Name:           tngs-bootstrap
Version:        0.2.4
Release:        1%{?dist}
Summary:        Bootstrap Docker and run hello-world for Rocky Linux

License:        Proprietary
URL:            https://example.local/tngs
BuildArch:      noarch
Source0:        %{name}-%{version}.tar.gz

Requires(post): /usr/bin/bash
Requires(post): /usr/bin/systemctl
Requires(post): /usr/bin/systemd-run
Requires(preun): /usr/bin/bash

%description
tngs-bootstrap installs Docker when missing, checks/pulls hello-world image,
stops running containers, clears Docker cache, and runs hello-world container.

%prep
%autosetup

%build
# no build step

%install
install -d %{buildroot}/usr/local/libexec/tngs-bootstrap
cp -a scripts %{buildroot}/usr/local/libexec/tngs-bootstrap/
cp -a images %{buildroot}/usr/local/libexec/tngs-bootstrap/
cp -a rpm %{buildroot}/usr/local/libexec/tngs-bootstrap/
install -m 0755 build-rpm.sh %{buildroot}/usr/local/libexec/tngs-bootstrap/build-rpm.sh
install -m 0644 README.md %{buildroot}/usr/local/libexec/tngs-bootstrap/README.md

%post
LOG_FILE=/var/log/tngs-bootstrap.log
UNIT_NAME=tngs-bootstrap-install
mkdir -p /var/log || :
touch "${LOG_FILE}" || :
{
  echo "[$(date '+%F %T')] [tngs-bootstrap] RPM post-install started."
  echo "[$(date '+%F %T')] [tngs-bootstrap] Installer is scheduled to start in about 20 seconds."
} >> "${LOG_FILE}" 2>&1 || :

# Best effort: open a terminal in the active graphical user session.
/usr/local/libexec/tngs-bootstrap/scripts/open-log-terminal.sh "${LOG_FILE}" "tngs-bootstrap installing" >/dev/null 2>&1 || :

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
    echo "[$(date '+%F %T')] [tngs-bootstrap] systemd-run scheduled successfully for unit ${UNIT_NAME}."
    echo "[$(date '+%F %T')] [tngs-bootstrap] systemd-run output: ${SYSTEMD_RUN_OUTPUT}"
  else
    echo "[$(date '+%F %T')] [tngs-bootstrap] systemd-run failed for unit ${UNIT_NAME} with exit code ${SYSTEMD_RUN_RC}."
    echo "[$(date '+%F %T')] [tngs-bootstrap] systemd-run output: ${SYSTEMD_RUN_OUTPUT}"
  fi
} >> "${LOG_FILE}" 2>&1 || :

%preun
if [ "$1" -eq 0 ]; then
  LOG_FILE=/var/log/tngs-bootstrap.log
  mkdir -p /var/log || :
  touch "${LOG_FILE}" || :
  {
    echo "[$(date '+%F %T')] [tngs-bootstrap] RPM uninstall requested."
  } >> "${LOG_FILE}" 2>&1 || :

  /usr/local/libexec/tngs-bootstrap/scripts/open-log-terminal.sh "${LOG_FILE}" "tngs-bootstrap uninstalling" >/dev/null 2>&1 || :
  /usr/local/libexec/tngs-bootstrap/scripts/tngs-uninstall.sh || :
fi

%files
/usr/local/libexec/tngs-bootstrap

%changelog
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
