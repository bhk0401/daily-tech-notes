# Container Image Signing & Supplychain Security：Sigstore/Cosign 生产级实践

## 背景与目标

在云原生和 DevOps 流水线中，容器镜像已成为软件交付的标准载体。然而，2020 年的 SolarWinds 供应链攻击事件揭示了一个严峻现实：攻击者可以篡改构建流水线，将恶意代码注入看似可信的镜像中。传统的镜像仓库认证（用户名/密码、机器人令牌）只能控制"谁能推送"，却无法回答"这个镜像是否由可信的构建系统生成"以及"镜像在推送后是否被篡改"这两个关键问题。

**容器镜像签名**正是为了解决这一信任缺口而生。通过对镜像进行密码学签名，我们可以在部署前验证镜像的完整性和来源真实性，确保生产环境只运行经过授权的代码。

本文的目标是：

1. 深入理解 Sigstore 项目的核心架构与设计理念
2. 掌握 Cosign 工具的镜像签名与验证流程
3. 实现基于密钥对和密钥less（OIDC）两种签名模式
4. 在 Kubernetes 环境中集成签名验证（Sigstore Policy Controller）
5. 构建端到端的供应链安全 CI/CD 流水线

**为什么选择 Sigstore？**

Sigstore 是由 Linux 基金会托管的开源项目，得到了 Google、Red Hat、VMware 等主流厂商的支持。其核心优势在于：

- **免费透明的签名基础设施**：Rekor（透明度日志）和 Fulcio（证书颁发机构）公共实例免费使用
- **无需管理 PKI**：传统 PKI 体系复杂昂贵，Sigstore 提供开箱即用的证书颁发和验证服务
- **密钥less 签名**：支持基于 OIDC 的短期证书签名，无需长期存储私钥
- **云原生友好**：与 Kubernetes、Tekton、GitHub Actions 深度集成

通过本文的实践，你将建立起一套可审计、可验证的容器供应链安全体系，为生产环境的镜像部署增加一道关键防线。

## 核心概念

在深入实践之前，我们需要理解 Sigstore 生态系统的核心组件及其协作机制。

### Sigstore 三大支柱

**1. Cosign（签名工具）**

Cosign 是 Sigstore 项目的命令行工具，用于对容器镜像、SBOM（软件物料清单）、以及其他工件进行签名和验证。它支持多种签名模式：

- **密钥对签名**：使用传统的公私钥对（支持 ECDSA、RSA、Ed25519）
- **密钥less 签名**：基于 OIDC 身份（GitHub、Google、Microsoft 等）获取短期证书
- **KMS 集成**：支持 AWS KMS、GCP KMS、Azure Key Vault、HashiCorp Vault

Cosign 签名的关键特性是**无侵入性**——签名作为 OCI 镜像的附件存储，无需修改原始镜像，兼容任何 OCI 兼容的镜像仓库。

**2. Rekor（透明度日志）**

Rekor 是一个透明的、不可篡改的日志服务，用于存储签名事件的元数据。每次签名操作都会在 Rekor 中创建一条记录，包含：

- 签名的哈希值
- 签名者的身份（OIDC subject 或公钥指纹）
- 时间戳
- 签名内容的引用

透明度日志的设计灵感来自 Certificate Transparency（CT），其核心价值在于**可审计性**——任何人都可以查询 Rekor 来验证某个签名是否在特定时间由特定身份生成，且无法事后否认。

**3. Fulcio（证书颁发机构）**

Fulcio 是 Sigstore 的根证书颁发机构（CA），专门用于签发短期代码签名证书。当使用 OIDC 进行密钥less 签名时，Fulcio 会：

1. 验证用户的 OIDC 身份令牌（如 GitHub JWT）
2. 将 OIDC subject（如 `https://github.com/bhk0401`）嵌入证书
3. 签发有效期极短（通常几分钟）的 X.509 证书
4. 将证书提交到 Rekor 日志

这种设计消除了长期私钥管理的安全风险——即使攻击者获取了私钥，其有效期也已过期。

### 签名验证的信任链

理解 Sigstore 的验证信任链至关重要：

```
验证流程：
1. 获取镜像的签名附件（.sig 层）
2. 从签名中提取证书和签名值
3. 验证证书是否由 Fulcio 根 CA 签发（或验证公钥指纹）
4. 查询 Rekor 验证签名事件是否存在于透明度日志
5. 验证 OIDC 身份是否符合预期（如 GitHub repo、workflow 等）
6. 验证镜像摘要是否匹配
```

