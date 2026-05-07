# Container Networking & Service Mesh 基础：从 Docker 网络到 Istio 服务网格

## 背景与目标

在容器化应用从开发环境走向生产环境的过程中，网络是最容易被忽视却又最关键的基础设施之一。许多工程师能够熟练编写 Dockerfile、部署 Kubernetes Deployment，但当面对"为什么服务 A 无法访问服务 B"、"如何实现灰度发布"、"如何追踪跨服务调用"等问题时，往往束手无策。

本文的目标是帮助你建立容器网络和服务网格的系统性认知：

1. **理解 Docker 网络模型**：掌握 bridge、host、overlay 网络的区别与适用场景
2. **掌握 Kubernetes 网络基础**：理解 Pod 网络、Service、Ingress、NetworkPolicy 的工作原理
3. **认识服务网格的价值**：了解 Istio 等 Service Mesh 如何解决生产环境的流量治理问题
4. **获得实战能力**：能够独立排查网络连通性问题，并设计合理的网络架构

通过本文，你将获得从单机容器网络到分布式服务网格的完整知识链条，为构建高可用、可观测的云原生应用打下坚实基础。

## 核心概念

### Docker 网络模型

Docker 提供了多种网络驱动，每种适用于不同的场景：

| 网络类型 | 隔离级别 | 适用场景 |
|---------|---------|---------|
| **bridge** | 容器间隔离，宿主机可访问 | 单机多容器通信（默认） |
| **host** | 无隔离，直接使用宿主机网络 | 高性能场景，牺牲隔离性 |
| **overlay** | 跨宿主机容器通信 | Swarm 集群、多节点部署 |
| **none** | 完全隔离 | 安全敏感场景，需手动配置网络 |

**Bridge 网络工作原理**：
Docker 在宿主机上创建虚拟网桥（docker0），每个容器获得一个 veth pair（虚拟以太网设备对），一端在容器内，另一端连接到网桥。容器间通信通过网桥转发，容器访问外网通过 NAT 转换。

### Kubernetes 网络模型

K8s 网络建立在几个核心假设之上：

1. **Pod IP 可达性**：所有 Pod 无需 NAT 即可相互通信
2. **节点 -Pod 可达性**：节点上的 agent 可与该节点上所有 Pod 通信
3. **ClusterIP 服务发现**：Service 提供稳定的虚拟 IP 和 DNS 名称

**关键组件**：

- **CNI（Container Network Interface）**：K8s 网络插件标准接口，常见实现包括 Calico、Flannel、Cilium
- **kube-proxy**：维护节点上的网络规则，实现 Service 的负载均衡
- **Ingress Controller**：七层负载均衡，处理外部流量进入集群
- **NetworkPolicy**：定义 Pod 间的网络访问控制策略（类似防火墙规则）

### 服务网格（Service Mesh）

服务网格是专为微服务架构设计的 инфраструктур层，通过 Sidecar 代理模式拦截所有服务间通信，提供：

- **流量管理**：路由规则、负载均衡、熔断、重试、超时控制
- **安全**：mTLS 加密、身份认证、授权策略
- **可观测性**：分布式追踪、指标收集、访问日志

**Istio 架构核心**：

```
┌─────────────┐    ┌─────────────┐
│   Service A │    │   Service B │
│   ┌─────┐   │    │   ┌─────┐   │
│   │ App │   │    │   │ App │   │
│   └──┬──┘   │    │   └──┬──┘   │
│   ┌──▼──┐   │    │   ┌──▼──┐   │
│   │Envoy│   │    │   │Envoy│   │  ← Sidecar 代理
│   └──┬──┘   │    │   └──┬──┘   │
└──────┼──────┘    └──────┼──────┘
       │                  │
       └────────┬─────────┘
                │
         ┌──────▼──────┐
         │   Istio     │
         │  Control    │  ← 控制平面
         │   Plane     │
         └─────────────┘
```

## 实战/示例

### 示例 1：Docker 网络排查实战

创建一个可复现的网络隔离测试环境：

