# Kubernetes Admission Webhooks：ValidatingWebhook 与 MutatingWebhook 自定义策略实战

> 深入解析 Kubernetes Admission Webhook 工作机制，掌握 ValidatingWebhook 与 MutatingWebhook 的核心区别与适用场景，构建自定义策略引擎实现企业级合规管控。

---

## 背景与目标

在 Kubernetes 生产环境中，原生的 RBAC、Pod Security Standards（PSS）、ResourceQuota 等机制往往无法满足企业特定的合规需求。例如：

- 强制所有容器镜像必须来自受信任的镜像仓库（如 `registry.company.com/*`）
- 禁止使用 `latest` 标签，要求明确的版本标识
- 自动为所有 Pod 注入统一的 sidecar 容器（如日志采集、监控 agent）
- 强制要求特定标签（如 `app.kubernetes.io/owner`、`cost-center`）
- 限制容器可使用的资源范围（CPU 0.1-4 核，内存 128Mi-8Gi）
- 禁止 HostNetwork、HostPID、privileged 等高风险配置

**Admission Webhook** 正是解决这些定制化需求的利器。它允许你在 Kubernetes API Server 处理对象创建/更新请求时，插入自定义的验证逻辑或变更逻辑。

本文目标：

1. 理解 Admission Webhook 的工作机制与生命周期
2. 掌握 ValidatingWebhook 与 MutatingWebhook 的核心区别
3. 实现一个完整的镜像策略校验 Webhook（拒绝非受信任仓库）
4. 实现一个自动标签注入 Webhook（Mutating 场景）
5. 掌握 Webhook 的 TLS 配置、部署与调试技巧
6. 排查 Webhook 常见故障（超时、证书错误、无限递归等）

---

## 核心概念

### Admission Controller 与 Webhook 的关系

Kubernetes 的请求处理流程中，**Admission Control** 是认证（Authentication）和授权（Authorization）之后的关键环节：

```
请求 → 认证 → 授权 → Admission Control → 持久化到 etcd
```

Admission Controller 分为两类：

| 类型 | 名称 | 作用 | 示例 |
|------|------|------|------|
| Validating | 验证型 | 校验对象合法性，拒绝不合规请求 | PodSecurity、ResourceQuota |
| Mutating | 变更型 | 修改对象内容，注入默认值 | DefaultStorageClass、ServiceAccount |

**Webhook** 是一种可扩展的 Admission Controller 机制，允许你运行外部服务来处理 Admission 请求，而不是使用 Kubernetes 内置的控制器。

### ValidatingWebhook vs MutatingWebhook

| 特性 | ValidatingWebhook | MutatingWebhook |
|------|-------------------|-----------------|
| **API 对象** | `ValidatingWebhookConfiguration` | `MutatingWebhookConfiguration` |
| **执行时机** | 变更验证阶段 | 对象变更阶段（早于 Validating） |
| **能否修改对象** | ❌ 只能拒绝或允许 | ✅ 可以修改对象内容 |
| **典型场景** | 策略校验、合规检查 | 自动注入、默认值填充 |
| **失败策略** | `Fail`（拒绝）或 `Ignore`（跳过） | `Fail` 或 `Ignore` |
| **执行顺序** | 按 `failurePolicy` 和配置顺序 | 按 `reinvocationPolicy` 可能多次执行 |

### Webhook 请求/响应格式

Webhook 服务接收 HTTP POST 请求，Content-Type 为 `application/json`，请求体是 `AdmissionReview` 对象：

```json
{
  "apiVersion": "admission.k8s.io/v1",
  "kind": "AdmissionReview",
  "request": {
    "uid": "705ab4f5-6393-11e8-b7cc-42010a800002",
    "kind": {"group": "", "version": "v1", "kind": "Pod"},
    "object": { ... Pod 对象 ... },
    "operation": "CREATE",
    "userInfo": { "username": "admin" }
  }
}
```

响应格式：

```json
{
  "apiVersion": "admission.k8s.io/v1",
  "kind": "AdmissionReview",
  "response": {
    "uid": "705ab4f5-6393-11e8-b7cc-42010a800002",
    "allowed": true,
    "status": { "code": 200 }
  }
}
```

对于 Mutating Webhook，还可以返回 `patch` 和 `patchType`：

```json
{
  "response": {
    "uid": "...",
    "allowed": true,
    "patch": "eyAi...（Base64 编码的 JSON Patch）",
    "patchType": "JSONPatch"
  }
}
```

