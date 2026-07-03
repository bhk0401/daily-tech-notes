# Kubernetes Pod Security Standards & Admission Controllers：生产环境安全基线

## 背景与目标

在 Kubernetes 生产环境中，容器安全是零信任架构的最后一道防线。即使你的镜像经过签名验证、网络策略已经配置，如果 Pod 本身以 root 身份运行、挂载了宿主机敏感目录、或拥有过高的 Linux capabilities，攻击者一旦突破应用层防御，就能轻易实现容器逃逸，危及整个集群。

Pod Security Standards (PSS) 是 Kubernetes 原生提供的安全基线规范，定义了三种安全级别：**Privileged**（无限制）、**Baseline**（阻止已知特权升级）、**Restricted**（遵循最小权限原则）。从 Kubernetes 1.23 开始，PSS 作为 GA 功能内置于集群，通过 Pod Security Admission (PSA) 控制器在 Pod 创建时进行强制校验。

本文目标：
1. 理解 PSS 三个安全级别的具体约束差异
2. 掌握 PSA 的命名空间级配置方法
3. 学会在现有集群中渐进式迁移到 Restricted 级别
4. 提供可运行的 Demo 验证安全策略生效

适用场景：
- 新集群初始化时的安全基线配置
- 现有集群的安全加固迁移
- 合规审计（SOC2、ISO27001、等保 2.0）的容器安全要求
- 多租户集群的租户隔离策略

## 核心概念

### Pod Security Standards 三个级别

| 级别 | 描述 | 适用场景 |
|------|------|----------|
| **Privileged** | 无任何限制，等同于禁用 PSS | 系统命名空间（kube-system）、特权工作负载 |
| **Baseline** | 阻止已知特权升级，最小侵入性 | 大多数通用工作负载，迁移过渡期 |
| **Restricted** | 遵循最小权限，接近 Pod Security Context 最佳实践 | 高安全要求场景、多租户隔离、合规审计 |

### Baseline 级别关键约束

Baseline 级别主要阻止以下高风险配置：

```yaml
# 禁止 Host 命名空间共享
hostNetwork: true      # ❌
hostPID: true          # ❌
hostIPC: true          # ❌

# 禁止特权容器
securityContext:
  privileged: true     # ❌

# 禁止敏感能力添加
securityContext:
  capabilities:
    add:
      - SYS_ADMIN      # ❌
      - NET_ADMIN      # ❌
      - SYS_PTRACE     # ❌

# 禁止 HostPort
ports:
  - hostPort: 80       # ❌

# 禁止 AppArmor 非运行时配置
annotations:
  container.apparmor.security.beta.kubernetes.io: unconfined  # ❌
```

### Restricted 级别额外约束

Restricted 在 Baseline 基础上进一步要求：

```yaml
# 必须非 root 运行
securityContext:
  runAsNonRoot: true   # ✅ 必须
  runAsUser: 1000      # ✅ 非 0

# 禁止 root 文件系统写入
securityContext:
  readOnlyRootFilesystem: true  # ✅ 必须

# 禁止能力添加（只能 drop）
securityContext:
  capabilities:
    drop:
      - ALL            # ✅ 推荐
    # add: []          # ❌ 禁止任何 add

# 必须设置 seccompProfile
securityContext:
  seccompProfile:
    type: RuntimeDefault  # ✅ 必须
```

### Pod Security Admission 工作机制

PSA 是 Kubernetes 内置的准入控制器，在 Pod 创建请求到达 API Server 时介入：

```
用户 kubectl apply
       ↓
API Server 认证授权
       ↓
Pod Security Admission (PSA) ← 检查 namespace labels
       ↓
其他准入控制器（ValidatingWebhook 等）
       ↓
Etcd 持久化
```

PSA 通过命名空间标签配置策略：

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: production
  labels:
    pod-security.kubernetes.io/enforce: restricted      # 强制级别
    pod-security.kubernetes.io/enforce-version: latest   # PSS 版本
    pod-security.kubernetes.io/audit: restricted         # 审计级别
    pod-security.kubernetes.io/audit-version: latest
    pod-security.kubernetes.io/warn: restricted          # 警告级别
    pod-security.kubernetes.io/warn-version: latest
```

三种模式说明：
- **enforce**: 违反策略直接拒绝 Pod 创建
- **audit**: 允许创建，但记录审计日志（用于观察）
- **warn**: 允许创建，但返回警告信息给用户

## 实战/示例

### 环境准备

```bash
# 确认集群版本（PSS 需要 1.23+）
kubectl version --short

# 查看当前准入控制器
kubectl get apiservice v1.admissionregistration.k8s.io -o yaml | grep -A5 controllers
```

### Demo 1：创建测试命名空间并配置 PSA

```bash
# 创建 baseline 级别的命名空间
kubectl create namespace baseline-test
kubectl label namespace baseline-test \
  pod-security.kubernetes.io/enforce=baseline \
  pod-security.kubernetes.io/enforce-version=latest

