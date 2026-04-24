# tngs-bootstrap RPM

Target OS: Rocky Linux / RHEL-compatible Linux.

## Runtime behavior

When the RPM is installed, the package `%post` script does two things:

1. Opens a terminal window in the active graphical desktop session and tails:

```bash
/var/log/tngs-bootstrap.log
```

2. Starts the real installer asynchronously through `systemd-run`, delayed by 20 seconds to avoid `dnf` lock conflicts during the RPM install transaction.

The installer then:

1. Checks Docker and installs it if missing.
2. Checks `hello-world:latest` and pulls it if missing.
3. Stops all running containers and clears unused Docker cache.
4. Runs the `hello-world` container.

## Terminal support

The log window is best effort. The launcher detects the active graphical user session with `loginctl`, then tries:

1. `gnome-terminal`
2. `konsole`
3. `xterm`

If no terminal opens, the install still runs. Check the log manually:

```bash
sudo tail -n 200 /var/log/tngs-bootstrap.log
```

## Build

```bash
sudo dnf install -y rpm-build rpmdevtools tar dnf-plugins-core
chmod +x build-rpm.sh
./build-rpm.sh
```

Output:

```bash
./out/RPMS/noarch/tngs-bootstrap-0.2.3-1.el9.noarch.rpm
```

## Install

```bash
sudo dnf install -y ./out/RPMS/noarch/tngs-bootstrap-0.2.3-1.el9.noarch.rpm
```

## Manual rerun

```bash
sudo /usr/local/libexec/tngs-bootstrap/tngs-bootstrap.sh
```
