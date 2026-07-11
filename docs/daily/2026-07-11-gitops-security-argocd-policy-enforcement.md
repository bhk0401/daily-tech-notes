# GitOps Security: ArgoCD Policy Enforcement, Image Verification & Supply Chain Protection

> 深入解析 GitOps 安全最佳实践，掌握 ArgoCD 策略 enforcement、镜像签名验证、密钥管理与供应链防护，构建零信任持续交付流水线。

## 背景与目标

随着云原生架构的普及，GitOps 已成为 Kubernetes 部署的事实标准。根据 CNCF 2025 年调查，超过 68% 的生产环境采用 GitOps 工作流，其中 ArgoCD 占据 76% 的市场份额。然而，GitOps 的"一切即代码"理念也带来了新的安全挑战：

**核心痛点：**
1. **配置漂移风险**：手动 kubectl 应用绕过 Git 审计，导致集群状态与 Git 仓库不一致
2. **恶意镜像注入**：未签名的容器镜像可能被篡改，引入漏洞或后门
3. **密钥泄露**：Secret 明文提交到 Git 仓库，或加密密钥管理不当
4. **权限过度授予**：ServiceAccount 权限过大，横向移动风险高
5. **供应链攻击**：依赖的 Helm Chart、Kustomize 模板可能被篡改

**本文目标：**
- 掌握 ArgoCD 策略引擎（OPA/Gatekeeper/Kyverno）的配置与 enforcement
- 实现容器镜像签名验证（Cosign + Sigstore）
- 学习密钥管理最佳实践（Sealed Secrets/External Secrets）
- 构建零信任 GitOps 流水线的完整 Checklist

通过本文，你将获得一套可直接应用于生产环境的 GitOps 安全防护体系。

## 核心概念

### 1. GitOps 安全模型

GitOps 安全基于三大支柱：

```
┌─────────────────────────────────────────────────────────────┐
│                    GitOps Security Triangle                  │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│   ┌──────────────┐      ┌──────────────┐      ┌──────────┐ │
│   │   Integrity  │──────│  Auditability │──────│ Reversibility│ │
│   │   (完整性)    │      │   (可审计性)   │      │  (可回滚)  │ │
│   └──────────────┘      └──────────────┘      └──────────┘ │
│         │                     │                     │        │
│         └─────────────────────┴─────────────────────┘        │
│                           │                                   │
│                    Git as Source of Truth                     │
│                    (Git 作为唯一事实源)                          │
└─────────────────────────────────────────────────────────────┘
```

**完整性 (Integrity)**：确保 Git 仓库中的配置未被篡改，通过 Git commit 签名、分支保护规则实现。

**可审计性 (Auditability)**：所有变更都有清晰的提交历史、作者信息和审批记录，支持追溯。

**可回滚 (Reversibility)**：任何问题都可以通过 Git revert 快速恢复到已知良好状态。

### 2. ArgoCD 架构与安全边界

```
┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
│   Git Repository│     │    ArgoCD       │     │  Kubernetes     │
│   (Source of    │────▶│  Control Plane  │────▶│  Cluster        │
│    Truth)       │     │                 │     │                 │
└─────────────────┘     └─────────────────┘     └─────────────────┘
        │                       │                       │
        │ 1. Commit Signing     │ 2. RBAC + Policy      │ 3. Image Verify
        │    Branch Protection  │    Webhook Validation │    Admission Ctrl
        ▼                       ▼                       ▼
┌─────────────────────────────────────────────────────────────────┐
│                    Security Enforcement Layers                   │
├─────────────────────────────────────────────────────────────────┤
│ Layer 1: Git Level    → GPG/SSH Signatures, Branch Rules       │
│ Layer 2: ArgoCD Level → RBAC, Project Scopes, Webhook Auth     │
│ Layer 3: Cluster Level→ OPA/Kyverno, Pod Security, Image Verify│
└─────────────────────────────────────────────────────────────────┘
```

### 3. 策略引擎对比

