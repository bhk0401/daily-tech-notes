# GitOps 实战：用 ArgoCD 实现 Kubernetes 持续部署

## 背景与目标

在现代云原生架构中，持续部署（Continuous Deployment）已经成为标准实践。传统的 CI/CD 流水线通常采用 "push" 模式——CI 服务器构建镜像后，通过 kubectl 或 Helm 直接部署到集群。这种方式存在几个问题：

1. **权限分散**：CI 系统需要持有 K8s 集群的写权限，增加了安全风险
2. **状态漂移**：手动 kubectl apply 会导致集群实际状态与 Git 中声明的状态不一致
3. **可追溯性差**：难以审计谁在什么时候做了什么变更
4. **恢复困难**：没有统一的回滚机制

GitOps 提供了一种更好的范式。它的核心思想是：**将 Git 仓库作为集群的唯一真实来源（Single Source of Truth）**，通过自动化代理持续对比 Git 中的期望状态与集群的实际状态，并自动同步两者。

ArgoCD 是目前最流行的 GitOps 工具之一，它是 CNCF 毕业项目，专为 Kubernetes 设计。本文的目标是：

- 理解 GitOps 的核心概念和工作原理
- 掌握 ArgoCD 的安装与配置方法
- 通过实战案例实现一个完整的 GitOps 部署流程
- 了解常见问题的排查方法和最佳实践

完成本文后，你将能够独立搭建一套生产级别的 GitOps 部署系统，实现应用变更的自动化、可审计、可回滚的持续部署。

## 核心概念

### GitOps 四大原则

Weaveworks 在 2017 年首次提出 GitOps 概念时，定义了四个核心原则：

1. **声明式（Declarative）**：系统的期望状态必须以声明式方式描述，存储在版本控制系统中
2. **版本化（Versioned）**：所有变更都通过 Git 提交记录，具备完整的审计日志
3. **自动推送（Automated Push）**：变更批准后，系统自动将期望状态应用到实际环境
4. **持续收敛（Continuous Reconciliation）**：代理程序持续监控并自动修复状态漂移

### ArgoCD 架构组件

ArgoCD 采用控制器模式运行，主要组件包括：

| 组件 | 职责 |
|------|------|
| **API Server** | 暴露 gRPC/REST API，供 UI、CLI 和 CI 系统调用 |
| **Repository Server** | 维护 Git 仓库的本地缓存，生成 K8s 清单 |
| **Application Controller** | 核心控制器，持续对比期望状态与实际状态 |
| **Redis** | 缓存 Git 仓库数据和集群状态 |

### Application 资源模型

ArgoCD 通过自定义资源 `Application` 来管理部署：

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: my-app
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/org/app-manifests.git
    targetRevision: HEAD
    path: environments/production
  destination:
    server: https://kubernetes.default.svc
    namespace: production
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
```

关键字段说明：
- `source.repoURL`：Git 仓库地址
- `source.targetRevision`：跟踪的分支或 Tag
- `source.path`：清单文件在仓库中的路径
- `destination.namespace`：部署目标命名空间
- `syncPolicy.automated`：启用自动同步

### 同步策略详解

| 策略 | 说明 |
|------|------|
| **Manual** | 需要手动点击 Sync 按钮确认部署 |
| **Automated** | Git 变更后自动同步到集群 |
| **Prune** | 自动删除 Git 中不存在但集群中存在的资源 |
| **Self-Heal** | 检测到状态漂移时自动修复 |

生产环境建议：开发环境使用 Automated + Self-Heal，生产环境使用 Manual + Prune，确保变更经过人工审核。

## 实战/示例

### 环境准备

假设你已有一个可用的 Kubernetes 集群（v1.25+），并且有 cluster-admin 权限。

```bash
# 1. 创建 ArgoCD 命名空间
kubectl create namespace argocd

# 2. 安装 ArgoCD（使用官方 Manifest）
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# 3. 等待所有组件就绪
kubectl wait --for=condition=available deployment --all -n argocd --timeout=300s
```

### 配置初始访问

```bash
# 获取初始 admin 密码
ARGOCD_INITIAL_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)
echo "初始密码：$ARGOCD_INITIAL_PASSWORD"

# 端口转发访问 UI
kubectl port-forward svc/argocd-server -n argocd 8080:443
# 访问 https://localhost:8080，用户名：admin
```

### 创建示例应用仓库

首先创建一个 Git 仓库存放 K8s 清单：

```bash
# 创建仓库目录结构
mkdir -p gitops-demo/{base,environments/{dev,prod}}