# 创建 restricted 级别的命名空间
kubectl create namespace restricted-test
kubectl label namespace restricted-test \
  pod-security.kubernetes.io/enforce=restricted \
  pod-security.kubernetes.io/enforce-version=latest
```

### Demo 2：验证 Baseline 策略拦截

创建 `violation-privileged.yaml`：

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: privileged-pod
  namespace: baseline-test
spec:
  containers:
  - name: test
    image: nginx:alpine
    securityContext:
      privileged: true
```

应用并观察拒绝：

```bash
kubectl apply -f violation-privileged.yaml
# 预期输出：
# Error from server: admission webhook "pod-security.kubernetes.io" denied the request:
# would violate PodSecurity "baseline:latest": privileged (container "test" must not set securityContext.privileged=true)
```

### Demo 3：验证 Restricted 策略拦截

创建 `violation-root.yaml`：

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: root-pod
  namespace: restricted-test
spec:
  containers:
  - name: test
    image: nginx:alpine
    # 缺少 runAsNonRoot: true
```

```bash
kubectl apply -f violation-root.yaml
# 预期输出：
# would violate PodSecurity "restricted:latest": runAsNonRoot (container "test" must set securityContext.runAsNonRoot=true)
```

### Demo 4：符合 Restricted 标准的 Pod

创建 `compliant-pod.yaml`：

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: secure-pod
  namespace: restricted-test
  labels:
    app: secure-demo
spec:
  securityContext:
    runAsNonRoot: true
    runAsUser: 1000
    runAsGroup: 1000
    fsGroup: 1000
    seccompProfile:
      type: RuntimeDefault
  containers:
  - name: app
    image: nginx:alpine
    securityContext:
      allowPrivilegeEscalation: false
      readOnlyRootFilesystem: true
      capabilities:
        drop:
          - ALL
    volumeMounts:
    - name: tmp
      mountPath: /tmp
    - name: cache
      mountPath: /var/cache/nginx
    - name: run
      mountPath: /var/run
  volumes:
  - name: tmp
    emptyDir: {}
  - name: cache
    emptyDir: {}
  - name: run
    emptyDir: {}
```

```bash
kubectl apply -f compliant-pod.yaml
kubectl get pod secure-pod -n restricted-test
# 预期：Running 状态
```

### Demo 5：渐进式迁移策略

对于现有集群，不要直接从 Privileged 跳到 Restricted。建议分阶段：

```bash
# Phase 1: 仅 warn 模式，观察影响
kubectl label namespace production \
  pod-security.kubernetes.io/warn=restricted \
  pod-security.kubernetes.io/warn-version=latest

# 观察 1-2 周，检查审计日志
kubectl logs -n kube-system -l component=kube-apiserver | grep -i podsecurity

# Phase 2: 切换到 audit 模式
kubectl label namespace production \
  pod-security.kubernetes.io/audit=restricted \
  pod-security.kubernetes.io/audit-version=latest

# Phase 3: 修复所有违规后，启用 enforce
kubectl label namespace production \
  pod-security.kubernetes.io/enforce=restricted \
  pod-security.kubernetes.io/enforce-version=latest
```

### demos/ 目录结构

本示例代码已整理到仓库 demos/pod-security/ 目录：

```
demos/
└── pod-security/
    ├── 01-namespace-baseline.yaml
    ├── 02-namespace-restricted.yaml
    ├── 03-violation-privileged.yaml
    ├── 04-violation-root.yaml
    ├── 05-compliant-pod.yaml
    └── README.md
```

## 常见坑与排查

### 坑 1：系统命名空间被误伤

**问题**: 给 kube-system 打了 restricted 标签，导致 CoreDNS、kube-proxy 无法启动。

**原因**: 系统组件需要特权权限，不应受 PSS 约束。

**解决**:

```bash
# 排除系统命名空间
kubectl label namespace kube-system \
  pod-security.kubernetes.io/enforce=privileged \
  --overwrite

# 或使用豁免配置（Kubernetes 1.25+）
# 在 kube-apiserver 启动参数中添加：
--admission-control-config-file=/etc/kubernetes/admission-config.yaml
```

admission-config.yaml:

```yaml
apiVersion: apiserver.config.k8s.io/v1
kind: AdmissionConfiguration
plugins:
- name: PodSecurity
  configuration:
    apiVersion: pod-security.admission.config.k8s.io/v1
    kind: PodSecurityConfiguration
    exemptions:
      usernames: []
      runtimeClasses: []
      namespaces:
      - kube-system
      - kube-public
      - kube-node-lease
```

### 坑 2：Init Container 被忽略

**问题**: 主容器符合规范，但 Init Container 使用了 privileged，Pod 仍被拒绝。

**原因**: PSA 会校验所有容器（包括 Init Container 和 Ephemeral Containers）。

**排查**:

