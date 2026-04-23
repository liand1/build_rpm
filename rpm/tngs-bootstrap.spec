Name:           tngs-bootstrap
Version:        0.2.0
Release:        1%{?dist}
Summary:        Bootstrap Docker and run hello-world for Rocky Linux

License:        Proprietary
URL:            https://example.local/tngs
BuildArch:      noarch
Source0:        %{name}-%{version}.tar.gz

Requires(post): /usr/bin/bash
Requires(post): /usr/bin/systemctl
Requires(post): /usr/bin/dnf

%description
tngs-bootstrap installs Docker when missing, checks/pulls hello-world image,
stops running containers, clears Docker cache, and runs hello-world container.

%prep
%autosetup

%build
# no build step

%install
install -d %{buildroot}/usr/local/libexec/tngs-bootstrap
install -m 0755 scripts/tngs-bootstrap.sh %{buildroot}/usr/local/libexec/tngs-bootstrap/tngs-bootstrap.sh

%post
/usr/local/libexec/tngs-bootstrap/tngs-bootstrap.sh || :

%files
/usr/local/libexec/tngs-bootstrap/tngs-bootstrap.sh

%changelog
* Fri Apr 24 2026 Codex <codex@example.local> - 0.2.0-1
- Switch first-stage flow to Docker + hello-world

* Tue Apr 21 2026 Codex <codex@example.local> - 0.1.0-1
- Initial package: install Docker and ensure Redis container is running