| 引擎 | 语言 | 性能 | 生态 | 适用场景 |
|------|------|------|------|----------|
| OPA/Gatekeeper | Rego | 中 | 成熟 | 通用策略、复杂逻辑 |
| Kyverno | YAML | 高 | 快速增长 | Kubernetes 原生、易上手 |
| ArgoCD Policies | YAML/Rego | 高 | Argo 生态 | GitOps 特定场景 |

### 4. 镜像签名与验证

Sigstore 项目提供了无密钥（keyless）签名机制：

```
┌─────────────┐     ┌─────────────┐     ┌─────────────┐
│   Developer │     │   Fulcio    │     │    Rekor    │
│             │────▶│  (CA/OIDC)  │────▶│ (Transparency│
│  cosign sign│     │  Issuance   │     │   Log)      │
└─────────────┘     └─────────────┘     └─────────────┘
       │                                       │
       │  Push Image + Signature               │
       ▼                                       ▼
┌─────────────────────────────────────────────────────────────┐
│                    Container Registry                        │
│   (Docker Hub / GHCR / Harbor / etc.)                       │
└─────────────────────────────────────────────────────────────┘
       │
       │  Verify on Pull/Deploy
       ▼
┌─────────────────────────────────────────────────────────────┐
│              Kubernetes Admission Controller                 │
│   (Sigstore Policy Controller / Kyverno / OPA)             │
└─────────────────────────────────────────────────────────────┘
```

## 实战/示例

### 示例 1: ArgoCD + Kyverno 策略 enforcement

**场景**：禁止 privileged 容器、强制 resource limits、要求镜像标签不可为 latest。

**Step 1: 安装 Kyverno**

```bash
# 添加 Kyverno Helm 仓库
helm repo add kyverno https://kyverno.github.io/kyverno/
helm repo update

# 安装 Kyverno 到专用命名空间
helm install kyverno kyverno/kyverno \
  -n kyverno \
  --create-namespace \
  --version 3.2.0
```

**Step 2: 创建 ClusterPolicy 禁止 privileged 容器**

```yaml
# policies/disallow-privileged-containers.yaml
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: disallow-privileged-containers
  annotations:
    policies.kyverno.io/title: Disallow Privileged Containers
    policies.kyverno.io/category: Pod Security Standards (Baseline)
    policies.kyverno.io/severity: high
    policies.kyverno.io/description: >-
      Privileged containers can access host resources and should be blocked
      in multi-tenant clusters.
spec:
  validationFailureAction: Enforce
  background: true
  rules:
    - name: deny-privileged
      match:
        any:
          - resources:
              kinds:
                - Pod
      validate:
        message: "Privileged containers are not allowed. Set securityContext.privileged to false."
        pattern:
          spec:
            containers:
              - securityContext:
                  privileged: "false"
```

**Step 3: 强制 resource limits**

```yaml
# policies/require-resource-limits.yaml
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: require-resource-limits
  annotations:
    policies.kyverno.io/title: Require Resource Limits
    policies.kyverno.io/category: Resource Management
    policies.kyverno.io/severity: medium
spec:
  validationFailureAction: Enforce
  background: true
  rules:
    - name: require-limits
      match:
        any:
          - resources:
              kinds:
                - Pod
      validate:
        message: "CPU and memory limits are required for all containers."
        pattern:
          spec:
            containers:
              - resources:
                  limits:
                    cpu: "?*"
                    memory: "?*"
```

**Step 4: 禁止 latest 标签**

```yaml
# policies/disallow-latest-tag.yaml
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: disallow-latest-tag
  annotations:
    policies.kyverno.io/title: Disallow Latest Tag
    policies.kyverno.io/category: Best Practices
    policies.kyverno.io/severity: high
spec:
  validationFailureAction: Enforce
  background: true
  rules:
    - name: deny-latest
      match:
        any:
          - resources:
              kinds:
                - Pod
      validate:
        message: "Using 'latest' tag is not allowed. Use specific version tags."
        pattern:
          spec:
            containers:
              - image: "!*:latest"
```

**Step 5: 应用策略到 ArgoCD Application**

