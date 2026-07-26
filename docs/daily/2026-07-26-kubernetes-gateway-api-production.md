# Kubernetes Gateway API：下一代流量管理标准生产实践

> **日期**: 2026-07-26  
> **领域**: 云原生 / Kubernetes / 服务网格  
> **关键词**: Gateway API, HTTPRoute, TLSRoute, GatewayClass, 流量管理

---

## 背景与目标

Kubernetes Ingress API 自 2015 年引入以来，已成为集群外部流量入口的事实标准。然而，随着云原生生态的演进，Ingress 的局限性日益凸显：仅支持 HTTP/HTTPS 协议、配置能力有限、缺乏多租户支持、扩展机制复杂。2020 年，Kubernetes SIG-Network 社区启动了 **Gateway API** 项目，旨在构建一个更强大、更灵活、更具扩展性的下一代流量管理标准。

Gateway API 的核心设计目标包括：

1. **角色分离（Role Separation）**：明确划分基础设施团队（Infra Team）、应用开发团队（App Team）和安全团队（Security Team）的职责边界，避免配置冲突
2. **协议无关（Protocol Agnostic）**：原生支持 HTTP/HTTPS、gRPC、TCP、UDP、TLS 等多种协议，适应现代微服务架构的多样化需求
3. **可扩展性（Extensibility）**：通过自定义策略（Custom Policies）和参数化配置（Parameterized Configuration）机制，支持厂商自定义扩展
4. **多租户支持（Multi-tenancy）**：通过命名空间隔离和路由绑定机制，实现安全的跨命名空间流量管理
5. **状态反馈（Status Feedback）**：丰富的状态字段和条件（Conditions），提供配置生效状态的实时反馈

本文将以生产环境部署为目标，深入解析 Gateway API 的核心资源模型、配置实践、与 Ingress 的对比分析，以及从 Ingress 迁移到 Gateway API 的完整路径。通过本文，你将掌握：

- Gateway API 的四大核心资源（GatewayClass、Gateway、HTTPRoute、ReferenceGrant）
- 高级流量管理功能（加权路由、头部匹配、URL 重写、请求重定向）
- TLS 终止与证书管理策略
- 从传统 Ingress 迁移到 Gateway API 的实操步骤
- 生产环境常见问题的排查方法

---

## 核心概念

Gateway API 采用分层资源模型，通过职责分离实现灵活的流量管理。理解以下核心概念是掌握 Gateway API 的关键：

### 1. GatewayClass（网关类）

GatewayClass 是 Gateway API 的顶层抽象，定义了一组具有相同配置和行为的 Gateway。它由**基础设施团队**管理，通常对应一个具体的控制器实现（如 NGINX Gateway Fabric、Envoy Gateway、GKE Gateway Controller 等）。

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: GatewayClass
metadata:
  name: nginx-gateway
spec:
  controllerName: gateway.nginx.org/gateway-controller
  parametersRef:
    group: gateway.nginx.org
    kind: NginxProxy
    name: nginx-proxy-config
```

GatewayClass 的核心作用：
- **控制器绑定**：通过 `controllerName` 字段关联具体的控制器实现
- **参数化配置**：通过 `parametersRef` 引用控制器特定的配置资源
- **版本管理**：支持多个 GatewayClass 并存，实现平滑升级

### 2. Gateway（网关）

Gateway 是流量入口的具体实例，定义监听器（Listeners）配置。它由**基础设施团队**创建，但可被**应用团队**的路由资源引用。

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: production-gateway
  namespace: gateway-system
spec:
  gatewayClassName: nginx-gateway
  listeners:
  - name: http
    protocol: HTTP
    port: 80
    hostname: "*.example.com"
    allowedRoutes:
      namespaces:
        from: Selector
        selector:
          matchLabels:
            allow-gateway: "true"
  - name: https
    protocol: HTTPS
    port: 443
    hostname: "*.example.com"
    tls:
      mode: Terminate
      certificateRefs:
      - name: example-tls-secret
    allowedRoutes:
      namespaces:
        from: Same
```

Listener 配置要点：
- **协议类型**：支持 HTTP、HTTPS、TCP、UDP、TLS、GRPC、TLS-PASSTHROUGH
- **主机名匹配**：支持精确匹配（`api.example.com`）和通配符（`*.example.com`）
- **路由绑定策略**：通过 `allowedRoutes` 控制哪些命名空间的路由可以绑定到此监听器
- **TLS 配置**：支持 TLS 终止（Terminate）和透传（Passthrough）两种模式

