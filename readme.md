# tngs-bootstrap RPM (Rocky Linux)

当前版本实现以下安装流程（双击安装 RPM 后触发）：

1. 检查 Docker，未安装则自动安装
2. 检查 `hello-world` 镜像，没有则拉取
3. 停止所有正在运行的容器，并清理 Docker 未使用缓存
4. 启动 `hello-world` 容器（用于验证 Docker 可用）

## 项目文件

- `scripts/tngs-bootstrap.sh`: 核心安装脚本
- `rpm/tngs-bootstrap.spec`: RPM 打包规范
- `build-rpm.sh`: 构建 RPM

## 构建 RPM（在 Rocky Linux）

```bash
sudo dnf install -y rpm-build rpmdevtools tar dnf-plugins-core
chmod +x build-rpm.sh
./build-rpm.sh
```

输出文件：

```bash
./out/RPMS/noarch/tngs-bootstrap-0.2.0-1.el9.noarch.rpm
```

## 安装 RPM

```bash
sudo dnf install -y ./out/RPMS/noarch/tngs-bootstrap-0.2.0-1.el9.noarch.rpm
```

安装后 `%post` 会自动执行脚本：

```bash
sudo /usr/local/libexec/tngs-bootstrap/tngs-bootstrap.sh
```