**关键概念：身份 vs 公钥**

在传统签名中，我们信任的是公钥——"这个公钥对应的私钥持有者签名的镜像可信"。但在 Sigstore 的密钥less 模式中，我们信任的是**身份**——"这个 GitHub Action workflow 签名的镜像可信"。这种基于身份的信任模型更符合现代 CI/CD 的实际场景。

### OCI 镜像签名存储机制

Cosign 使用 OCI 镜像规范的原生功能存储签名：

- 签名作为独立的 OCI 镜像（layer mediaType: `application/vnd.dev.cosign.signature`）
- 通过 tag 关联：`<image>:<digest>.sig` 或使用 OCI Referrers API
- 支持多重签名：同一镜像可被多个身份签名

这种设计确保了签名与镜像的松耦合，便于密钥轮换和多级审批流程。

## 实战/示例

本节将通过完整的实操示例，演示从本地签名到 Kubernetes 集成的全流程。

### 环境准备

```bash
# 安装 Cosign CLI（Linux）
curl -O -L "https://github.com/sigstore/cosign/releases/latest/download/cosign-linux-amd64"
sudo cp cosign-linux-amd64 /usr/local/bin/cosign
chmod +x /usr/local/bin/cosign

# 验证安装
cosign version

# 准备测试镜像（使用 Docker Hub 公共镜像）
export IMAGE_NAME="docker.io/bhk0401/test-app:latest"
docker pull alpine:3.19
docker tag alpine:3.19 $IMAGE_NAME
docker push $IMAGE_NAME
```

### 模式一：密钥对签名（适合自动化流水线）

密钥对签名适合 CI/CD 流水线，私钥可作为 Secret 存储在 CI 系统中。

```bash
# 1. 生成密钥对（首次使用）
cosign generate-key-pair

# 输入密码保护私钥（生产环境建议使用 KMS）
# 生成文件：cosign.key（私钥）, cosign.pub（公钥）

# 2. 对镜像签名
cosign sign --key cosign.key $IMAGE_NAME

# 输入私钥密码后，签名完成

# 3. 验证签名
cosign verify --key cosign.pub $IMAGE_NAME

# 输出示例：
# Verification for index.docker.io/bhk0401/test-app:latest --
# The following checks were performed on each of these signatures:
#   - The cosign claims were validated
#   - Existence of the claims in the transparency log was verified offline
#   - The signatures were verified against the specified public key
```

**密钥管理最佳实践：**

- 不要将私钥提交到 Git 仓库
- 在 GitHub Actions 中使用 Encrypted Secrets 存储
- 考虑使用 KMS（AWS/GCP/Azure）托管私钥，Cosign 直接集成
- 定期轮换密钥（建议每 90 天）

### 模式二：密钥less 签名（适合开发者本地签名）

密钥less 签名利用 OIDC 身份，无需管理长期私钥。

```bash
# 1. 使用 GitHub OIDC 签名（需登录 GitHub CLI）
export COSIGN_EXPERIMENTAL=1
cosign sign $IMAGE_NAME

# 浏览器会打开 GitHub  OAuth 授权页面
# 授权后，Cosign 自动获取 OIDC 令牌并从 Fulcio 获取证书

# 2. 验证签名（基于身份）
cosign verify \
  --certificate-identity-regexp="https://github.com/bhk0401" \
  --certificate-oidc-issuer="https://token.actions.githubusercontent.com" \
  $IMAGE_NAME
```

**GitHub Actions 中的密钥less 签名：**

```yaml
# .github/workflows/sign-image.yml
name: Sign Container Image

on:
  push:
    branches: [main]

permissions:
  id-token: write  # OIDC 令牌权限
  contents: read

jobs:
  sign:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Set up Cosign
        uses: sigstore/cosign-installer@v3

      - name: Build and push image
        run: |
          docker build -t ghcr.io/${{ github.repository }}:${{ github.sha }} .
          docker push ghcr.io/${{ github.repository }}:${{ github.sha }}

      - name: Sign image
        env:
          COSIGN_EXPERIMENTAL: 1
        run: |
          cosign sign ghcr.io/${{ github.repository }}:${{ github.sha }}

      - name: Verify signature
        run: |
          cosign verify \
            --certificate-identity-regexp="https://github.com/${{ github.repository }}" \
            --certificate-oidc-issuer="https://token.actions.githubusercontent.com" \
            ghcr.io/${{ github.repository }}:${{ github.sha }}
```

### 模式三：KMS 托管签名（企业级方案）