### 3. HTTPRoute（HTTP 路由）

HTTPRoute 是应用团队管理的路由资源，定义请求如何被路由到后端服务。它是 Gateway API 中最常用的路由类型。

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: api-route
  namespace: api-team
spec:
  parentRefs:
  - name: production-gateway
    namespace: gateway-system
    sectionName: https
  hostnames:
  - api.example.com
  rules:
  - name: primary-route
    matches:
    - path:
        type: PathPrefix
        value: /v1
    - headers:
      - name: X-API-Version
        value: v1
    filters:
    - type: RequestHeaderModifier
      requestHeaderModifier:
        add:
        - name: X-Forwarded-Proto
          value: https
    - type: URLRewrite
      urlRewrite:
        path:
          type: ReplacePrefixMatch
          replacePrefixMatch: /api
    backendRefs:
    - name: api-service-v1
      port: 8080
      weight: 90
    - name: api-service-v2
      port: 8080
      weight: 10
```

HTTPRoute 核心能力：
- **匹配规则**：支持路径匹配（Exact/PathPrefix/RegularExpression）、头部匹配、查询参数匹配、HTTP 方法匹配
- **过滤器链**：支持请求头修改、URL 重写、请求重定向、请求镜像、CORS 配置等
- **加权路由**：通过 `weight` 字段实现金丝雀发布和流量分割
- **后端引用**：支持跨命名空间引用服务（需 ReferenceGrant 授权）

### 4. ReferenceGrant（引用授权）

ReferenceGrant 是 Gateway API 的安全机制，用于控制跨命名空间引用的权限。当路由需要引用其他命名空间的 Gateway 或 Service 时，必须在目标命名空间创建 ReferenceGrant。

```yaml
apiVersion: gateway.networking.k8s.io/v1beta1
kind: ReferenceGrant
metadata:
  name: allow-api-route
  namespace: gateway-system
spec:
  from:
  - group: gateway.networking.k8s.io
    kind: HTTPRoute
    namespace: api-team
  to:
  - group: ""
    kind: Service
  - group: gateway.networking.k8s.io
    kind: Gateway
```

ReferenceGrant 的安全模型：
- **显式授权**：默认禁止跨命名空间引用，必须显式授权
- **细粒度控制**：可精确控制哪些命名空间的哪些资源可以引用
- **最小权限原则**：只授予必要的引用权限

### 5. 其他路由类型

除了 HTTPRoute，Gateway API 还支持多种协议的路由类型：

| 路由类型 | API 版本 | 适用场景 |
|---------|---------|---------|
| HTTPRoute | v1 | HTTP/HTTPS 流量（最常用） |
| GRPCRoute | v1 | gRPC 流量（基于 HTTP/2） |
| TLSRoute | v1 | TLS 透传流量 |
| TCPRoute | v1alpha2 | TCP 流量（数据库、消息队列） |
| UDPRoute | v1alpha2 | UDP 流量（DNS、游戏） |

---

## 实战/示例

本节将通过一个完整的电商场景，演示 Gateway API 在生产环境的配置实践。

### 场景描述

假设我们有一个电商平台，包含以下服务：
- **前端服务**（frontend）：React SPA，需要支持 HTTPS 和 HTTP 重定向
- **API 服务**（api）：Node.js 后端，需要金丝雀发布能力
- **支付服务**（payment）：独立部署，需要严格的 TLS 配置
- **管理后台**（admin）：内网访问，需要 IP 白名单

### 完整配置示例

#### Step 1: 安装 Gateway API CRDs 和控制器

```bash
# 安装 Gateway API CRDs
kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.0.0/standard-install.yaml

# 安装 NGINX Gateway Fabric（示例控制器）
helm repo add nginx-gateway https://nginxinc.github.io/nginx-gateway-fabric
helm repo update
helm install nginx-gateway nginx-gateway/nginx-gateway-fabric \
  --namespace gateway-system \
  --create-namespace \
  --set controller.service.type=LoadBalancer
```

#### Step 2: 创建 GatewayClass 和 Gateway

```yaml
# gateway-class.yaml
apiVersion: gateway.networking.k8s.io/v1
kind: GatewayClass
metadata:
  name: nginx-gateway