# 基础 Deployment
cat > gitops-demo/base/deployment.yaml << 'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: demo-app
spec:
  replicas: 2
  selector:
    matchLabels:
      app: demo
  template:
    metadata:
      labels:
        app: demo
    spec:
      containers:
      - name: app
        image: nginx:1.25-alpine
        ports:
        - containerPort: 80
        resources:
          requests:
            cpu: 100m
            memory: 128Mi
          limits:
            cpu: 500m
            memory: 512Mi
EOF

# 基础 Service
cat > gitops-demo/base/service.yaml << 'EOF'
apiVersion: v1
kind: Service
metadata:
  name: demo-app
spec:
  selector:
    app: demo
  ports:
  - port: 80
    targetPort: 80
  type: ClusterIP
EOF

# 开发环境 Kustomize 配置
cat > gitops-demo/environments/dev/kustomization.yaml << 'EOF'
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - ../../base
namespace: dev
namePrefix: dev-
patches:
  - patch: |-
      - op: replace
        path: /spec/replicas
        value: 1
    target:
      kind: Deployment
EOF

# 生产环境 Kustomize 配置
cat > gitops-demo/environments/prod/kustomization.yaml << 'EOF'
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - ../../base
namespace: prod
namePrefix: prod-
patches:
  - patch: |-
      - op: replace
        path: /spec/replicas
        value: 3
    target:
      kind: Deployment
EOF

# 初始化 Git 仓库
cd gitops-demo
git init
git add .
git commit -m "Initial commit: base manifests + env overlays"
# 推送到远程仓库（GitHub/GitLab 等）
```

### 在 ArgoCD 中注册应用

```bash
# 登录 ArgoCD CLI
argocd login localhost:8080 --username admin --password $ARGOCD_INITIAL_PASSWORD --insecure

# 注册 Git 仓库
argocd repo add https://github.com/your-org/gitops-demo.git \
  --username your-username \
  --password your-token \
  --name demo-repo

# 创建 Application
argocd app create demo-dev \
  --repo https://github.com/your-org/gitops-demo.git \
  --path environments/dev \
  --dest-server https://kubernetes.default.svc \
  --dest-namespace dev \
  --sync-policy automated \
  --auto-prune \
  --self-heal

# 同步应用
argocd app sync demo-dev

# 查看状态
argocd app get demo-dev
```

### 演示 demos/目录示例

完整的示例代码已整理到 demos 目录：

```
demos/
├── argocd-install/          # ArgoCD 安装脚本
├── sample-app/              # 示例应用清单
│   ├── base/
│   └── overlays/
│       ├── dev/
│       └── prod/
├── app-of-apps/             # App of Apps 模式示例
└── helm-chart/              # Helm Chart 部署示例
```

运行 demos 中的脚本可快速搭建完整环境：

```bash
cd demos/argocd-install
./setup.sh  # 一键安装和配置
```

## 常见坑与排查

### 问题 1：应用状态显示 OutOfSync

**现象**：ArgoCD UI 显示应用为 OutOfSync 状态，但实际已手动同步。

**原因**：
- 集群中有手动变更（kubectl edit/apply）
- Git 中的清单与实际部署不一致
- 某些资源有自动生成字段（如 Service 的 clusterIP）

**排查步骤**：
```bash
# 查看差异详情
argocd app diff demo-dev

# 查看应用事件
argocd app get demo-dev --show-events

# 强制同步（忽略差异）
argocd app sync demo-dev --force
```

**解决方案**：
- 启用 `selfHeal` 自动修复漂移
- 使用 `ignoreDifferences` 忽略特定字段：
```yaml
spec:
  ignoreDifferences:
  - group: ""
    kind: Service
    jsonPointers:
    - /spec/clusterIP
```

### 问题 2：镜像更新不触发同步

**现象**：CI 流水线更新了镜像 Tag，但 ArgoCD 没有自动部署新版本。

**原因**：
- ArgoCD 默认只监控 Git 变更，不监控镜像 Registry
- 镜像 Tag 使用了 `latest` 或可变 Tag

**解决方案**：

方案 A：使用 Image Updater（推荐）
```bash
# 安装 ArgoCD Image Updater
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj-labs/argocd-image-updater/stable/install/kubernetes/install.yaml