```yaml
# argocd-apps/policies-app.yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: security-policies
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/your-org/gitops-policies.git
    targetRevision: HEAD
    path: policies
  destination:
    server: https://kubernetes.default.svc
    namespace: kyverno
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - Validate=true
      - CreateNamespace=true
```

### 示例 2: 镜像签名验证集成

**Step 1: 使用 Cosign 签名镜像**

```bash
# 对镜像进行签名（使用 OIDC keyless 模式）
cosign sign ghcr.io/your-org/your-app:v1.2.3

# 验证签名
cosign verify ghcr.io/your-org/your-app:v1.2.3 \
  --certificate-identity-regexp=https://github.com/your-org/.* \
  --certificate-oidc-issuer=https://token.actions.githubusercontent.com
```

**Step 2: 配置 ArgoCD Image Updater 验证签名**

```yaml
# argocd-image-updater/config.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: argocd-image-updater-config
  namespace: argocd
data:
  config.yaml: |
    registries:
      - name: GitHub Container Registry
        api_url: https://ghcr.io
        prefix: ghcr.io
        default: true
        credentials: secret:argocd/image-updater#ghcr-credentials
        insecure: false
        defaultns: your-org
    
    # 启用签名验证
    verify: true
    verify-key: |
      -----BEGIN PUBLIC KEY-----
      MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAE...
      -----END PUBLIC KEY-----
```

**Step 3: Kyverno 镜像验证策略**

```yaml
# policies/image-verification.yaml
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: verify-image-signatures
  annotations:
    policies.kyverno.io/title: Verify Image Signatures
    policies.kyverno.io/category: Supply Chain Security
    policies.kyverno.io/severity: critical
spec:
  validationFailureAction: Enforce
  background: false
  rules:
    - name: verify-cosign-signature
      match:
        any:
          - resources:
              kinds:
                - Pod
      verifyImages:
        - imageReferences:
            - "ghcr.io/your-org/*"
          attestors:
            - count: 1
              entries:
                - keys:
                    publicKeys: |
                      -----BEGIN PUBLIC KEY-----
                      MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAE...
                      -----END PUBLIC KEY-----
```

### 示例 3: Sealed Secrets 密钥管理

**Step 1: 安装 Sealed Secrets Controller**

```bash
helm install sealed-secrets bitnami/sealed-secrets \
  -n sealed-secrets \
  --create-namespace \
  --version 2.15.0
```

**Step 2: 创建 SealedSecret**

```bash
# 创建普通 Secret
kubectl create secret generic db-credentials \
  --from-literal=username=admin \
  --from-literal=password='super-secret-123' \
  --dry-run=client -o yaml > db-credentials.yaml

# 使用 kubeseal 加密
kubeseal --format yaml < db-credentials.yaml > db-credentials-sealed.yaml

# 提交加密后的 SealedSecret 到 Git
git add db-credentials-sealed.yaml
git commit -m "feat: add sealed DB credentials"
git push
```

**Step 3: ArgoCD 应用引用 SealedSecret**

```yaml
# argocd-apps/app-with-secrets.yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: my-app
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/your-org/gitops-repo.git
    targetRevision: HEAD
    path: apps/my-app
  destination:
    server: https://kubernetes.default.svc
    namespace: production
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
```

### 示例 4: ArgoCD RBAC 与 Project 隔离

```yaml
# argocd-rbac/argocd-rbac-cm.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: argocd-rbac-cm
  namespace: argocd
data:
  policy.csv: |
    # 管理员角色
    g, admin-team, role:admin
    
    # 开发者角色 - 只能访问特定项目
    g, devs-team, role:developer
    
    # 只读角色
    g, auditors, role:readonly
  
  policy.default: role:readonly

---
# argocd-projects/production-project.yaml
apiVersion: argoproj.io/v1alpha1
kind: AppProject
metadata:
  name: production
  namespace: argocd
spec:
  description: Production applications
  sourceRepos:
    - https://github.com/your-org/production-apps.git
    - https://github.com/your-org/production-config.git
  destinations:
    - namespace: production
      server: https://kubernetes.default.svc
    - namespace: staging
      server: https://kubernetes.default.svc
  clusterResourceWhitelist:
    - group: ''
      kind: Namespace
  namespaceResourceBlacklist:
    - group: ''
      kind: ResourceQuota
    - group: ''
      kind: LimitRange
  roles:
    - name: developer
      description: Developer access to production project
      policies:
        - p, proj:production:developer, applications, get, your-org/production-apps/*, allow
        - p, proj:production:developer, applications, sync, your-org/production-apps/*, allow
        - p, proj:production:developer, applications, *, your-org/production-apps/*, deny
      groups:
        - devs-team
```