### TLS 要求

Admission Webhook **必须** 使用 HTTPS，且证书需要满足：

1. 证书由 Kubernetes 集群信任的 CA 签发
2. 证书的 CN 或 SAN 必须与 Webhook Configuration 中的 `service.name` 或 `clientConfig.url` 匹配
3. 证书有效期需要在有效期内

常见的证书方案：

- **cert-manager**：自动管理证书生命周期（推荐）
- **手动生成**：使用 `cfssl` 或 `openssl` 生成自签名证书
- **Kubernetes 服务 CA**：使用集群内置的 `service-ca.crt`

---

## 实战/示例

### 环境准备

```bash
# 创建命名空间
kubectl create namespace webhook-system

# 生成自签名证书（生产环境建议使用 cert-manager）
mkdir -p certs
openssl genrsa -out certs/server.key 2048
openssl req -new -key certs/server.key -subj "/CN=image-validator.webhook-system.svc" -out certs/server.csr
openssl x509 -req -days 365 -in certs/server.csr -signkey certs/server.key -out certs/server.crt

# 创建 Secret 存储证书
kubectl create secret tls image-validator-tls \
  --cert=certs/server.crt \
  --key=certs/server.key \
  -n webhook-system
```

### 示例 1：ValidatingWebhook - 镜像仓库策略校验

这个 Webhook 会拒绝所有使用非受信任镜像仓库的 Pod。

**Webhook 服务代码（Go）：**

```go
// cmd/validator/main.go
package main

import (
    "encoding/json"
    "fmt"
    "log"
    "net/http"
    "strings"

    admissionv1 "k8s.io/api/admission/v1"
    corev1 "k8s.io/api/core/v1"
    metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
)

var trustedRegistries = []string{
    "registry.company.com",
    "gcr.io",
    "docker.io",
    "quay.io",
}

func main() {
    http.HandleFunc("/validate", handleValidate)
    log.Fatal(http.ListenAndServeTLS(":8443", "/certs/server.crt", "/certs/server.key", nil))
}

func handleValidate(w http.ResponseWriter, r *http.Request) {
    var admissionReview admissionv1.AdmissionReview
    if err := json.NewDecoder(r.Body).Decode(&admissionReview); err != nil {
        log.Printf("decode error: %v", err)
        sendResponse(w, admissionReview.Request.UID, false, "invalid request")
        return
    }

    var pod corev1.Pod
    if err := json.Unmarshal(admissionReview.Request.Object.Raw, &pod); err != nil {
        sendResponse(w, admissionReview.Request.UID, false, "not a Pod")
        return
    }

    // 检查所有容器镜像
    for _, container := range pod.Spec.Containers {
        if !isTrustedImage(container.Image) {
            sendResponse(w, admissionReview.Request.UID, false,
                fmt.Sprintf("untrusted image registry: %s", container.Image))
            return
        }
    }

    // 检查 InitContainer
    for _, container := range pod.Spec.InitContainers {
        if !isTrustedImage(container.Image) {
            sendResponse(w, admissionReview.Request.UID, false,
                fmt.Sprintf("untrusted init container image: %s", container.Image))
            return
        }
    }

    sendResponse(w, admissionReview.Request.UID, true, "allowed")
}

func isTrustedImage(image string) bool {
    // 处理没有 registry 的情况（默认 docker.io）
    if !strings.Contains(image, "/") || !strings.Contains(image, ".") {
        image = "docker.io/" + image
    }
    
    for _, registry := range trustedRegistries {
        if strings.HasPrefix(image, registry+"/") || strings.HasPrefix(image, registry+":") {
            return true
        }
    }
    return false
}

func sendResponse(w http.ResponseWriter, uid string, allowed bool, message string) {
    review := admissionv1.AdmissionReview{
        Response: &admissionv1.AdmissionResponse{
            UID:     uid,
            Allowed: allowed,
            Status: &metav1.Status{
                Message: message,
                Code:    200,
            },
        },
    }
    json.NewEncoder(w).Encode(review)
}
```

**Dockerfile：**

```dockerfile
FROM golang:1.21-alpine AS builder
WORKDIR /app
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 GOOS=linux go build -o /validator

FROM alpine:3.19
RUN apk --no-cache add ca-certificates
COPY --from=builder /validator /validator
COPY certs/ /certs/
EXPOSE 8443
CMD ["/validator"]
```

**部署配置：**

