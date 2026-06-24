# Kubernetes Network Policies：零信任微隔离生产实践

## 背景与目标

在 Kubernetes 集群中，默认情况下所有 Pod 之间可以自由通信——同一个命名空间内的 Pod 无需任何配置即可互相访问，跨命名空间的 Pod 也可以通过 Service 或直接 IP 进行通信。这种"默认允许"的网络模型虽然便于开发调试，但在生产环境中却带来了严重的安全隐患。

**零信任（Zero Trust）安全模型**的核心原则是"永不信任，始终验证"。将这一原则应用到 Kubernetes 网络层，意味着我们需要：
1. 默认拒绝所有 Pod 间通信
2. 显式定义允许的流量路径
3. 基于最小权限原则限制访问范围
4. 对东西向流量（East-West Traffic）进行细粒度控制

Kubernetes 的 **NetworkPolicy** 资源正是实现这一目标的关键工具。它允许你基于标签选择器、命名空间、端口和协议等条件，精确控制 Pod 的入站（Ingress）和出站（Egress）流量。

本文的目标是：
1. 深入理解 NetworkPolicy 的工作原理和匹配规则
2. 掌握零信任网络架构的设计模式和实施步骤
3. 学会编写可维护、可扩展的网络策略
4. 提供生产环境的排查工具和最佳实践 Checklist

通过本文，你将能够在 Kubernetes 集群中构建纵深防御体系，有效遏制横向移动攻击，满足合规审计要求。

## 核心概念

### NetworkPolicy 基础结构

NetworkPolicy 是 Kubernetes 的网络访问控制资源，定义在命名空间级别。它通过标签选择器指定适用的 Pod 集合，并通过规则列表定义允许的流量。

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: api-ingress-policy
  namespace: production
spec:
  podSelector:
    matchLabels:
      app: api-gateway
  policyTypes:
    - Ingress
    - Egress
  ingress:
    - from:
        - namespaceSelector:
            matchLabels:
              name: ingress-nginx
        - podSelector:
            matchLabels:
              app: frontend
      ports:
        - protocol: TCP
          port: 8080
  egress:
    - to:
        - podSelector:
            matchLabels:
              app: backend-service
      ports:
        - protocol: TCP
          port: 3000
```

**关键字段说明：**
- `podSelector`：选择策略适用的 Pod。空选择器 `{}` 匹配命名空间内所有 Pod
- `policyTypes`：声明策略类型（Ingress、Egress 或两者）。若未指定，根据规则自动推断
- `ingress`：入站规则列表。每条规则定义允许的源和端口
- `egress`：出站规则列表。每条规则定义允许的目标和端口

### 默认策略：Deny All

实现零信任的第一步是创建"默认拒绝"策略。这会阻断命名空间内所有 Pod 的入站和出站流量，然后逐步添加允许规则。

```yaml
# 拒绝所有入站流量
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-ingress
  namespace: production
spec:
  podSelector: {}
  policyTypes:
    - Ingress
---
# 拒绝所有出站流量
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-egress
  namespace: production
spec:
  podSelector: {}
  policyTypes:
    - Egress