```bash
kubectl describe pod <pod-name> -n <namespace>
# 查看 Events 中的拒绝原因，会明确指出哪个容器违规
```

### 坑 3：Helm Chart 不兼容

**问题**: 部署第三方 Helm Chart 时大量 Pod 被拒绝。

**解决**:

```bash
# 方案 1: 在 values.yaml 中覆盖 securityContext
helm install myapp ./chart \
  --set podSecurityContext.runAsNonRoot=true \
  --set containerSecurityContext.allowPrivilegeEscalation=false

# 方案 2: 为特定命名空间降级策略（临时）
kubectl label namespace myapp-ns \
  pod-security.kubernetes.io/enforce=baseline \
  --overwrite

# 方案 3: 使用 Helm post-renderer 自动注入安全配置
```

### 坑 4：审计日志找不到

**问题**: 配置了 audit 模式，但看不到审计日志。

**原因**: Kubernetes 审计日志需要单独配置。

**解决**:

```bash
# 检查 API Server 审计配置
cat /etc/kubernetes/audit-policy.yaml

# 确保包含 PodSecurity 相关规则
# 审计日志默认输出到 /var/log/kubernetes/audit.log

# 实时查看
tail -f /var/log/kubernetes/audit.log | grep -i podsecurity
```

### 坑 5：与 OPA/Gatekeeper 冲突

**问题**: 同时启用 PSA 和 OPA Gatekeeper，策略冲突导致难以排查。

**建议**:

1. PSA 作为基础基线（L1），处理常见安全约束
2. OPA/Gatekeeper 作为补充（L2），处理业务特定策略
3. 明确分工，避免重复校验同一字段

```yaml
# OPA 中跳过已由 PSA 处理的检查
violation[{"msg": msg}] {
  # 不重复检查 runAsNonRoot，PSA 已处理
  # 检查业务特定逻辑
  input.review.object.kind == "Deployment"
  ...
}
```

## Checklist

部署前检查清单：

### 集群准备
- [ ] Kubernetes 版本 ≥ 1.23（PSS GA）
- [ ] PodSecurity 准入控制器已启用（默认启用）
- [ ] 审计日志已配置（用于 audit 模式观察）

### 命名空间策略
- [ ] 系统命名空间（kube-system 等）设置为 privileged
- [ ] 开发/测试命名空间设置为 baseline
- [ ] 生产命名空间设置为 restricted（或渐进迁移）
- [ ] 所有命名空间都明确设置了 enforce 标签

### Pod 规范
- [ ] 所有容器设置 `runAsNonRoot: true`
- [ ] 所有容器设置 `allowPrivilegeEscalation: false`
- [ ] 所有容器 drop 全部 capabilities（`drop: ["ALL"]`）
- [ ] 所有容器设置 `readOnlyRootFilesystem: true`
- [ ] 所有 Pod 设置 `seccompProfile.type: RuntimeDefault`
- [ ] Init Container 同样符合上述要求

### 迁移计划
- [ ] 已识别所有现有 Pod 的安全上下文配置
- [ ] 已测试关键应用在 restricted 模式下的兼容性
- [ ] 已制定回滚方案（标签快速降级）
- [ ] 已通知相关团队策略变更时间表

### 持续监控
- [ ] 审计日志已接入 SIEM/告警系统
- [ ] 定期扫描现有 Pod 的合规性（使用 kubectl-convert 或第三方工具）
- [ ] CI/CD 流水线集成 PSS 预检（如使用 kubeval、conftest）

## 参考资料

1. **Kubernetes 官方文档 - Pod Security Admission**
   https://kubernetes.io/docs/concepts/security/pod-security-admission/
   - PSA 配置指南、命名空间标签说明、豁免配置

2. **Kubernetes 官方文档 - Pod Security Standards**
   https://kubernetes.io/docs/concepts/security/pod-security-standards/
   - 三个安全级别的详细约束列表、逐条解释

3. **Kubernetes 官方 - Pod Security Standards 参考（按级别）**
   https://kubernetes.io/docs/concepts/security/pod-security-standards/privileged/
   https://kubernetes.io/docs/concepts/security/pod-security-standards/baseline/
   https://kubernetes.io/docs/concepts/security/pod-security-standards/restricted/

4. **NSA/CISA Kubernetes Hardening Guide**
   https://media.defense.gov/2022/Aug/29/2003066362/-1/-1/0/CTR_KUBERNETES_HARDENING_GUIDANCE_1.2_20220829.PDF
   - 美国国家安全局发布的 K8s 加固指南，PSS 是核心推荐

5. **kube-score - Pod 安全配置静态检查工具**
   https://kube-score.com/
   - CI/CD 集成，提前发现 PSS 违规

6. **Datadog - Kubernetes Pod Security Standards 实践指南**
   https://www.datadoghq.com/blog/kubernetes-pod-security-standards/
   - 生产环境迁移经验、常见问题排查