## 常见坑与排查

### 坑 1: Kyverno 策略未生效

**现象**：策略已应用，但违规 Pod 仍能创建。

**排查步骤：**

```bash
# 1. 检查策略状态
kubectl get clusterpolicy disallow-privileged-containers -o yaml | grep -A5 status

# 2. 查看 Kyverno 日志
kubectl logs -n kyverno -l app.kubernetes.io/name=kyverno --tail=100

# 3. 验证 webhook 配置
kubectl get validatingwebhookconfiguration kyverno-resource-validating-webhook-cfg -o yaml

# 4. 检查命名空间排除
kubectl get namespace kube-system -o yaml | grep -i kyverno
```

**常见原因：**
- `validationFailureAction` 设置为 `Audit` 而非 `Enforce`
- Webhook 被其他 admission controller 覆盖
- 命名空间在排除列表中（如 `kube-system`）
- Kyverno Pod 未就绪

**解决方案：**
```yaml
spec:
  validationFailureAction: Enforce  # 确保是 Enforce
  background: true                   # 启用背景扫描
```

### 坑 2: 镜像验证导致部署失败

**现象**：ArgoCD sync 失败，报错 "image verification failed"。

**排查步骤：**

```bash
# 1. 手动验证镜像签名
cosign verify ghcr.io/your-org/app:v1.0.0 \
  --certificate-identity-regexp=.* \
  --certificate-oidc-issuer=https://token.actions.githubusercontent.com

# 2. 检查公钥是否匹配
cosign public-key --key k8s://kyverno/cosign-public-key

# 3. 查看 ArgoCD Image Updater 日志
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-image-updater --tail=50
```

**常见原因：**
- 公钥不匹配（使用了不同的密钥对）
- 镜像标签被覆盖但未重新签名
- OIDC issuer 配置错误
- 证书过期

**解决方案：**
- 确保 CI/CD 流水线每次构建都签名
- 使用 immutable 标签策略（如 Git SHA）
- 定期轮换密钥并更新策略

### 坑 3: SealedSecret 无法解密

**现象**：SealedSecret 提交后，对应的 Secret 未创建。

**排查步骤：**

```bash
# 1. 检查 SealedSecret 状态
kubectl get sealedsecret db-credentials -o yaml

# 2. 查看 Controller 日志
kubectl logs -n sealed-secrets -l name=sealed-secrets-controller --tail=100

# 3. 验证密钥是否存在
kubectl get secret -n sealed-secrets -l sealedsecrets.bitnami.com/sealed-secrets-key
```

**常见原因：**
- SealedSecret 使用了错误的集群密钥加密
- 命名空间不匹配
- Controller RBAC 权限不足

**解决方案：**
```bash
# 重新使用正确的密钥加密
kubeseal --format yaml --cert ./sealed-secrets.crt < secret.yaml > sealed.yaml

# 确保命名空间匹配
kubectl apply -f sealed.yaml -n production
```

### 坑 4: ArgoCD 应用持续 OutOfSync

**现象**：应用状态持续显示 OutOfSync，无法自动同步。

**排查步骤：**

```bash
# 1. 查看应用详情
argocd app get my-app

# 2. 查看同步历史
argocd app history my-app

# 3. 检查资源差异
argocd app diff my-app

# 4. 查看 ArgoCD 日志
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-application-controller --tail=100
```

**常见原因：**
- 集群资源被手动修改（配置漂移）
- 策略阻止了某些资源创建
- 资源依赖顺序问题