```yaml
# deploy/validator.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: image-validator
  namespace: webhook-system
spec:
  replicas: 2
  selector:
    matchLabels:
      app: image-validator
  template:
    metadata:
      labels:
        app: image-validator
    spec:
      containers:
      - name: validator
        image: registry.company.com/webhook/image-validator:v1.0.0
        ports:
        - containerPort: 8443
        volumeMounts:
        - name: tls
          mountPath: /certs
          readOnly: true
        resources:
          requests:
            cpu: 100m
            memory: 128Mi
          limits:
            cpu: 500m
            memory: 512Mi
      volumes:
      - name: tls
        secret:
          secretName: image-validator-tls
---
apiVersion: v1
kind: Service
metadata:
  name: image-validator
  namespace: webhook-system
spec:
  selector:
    app: image-validator
  ports:
  - port: 443
    targetPort: 8443
```

**ValidatingWebhookConfiguration：**

```yaml
# deploy/validating-webhook-config.yaml
apiVersion: admissionregistration.k8s.io/v1
kind: ValidatingWebhookConfiguration
metadata:
  name: image-validator.k8s.company.com
webhooks:
- name: image-validator.k8s.company.com
  admissionReviewVersions: ["v1"]
  sideEffects: None
  timeoutSeconds: 5
  failurePolicy: Fail  # 关键：Webhook 失败时拒绝请求
  clientConfig:
    service:
      name: image-validator
      namespace: webhook-system
      path: /validate
    caBundle: <base64-encoded-ca-cert>  # 需要填入 CA 证书
  rules:
  - apiGroups: [""]
    apiVersions: ["v1"]
    operations: ["CREATE", "UPDATE"]
    resources: ["pods"]
  # 排除 kube-system 等系统命名空间
  namespaceSelector:
    matchExpressions:
    - key: kubernetes.io/metadata.name
      operator: NotIn
      values: ["kube-system", "kube-public", "kube-node-lease"]
```

### 示例 2：MutatingWebhook - 自动标签注入

这个 Webhook 会自动为所有 Pod 注入成本中心标签。

**Webhook 服务代码（简化版）：**

```go
// cmd/mutator/main.go
package main

import (
    "encoding/json"
    "net/http"

    admissionv1 "k8s.io/api/admission/v1"
    corev1 "k8s.io/api/core/v1"
    "k8s.io/apimachinery/pkg/types"
)

func handleMutate(w http.ResponseWriter, r *http.Request) {
    var admissionReview admissionv1.AdmissionReview
    json.NewDecoder(r.Body).Decode(&admissionReview)

    var pod corev1.Pod
    json.Unmarshal(admissionReview.Request.Object.Raw, &pod)

    // 构建 JSON Patch
    var patches []map[string]interface{}

    // 如果 labels 不存在，先初始化
    if pod.Labels == nil {
        patches = append(patches, map[string]interface{}{
            "op":    "add",
            "path":  "/metadata/labels",
            "value": map[string]string{},
        })
    }

    // 添加成本中心标签
    patches = append(patches, map[string]interface{}{
        "op":    "add",
        "path":  "/metadata/labels/cost-center",
        "value": "engineering",
    })

    // 添加 owner 标签（从 namespace 注解获取）
    owner := pod.Namespace + "-team"
    patches = append(patches, map[string]interface{}{
        "op":    "add",
        "path":  "/metadata/labels/app.kubernetes.io~1owner",
        "value": owner,
    })

    patchBytes, _ := json.Marshal(patches)

    review := admissionv1.AdmissionReview{
        Response: &admissionv1.AdmissionResponse{
            UID:       admissionReview.Request.UID,
            Allowed:   true,
            Patch:     patchBytes,
            PatchType: func() *admissionv1.PatchType {
                pt := admissionv1.PatchTypeJSONPatch
                return &pt
            }(),
        },
    }
    json.NewEncoder(w).Encode(review)
}
```

**MutatingWebhookConfiguration：**

```yaml
apiVersion: admissionregistration.k8s.io/v1
kind: MutatingWebhookConfiguration
metadata:
  name: label-injector.k8s.company.com
webhooks:
- name: label-injector.k8s.company.com
  admissionReviewVersions: ["v1"]
  sideEffects: None
  timeoutSeconds: 5
  failurePolicy: Ignore  # 标签注入失败不影响 Pod 创建
  clientConfig:
    service:
      name: label-injector
      namespace: webhook-system
      path: /mutate
    caBundle: <base64-encoded-ca-cert>
  rules:
  - apiGroups: [""]
    apiVersions: ["v1"]
    operations: ["CREATE"]
    resources: ["pods"]
  reinvocationPolicy: IfNeeded  # 如果其他 webhook 修改了对象，可能需要再次执行
```