使用云厂商 KMS 托管私钥，避免私钥落地。

```bash
# AWS KMS 示例
export COSIGN_AWS_KMS_KEY_ID="arn:aws:kms:us-east-1:123456789012:key/abc-def-ghi"
cosign sign --key awskms://${COSIGN_AWS_KMS_KEY_ID} $IMAGE_NAME

# GCP KMS 示例
export COSIGN_GCP_KMS_KEY_ID="projects/my-project/locations/global/keyRings/my-kr/cryptoKeys/my-key"
cosign sign --key gcpkms://${COSIGN_GCP_KMS_KEY_ID} $IMAGE_NAME
```

### Kubernetes 集成：Sigstore Policy Controller

在生产 Kubernetes 集群中，可以部署 Sigstore Policy Controller 自动验证镜像签名。

```yaml
# sigstore-policy.yaml
apiVersion: policy.sigstore.dev/v1beta1
kind: ClusterImagePolicy
metadata:
  name: require-signed-images
spec:
  images:
  - glob: "**"  # 对所有镜像生效
  authorities:
  - key:
      secretRef:
        name: cosign-public-key
        namespace: sigstore-system
    ctlog:
      url: https://rekor.sigstore.dev
  - keyless:
      url: https://fulcio.sigstore.dev
      identities:
      - issuer: https://token.actions.githubusercontent.com
        subjectRegExp: "https://github.com/my-org/.*"
      ctlog:
        url: https://rekor.sigstore.dev
```

```bash
# 部署 Policy Controller
kubectl apply -f https://github.com/sigstore/policy-controller/releases/latest/download/release.yaml

# 创建公钥 Secret
kubectl create secret generic cosign-public-key \
  --from-file=cosign.pub \
  -n sigstore-system

# 应用策略
kubectl apply -f sigstore-policy.yaml

# 测试：部署未签名镜像会被拒绝
kubectl run test --image=alpine:3.19
# Error: admission webhook "validation.webhook.policy.sigstore.dev" denied the request
```

### Demo 项目：完整的签名验证流水线

在 `demos/image-signing-pipeline/` 目录下，我们提供了一个完整的示例项目：

```
demos/image-signing-pipeline/
├── Dockerfile              # 测试应用 Dockerfile
├── app.py                  # 简单的 Python Flask 应用
├── .github/workflows/
│   ├── build-and-push.yml  # 构建推送 workflow
│   └── sign-verify.yml     # 签名验证 workflow
├── cosign/
│   └── policy.yaml         # Kubernetes 策略配置
└── README.md               # 详细使用说明
```

完整代码可在仓库的 demos 目录查看。

## 常见坑与排查

### 坑 1：签名验证失败 - "signature unknown"

**现象：** `cosign verify` 返回 `Error: signature unknown`

**原因：** 镜像仓库不支持 OCI Referrers API，签名存储位置不兼容。

**排查：**

```bash
# 检查镜像仓库是否支持 Referrers API
cosign verify $IMAGE_NAME 2>&1 | grep -i referrer

# 查看镜像的 tag 列表，确认 .sig tag 是否存在
crane tags $IMAGE_NAME | grep sig
```

**解决：**

- 升级镜像仓库（Harbor 2.5+、Docker Hub、GHCR 均支持）
- 或使用传统 tag 模式：`cosign sign --tlog-upload=false $IMAGE_NAME`

### 坑 2：OIDC 签名超时 - "context deadline exceeded"

**现象：** 密钥less 签名时浏览器 OAuth 流程超时

**原因：** 网络问题或 OIDC 提供商限流

**排查：**

```bash
# 检查 OIDC 令牌获取
curl -H "Authorization: Bearer $(gh auth token)" \
  https://token.actions.githubusercontent.com
```

**解决：**

- 确保系统时间同步（`timedatectl status`）
- 在 CI 环境中确保 `id-token: write` 权限已配置
- 使用 `COSIGN_EXPERIMENTAL=1` 环境变量

### 坑 3：Kubernetes Policy Controller 不生效

**现象：** 未签名镜像仍能部署到集群

**原因：** Policy Controller webhook 未正确配置或策略未匹配

**排查：**

```bash
# 检查 webhook 是否注册
kubectl get validatingwebhookconfiguration

# 检查 Policy Controller 日志
kubectl logs -n sigstore-system -l app=policy-controller

# 验证策略是否应用
kubectl get clusterimagepolicy require-signed-images -o yaml
```

**解决：**