# 在 Application 中添加注解
metadata:
  annotations:
    argocd-image-updater.argoproj.io/image-list: nginx=ghcr.io/org/app:latest
    argocd-image-updater.argoproj.io/update-strategy: latest
```

方案 B：CI 流水线更新 Git
```bash
# CI 中更新 Git 清单中的镜像 Tag
sed -i "s|image:.*|image: ghcr.io/org/app:$NEW_TAG|" environments/prod/deployment.yaml
git commit -am "chore: bump image to $NEW_TAG"
git push
```

### 问题 3：私有 Helm Chart 拉取失败

**现象**：部署 Helm Chart 时出现 `unauthorized` 或 `not found` 错误。

**原因**：
- Chart 仓库需要认证
- 凭证未正确配置到 ArgoCD

**解决方案**：
```bash
# 添加 Helm 仓库凭证
argocd repo add https://charts.private.io \
  --type helm \
  --username $HELM_USER \
  --password $HELM_PASS \
  --name private-charts

# 或在 values 中引用 Secret
argocd app create my-app \
  --helm-set image.pullSecrets[0].name=regcred
```

### 问题 4：同步钩子（Sync Hooks）不执行

**现象**：定义的 Job 资源没有在同步前后执行。

**原因**：
- 缺少正确的 Hook 注解
- Hook 资源命名冲突
- Hook 删除策略配置错误

**正确配置示例**：
```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: pre-deploy-migration
  annotations:
    argocd.argoproj.io/hook: PreSync
    argocd.argoproj.io/hook-delete-policy: HookSucceeded
spec:
  template:
    spec:
      containers:
      - name: migrate
        image: my-app:latest
        command: ["./run-migrations.sh"]
      restartPolicy: Never
  backoffLimit: 1
```

可用 Hook 类型：`PreSync`、`PostSync`、`SyncFail`、`Skip`

## Checklist

部署前检查清单：

- [ ] **集群准备**
  - [ ] Kubernetes 版本 ≥ 1.25
  - [ ] 有足够的计算资源（ArgoCD 本身需要 ~2GB 内存）
  - [ ] 网络策略允许 ArgoCD 访问 Git 仓库和 K8s API

- [ ] **Git 仓库配置**
  - [ ] 仓库已初始化并推送基础清单
  - [ ] 分支策略明确（main 对应生产，develop 对应开发）
  - [ ] 配置了 Webhook（可选，用于加速变更检测）

- [ ] **安全配置**
  - [ ] 修改了默认 admin 密码
  - [ ] 配置了 RBAC 权限（最小权限原则）
  - [ ] 启用了 SSO/OIDC 集成（生产环境推荐）
  - [ ] Git 凭证使用 Token 而非密码

- [ ] **应用配置**
  - [ ] Application 的 syncPolicy 符合环境要求
  - [ ] 配置了资源配额和 LimitRange
  - [ ] 定义了健康检查（Health Checks）

- [ ] **监控告警**
  - [ ] 配置了 ArgoCD 自身的监控（Prometheus metrics）
  - [ ] 设置了同步失败的告警通知
  - [ ] 定期备份 etcd 和 Git 仓库

- [ ] **灾备方案**
  - [ ] 有 ArgoCD 自身的恢复流程文档
  - [ ] 关键应用有回滚策略
  - [ ] 定期演练故障恢复

## 参考资料

1. **ArgoCD 官方文档** - 最权威的安装、配置和使用指南
   https://argo-cd.readthedocs.io/

2. **GitOps 官方白皮书** - Weaveworks 提出的 GitOps 原则和最佳实践
   https://www.gitops.tech/

3. **ArgoCD 示例仓库** - 官方维护的多种部署模式示例
   https://github.com/argoproj/argocd-example-apps

4. **CNCF GitOps 工作组** - 社区驱动的 GitOps 标准和工具生态
   https://github.com/cncf/tag-app-delivery/tree/main/gitops-wg

5. **Kustomize 官方文档** - 配合 ArgoCD 使用的声明式配置管理工具
   https://kustomize.io/

6. **ArgoCD Image Updater** - 自动镜像更新组件，解决镜像 Tag 跟踪问题
   https://argocd-image-updater.readthedocs.io/

---

*本文档遵循 GitOps 最佳实践编写，示例代码可在 GitHub 仓库获取。生产环境部署前请务必在测试环境验证。*
