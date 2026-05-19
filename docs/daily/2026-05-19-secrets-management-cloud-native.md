# Secrets Management 云原生实践：从环境变量到 HashiCorp Vault

## 背景与目标

在云原生架构中，应用需要访问各种敏感信息：数据库密码、API 密钥、TLS 证书、OAuth 客户端凭证等。这些敏感数据统称为"Secrets"。传统的 Secrets 管理方式（硬编码在代码中、明文配置文件、环境变量）存在严重安全隐患：

- **代码泄露风险**：Git 仓库泄露导致密钥暴露
- **权限失控**：所有环境共用同一套凭证
- **审计缺失**：无法追踪谁在何时访问了哪些 Secrets
- **轮换困难**：手动更新密钥容易遗漏，导致服务中断

本文目标：建立云原生环境下的 Secrets 管理最佳实践体系，涵盖从基础的环境变量隔离到生产级的 HashiCorp Vault 部署，帮助团队构建安全、可审计、易轮换的密钥管理基础设施。

适用场景：
- Kubernetes 集群应用部署
- 多环境（dev/staging/prod）密钥隔离
- 合规要求（SOC2、ISO27001）的审计追踪
- 动态密钥轮换与自动刷新

## 核心概念

### 1. Secrets 分类与敏感度分级

| 级别 | 类型 | 示例 | 保护要求 |
|------|------|------|----------|
| L1 - 极高 | 根凭证 | AWS Root Key、数据库主密码 | 硬件安全模块 (HSM)、双人审批 |
| L2 - 高 | 服务凭证 | API Key、JWT 签名密钥、TLS 私钥 | 加密存储、访问审计、90 天轮换 |
| L3 - 中 | 配置密钥 | 第三方服务 Token、OAuth Client Secret | 环境变量隔离、最小权限 |
| L4 - 低 | 公开配置 | 功能开关、非敏感端点 URL | 版本控制可接受 |

### 2. Kubernetes Secrets 机制

Kubernetes 原生提供 Secrets 资源对象，但需要注意：

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: app-secrets
type: Opaque
data:
  # 值必须是 base64 编码
  database-password: cGFzc3dvcmQxMjM=
  api-key: YXBpLWtleS14eXoxMjM=
```

**关键限制**：
- etcd 中默认明文存储（需启用加密）
- 任何能访问 Pod 的人都能通过环境变量读取
- 缺乏细粒度访问控制和审计日志

### 3. 外部 Secrets 管理方案

| 方案 | 适用场景 | 优势 | 复杂度 |
|------|----------|------|--------|
| 环境变量 + .env 文件 | 本地开发、小型项目 | 简单、零依赖 | 低 |
| Kubernetes Secrets + Sealed Secrets | 中小规模 K8s 集群 | GitOps 友好、加密存储 | 中 |
| AWS Secrets Manager / GCP Secret Manager | 公有云原生应用 | 托管服务、自动轮换 | 中 |
| HashiCorp Vault | 生产级、多集群、合规要求 | 动态密钥、细粒度 ACL、完整审计 | 高 |

### 4. 动态密钥 (Dynamic Secrets)

Vault 的核心优势：按需生成短期凭证，用后即焚。

- **数据库凭证**：应用请求时临时创建 DB 用户，TTL=1 小时
- **云厂商凭证**：生成临时 STS Token，TTL=15 分钟
- **TLS 证书**：自动签发短期证书，自动续期

这大幅降低了凭证泄露的影响范围。

## 实战/示例

### 示例 1：Kubernetes + External Secrets Operator 集成 AWS Secrets Manager

这是一个生产级方案：Secrets 存储在 AWS，K8s 通过 Operator 自动同步。

**Step 1：部署 External Secrets Operator**

```bash
helm repo add external-secrets https://charts.external-secrets.io
helm install external-secrets external-secrets/external-secrets \
  -n external-secrets --create-namespace
```

**Step 2：创建 SecretStore（集群级）**

```yaml
# secretstore.yaml
apiVersion: external-secrets.io/v1beta1
kind: ClusterSecretStore
metadata:
  name: aws-secret-store