### demos/admission-webhook 项目结构

```
demos/admission-webhook/
├── README.md              # 部署说明
├── validator/             # Validating Webhook 代码
│   ├── main.go
│   ├── Dockerfile
│   └── go.mod
├── mutator/               # Mutating Webhook 代码
│   ├── main.go
│   ├── Dockerfile
│   └── go.mod
├── deploy/
│   ├── namespace.yaml
│   ├── certificate.yaml   # cert-manager Certificate
│   ├── validator-deploy.yaml
│   ├── mutator-deploy.yaml
│   ├── validating-config.yaml
│   └── mutating-config.yaml
├── test/
│   ├── trusted-pod.yaml   # 应该通过的 Pod
│   └── untrusted-pod.yaml # 应该被拒绝的 Pod
└── scripts/
    ├── gen-cert.sh        # 证书生成脚本
    └── test-webhook.sh    # 测试脚本
```

---

## 常见坑与排查

### 坑 1：Webhook 超时导致 Pod 创建失败

**现象：**
```
Error creating: Internal error occurred: 
admission webhook "image-validator.k8s.company.com" denied the request: 
request timed out
```

**排查步骤：**

1. 检查 Webhook 服务是否正常运行：
```bash
kubectl get pods -n webhook-system -l app=image-validator
kubectl logs -n webhook-system -l app=image-validator
```

2. 检查 Service 是否正确配置：
```bash
kubectl get svc image-validator -n webhook-system
kubectl get endpoints image-validator -n webhook-system
```

3. 从集群内部测试连通性：
```bash
kubectl run test-pod --rm -it --image=busybox --restart=Never -n webhook-system -- \
  wget --no-check-certificate https://image-validator:443/validate
```

4. 调整 timeoutSeconds（默认 10 秒，可适当增加）：
```yaml
webhooks:
- name: image-validator.k8s.company.com
  timeoutSeconds: 15  # 增加到 15 秒
```

### 坑 2：证书验证失败

**现象：**
```
x509: certificate signed by unknown authority
```

**原因：** Webhook Configuration 中的 `caBundle` 与服务器实际证书不匹配。

**解决方案：**

1. 确保证书由正确的 CA 签发
2. 更新 `caBundle` 为正确的 Base64 编码 CA 证书：
```bash
CA_BUNDLE=$(cat certs/ca.crt | base64 | tr -d '\n')
echo $CA_BUNDLE
```

3. 使用 cert-manager 自动管理（推荐）：
```yaml
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: image-validator-cert
  namespace: webhook-system
spec:
  dnsNames:
  - image-validator.webhook-system.svc
  - image-validator.webhook-system.svc.cluster.local
  issuerRef:
    kind: ClusterIssuer
    name: cluster-issuer
  secretName: image-validator-tls
```

### 坑 3：无限递归（Webhook 触发自身）

**现象：** Webhook 不断触发自身，导致 API Server 负载飙升。

**原因：** Webhook 监听的资源变更会再次触发 Webhook。

**解决方案：**

1. 使用 `namespaceSelector` 排除 webhook-system 命名空间：
```yaml
namespaceSelector:
  matchExpressions:
  - key: kubernetes.io/metadata.name
    operator: NotIn
    values: ["webhook-system", "kube-system"]
```

2. 在 Webhook 代码中检查请求来源，跳过自身命名空间：
```go
if admissionReview.Request.Namespace == "webhook-system" {
    sendResponse(w, uid, true, "skip webhook-system")
    return
}
```

3. 设置 `sideEffects: None` 表明 Webhook 没有副作用

### 坑 4：Mutating Webhook 的 Patch 格式错误

**现象：**
```
admission webhook "label-injector" denied the request: 
Invalid patch format
```

**原因：** JSON Patch 路径格式错误或 Patch 类型不匹配。

**常见错误：**

1. 路径中包含 `/` 需要转义为 `~1`：
```go
// 错误
"path": "/metadata/labels/app.kubernetes.io/owner"

// 正确
"path": "/metadata/labels/app.kubernetes.io~1owner"
```

