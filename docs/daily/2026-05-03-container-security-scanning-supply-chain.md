# 容器安全：镜像扫描、运行时防护与供应链安全

> 日期：2026-05-03 | 领域：容器安全/云原生 | 字数：约 2800 字

## 背景与目标

容器技术已成为云原生应用的基石，但安全威胁也随之而来。根据 Aqua Security 2025 年报告，76% 的组织在过去一年中经历过容器安全事件，其中镜像漏洞、配置错误和供应链攻击是最主要的三大威胁向量。

本文旨在帮助开发者和 DevOps 工程师建立完整的容器安全防线，涵盖三个核心层面：

1. **镜像扫描**：在构建和部署前发现已知漏洞
2. **运行时防护**：监控容器运行时的异常行为
3. **供应链安全**：确保从代码到镜像的完整链路可信

通过本文，你将掌握：
- 使用 Trivy/Grype 进行镜像漏洞扫描的完整流程
- 配置 Kubernetes 安全上下文与网络策略
- 实现镜像签名与验证的供应链安全实践
- 建立 CI/CD 中的安全门禁（Security Gate）

## 核心概念

### 容器安全威胁模型

容器安全需要分层防御，典型威胁包括：

| 威胁类型 | 攻击向量 | 影响范围 |
|---------|---------|---------|
| 镜像漏洞 | 基础镜像/依赖库 CVE | 容器内权限提升 |
| 配置错误 | 特权容器、root 运行 | 宿主机逃逸风险 |
| 供应链攻击 | 恶意镜像、投毒依赖 | 大规模横向渗透 |
| 运行时攻击 | 异常进程、网络外连 | 数据泄露/挖矿 |

### 镜像扫描原理

镜像扫描工具通过以下方式工作：

1. **文件系统分析**：解压镜像层，提取安装包清单（dpkg/rpm/apk）
2. **漏洞数据库匹配**：对照 CVE 数据库（NVD、Alpine SecDB、Debian Security Tracker）
3. **依赖树分析**：追踪语言包依赖（npm/pip/maven）的传递性漏洞
4. **风险评级**：根据 CVSS 评分和可利用性给出修复优先级

### 供应链安全：Sigstore 与 Cosign

Sigstore 是一个开源的签名基础设施，核心组件包括：

- **Cosign**：容器镜像签名与验证工具
- **Fulcio**：基于 OIDC 的短期证书颁发机构
- **Rekor**：透明日志，记录所有签名事件

通过签名验证，可以确保：
- 镜像确实由声称的发布者构建
- 镜像自签名后未被篡改
- 可追溯镜像的完整构建历史

## 实战/示例

### 示例 1：使用 Trivy 进行镜像漏洞扫描

Trivy 是最流行的容器扫描工具，支持多种扫描模式：

```bash
# 安装 Trivy
curl -sfL https://raw.githubusercontent.com/aquasecurity/trivy/main/contrib/install.sh | sh -s -- -b /usr/local/bin

# 扫描镜像（输出表格格式）
trivy image --format table nginx:1.24.0

# 扫描并仅显示高危漏洞
trivy image --severity HIGH,CRITICAL nginx:1.24.0

# 扫描本地 Docker 镜像
trivy image --format json --output trivy-results.json nginx:1.24.0

# 扫描 Dockerfile 最佳实践
trivy config --format table Dockerfile
```

**典型输出解读**：
```
┌──────────────┬────────────────┬──────────┬─────────┬─────────────────────┐
│    Library   │  Vulnerability │ Severity │ Status  │   Fixed Version     │
├──────────────┼────────────────┼──────────┼─────────┼─────────────────────┤
│ libssl3      │ CVE-2024-0727  │ CRITICAL │ FIXED   │ 3.0.13-0~deb12u1    │
│ openssl      │ CVE-2024-2511  │ HIGH     │ FIXED   │ 3.0.13-0~deb12u1    │
└──────────────┴────────────────┴──────────┴─────────┴─────────────────────┘
```

### 示例 2：CI/CD 中的安全门禁（GitHub Actions）

在 CI 流水线中集成扫描，阻止高危漏洞镜像进入生产：