```bash
#!/bin/bash
# demo/docker-network-test.sh

# 创建两个独立的网络
docker network create net-alpha
docker network create net-beta

# 在 alpha 网络中启动服务 A
docker run -d --name service-a --network net-alpha nginx:alpine

# 在 beta 网络中启动服务 B
docker run -d --name service-b --network net-beta nginx:alpine

# 测试连通性（预期：不通）
echo "=== 测试跨网络连通性（预期失败）==="
docker exec service-a ping -c 2 service-b || echo "✓ 按预期：跨网络无法通信"

# 将 service-b 连接到 alpha 网络
docker network connect net-alpha service-b

# 再次测试（预期：成功）
echo "=== 连接同一网络后测试（预期成功）==="
docker exec service-a ping -c 2 service-b && echo "✓ 同一网络内可通信"

# 清理
docker rm -f service-a service-b
docker network rm net-alpha net-beta
```

**运行结果分析**：
- 第一次 ping 失败，因为两个容器在不同网络命名空间
- 连接同一网络后，Docker 的 DNS 解析和网桥转发使通信成为可能

### 示例 2：Kubernetes NetworkPolicy 实践

NetworkPolicy 是 K8s 中实现零信任网络的关键工具。以下示例限制前端 Pod 只能访问后端特定端口：

```yaml
# demo/network-policy.yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: backend-restrict
  namespace: default
spec:
  podSelector:
    matchLabels:
      app: backend
  policyTypes:
    - Ingress
    - Egress
  ingress:
    # 只允许来自 frontend 的 8080 端口流量
    - from:
        - podSelector:
            matchLabels:
              app: frontend
      ports:
        - protocol: TCP
          port: 8080
  egress:
    # 只允许访问数据库和外部 API
    - to:
        - podSelector:
            matchLabels:
              app: database
      ports:
        - protocol: TCP
          port: 5432
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

**应用策略**：
```bash
kubectl apply -f demo/network-policy.yaml

# 验证策略生效
kubectl get networkpolicy backend-restrict -o yaml

# 测试连通性（从非 frontend Pod 访问应被拒绝）
kubectl run test-pod --rm -it --image=busybox --restart=Never -- \
  wget --timeout=2 http://backend-svc:8080
```

### 示例 3：Istio 流量分割（灰度发布）

使用 Istio VirtualService 实现 90/10 的灰度发布：

```yaml
# demo/istio-canary.yaml
apiVersion: networking.istio.io/v1beta1
kind: VirtualService
metadata:
  name: myapp-vs
spec:
  hosts:
    - myapp.example.com
  http:
    - match:
        - headers:
            x-canary:
              exact: "true"
      route:
        - destination:
            host: myapp
            subset: canary
    - route:
        - destination:
            host: myapp
            subset: stable
          weight: 90
        - destination:
            host: myapp
            subset: canary
          weight: 10
---
apiVersion: networking.istio.io/v1beta1
kind: DestinationRule
metadata:
  name: myapp-dr
spec:
  host: myapp
  subsets:
    - name: stable
      labels:
        version: v1
    - name: canary
      labels:
        version: v2
```

## 常见坑与排查

### 坑 1：DNS 解析失败

**现象**：Pod 内无法通过 Service 名称解析到其他服务

**排查步骤**：
```bash
# 1. 检查 CoreDNS 是否正常运行
kubectl get pods -n kube-system -l k8s-app=kube-dns

# 2. 在 Pod 内测试 DNS 解析
kubectl exec -it <pod-name> -- nslookup kubernetes.default

# 3. 检查 resolv.conf 配置
kubectl exec -it <pod-name> -- cat /etc/resolv.conf

# 4. 查看 CoreDNS 日志
kubectl logs -n kube-system -l k8s-app=kube-dns --tail=50
```

**常见原因**：
- CoreDNS Pod 崩溃或资源不足
- 节点 DNS 配置错误（/etc/resolv.conf 指向不可达 DNS）
- NetworkPolicy 阻止了 DNS 查询（UDP 53 端口）

### 坑 2：Service 无法访问后端 Pod

**现象**：ClusterIP 可 ping 通，但端口无法连接

**排查步骤**：
```bash
# 1. 检查 Endpoints 是否有后端
kubectl get endpoints <service-name>