```

**重要注意事项：**
- 空 `podSelector: {}` 匹配命名空间内所有 Pod
- 仅声明 `policyTypes` 而不定义 `ingress/egress` 规则，表示拒绝所有对应方向的流量
- 默认策略应先于其他策略应用，确保"默认拒绝"生效

### 流量匹配规则

NetworkPolicy 的流量匹配遵循以下逻辑：

1. **源/目标选择器**：可以是 `podSelector`、`namespaceSelector` 或两者组合
   - 仅 `podSelector`：匹配当前命名空间内的 Pod
   - 仅 `namespaceSelector`：匹配所有命名空间中带指定标签的 Pod
   - 两者组合：匹配指定命名空间中带指定标签的 Pod

2. **端口匹配**：可指定单个端口、端口范围或协议类型
   ```yaml
   ports:
     - protocol: TCP
       port: 443
     - protocol: TCP
       port: 80
     - protocol: UDP
       endPort: 53
       port: 53
   ```

3. **CIDR 块匹配**（需要 CNI 插件支持）：
   ```yaml
   ingress:
     - from:
         - ipBlock:
             cidr: 10.0.0.0/8
             except:
               - 10.0.0.0/24
   ```

### CNI 插件兼容性

NetworkPolicy 的实现依赖于 CNI（Container Network Interface）插件。并非所有 CNI 都支持 NetworkPolicy：

| CNI 插件 | NetworkPolicy 支持 | 备注 |
|----------|-------------------|------|
| Calico | ✅ 完整支持 | 功能最丰富，支持全局策略 |
| Cilium | ✅ 完整支持 | 基于 eBPF，性能优异 |
| Weave Net | ✅ 支持 | 简单易用 |
| Flannel | ❌ 不支持 | 需配合其他插件 |
| Canal (Flannel + Calico) | ✅ 支持 | Calico 提供策略 |

**生产建议**：选择 Calico 或 Cilium 作为 CNI 插件，两者都提供完整的 NetworkPolicy 支持和丰富的扩展功能。

## 实战/示例

### 示例 1：三层架构网络隔离

考虑一个典型的三层应用架构：前端（Frontend）→ API 网关（API Gateway）→ 后端服务（Backend）→ 数据库（Database）。我们需要实现以下访问控制：

- 前端只能访问 API 网关
- API 网关可以访问后端服务和外部 API
- 后端服务只能访问数据库
- 数据库不接受任何入站连接（除后端服务外）

```yaml
# 1. 默认拒绝所有流量（应用于整个命名空间）
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-all
  namespace: ecommerce
spec:
  podSelector: {}
  policyTypes:
    - Ingress
    - Egress
---
# 2. 前端策略：允许入站（从 Ingress），允许出站（到 API）
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: frontend-policy
  namespace: ecommerce
spec:
  podSelector:
    matchLabels:
      tier: frontend
  policyTypes:
    - Ingress
    - Egress
  ingress:
    - from:
        - namespaceSelector:
            matchLabels:
              name: ingress-nginx
      ports:
        - protocol: TCP
          port: 3000
  egress:
    - to:
        - podSelector:
            matchLabels:
              tier: api-gateway
      ports:
        - protocol: TCP
          port: 8080
    # 允许 DNS 解析
    - to:
        - namespaceSelector: {}
          podSelector:
            matchLabels:
              k8s-app: kube-dns
      ports:
        - protocol: UDP
          port: 53
---
# 3. API 网关策略
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: api-gateway-policy
  namespace: ecommerce
spec:
  podSelector:
    matchLabels:
      tier: api-gateway
  policyTypes:
    - Ingress
    - Egress
  ingress:
    - from:
        - podSelector:
            matchLabels:
              tier: frontend
      ports:
        - protocol: TCP
          port: 8080
  egress:
    - to:
        - podSelector:
            matchLabels:
              tier: backend
      ports:
        - protocol: TCP
          port: 3000
    - to:
        - ipBlock:
            cidr: 0.0.0.0/0
            except:
              - 10.0.0.0/8  # 排除内网
      ports:
        - protocol: TCP
          port: 443
    # 允许 DNS
    - to:
        - namespaceSelector: {}
          podSelector:
            matchLabels:
              k8s-app: kube-dns
      ports:
        - protocol: UDP
          port: 53
---
# 4. 后端服务策略
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: backend-policy
  namespace: ecommerce
spec:
  podSelector:
    matchLabels:
      tier: backend
  policyTypes:
    - Ingress
    - Egress
  ingress:
    - from:
        - podSelector:
            matchLabels:
              tier: api-gateway
      ports:
        - protocol: TCP
          port: 3000
  egress:
    - to:
        - podSelector:
            matchLabels:
              tier: database
      ports:
        - protocol: TCP
          port: 5432
    # 允许 DNS
    - to:
        - namespaceSelector: {}
          podSelector:
            matchLabels:
              k8s-app: kube-dns
      ports:
        - protocol: UDP
          port: 53
---
# 5. 数据库策略：仅允许后端访问
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: database-policy
  namespace: ecommerce
spec:
  podSelector:
    matchLabels:
      tier: database
  policyTypes:
    - Ingress
  ingress:
    - from:
        - podSelector:
            matchLabels:
              tier: backend
      ports:
        - protocol: TCP
          port: 5432
```

### 示例 2：多租户命名空间隔离

在多租户场景中，不同团队的命名空间应该相互隔离，但允许访问共享服务（如监控、日志）。

```yaml
# 团队 A 命名空间：允许访问共享服务，拒绝访问其他团队
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: team-a-isolation
  namespace: team-a