spec:
  provider:
    aws:
      service: SecretsManager
      region: us-east-1
      auth:
        jwt:
          serviceAccountRef:
            name: external-secrets-sa
            namespace: external-secrets
```

**Step 3：创建 ExternalSecret（自动同步）**

```yaml
# externalsecret.yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: app-db-credentials
  namespace: production
spec:
  refreshInterval: 1h
  secretStoreRef:
    kind: ClusterSecretStore
    name: aws-secret-store
  target:
    name: app-db-credentials
    creationPolicy: Owner
  data:
    - secretKey: username
      remoteRef:
        key: prod/app/database
        property: username
    - secretKey: password
      remoteRef:
        key: prod/app/database
        property: password
```

**Step 4：Pod 中引用**

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: my-app
spec:
  containers:
    - name: app
      image: my-app:latest
      env:
        - name: DB_USERNAME
          valueFrom:
            secretKeyRef:
              name: app-db-credentials
              key: username
        - name: DB_PASSWORD
          valueFrom:
            secretKeyRef:
              name: app-db-credentials
              key: password
```

### 示例 2：HashiCorp Vault 动态数据库凭证

**Vault 策略配置（HCL）**

```hcl
# app-policy.hcl
path "database/creds/app-role" {
  capabilities = ["read"]
}

path "secret/data/prod/app" {
  capabilities = ["read"]
}
```

**应用侧代码（Node.js + vault-client）**

```javascript
// app.js - 动态获取数据库凭证
const { VaultClient } = require('node-vault-client');

class DatabaseService {
  constructor() {
    this.vault = new VaultClient({
      endpoint: process.env.VAULT_ADDR,
      token: process.env.VAULT_TOKEN,
    });
    this.dbPool = null;
  }

  async initialize() {
    // 获取动态数据库凭证（TTL=1 小时）
    const creds = await this.vault.read('database/creds/app-role');
    
    this.dbPool = await createPool({
      host: process.env.DB_HOST,
      user: creds.data.username,
      password: creds.data.password,
      database: 'app_db',
      // 凭证过期前 5 分钟主动刷新
      expirationCheckInterval: 55 * 60 * 1000,
      onCredentialRefresh: async () => {
        const newCreds = await this.vault.read('database/creds/app-role');
        await this.dbPool.updateCredentials(newCreds);
        console.log('Database credentials rotated');
      }
    });
  }

  async query(sql, params) {
    return this.dbPool.execute(sql, params);
  }
}

// 使用示例
const db = new DatabaseService();
await db.initialize();
const users = await db.query('SELECT * FROM users WHERE id = $1', [123]);
```

### 示例 3：本地开发环境 .env 加密方案

使用 `git-crypt` 或 `sops` 加密敏感配置文件：

```bash
# 安装 sops
brew install sops

# 初始化 GPG 密钥（或使用 AWS KMS）
gpg --full-generate-key

# 创建 .sops.yaml 配置
cat > .sops.yaml <<EOF
creation_rules:
  - path_regex: .*\.env\.prod$
    kms: "arn:aws:kms:us-east-1:123456789012:key/abc123"
  - path_regex: .*\.env$
    pgp: "YOUR_GPG_FINGERPRINT"
EOF

# 加密文件
sops -e .env.prod > .env.prod.enc

# 解密文件（CI/CD 中自动执行）
sops -d .env.prod.enc > .env.prod
```

## 常见坑与排查

### 坑 1：Kubernetes Secrets 在 etcd 中明文存储

**问题**：默认配置下，任何能访问 etcd 的人都能读取所有 Secrets。

**排查**：
```bash
# 检查 etcd 加密配置
kubectl get apiserver.config -o yaml | grep -A 10 encryptionConfiguration
```

**解决**：启用 etcd 静态加密（EncryptionConfiguration）

```yaml
# /etc/kubernetes/pki/encryption-config.yaml
apiVersion: apiserver.config.k8s.io/v1
kind: EncryptionConfiguration
resources:
  - resources:
      - secrets
    providers:
      - aescbc:
          keys:
            - name: key1
              secret: <base64-encoded-32-byte-key>
      - identity: {}
```