# 2. 验证 Pod 标签是否与 Service selector 匹配
kubectl get pods --show-labels
kubectl get svc <service-name> -o jsonpath='{.spec.selector}'

# 3. 检查 kube-proxy 状态
kubectl get pods -n kube-system -l k8s-app=kube-proxy

# 4. 查看 iptables/ipvs 规则（在节点上）
iptables-save | grep <service-cluster-ip>
```

**常见原因**：
- Pod 标签与 Service selector 不匹配
- Pod 未通过就绪探针（Ready 状态为 false）
- kube-proxy 异常导致规则未更新

### 坑 3：Istio Sidecar 注入失败

**现象**：Pod 只有一个容器，没有 Envoy Sidecar

**排查步骤**：
```bash
# 1. 检查命名空间是否有注入标签
kubectl get namespace <ns> --show-labels

# 2. 手动注入测试
istioctl kube-inject -f deployment.yaml | kubectl apply -f -

# 3. 查看 MutatingWebhookConfiguration
kubectl get mutatingwebhookconfiguration istio-sidecar-injector -o yaml

# 4. 检查 sidecar-injector 日志
kubectl logs -n istio-system -l app=sidecar-injector
```

**常见原因**：
- 命名空间缺少 `istio-injection=enabled` 标签
- MutatingWebhook 被其他准入控制器覆盖
- Istio 控制平面组件异常

### 坑 4：跨命名空间通信失败

**现象**：同一集群内不同命名空间的 Pod 无法通信

**排查要点**：
- Service 跨命名空间访问需使用 `<svc-name>.<namespace>.svc.cluster.local` 完整域名
- NetworkPolicy 默认允许跨命名空间，除非显式拒绝
- Istio 中需配置 PeerAuthentication 允许跨命名空间 mTLS

## Checklist

在部署容器网络和服务网格前，请确认以下事项：

**Docker 网络**
- [ ] 明确容器通信范围（单机/跨主机）
- [ ] 选择合适的网络驱动（bridge/overlay/host）
- [ ] 敏感服务使用独立网络隔离
- [ ] 测试容器 DNS 解析正常

**Kubernetes 网络**
- [ ] CNI 插件已正确安装且所有节点 Ready
- [ ] Pod 间网络连通性测试通过
- [ ] Service 的 selector 与 Pod 标签匹配
- [ ] 关键服务配置 NetworkPolicy 限制访问
- [ ] Ingress Controller 已部署且外部可访问
- [ ] DNS 解析（CoreDNS）工作正常

**服务网格（Istio）**
- [ ] 控制平面组件全部 Running
- [ ] 命名空间已启用 Sidecar 注入
- [ ] mTLS 策略符合安全要求（STRICT/PERMISSIVE）
- [ ] VirtualService 路由规则已验证
- [ ] 分布式追踪（Jaeger/Zipkin）可访问
- [ ] 指标收集（Prometheus/Grafana）正常

**生产环境额外检查**
- [ ] 网络策略已实施零信任原则（默认拒绝）
- [ ] 关键路径有冗余（多副本、多可用区）
- [ ] 网络监控告警已配置（延迟、错误率、带宽）
- [ ] 有网络故障应急预案和回滚方案

## 参考资料

1. **Kubernetes Networking 官方文档** - 深入理解 K8s 网络模型、Service、Ingress、NetworkPolicy 的权威指南
   https://kubernetes.io/docs/concepts/services-networking/

2. **Istio 官方文档** - 服务网格的完整参考，包含流量管理、安全、可观测性的详细配置
   https://istio.io/latest/docs/

3. **Docker 网络驱动文档** - Docker 官方对各类网络驱动的说明和使用示例
   https://docs.docker.com/network/

4. **Calico 网络策略指南** - 流行的 K8s CNI 插件，提供强大的 NetworkPolicy 实现
   https://docs.tigera.io/calico/latest/about/

5. **Service Mesh 对比分析** - Istio、Linkerd、Consul Connect 等主流方案的技术对比
   https://www.cncf.io/blog/2022/05/04/service-meshes-explained/

6. **Kubernetes 网络故障排查手册** - 系统化的网络问题诊断流程和工具集
   https://kubernetes.io/docs/tasks/debug/debug-cluster/