```yaml
# .github/workflows/container-security.yml
name: Container Security Scan

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

jobs:
  security-scan:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Build image
        run: docker build -t myapp:${{ github.sha }} .

      - name: Run Trivy scan
        uses: aquasecurity/trivy-action@master
        with:
          image-ref: 'myapp:${{ github.sha }}'
          format: 'sarif'
          output: 'trivy-results.sarif'
          severity: 'CRITICAL,HIGH'
          exit-code: '1'  # 发现高危漏洞时失败

      - name: Upload SARIF to GitHub Security
        uses: github/codeql-action/upload-sarif@v3
        with:
          sarif_file: 'trivy-results.sarif'
```

### 示例 3：使用 Cosign 进行镜像签名与验证

```bash
# 生成密钥对（或使用无密钥签名）
cosign generate-key-pair

# 签名镜像
cosign sign --key cosign.key myregistry.io/myapp:v1.0.0

# 验证签名
cosign verify --key cosign.pub myregistry.io/myapp:v1.0.0

# 无密钥签名（使用 OIDC 身份）
cosign sign myregistry.io/myapp:v1.0.0

# 验证无密钥签名（自动获取 OIDC 身份）
cosign verify myregistry.io/myapp:v1.0.0 \
  --certificate-identity-regexp=".*@mycompany.com" \
  --certificate-oidc-issuer="https://accounts.google.com"
```

### 示例 4：Kubernetes 安全上下文配置

限制容器权限，防止特权升级：

```yaml
# secure-deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: secure-app
spec:
  template:
    spec:
      securityContext:
        runAsNonRoot: true          # 禁止 root 运行
        runAsUser: 1000             # 指定非特权用户
        runAsGroup: 1000
        fsGroup: 1000
        seccompProfile:
          type: RuntimeDefault      # 启用默认 seccomp 配置
      
      containers:
      - name: app
        image: myapp:v1.0.0
        securityContext:
          allowPrivilegeEscalation: false  # 禁止提权
          readOnlyRootFilesystem: true     # 只读根文件系统
          capabilities:
            drop:
              - ALL                        # 丢弃所有 Linux capabilities
        
        # 资源限制（防止 DoS）
        resources:
          limits:
            cpu: "500m"
            memory: "256Mi"
          requests:
            cpu: "100m"
            memory: "128Mi"
        
        # 健康检查
        livenessProbe:
          httpGet:
            path: /health
            port: 8080
          initialDelaySeconds: 10
          periodSeconds: 10
```

### 示例 5：网络策略限制容器通信

```yaml
# network-policy.yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: deny-all-ingress
  namespace: production
spec:
  podSelector: {}  # 选择所有 Pod
  policyTypes:
  - Ingress
  - Egress
  
  # 默认拒绝所有入站流量
  ingress: []
  
  # 仅允许特定出站流量
  egress:
  - to:
    - namespaceSelector:
        matchLabels:
          name: kube-system
    ports:
    - protocol: UDP
      port: 53  # 允许 DNS 查询
  
  - to:
    - podSelector:
        matchLabels:
          app: database
    ports:
    - protocol: TCP
      port: 5432  # 仅允许访问数据库
```

## 常见坑与排查

### 坑 1：基础镜像漏洞无限循环

**问题**：修复了应用依赖的漏洞，但基础镜像仍有 CVE。

**解决方案**：
```bash
# 使用最小化基础镜像
FROM alpine:3.19  # 或 distroless
# FROM ubuntu:22.04  # 避免臃肿镜像

# 定期更新基础镜像
docker pull alpine:latest
docker image ls | grep alpine
```

**排查命令**：
```bash
# 查看镜像层级和大小
docker history --no-trunc myapp:latest

# 分析哪一层引入了漏洞
trivy image --format json myapp:latest | jq '.Results[] | select(.Vulnerabilities[] | .Severity == "CRITICAL")'
```

### 坑 2：Cosign 验证失败

**问题**：`cosign verify` 返回 "signature unknown" 错误。

**排查步骤**：
```bash
# 1. 确认镜像确实已签名
cosign tree myregistry.io/myapp:v1.0.0

# 2. 检查公钥是否匹配
cosign verify --key cosign.pub myregistry.io/myapp:v1.0.0 --verbose

# 3. 确认镜像标签未被覆盖（签名绑定到特定 digest）
docker inspect myregistry.io/myapp:v1.0.0 | grep Digest

# 正确做法：按 digest 验证
cosign verify --key cosign.pub myregistry.io/myapp@sha256:abc123...
```

