# Runtime Security Demos

本目录包含容器运行时安全的完整示例配置和脚本。

## 目录结构

```
demos/
├── runtime-security/
│   ├── seccomp-profiles/    # seccomp 配置文件
│   ├── apparmor-profiles/   # AppArmor 配置文件
│   └── gvisor/              # gVisor 运行时配置
└── scripts/                 # 工具脚本
```

## 快速开始

### 1. seccomp 配置

```bash
# 使用严格白名单运行容器
docker run --rm -it \
  --security-opt seccomp=demos/runtime-security/seccomp-profiles/restrictive.json \
  nginx:alpine

# 审计模式（记录但不阻止）
docker run --rm -it \
  --security-opt seccomp=demos/runtime-security/seccomp-profiles/audit.json \
  myapp:latest
```

### 2. AppArmor 配置

```bash
# 加载配置文件
sudo apparmor_parser -r demos/runtime-security/apparmor-profiles/nginx-profile

# 验证加载
sudo aa-status | grep docker-nginx

# 使用配置文件运行容器
docker run --rm -it \
  --security-opt apparmor=docker-nginx \
  nginx:alpine
```

### 3. gVisor 沙箱

```bash
# 安装 gVisor (Ubuntu)
curl -fsSL https://gvisor.dev/archive.key | sudo gpg --dearmor
echo "deb [arch=$(dpkg --print-architecture)] https://storage.googleapis.com/gvisor/releases release main" | sudo tee /etc/apt/sources.list.d/gvisor.list
sudo apt-get update && sudo apt-get install -y runsc

# 配置 containerd
sudo mkdir -p /etc/containerd
containerd config default | sudo tee /etc/containerd/config.toml
# 编辑 config.toml 添加 runsc 运行时配置
sudo systemctl restart containerd

# Kubernetes 部署
kubectl apply -f demos/runtime-security/gvisor/runtime-class.yaml
kubectl apply -f demos/runtime-security/gvisor/sandbox-pod.yaml
```

### 4. 安全验证脚本

```bash
# 使脚本可执行
chmod +x demos/scripts/*.sh

# 验证容器安全配置
./demos/scripts/verify-security.sh <container-id>

# 生成 seccomp 配置（从运行中的容器）
./demos/scripts/generate-seccomp.sh <container-name>
```

## 配置文件说明

### seccomp-profiles/

| 文件 | 用途 | 生产建议 |
|------|------|----------|
| `default.json` | Docker 默认配置 | 仅开发环境 |
| `restrictive.json` | 严格白名单 | 推荐生产使用 |
| `audit.json` | 审计模式 | 用于收集系统调用 |

### apparmor-profiles/

| 文件 | 适用场景 |
|------|----------|
| `nginx-profile` | Nginx/Web 服务器容器 |
| `nodejs-profile` | Node.js 应用容器 |

### gvisor/

| 文件 | 说明 |
|------|------|
| `runtime-class.yaml` | Kubernetes RuntimeClass 定义 |
| `sandbox-pod.yaml` | 沙箱 Pod 完整示例（含 NetworkPolicy） |

## 安全最佳实践

1. **渐进式部署**：先用 audit 模式收集，再切换到 restrictive
2. **测试验证**：所有配置在 staging 环境充分测试
3. **监控告警**：记录 seccomp/AppArmor 拒绝事件
4. **定期审查**：季度审查安全配置有效性

## 故障排查

```bash
# 查看 seccomp 拒绝日志
dmesg | grep seccomp

# 查看 AppArmor 拒绝日志
sudo aa-logprof

# 查看 gVisor 沙箱日志
kubectl logs <pod> -c <sandbox-container>
```

## 参考资源

- [Docker Security Documentation](https://docs.docker.com/engine/security/)
- [gVisor Documentation](https://gvisor.dev/docs/)
- [AppArmor Quickstart](https://apparmor.net/quickstart/)