spec:
  controllerName: gateway.nginx.org/gateway-controller
---
# gateway.yaml
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: ecommerce-gateway
  namespace: gateway-system
spec:
  gatewayClassName: nginx-gateway
  listeners:
  - name: http-redirect
    protocol: HTTP
    port: 80
    hostname: "*.ecommerce.example.com"
    allowedRoutes:
      namespaces:
        from: All
  - name: https
    protocol: HTTPS
    port: 443
    hostname: "*.ecommerce.example.com"
    tls:
      mode: Terminate
      certificateRefs:
      - name: ecommerce-tls
    allowedRoutes:
      namespaces:
        from: Selector
        selector:
          matchLabels:
            environment: production
  - name: admin-https
    protocol: HTTPS
    port: 8443
    hostname: admin.ecommerce.example.com
    tls:
      mode: Terminate
      certificateRefs:
      - name: admin-tls
    allowedRoutes:
      namespaces:
        from: Same
```

#### Step 3: 创建 TLS 证书

```bash
# 使用 cert-manager 自动申请证书（推荐）
kubectl apply -f - <<EOF
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: ecommerce-tls
  namespace: gateway-system
spec:
  secretName: ecommerce-tls
  issuerRef:
    name: letsencrypt-prod
    kind: ClusterIssuer
  dnsNames:
  - "*.ecommerce.example.com"
  - "ecommerce.example.com"
---
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: admin-tls
  namespace: gateway-system
spec:
  secretName: admin-tls
  issuerRef:
    name: letsencrypt-prod
    kind: ClusterIssuer
  dnsNames:
  - "admin.ecommerce.example.com"
EOF
```

#### Step 4: 创建前端路由（HTTP 重定向 + HTTPS）

```yaml
# frontend-route.yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: frontend-route
  namespace: frontend-team
  labels:
    environment: production
spec:
  parentRefs:
  - name: ecommerce-gateway
    namespace: gateway-system
    sectionName: https
  hostnames:
  - www.ecommerce.example.com
  - ecommerce.example.com
  rules:
  - filters:
    - type: RequestRedirect
      requestRedirect:
        scheme: https
        statusCode: 301
---
# HTTPS 路由
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: frontend-https-route
  namespace: frontend-team
  labels:
    environment: production
spec:
  parentRefs:
  - name: ecommerce-gateway
    namespace: gateway-system
    sectionName: https
  hostnames:
  - www.ecommerce.example.com
  - ecommerce.example.com
  rules:
  - backendRefs:
    - name: frontend-service
      port: 80
    filters:
    - type: ResponseHeaderModifier
      responseHeaderModifier:
        add:
        - name: X-Frame-Options
          value: DENY
        - name: X-Content-Type-Options
          value: nosniff
        - name: Content-Security-Policy
          value: "default-src 'self'"
```

#### Step 5: 创建 API 路由（金丝雀发布）

```yaml
# api-route.yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: api-route
  namespace: api-team
  labels:
    environment: production
spec:
  parentRefs:
  - name: ecommerce-gateway
    namespace: gateway-system
    sectionName: https
  hostnames:
  - api.ecommerce.example.com
  rules:
  # v1 API - 稳定版本（90% 流量）
  - name: v1-stable
    matches:
    - path:
        type: PathPrefix
        value: /v1
    backendRefs:
    - name: api-service-v1
      port: 8080
      weight: 90
    - name: api-service-v2
      port: 8080
      weight: 10
    filters:
    - type: RequestHeaderModifier
      requestHeaderModifier:
        add:
        - name: X-API-Version
          value: v1
  # v2 API - 新版本（仅测试用户）
  - name: v2-beta
    matches:
    - path:
        type: PathPrefix
        value: /v2
    - headers:
      - name: X-Beta-User
        value: "true"
    backendRefs:
    - name: api-service-v2
      port: 8080
    filters:
    - type: RequestHeaderModifier
      requestHeaderModifier:
        add:
        - name: X-API-Version
          value: v2
  # 默认路由 - 重定向到 v1
  - name: default
    filters:
    - type: RequestRedirect
      requestRedirect:
        path:
          type: ReplacePrefixMatch
          replacePrefixMatch: /v1