spec:
  podSelector: {}
  policyTypes:
    - Ingress
    - Egress
  ingress:
    # 允许来自同命名空间的流量
    - from:
        - podSelector: {}
    # 允许来自监控命名空间的流量
    - from:
        - namespaceSelector:
            matchLabels:
              name: monitoring
      ports:
        - protocol: TCP
          port: 9090  # Prometheus
  egress:
    # 允许访问同命名空间
    - to:
        - podSelector: {}
    # 允许访问共享服务命名空间
    - to:
        - namespaceSelector:
            matchLabels:
              name: shared-services
    # 允许 DNS
    - to:
        - namespaceSelector: {}
          podSelector:
            matchLabels:
              k8s-app: kube-dns
      ports:
        - protocol: UDP
          port: 53
```

### 示例 3：使用 Cilium 实现 L7 策略

Cilium 支持基于 HTTP/gRPC 等应用层协议的细粒度策略，这是标准 NetworkPolicy 无法实现的。

```yaml
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: l7-api-policy
  namespace: production
spec:
  endpointSelector:
    matchLabels:
      app: api-gateway
  egress:
    - toEndpoints:
        - matchLabels:
            app: user-service
      toPorts:
        - ports:
            - port: "8080"
          rules:
            http:
              - method: "GET"
                path: "/api/users/*"
              - method: "POST"
                path: "/api/users"
```

## 常见坑与排查

### 坑 1：忘记允许 DNS 流量

**症状**：应用无法解析域名，报错 `getaddrinfo ENOTFOUND` 或 `Temporary failure in name resolution`

**原因**：默认拒绝策略阻断了 Pod 到 CoreDNS/KubeDNS 的 UDP 53 端口流量

**解决方案**：
```yaml
egress:
  - to:
      - namespaceSelector: {}
        podSelector:
          matchLabels:
            k8s-app: kube-dns
    ports:
      - protocol: UDP
        port: 53
```

**排查命令**：
```bash
# 检查 DNS Pod 标签
kubectl get pods -n kube-system -l k8s-app=kube-dns --show-labels

# 测试 DNS 解析
kubectl run -it --rm dns-test --image=busybox:1.36 --restart=Never -- nslookup kubernetes.default
```

### 坑 2：namespaceSelector 与 podSelector 组合逻辑混淆

**症状**：策略未按预期工作，流量被意外允许或拒绝

**原因**：`namespaceSelector` 和 `podSelector` 在同一列表项中是"与"关系，在不同列表项中是"或"关系

**错误示例**（意图：允许所有命名空间中标签为 app=monitoring 的 Pod）：
```yaml
# 错误：这会匹配 monitoring 命名空间中 app=monitoring 的 Pod
ingress:
  - from:
      - namespaceSelector:
          matchLabels:
            name: monitoring
        podSelector:
          matchLabels:
            app: monitoring
```

**正确示例**：
```yaml
# 正确：允许所有命名空间中标签为 app=monitoring 的 Pod
ingress:
  - from:
      - podSelector:
          matchLabels:
            app: monitoring
```

### 坑 3：策略优先级误解

**症状**：多条策略同时存在时，行为不符合预期

**原因**：NetworkPolicy 是累加的（additive），不是优先级覆盖。只要有一条策略允许某条流量，该流量就被允许

**设计原则**：
1. 默认拒绝策略作为基线
2. 允许策略逐步开放必要流量
3. 不要期望"拒绝策略覆盖允许策略"

### 坑 4：CNI 插件不支持

**症状**：策略应用后无效果，`kubectl describe networkpolicy` 显示正常但流量未被阻断

**排查步骤**：
```bash
# 检查 CNI 插件
kubectl get pods -n kube-system -o wide | grep -E 'calico|cilium|weave'

# 查看 NetworkPolicy 状态
kubectl describe networkpolicy <policy-name> -n <namespace>

# 检查 CNI 日志
kubectl logs -n kube-system -l k8s-app=calico-node --tail=100
```

### 坑 5：出站流量未考虑外部依赖

**症状**：应用无法访问外部 API、对象存储、数据库等

**解决方案**：
```yaml
egress:
  # 允许访问特定外部 IP
  - to:
      - ipBlock:
          cidr: 52.84.123.0/24  # AWS 某区域 IP 段
    ports:
      - protocol: TCP
        port: 443
  # 或允许所有外部流量（不推荐生产环境）
  - to:
      - ipBlock:
          cidr: 0.0.0.0/0
          except:
            - 10.0.0.0/8
            - 172.16.0.0/12
            - 192.168.0.0/16
    ports:
      - protocol: TCP
        port: 443