**解决方案：**
```bash
# 强制同步（谨慎使用）
argocd app sync my-app --force

# 或者启用自修复
argocd app set my-app --self-heal true
```

### 坑 5: Git 提交签名验证失败

**现象**：ArgoCD 拒绝未签名的提交。

**排查步骤：**

```bash
# 1. 验证本地提交签名
git log --show-signature -1

# 2. 检查 GPG 密钥
gpg --list-keys

# 3. 查看 ArgoCD webhook 日志
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-repo-server --tail=50
```

**解决方案：**
```bash
# 配置 Git 自动签名
git config --global commit.gpgsign true
git config --global user.signingkey YOUR_KEY_ID

# 或者使用 SSH 签名
git config --global gpg.format ssh
git config --global user.signingkey ~/.ssh/id_ed25519.pub
```

## Checklist

### Git 仓库安全
- [ ] 启用分支保护规则（main 分支禁止 force push）
- [ ] 配置 Required Reviews（至少 1 人审批）
- [ ] 启用 Commit 签名验证（GPG 或 SSH）
- [ ] 配置 CODEOWNERS 文件
- [ ] 启用 Secret Scanning（GitHub Advanced Security）
- [ ] 定期审计依赖漏洞（Dependabot/Renovate）

### ArgoCD 配置
- [ ] 启用 RBAC 最小权限原则
- [ ] 配置 AppProject 隔离不同环境
- [ ] 禁用自动同步到生产环境（需手动审批）
- [ ] 启用 Webhook 认证（GitHub App 或 HMAC）
- [ ] 配置审计日志持久化
- [ ] 定期轮换 ArgoCD admin 密码

### 策略 Enforcement
- [ ] 部署 Kyverno/OPA 策略引擎
- [ ] 禁止 privileged 容器
- [ ] 强制 resource limits
- [ ] 禁止 latest 标签
- [ ] 要求 non-root 用户运行
- [ ] 限制 capabilities（NET_RAW 等）
- [ ] 启用只读根文件系统

### 镜像安全
- [ ] 配置镜像签名（Cosign/Sigstore）
- [ ] 部署镜像验证 admission controller
- [ ] 使用可信 registry 白名单
- [ ] 定期扫描镜像漏洞（Trivy/Grype）
- [ ] 禁止从公共 registry 拉取未验证镜像

### 密钥管理
- [ ] 使用 Sealed Secrets 或 External Secrets
- [ ] 禁止明文 Secret 提交到 Git
- [ ] 集成外部密钥管理（Vault/AWS Secrets Manager）
- [ ] 定期轮换密钥
- [ ] 启用 Secret 访问审计

### 监控与告警
- [ ] 配置策略违规告警
- [ ] 监控 ArgoCD sync 失败
- [ ] 追踪镜像验证失败
- [ ] 审计 Secret 访问
- [ ] 集成 SIEM 系统（可选）

### 应急响应
- [ ] 文档化回滚流程
- [ ] 准备紧急访问凭证（break-glass）
- [ ] 定期演练安全事件响应
- [ ] 维护已知良好配置基线

## 参考资料

1. **ArgoCD 官方文档** - 安全与 RBAC 配置指南  
   https://argo-cd.readthedocs.io/en/stable/operator-manual/security/

2. **Kyverno 官方文档** - 策略编写与最佳实践  
   https://kyverno.io/docs/

3. **Sigstore 项目** - 无密钥签名与验证  
   https://docs.sigstore.dev/

4. **CNCF GitOps 白皮书** - 云原生 GitOps 架构指南  
   https://www.cncf.io/reports/cncf-gitops-white-paper/

5. **NIST SP 800-204B** - 微服务应用安全指南（含 GitOps）  
   https://csrc.nist.gov/publications/detail/sp/800-204b/final

6. **Sealed Secrets GitHub** - Bitnami 开源项目  
   https://github.com/bitnami-labs/sealed-secrets

7. **Open Policy Agent** - 通用策略引擎  
   https://www.openpolicyagent.org/docs/latest/

---

*本文档遵循 GitOps 安全最佳实践编写，示例代码可在 `demos/gitops-security` 目录找到完整可运行项目。*