```

#### Step 6: 创建 ReferenceGrant（跨命名空间授权）

```yaml
# reference-grant.yaml
apiVersion: gateway.networking.k8s.io/v1beta1
kind: ReferenceGrant
metadata:
  name: allow-frontend-route
  namespace: gateway-system
spec:
  from:
  - group: gateway.networking.k8s.io
    kind: HTTPRoute
    namespace: frontend-team
  to:
  - group: ""
    kind: Service
---
apiVersion: gateway.networking.k8s.io/v1beta1
kind: ReferenceGrant
metadata:
  name: allow-api-route
  namespace: gateway-system
spec:
  from:
  - group: gateway.networking.k8s.io
    kind: HTTPRoute
    namespace: api-team
  to:
  - group: ""
    kind: Service
```

### demos/gateway-api 项目结构

```
demos/gateway-api/
├── README.md                 # 部署说明
├── crds/
│   └── gateway-api-crds.yaml # Gateway API CRDs
├── gateway/
│   ├── gateway-class.yaml    # GatewayClass 定义
│   ├── gateway.yaml          # Gateway 配置
│   └── tls-cert.yaml         # TLS 证书配置
├── routes/
│   ├── frontend-route.yaml   # 前端路由
│   ├── api-route.yaml        # API 路由（金丝雀）
│   └── admin-route.yaml      # 管理后台路由
├── reference-grants/
│   └── reference-grant.yaml  # 跨命名空间授权
├── services/
│   ├── frontend-service.yaml
│   ├── api-service-v1.yaml
│   ├── api-service-v2.yaml
│   └── admin-service.yaml
└── scripts/
    ├── deploy.sh             # 一键部署脚本
    └── test-routes.sh        # 路由测试脚本
```

部署测试：

```bash
# 一键部署
cd demos/gateway-api
./scripts/deploy.sh

# 测试路由
./scripts/test-routes.sh

# 验证 Gateway 状态
kubectl get gateway -n gateway-system
kubectl get httproute -A
kubectl get referencegrant -A
```

---

## 常见坑与排查

### 坑 1：路由未绑定到 Gateway（Status 显示 "No matching parent"）

**现象**：HTTPRoute 创建成功，但 Status 中 `Accepted` 条件为 `False`，原因显示 "No matching parent"。

**排查步骤**：

```bash
# 查看 HTTPRoute 状态
kubectl describe httproute api-route -n api-team

# 检查 parentRefs 配置
kubectl get httproute api-route -n api-team -o jsonpath='{.spec.parentRefs}'

# 检查 Gateway 监听器配置
kubectl get gateway ecommerce-gateway -n gateway-system -o yaml

# 查看 Gateway 状态
kubectl describe gateway ecommerce-gateway -n gateway-system
```

**常见原因**：
1. `parentRefs.name` 与 Gateway 名称不匹配
2. `parentRefs.namespace` 未指定或错误（跨命名空间引用必须指定）
3. `parentRefs.sectionName` 与 Gateway Listener 名称不匹配
4. Gateway Listener 的 `allowedRoutes` 未允许该命名空间
5. 缺少 ReferenceGrant（跨命名空间引用时）

**解决方案**：
```yaml
# 确保 parentRefs 配置正确
spec:
  parentRefs:
  - name: ecommerce-gateway          # 必须与 Gateway metadata.name 一致
    namespace: gateway-system        # 跨命名空间必须指定
    sectionName: https               # 必须与 Listener name 一致
```

### 坑 2：跨命名空间引用被拒绝（"Ref not allowed"）

**现象**：HTTPRoute 引用其他命名空间的 Service 或 Gateway 时，Status 显示 "Ref not allowed"。

**排查步骤**：

```bash
# 检查 ReferenceGrant 是否存在
kubectl get referencegrant -n gateway-system

# 检查 ReferenceGrant 配置
kubectl get referencegrant allow-api-route -n gateway-system -o yaml

# 查看 HTTPRoute 状态详情
kubectl get httproute api-route -n api-team -o jsonpath='{.status.parents[*].conditions}'
```

**常见原因**：
1. 目标命名空间缺少 ReferenceGrant
2. ReferenceGrant 的 `from.namespace` 与实际路由命名空间不匹配
3. ReferenceGrant 的 `to.kind` 未包含被引用的资源类型

**解决方案**：
```yaml
# 在目标命名空间（被引用资源所在命名空间）创建 ReferenceGrant
apiVersion: gateway.networking.k8s.io/v1beta1
kind: ReferenceGrant
metadata:
  name: allow-cross-namespace
  namespace: gateway-system  # 被引用资源所在命名空间