```

### 通用排查工具

```bash
# 1. 查看 Pod 应用了哪些 NetworkPolicy
kubectl get networkpolicy -n <namespace> -o yaml | grep -A 20 "podSelector"

# 2. 使用 Calico 的 calicoctl 工具（如使用 Calico CNI）
calicoctl get networkpolicy -n <namespace> -o yaml

# 3. 测试连通性
kubectl run test-pod --image=busybox:1.36 -it --rm --restart=Never -- \
  wget -T 5 -qO- http://<target-service>:<port>

# 4. 查看策略生效状态（Cilium）
cilium policy get

# 5. 捕获网络流量（需要特权 Pod）
kubectl run tcpdump --image=corfrank/tcpdump -it --rm --restart=Never -- \
  tcpdump -i any -n port <port>
```

## Checklist

### 设计阶段
- [ ] 绘制应用架构图，标注所有流量路径
- [ ] 识别敏感数据流和关键服务
- [ ] 确定命名空间划分策略（按团队/环境/功能）
- [ ] 规划共享服务访问模式（监控、日志、DNS）
- [ ] 评估 CNI 插件是否支持所需策略功能

### 实施阶段
- [ ] 先部署默认拒绝策略（在测试环境验证）
- [ ] 逐层添加允许规则，每次变更后验证连通性
- [ ] 确保所有需要 DNS 解析的 Pod 都有出站 DNS 规则
- [ ] 为外部依赖（API、存储）配置明确的 IP 白名单
- [ ] 使用标签一致性命名规范（如 `tier=`, `app=`, `team=`）

### 验证阶段
- [ ] 使用 `kubectl describe networkpolicy` 确认策略语法正确
- [ ] 从各 Pod 测试预期允许和拒绝的流量路径
- [ ] 验证 DNS 解析正常工作
- [ ] 检查应用日志无连接超时或拒绝错误
- [ ] 使用网络策略可视化工具（如 Cilium Hubble）确认流量图

### 运维阶段
- [ ] 将 NetworkPolicy 纳入 GitOps 流程，版本化管理
- [ ] 定期审计策略，清理不再使用的规则
- [ ] 监控策略变更，设置告警通知
- [ ] 在 CI/CD 中加入策略语法校验（如使用 conftest）
- [ ] 文档化每条策略的业务目的和负责人

### 安全合规
- [ ] 确保策略满足等保/PCI-DSS/SOC2 等合规要求
- [ ] 对敏感数据流实施额外加密（mTLS）
- [ ] 定期执行渗透测试，验证网络隔离有效性
- [ ] 建立策略变更审批流程
- [ ] 保留策略变更审计日志

## 参考资料

1. **Kubernetes 官方文档 - Network Policies**
   https://kubernetes.io/docs/concepts/services-networking/network-policies/
   - 官方权威文档，涵盖基础概念和 YAML 示例
   - 包含 CNI 插件兼容性说明

2. **Kubernetes 官方文档 - Network Policy Recipes**
   https://kubernetes.io/docs/tasks/administer-cluster/declare-network-policy/
   - 常见场景的策略模板（默认拒绝、多租户隔离等）
   - 可直接复用的 YAML 片段

3. **Cilium 文档 - Network Policy**
   https://docs.cilium.io/en/stable/security/network/policy/
   - Cilium 的 NetworkPolicy 实现详解
   - L7 策略、身份感知策略等高级功能

4. **Calico 文档 - Kubernetes Network Policy**
   https://docs.tigera.io/calico/latest/about/about-calico
   - Calico 的全局网络策略和扩展功能
   - 与 Kubernetes 原生 NetworkPolicy 的对比

5. **NIST SP 800-204B - Microservices Security**
   https://csrc.nist.gov/publications/detail/sp/800-204/b/final
   - 微服务安全架构指南，包含网络隔离最佳实践
   - 零信任模型在容器环境中的应用

6. **GitHub - awesome-network-policies**
   https://github.com/ahmetb/kubernetes-network-policy-recipes
   - 社区维护的策略模板集合
   - 涵盖多种实际场景的完整示例