### 坑 3：安全上下文导致应用崩溃

**问题**：配置 `runAsNonRoot: true` 后应用无法启动。

**排查**：
```bash
# 查看 Pod 事件
kubectl describe pod secure-app-xxxxx

# 典型错误：Error: container has runAsNonRoot and image will run as root

# 解决方案 1：在 Dockerfile 中创建非 root 用户
RUN addgroup -g 1000 appgroup && \
    adduser -u 1000 -G appgroup -D appuser
USER appuser

# 解决方案 2：使用 securityContext 覆盖
securityContext:
  runAsUser: 1000
  runAsGroup: 1000
```

### 坑 4：网络策略不生效

**问题**：配置了 NetworkPolicy 但流量未被阻止。

**排查清单**：
```bash
# 1. 确认 CNI 插件支持 NetworkPolicy
kubectl get pods -n kube-system | grep -E 'calico|cilium|weave'

# 2. 检查策略是否应用到正确命名空间
kubectl get networkpolicy -n production -o yaml

# 3. 测试连通性
kubectl run test-pod --rm -it --image=busybox --restart=Never -- \
  wget --timeout=5 http://secure-app:8080

# 4. 查看 CNI 日志（以 Calico 为例）
kubectl logs -n calico-system -l k8s-app=calico-node | grep -i policy
```

## Checklist

### 镜像安全
- [ ] 使用官方或可信的基础镜像
- [ ] 定期更新基础镜像（至少每月）
- [ ] 在 CI 中集成 Trivy/Grype 扫描
- [ ] 阻止 CRITICAL/HIGH 漏洞镜像部署
- [ ] 使用多阶段构建减少攻击面
- [ ] 不将敏感信息（密钥、token）硬编码到镜像

### 运行时安全
- [ ] 配置 `runAsNonRoot: true`
- [ ] 设置 `allowPrivilegeEscalation: false`
- [ ] 丢弃所有不必要的 Linux capabilities
- [ ] 启用只读根文件系统（`readOnlyRootFilesystem: true`）
- [ ] 配置资源限制（CPU/Memory）
- [ ] 配置健康检查（liveness/readiness probe）

### 网络安全
- [ ] 默认拒绝所有入站流量（Default Deny）
- [ ] 仅开放必要的端口
- [ ] 使用 NetworkPolicy 限制 Pod 间通信
- [ ] 生产环境启用 mTLS（如 Istio）
- [ ] 禁止容器直接访问外网（通过 NAT 网关）

### 供应链安全
- [ ] 对所有生产镜像进行签名
- [ ] 在部署前验证镜像签名
- [ ] 使用私有镜像仓库（Harbor/ECR/GCR）
- [ ] 启用镜像仓库的漏洞扫描功能
- [ ] 记录所有镜像的构建来源和依赖

### 监控与响应
- [ ] 部署运行时安全监控（Falco/Sysdig）
- [ ] 配置异常行为告警（特权进程、外连 IP）
- [ ] 建立漏洞响应流程（SLA：CRITICAL 24h 内修复）
- [ ] 定期进行安全审计和渗透测试

## 参考资料

1. **Trivy 官方文档** - 全面的容器扫描工具指南  
   https://aquasecurity.github.io/trivy/

2. **Sigstore/Cosign 文档** - 容器镜像签名与验证  
   https://docs.sigstore.dev/cosign/overview/

3. **Kubernetes 安全上下文最佳实践**  
   https://kubernetes.io/docs/tasks/configure-pod-container/security-context/

4. **CIS Kubernetes Benchmark** - 安全配置基线  
   https://www.cisecurity.org/benchmark/kubernetes

5. **Aqua Security 2025 容器安全报告**  
   https://www.aquasec.com/resources/container-security-report/

6. **Google Container Hardening Guide**  
   https://cloud.google.com/architecture/best-practices-for-operating-containers

---

*本文档由自动化流程生成 | GitHub: https://github.com/bhk0401/daily-tech-notes*