spec:
  from:
  - group: gateway.networking.k8s.io
    kind: HTTPRoute
    namespace: api-team      # 路由所在命名空间
  to:
  - group: ""
    kind: Service            # 允许引用的资源类型
```

### 坑 3：TLS 证书未生效（HTTPS 连接失败）

**现象**：HTTPS 监听器配置正确，但客户端连接时收到证书错误。

**排查步骤**：

```bash
# 检查证书 Secret 是否存在
kubectl get secret ecommerce-tls -n gateway-system

# 验证证书内容
kubectl get secret ecommerce-tls -n gateway-system -o jsonpath='{.data.tls\.crt}' | base64 -d | openssl x509 -text -noout

# 检查证书域名是否匹配
kubectl get secret ecommerce-tls -n gateway-system -o jsonpath='{.data.tls\.crt}' | base64 -d | openssl x509 -noout -subject -ext subjectAltName

# 查看 Gateway Listener 状态
kubectl get gateway ecommerce-gateway -n gateway-system -o jsonpath='{.status.listeners[*]}'
```

**常见原因**：
1. 证书 Secret 不存在或命名空间错误
2. 证书域名与 Listener hostname 不匹配
3. 证书已过期
4. Gateway 控制器未正确加载证书

**解决方案**：
```yaml
# 确保证书配置正确
spec:
  listeners:
  - name: https
    protocol: HTTPS
    port: 443
    hostname: "*.ecommerce.example.com"  # 通配符证书匹配
    tls:
      mode: Terminate
      certificateRefs:
      - name: ecommerce-tls              # 必须与 Secret name 一致
        group: ""                        # Secret 的 API group（空字符串）
        kind: Secret                     # 资源类型
```

### 坑 4：加权路由流量分配不符合预期

**现象**：配置了 90/10 的加权路由，但实际流量分配偏差较大。

**排查步骤**：

```bash
# 查看 HTTPRoute 配置
kubectl get httproute api-route -n api-team -o yaml

# 检查后端服务 Pod 数量
kubectl get pods -n api-team -l app=api-service

# 查看控制器日志
kubectl logs -n gateway-system -l app=nginx-gateway-fabric | grep -i "route\|weight"

# 使用压测工具验证流量分配
for i in {1..100}; do curl -s -o /dev/null -w "%{http_code}\n" https://api.ecommerce.example.com/v1; done
```

**常见原因**：
1. 后端 Pod 数量不同导致负载不均（Kubernetes Service 默认轮询）
2. 客户端连接复用导致流量倾斜
3. 控制器实现差异（某些控制器在 Pod 数量不同时调整权重）
4. 权重配置错误（总和不为 100）

**解决方案**：
```yaml
# 确保后端 Pod 数量一致
kubectl scale deployment api-service-v1 --replicas=3 -n api-team
kubectl scale deployment api-service-v2 --replicas=3 -n api-team

# 或者使用基于权重的负载均衡算法（如果控制器支持）
# 在 GatewayClass parametersRef 中配置
```

### 坑 5：Gateway 控制器日志报错 "Listener conflict"

**现象**：Gateway 创建失败，Status 显示 "Listener conflict" 或 "Hostname conflict"。

**排查步骤**：

```bash
# 查看 Gateway 状态
kubectl describe gateway ecommerce-gateway -n gateway-system

# 检查是否有其他 Gateway 使用相同配置
kubectl get gateway -A -o jsonpath='{range .items[*]}{.metadata.namespace}/{.metadata.name}: {.spec.listeners[*].hostname}{"\n"}{end}'

# 查看控制器日志
kubectl logs -n gateway-system -l app=nginx-gateway-fabric | grep -i "conflict"
```

**常见原因**：
1. 同一 Gateway 内多个 Listener 配置了相同的 hostname + port + protocol 组合
2. 不同 Gateway 使用了相同的 LoadBalancer IP 和端口
3. 通配符域名冲突（`*.example.com` 与 `api.example.com`）

**解决方案**：
```yaml
# 确保 Listener 配置唯一
spec:
  listeners:
  - name: https-production
    protocol: HTTPS
    port: 443
    hostname: "*.ecommerce.example.com"  # 生产环境
  - name: https-staging
    protocol: HTTPS
    port: 443
    hostname: "*.staging.ecommerce.example.com"  # 测试环境，不同域名