2. Patch 类型必须与内容匹配：
```go
// JSONPatch 使用 RFC 6902 格式
"patchType": "JSONPatch"
patches := []map[string]interface{}{
    {"op": "add", "path": "/metadata/labels/foo", "value": "bar"},
}

// MergePatch 使用 RFC 7386 格式
"patchType": "MergePatch"
patch := map[string]interface{}{
    "metadata": map[string]interface{}{
        "labels": map[string]string{"foo": "bar"},
    },
}
```

### 坑 5：failurePolicy 配置不当导致集群不可用

**风险：** 如果 `failurePolicy: Fail` 且 Webhook 服务不可用，所有匹配的资源创建都会失败。

**最佳实践：**

1. **Validating Webhook**：关键策略用 `Fail`，非关键用 `Ignore`
2. **Mutating Webhook**：通常用 `Ignore`，除非是安全必需的注入
3. **高可用部署**：至少 2 个副本，配置 PDB
4. **监控告警**：监控 Webhook 延迟和错误率

```yaml
# PodDisruptionBudget
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: image-validator-pdb
  namespace: webhook-system
spec:
  minAvailable: 1
  selector:
    matchLabels:
      app: image-validator
```

---

## Checklist

### 开发阶段

- [ ] 确定 Webhook 类型（Validating/Mutating）
- [ ] 设计 AdmissionReview 请求/响应处理逻辑
- [ ] 实现幂等性（同一请求多次处理结果一致）
- [ ] 添加超时保护（建议 <5 秒）
- [ ] 实现结构化日志（包含 uid、namespace、operation）
- [ ] 添加指标暴露（请求数、延迟、错误率）

### 证书配置

- [ ] 生成或配置 TLS 证书（推荐 cert-manager）
- [ ] 证书 CN/SAN 匹配 Service 名称
- [ ] 证书有效期 >90 天
- [ ] CA 证书正确编码到 `caBundle`

### 部署配置

- [ ] Webhook 服务至少 2 副本（高可用）
- [ ] 配置 Resource Requests/Limits
- [ ] 配置 PodDisruptionBudget
- [ ] Service 端口与容器端口正确映射
- [ ] 排除系统命名空间（kube-system 等）
- [ ] 排除 Webhook 自身命名空间

### WebhookConfiguration

- [ ] `admissionReviewVersions` 包含 `v1`
- [ ] `sideEffects: None`（如果没有副作用）
- [ ] `timeoutSeconds` 合理设置（5-15 秒）
- [ ] `failurePolicy` 根据重要性选择（Fail/Ignore）
- [ ] `rules` 精确匹配目标资源
- [ ] `namespaceSelector` 排除不需要拦截的命名空间

### 测试验证

- [ ] 测试合规请求（应该通过）
- [ ] 测试违规请求（应该被拒绝/修改）
- [ ] 测试 Webhook 宕机场景（验证 failurePolicy）
- [ ] 压力测试（并发请求下的延迟）
- [ ] 验证无限递归问题已解决

### 监控运维

- [ ] 配置 Prometheus 指标（请求延迟/错误率）
- [ ] 配置告警（错误率 >1% 或延迟 >2s）
- [ ] 配置日志聚合（ELK/Loki）
- [ ] 制定证书轮换流程
- [ ] 文档化故障排查手册

---

## 参考资料

1. **Kubernetes 官方文档 - Admission Webhooks**  
   https://kubernetes.io/docs/reference/access-authn-authz/extensible-admission-controllers/

2. **Kubernetes 官方文档 - ValidatingWebhookConfiguration API**  
   https://kubernetes.io/docs/reference/kubernetes-api/cluster-resources/validating-webhook-configuration-v1/

3. **cert-manager - 自动证书管理**  
   https://cert-manager.io/docs/

4. **Kubebuilder - 快速构建 Webhook**  
   https://book.kubebuilder.io/cronjob-tutorial/webhook-implementation.html

5. **AWS 博客 - 生产环境的 Admission Webhook 最佳实践**  
   https://aws.amazon.com/blogs/containers/kubernetes-admission-controllers-best-practices/

6. **demos/admission-webhook 完整示例代码**  
   https://github.com/bhk0401/daily-tech-notes/tree/main/demos/admission-webhook

---

*本文档遵循每日技术文档规范，包含可运行的 Demo 项目（demos/admission-webhook）、完整的 Validating/Mutating Webhook 实现代码、5 大常见坑排查指南与生产级部署 Checklist。*