### 坑 2：环境变量在日志中泄露

**问题**：应用崩溃时打印的环境变量包含敏感信息。

**排查**：检查日志中是否出现 `DB_PASSWORD=xxx` 格式内容。

**解决**：
```javascript
// 过滤敏感环境变量后再打印
const sensitiveKeys = ['PASSWORD', 'SECRET', 'KEY', 'TOKEN'];
const safeEnv = Object.entries(process.env)
  .filter(([key]) => !sensitiveKeys.some(s => key.includes(s)))
  .reduce((acc, [k, v]) => ({ ...acc, [k]: v }), {});

console.log('Environment:', safeEnv);
```

### 坑 3：Vault 令牌泄露与续期失败

**问题**：应用使用长期令牌，泄露后影响范围大；或令牌过期未续期导致服务中断。

**解决**：
1. 使用 Kubernetes Auth Method，Pod 自动获取短期令牌
2. 实现令牌自动续期逻辑（TTL 过半时续期）
3. 设置告警监控令牌过期时间

```javascript
// 令牌续期监控
async function monitorTokenRenewal(vaultClient) {
  const TTL_RENEW_THRESHOLD = 0.5; // 50% TTL 时续期
  
  setInterval(async () => {
    const info = await vaultClient.tokenLookupSelf();
    const ttlRemaining = info.data.ttl;
    const ttlMax = info.data.ttl_max;
    
    if (ttlRemaining < ttlMax * TTL_RENEW_THRESHOLD) {
      await vaultClient.tokenRenewSelf();
      console.log('Vault token renewed');
    }
  }, 5 * 60 * 1000); // 每 5 分钟检查
}
```

### 坑 4：多环境密钥混淆

**问题**：开发环境误用生产密钥，或反之。

**解决**：
1. 严格的环境隔离（不同 AWS Account / GCP Project）
2. 密钥命名包含环境前缀：`prod/db/password` vs `dev/db/password`
3. CI/CD 中强制校验环境标签

## Checklist

### 基础安全
- [ ] 所有 Secrets 不在代码仓库中明文存储
- [ ] 生产环境与开发环境密钥完全隔离
- [ ] 敏感环境变量不在日志中打印
- [ ] 使用最小权限原则分配密钥访问权限

### Kubernetes 环境
- [ ] 启用 etcd 静态加密（EncryptionConfiguration）
- [ ] 使用 External Secrets Operator 或 Vault Agent 注入
- [ ] Pod 级别限制 Secrets 访问（RBAC）
- [ ] 定期轮换 ServiceAccount Token

### Vault 生产部署
- [ ] 启用 Auto Unseal（云厂商 KMS 集成）
- [ ] 配置审计日志导出到 SIEM 系统
- [ ] 实现动态密钥（数据库/云凭证）
- [ ] 设置告警：异常访问模式、令牌即将过期
- [ ] 定期备份 Vault 数据（Raft 快照）

### 运维与合规
- [ ] 建立密钥轮换流程（至少 90 天）
- [ ] 所有 Secret 访问有审计日志
- [ ] 离职人员密钥访问权限及时回收
- [ ] 应急预案：密钥泄露后的快速轮换流程

## 参考资料

1. **HashiCorp Vault 官方文档** - 动态密钥、Auth Method、策略配置完整指南
   https://developer.hashicorp.com/vault/docs

2. **Kubernetes External Secrets Operator** - 与 AWS/GCP/Azure Secrets Manager 集成方案
   https://external-secrets.io/latest/

3. **Google Cloud Secret Manager 最佳实践** - 云原生密钥管理参考架构
   https://cloud.google.com/secret-manager/docs/best-practices

4. **NIST SP 800-57 密钥管理指南** - 密钥生命周期管理国家标准
   https://csrc.nist.gov/publications/detail/sp/800-57/part-1/rev-5/final

5. **OWASP Secrets Management Cheat Sheet** - Web 应用密钥安全清单
   https://cheatsheetseries.owasp.org/cheatsheets/Secrets_Management_Cheat_Sheet.html