```

---

## Checklist

部署 Gateway API 前，请逐项确认以下检查点：

### 前置条件
- [ ] Kubernetes 集群版本 ≥ 1.21（Gateway API v1 需要 1.21+）
- [ ] Gateway API CRDs 已安装（`kubectl get crd | grep gateway`）
- [ ] Gateway 控制器已部署并运行正常
- [ ] 集群具有 LoadBalancer 支持（云提供商或 MetalLB）

### GatewayClass 配置
- [ ] `controllerName` 与安装的控制器匹配
- [ ] `parametersRef` 配置正确（如果需要）
- [ ] GatewayClass 状态为 "Accepted"

### Gateway 配置
- [ ] Listener 名称唯一
- [ ] hostname + port + protocol 组合唯一
- [ ] TLS 证书 Secret 存在且有效
- [ ] `allowedRoutes` 配置符合安全策略
- [ ] Gateway 状态为 "Programmed"

### HTTPRoute 配置
- [ ] `parentRefs` 指向存在的 Gateway
- [ ] 跨命名空间引用时指定了 `namespace`
- [ ] `sectionName` 与 Listener 名称匹配
- [ ] 后端 Service 存在且端口正确
- [ ] 跨命名空间引用 Service 时有 ReferenceGrant
- [ ] HTTPRoute 状态为 "Accepted"

### ReferenceGrant 配置
- [ ] 在被引用资源所在命名空间创建
- [ ] `from.namespace` 包含所有需要引用的命名空间
- [ ] `to.kind` 包含所有被引用的资源类型

### 安全配置
- [ ] 生产环境启用 HTTPS（HTTP 重定向）
- [ ] TLS 证书使用受信任的 CA（如 Let's Encrypt）
- [ ] 敏感服务配置 IP 白名单或认证
- [ ] 启用安全响应头（CSP、X-Frame-Options 等）

### 监控与告警
- [ ] 配置 Gateway 控制器指标收集（Prometheus）
- [ ] 配置路由状态告警（HTTPRoute Accepted 状态）
- [ ] 配置证书过期告警
- [ ] 配置 5xx 错误率告警

### 迁移验证（从 Ingress 迁移）
- [ ] 新旧路由并行运行，流量逐步切换
- [ ] 验证所有路径匹配规则一致
- [ ] 验证 TLS 配置一致
- [ ] 验证重写/重定向规则一致
- [ ] 回滚方案已测试

---

## 参考资料

1. **Gateway API 官方文档** - https://gateway-api.sigs.k8s.io/
   - 完整的 API 参考、概念解释和实施指南
   - 包含 NGINX、Envoy、GKE 等控制器的具体实现文档

2. **Kubernetes Gateway API GitHub** - https://github.com/kubernetes-sigs/gateway-api
   - 源码仓库，包含最新的 API 规范和 GEP（Gateway Enhancement Proposals）
   - 查看 GEP-1 了解 Gateway API 的设计目标

3. **NGINX Gateway Fabric 文档** - https://docs.nginx.com/nginx-gateway-fabric/
   - NGINX 官方 Gateway API 控制器实现
   - 包含部署指南、配置示例和最佳实践

4. **Envoy Gateway 文档** - https://gateway.envoyproxy.io/
   - Envoy 项目官方的 Gateway API 控制器
   - 支持高级流量管理和可扩展性

5. **Gateway API vs Ingress 对比** - https://gateway-api.sigs.k8s.io/concepts/api-overview/#comparison-with-ingress
   - 官方对比文档，详细说明两种 API 的差异
   - 包含迁移指南和兼容性说明

6. **cert-manager 集成指南** - https://cert-manager.io/docs/usage/gateway-api/
   - 使用 cert-manager 为 Gateway API 自动管理 TLS 证书
   - 支持 Let's Encrypt 和其他 CA

7. **Gateway API 实施状态** - https://gateway-api.sigs.k8s.io/implementations/
   - 各控制器对 Gateway API 特性的支持情况
   - 帮助选择合适的控制器实现

---

*本文档遵循 Gateway API v1.0.0 规范，控制器实现可能因版本而异。生产部署前请在测试环境验证。*