- 确保 `mutatingwebhookconfiguration` 和 `validatingwebhookconfiguration` 都存在
- 检查策略中的 `images.glob` 是否匹配目标镜像
- 确认 namespace 未被排除（`policy.sigstore.dev/exclude: "true"` label）

### 坑 4：Rekor 查询失败 - "transparency log entry not found"

**现象：** 验证时提示透明度日志条目不存在

**原因：** 签名时未上传到 Rekor（`--tlog-upload=false`）或 Rekor 服务不可用

**排查：**

```bash
# 手动查询 Rekor
REKOR_UUID=$(cosign verify $IMAGE_NAME 2>&1 | grep -oP 'UUID: \K[a-f0-9]+')
curl https://rekor.sigstore.dev/api/v1/log/entries/$REKOR_UUID
```

**解决：**

- 确保签名时未禁用 tlog 上传
- 对于离线验证，使用 `--offline` 标志跳过 Rekor 检查
- 企业环境可部署私有 Rekor 实例

### 坑 5：CI/CD 流水线签名失败 - "permission denied"

**现象：** GitHub Actions 中 Cosign 签名失败

**原因：** OIDC 权限未配置或 KMS 权限不足

**排查：**

```yaml
# 检查 workflow 权限
permissions:
  id-token: write  # 必须
  contents: read
```

**解决：**

- 在 workflow 中添加 `id-token: write` 权限
- 对于 KMS 签名，确保 CI 角色有 `kms:Sign` 权限
- 检查 KMS key policy 是否允许 CI 服务账户访问

## Checklist

### 签名策略设计

- [ ] 确定签名模式（密钥对 / 密钥less / KMS）
- [ ] 定义签名身份要求（哪些 CI/CD、哪些开发者可签名）
- [ ] 规划密钥轮换策略（如使用密钥对模式）
- [ ] 确定是否需要多重签名（多角色审批）

### 基础设施准备

- [ ] 镜像仓库支持 OCI Referrers API 或传统 .sig tag
- [ ] Rekor 透明度日志可访问（公共或私有实例）
- [ ] （可选）部署私有 Fulcio CA（企业内网场景）
- [ ] （可选）集成 KMS 服务

### CI/CD 集成

- [ ] 在构建流水线中集成 Cosign 签名步骤
- [ ] 安全存储签名密钥（Secret/KMS）
- [ ] 配置 OIDC 身份信任（GitHub/GitLab 等）
- [ ] 添加签名验证作为部署前置检查

### Kubernetes 部署

- [ ] 部署 Sigstore Policy Controller
- [ ] 配置 ClusterImagePolicy 策略
- [ ] 导入信任的公钥或配置 OIDC 身份白名单
- [ ] 测试策略生效（尝试部署未签名镜像）

### 运维与审计

- [ ] 建立签名事件审计流程（定期查询 Rekor）
- [ ] 监控签名失败告警
- [ ] 文档化密钥轮换流程
- [ ] 定期演练签名验证流程

### 应急方案

- [ ] 准备紧急绕过策略（如 Rekor 服务不可用时）
- [ ] 定义签名密钥泄露的应急响应流程
- [ ] 备份公钥和策略配置

## 参考资料

1. **Sigstore 官方文档** - https://docs.sigstore.dev/ - 完整的 Sigstore 项目文档，包括 Cosign、Rekor、Fulcio 使用指南和 API 参考

2. **Cosign GitHub 仓库** - https://github.com/sigstore/cosign - Cosign 工具源码、安装指南、高级用法示例和 Release 下载

3. **Kubernetes Sigstore Policy Controller** - https://github.com/sigstore/policy-controller - Kubernetes 集成方案，支持自动镜像签名验证的 Admission Controller

4. **Supply-chain Levels for Software Artifacts (SLSA)** - https://slsa.dev/ - Google 发起的供应链安全框架，与 Sigstore 深度集成，定义软件供应链完整性等级

5. **OpenSSF Best Practices** - https://github.com/ossf/wg-best-practices-os-developers - 开源软件基金会的安全最佳实践，包含容器签名和供应链安全指南

6. **NIST Secure Software Development Framework** - https://csrc.nist.gov/projects/ssdf - 美国国家标准与技术研究院的安全软件开发框架，提供供应链安全的政策指导

---

**延伸阅读：**

- 《Secure Supply Chain with Sigstore》- Sigstore 团队官方白皮书
- 《Kubernetes Security Best Practices》- CNCF 官方安全指南
- 《Container Image Signing and Verification》- Red Hat 技术博客系列
