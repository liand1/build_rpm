# tngs-bootstrap RPM

Target OS: Rocky Linux / RHEL-compatible Linux.

## Runtime behavior

When the RPM is installed, `%post` opens a terminal window for:

```bash
/var/log/tngs-bootstrap.log
```

Then it schedules the real installer with `systemd-run`, delayed by 20 seconds to avoid `dnf` lock conflicts during the RPM transaction.

The installer:

1. Checks Docker and installs it if missing.
2. Creates the `docker` group if missing and adds the active graphical desktop user to it.
3. Loads bundled Docker images from the RPM payload when the target images are missing:

```bash
/usr/local/libexec/tngs-bootstrap/images/mysql_latest.tar
/usr/local/libexec/tngs-bootstrap/images/redis_latest.tar
/usr/local/libexec/tngs-bootstrap/images/tngs-server-prod-1.0.0.tar
```

The RPM package includes these image archives from the local `images` directory. They are packaged as explicit RPM sources (`Source1`, `Source2`, and `Source3`), so the generated RPM should be roughly hundreds of MB, not KB.

4. Creates host data directories if missing:

```bash
/tNGS/data/mysql
/tNGS/data/redis/data
/tngs_project_prod
/project
/tNGS/server/logs
```

5. Starts Redis:

```bash
docker run -d --name redis-tngs --restart=always -p 6380:6379 -v /tNGS/data/redis/data:/data -v /etc/localtime:/etc/localtime:ro dockerpull.pw/redis:latest --requirepass 123456
```

6. Starts MySQL:

```bash
docker run -v /tNGS/data/mysql/:/var/lib/mysql -v /etc/localtime:/etc/localtime:ro -p 3306:3306 -e MYSQL_ROOT_PASSWORD=123456 -e TZ=Asia/Shanghai --restart=always --name mysql-tngs -d dockerpull.pw/mysql:latest --lower_case_table_names=1
```

7. Waits 15 seconds after MySQL starts, then executes SQL files from the RPM payload in filename order:

```bash
/usr/local/libexec/tngs-bootstrap/sql/*.sql
```

After successful SQL initialization, the installer writes:

```bash
/tNGS/data/mysql/.tngs_sql_initialized
```

If this marker exists, SQL initialization is skipped on later installs.

SQL files are executed with MySQL binary mode enabled:

```bash
mysql --binary-mode=1 --default-character-set=utf8mb4 -uroot -p123456
```

8. Starts `tngs-server-prod` last:

```bash
docker run -d -e env=prod -p 58081:8080 --name tngs-server-prod -v /var/run/docker.sock:/var/run/docker.sock -v /tngs_project_prod:/tngs_project_prod -v /project:/project -v /tNGS/server/logs:/tNGS/server/logs tngs-server-prod:1.0.0
```

`hello-world` is no longer started.

Docker group changes do not affect an already-open login session. After install, the user must log out and log back in, or run:

```bash
newgrp docker
```

Then Docker commands can run without `sudo`.

## Uninstall behavior

When the RPM is removed, `%preun` opens the log window and prints:

```text
正在停止服务
```

Then it stops only the services started by this package:

```bash
mysql-tngs
redis-tngs
tngs-server-prod
```

It does not remove containers, images, or data directories.

## Terminal support

The log window is best effort. The launcher detects the active graphical user session with `loginctl`, reads the session environment from `/proc/<session-leader>/environ`, then tries:

1. `gnome-terminal`
2. `kgx`
3. `konsole`
4. `xterm`

If no terminal opens, check the log manually:

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
./out/RPMS/noarch/tngs-bootstrap-0.3.7-1.el9.noarch.rpm
```

Verify bundled image archives:

```bash
rpm -qpl ./out/RPMS/noarch/tngs-bootstrap-0.3.7-1.el9.noarch.rpm | grep '/images/'
```

Expected entries:

```bash
/usr/local/libexec/tngs-bootstrap/images/mysql_latest.tar
/usr/local/libexec/tngs-bootstrap/images/redis_latest.tar
/usr/local/libexec/tngs-bootstrap/images/tngs-server-prod-1.0.0.tar
```

Verify bundled SQL files:

```bash
rpm -qpl ./out/RPMS/noarch/tngs-bootstrap-0.3.7-1.el9.noarch.rpm | grep '/sql/'
```

## Install

```bash
sudo dnf install -y ./out/RPMS/noarch/tngs-bootstrap-0.3.7-1.el9.noarch.rpm
```

## Uninstall

```bash
sudo dnf remove -y tngs-bootstrap
```
