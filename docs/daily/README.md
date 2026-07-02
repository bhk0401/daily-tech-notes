# 每日技术文档索引

按时间倒序排列的技术文档。

---

## 2026-07-02

- [Kubernetes Resource Management：Requests、Limits 与 QoS Classes 生产实践](./2026-07-02-kubernetes-resource-management-requests-limits-qos.md) - 深入理解 Kubernetes 资源模型核心机制，掌握 Requests/Limits 配置策略与 QoS Class 对 Pod 调度和驱逐的影响，涵盖 CPU/内存资源管理、OOMKilled 排查、节点资源超卖控制，提供三大 QoS Class 配置模板、Node.js 应用资源配置实践、LimitRange/ResourceQuota 命名空间治理、Prometheus 监控告警规则，含 OOMKilled 误判/CPU Throttling/Pod Pending/Guaranteed 驱逐/资源超卖等 5 大常见坑排查指南与生产级部署 Checklist

## 2026-07-01

- [HTTP/3 与 QUIC 协议：生产环境的性能优化实践](./2026-07-01-http3-quic-performance-optimization.md) - 深入解析 HTTP/3 基于 QUIC 协议的核心架构与性能优势，掌握 0-RTT 握手、连接迁移、流复用消除队头阻塞等关键特性，涵盖 Nginx HTTP/3 配置、Node.js 原生实现、弱网性能对比测试，含防火墙 UDP 阻断/CDN 兼容性/0-RTT 重放攻击/客户端适配/QUIC 连接重置/证书配置等 6 大常见坑排查指南，提供完整 Docker 示例与生产级部署 Checklist

## 2026-06-30

- [多区域数据库复制与冲突解决策略：构建全球分布式数据系统](./2026-06-30-multi-region-database-replication-conflict-resolution.md) - 深入解析多区域数据库复制核心模式（同步/异步/半同步）与 CAP 定理实践，掌握 LWW/向量时钟/CRDT/操作转换/自定义合并五大冲突解决策略，涵盖 PostgreSQL 逻辑复制多主部署完整示例（发布/订阅/冲突检测触发器）、CRDT PNCounter 分布式限流器实现、AWS Aurora Global Database 托管方案，含复制延迟/LWW 数据丢失/循环复制/全局 ID 冲突/跨区事务等 5 大常见坑排查指南，提供 Node.js 冲突解决代码/Snowflake ID 生成器/监控 SQL 完整示例与生产级部署 Checklist

## 2026-06-29

- [Service Mesh mTLS：零信任通信与证书管理生产实践](./2026-06-29-service-mesh-mtls-zero-trust.md) - 深入解析 Service Mesh mTLS 核心架构与零信任通信原理，掌握 Istio/Linkerd 双向 TLS 配置方法、证书生命周期管理（签发/存储/轮换/撤销）、PeerAuthentication/DestinationRule 策略配置，涵盖 api-gateway + user-service 完整示例、证书验证脚本、外部服务 TLS originate 配置，含握手失败/证书过期/迁移中断/性能开销/外部访问等 5 大常见坑排查指南，提供 demos/mtls-demo 可运行项目与生产级部署 Checklist

## 2026-06-28

- [Event-Driven Architecture：事件溯源、CQRS 与事件风暴生产实践](./2026-06-28-event-driven-architecture-event-sourcing-cqrs.md) - 深入解析事件驱动架构三大核心模式：事件溯源（Event Sourcing）将状态变更持久化为不可变事件流、CQRS 实现读写职责分离独立优化、事件风暴（Event Storming）协作建模发现领域边界，涵盖电商订单系统完整 TypeScript 实现（事件定义/事件存储/聚合根/投影器）、PostgreSQL/EventStoreDB/Kafka/MongoDB/Redis Streams 五类事件存储选型对比，含事件版本演进/投影一致性/重复消费/聚合加载性能等 4 大常见坑排查指南，提供乐观并发控制/幂等处理器/快照优化完整代码示例与生产级部署 Checklist

## 2026-06-27

- [Container Image Signing & Supplychain Security：Sigstore/Cosign 生产级实践](./2026-06-27-container-image-signing-sigstore-cosign.md) - 深入理解 Sigstore 项目核心架构（Cosign/Rekor/Fulcio），掌握密钥对签名、密钥less OIDC 签名、KMS 托管签名三种模式，涵盖 GitHub Actions 集成、Kubernetes Policy Controller 自动验证、透明度日志审计等实战场景，含 signature unknown/OIDC 超时/Policy Controller 不生效/Rekor 查询失败/CI 权限不足等 5 大常见坑排查指南，提供完整 Cosign 命令示例与生产级部署 Checklist

## 2026-06-26

- [Frontend Build Optimization：打包、Tree Shaking 与代码分割生产实践](./2026-06-26-frontend-build-optimization-bundling-tree-shaking.md) - 深入解析 Webpack/Vite 构建优化核心机制，掌握 Tree Shaking 静态分析原理、路由级/组件级/库级代码分割策略与 Bundle 分析技巧，涵盖 lodash-es 具名导入、manualChunks 手动分割、terser 压缩配置等实战模式，含 Tree Shaking 未生效/动态 require 全量打包/重复依赖膨胀/过度分割请求瀑布/Sourcemap 泄露等 5 大常见坑排查指南，提供完整 Vite + React 配置示例与生产级部署 Checklist

## 2026-06-25

- [API Versioning Strategies：生产环境的版本管理实战](./2026-06-25-api-versioning-strategies-production.md) - 深入对比 URL Path/Header/Content Negotiation 三种 API 版本化方案，掌握破坏性变更识别、版本生命周期管理（发布/维护/弃用/下线）、Node.js + Express 多版本路由实现，涵盖版本路由冲突/共享状态污染/文档不同步/缓存未隔离/监控未区分等 5 大常见坑排查指南，提供完整 TypeScript 实现示例、迁移适配器模式与生产级部署 Checklist

## 2026-06-24

- [Kubernetes Network Policies：零信任微隔离生产实践](./2026-06-24-kubernetes-network-policies-zero-trust.md) - 深入理解 Kubernetes NetworkPolicy 工作原理与零信任网络架构设计，掌握默认拒绝策略、三层架构隔离、多租户命名空间隔离、L7 应用层策略（Cilium）等实战模式，涵盖 DNS 流量遗漏/选择器组合逻辑混淆/策略优先级误解/CNI 插件兼容性/外部依赖阻断等 5 大常见坑排查指南，提供完整 YAML 示例与生产级部署 Checklist

## 2026-06-23

- [Kubernetes Storage：PV/PVC/StorageClass 生产实践](./2026-06-23-kubernetes-storage-pv-pvc-storageclass.md) - 深入理解 Kubernetes 持久化存储三层抽象（PV/PVC/StorageClass）的工作原理与绑定机制，掌握 NFS/Local Path/云厂商存储（AWS EBS）配置方法，涵盖动态供应、访问模式（RWO/RWX/ROX）、回收策略、volumeBindingMode 核心概念，提供 StatefulSet MySQL 部署、多 Pod 共享存储完整示例，含 PVC Pending/挂载超时/数据竞争/StorageClass 删除/扩容失败等 5 大常见坑排查指南与生产级部署 Checklist

## 2026-06-22

- [Chaos Engineering：Kubernetes 生产环境的故障注入与韧性测试](./2026-06-22-chaos-engineering-kubernetes-production.md) - 深入理解混沌工程四大原则与爆炸半径控制，掌握 Chaos Mesh 核心 CRD（PodChaos/NetworkChaos/StressChaos/Workflow），涵盖 Pod Kill 自愈验证、网络延迟超时测试、CPU Stress 触发 HPA、复合故障工作流编排等 5 大实战示例，含 RBAC 权限不足/爆炸半径过大/稳态未恢复/Dashboard 失联/监控数据污染等 5 大常见坑排查指南与生产级部署 Checklist

## 2026-06-21

- [Kubernetes Operators：CRD 与 Controller 开发实战](./2026-06-21-kubernetes-operators-crds-controllers.md) - 深入解析 Kubernetes Operator 核心架构与协调循环原理，掌握 Kubebuilder 快速搭建方法、CRD Schema 设计、Controller 幂等性实现，涵盖 Database Operator 完整示例（StatefulSet/Service/PVC/Backup CronJob 自动化），含无限重试/版本升级数据丢失/RBAC 权限不足/最终一致性等 5 大常见坑排查指南与生产级部署 Checklist

## 2026-06-20

- [AI Streaming Responses：SSE/WebSocket 模式在 LLM 应用中的实战](./2026-06-20-ai-streaming-sse-websocket-patterns.md) - 深入解析 Server-Sent Events 与 WebSocket 在 AI 流式响应场景的技术选型，掌握 Next.js App Router SSE 实现、Express WebSocket 双向通信、Nginx 缓冲配置，涵盖连接中断恢复/认证传递/JSON 解析错误/代理缓冲等 5 大常见坑排查指南，提供 TypeScript 完整实现示例与生产级部署 Checklist

## 2026-06-19

- [gRPC Error Handling & Retry：生产环境的错误码、重试机制与 Deadline 管理](./2026-06-19-grpc-error-handling-retry-deadline.md) - 深入解析 gRPC 16 种标准错误码语义与处理策略，掌握声明式重试配置、指数退避 + 抖动算法、Deadline 传播机制，涵盖非幂等重试陷阱/级联超时/重试风暴/连接池耗尽等 5 大常见坑排查指南，提供 Node.js 完整实现示例与生产级部署 Checklist

## 2026-06-18

- [Micro-frontends 实战：Module Federation 与集成模式](./2026-06-18-microfrontends-module-federation.md) - 深入理解 Module Federation 核心原理与 Host/Remote 架构，掌握 Webpack 5 微前端配置方法、共享依赖优化策略，涵盖 React 重复加载/样式污染/CORS 错误/版本冲突/状态同步等 5 大常见坑排查指南，提供完整 TypeScript 示例代码与生产级部署 Checklist

## 2026-06-17

- [Kubernetes 批量处理：Job 与 CronJob 生产实践](./2026-06-17-kubernetes-batch-processing-job-cronjob.md) - 深入理解 Kubernetes Job/CronJob 核心概念与适用场景，掌握 completions/parallelism/backoffLimit 配置、并发策略控制、失败重试机制，涵盖批量数据处理/定时备份/报告生成完整示例，含 Pod Pending/无限重试/调度失败/数据竞争/日志丢失等 5 大常见坑排查指南与生产级部署 Checklist

## 2026-06-16

- [Serverless Functions + Edge Computing：无服务器与边缘计算的部署实战](./2026-06-16-serverless-edge-functions-deployment.md) - 深入理解 Serverless Functions 与 Edge Computing 核心架构差异，掌握 Cloudflare Workers、Vercel Functions、AWS Lambda@Edge 三大平台部署实践，涵盖 V8 Isolates vs 容器执行模型对比、冷启动优化、边缘中间件实现、A/B 测试架构，提供完整 TypeScript 代码示例、多环境配置、限流/认证/CORS 中间件链，含 5 大常见坑（冷启动延迟/执行超时/环境变量/CORS/状态管理）排查指南与生产级部署 Checklist

## 2026-06-15

- [分布式追踪实战：Trace 分析、故障定位与性能优化](./2026-06-15-distributed-tracing-debugging-patterns.md) - 深入解析分布式追踪核心数据结构与上下文传播机制，掌握 Jaeger/Tempo Trace 分析方法、慢请求根因定位技巧、错误传播路径追踪，涵盖 Trace 链路断裂/采样丢失关键请求/Span 爆炸/时钟不同步等 5 大常见坑排查指南，提供 Node.js + OpenTelemetry 完整埋点示例与生产级部署 Checklist

## 2026-06-14

- [Prometheus + Grafana：云原生指标监控生产实践](./2026-06-14-prometheus-grafana-metrics-monitoring.md) - 深入理解 Prometheus 核心架构与 PromQL 查询语言，掌握生产级 Kubernetes 监控配置、核心告警规则设计、Grafana 仪表板管理，涵盖高基数标签爆炸/Counter 误用/告警风暴/抓取超时/存储 retention 等 5 大常见坑排查指南与生产级部署 Checklist

## 2026-06-13

- [AI Agent Orchestration：状态管理、记忆持久化与多智能体协作模式](./2026-06-13-ai-agent-orchestration-state-memory.md) - 深入解析生产级 AI Agent 系统核心架构挑战，掌握 Redis/MongoDB 记忆存储方案、Agent 状态机设计模式、基于消息队列的多 Agent 通信架构，涵盖状态竞态条件/记忆存储爆炸/消息循环/向量检索冷启动/分布式状态一致性等 5 大常见坑排查指南与生产级部署 Checklist

## 2026-06-12

- [WebAssembly System Interface (WASI)：容器化之外的沙箱标准化方案](./2026-06-12-wasi-sandbox-standardization.md) - 深入理解 WASI 核心架构与 Capability-Based Security 模型，掌握 Wasmtime/Wasmer 运行时使用，对比 WASI 与容器沙箱的本质区别，涵盖 Rust 编译 WASI 模块、Docker/Kubernetes 部署完整示例、WASI Preview 版本兼容性/文件权限/网络限制/内存 OOM/多线程缺失等 5 大常见坑排查指南与生产级部署 Checklist

## 2026-06-11

- [结构化日志与日志管理平台：ELK vs Loki 生产级实践](./2026-06-11-structured-logging-elk-loki-production.md) - 深入结构化日志核心原则，对比 ELK Stack 与 Loki 架构差异，掌握 JSON 日志规范、高效查询语法、告警规则配置与成本控制策略，涵盖 Node.js/Python/Go 多语言实现、Promtail 采集配置、LogQL 查询实战、标签基数爆炸/内存溢出/日志重复等 5 大常见坑排查指南与生产级部署 Checklist

## 2026-06-10

- [Container Runtime Security：seccomp、AppArmor 与 gVisor 生产级实践](./2026-06-10-container-runtime-security-seccomp-apparmor-gvisor.md) - 深入理解容器运行时安全三大核心机制，掌握系统调用过滤、强制访问控制与沙箱运行时配置，涵盖 Docker/Kubernetes 完整集成方案、seccomp 白名单生成、AppArmor 策略编写、gVisor 沙箱部署，含特权容器逃逸防护、系统调用兼容性、性能优化等 5 大常见坑排查指南与生产级部署 Checklist

## 2026-06-09

- [LLM Function Calling：生产环境的工具集成模式](./2026-06-09-llm-function-calling-production-patterns.md) - 深入解析 Function Calling 核心机制与 Schema 设计原则，掌握 OpenAI/Anthropic/Google 多平台协议差异，涵盖并行调用优化、循环调用陷阱、敏感操作保护等 5 大常见坑排查指南，提供 Python 完整实现示例与生产级部署 Checklist

## 2026-06-08

- [React Server Components 实战：Streaming、Suspense Boundaries 与数据获取模式](./2026-06-08-react-server-components-streaming-suspense.md) - 深入理解 React Server Components 核心架构，掌握服务端流式渲染、Suspense Boundaries 精细控制与数据获取最佳实践，涵盖 async/await 直接获取/并行获取模式、电商产品页完整实现、bundle 膨胀/串行请求/CLS 布局偏移等 6 大常见坑排查指南与生产级部署 Checklist

## 2026-06-07

- [Sandbox 安全隔离：浏览器沙箱与云端沙箱的协同实践](./2026-06-07-sandbox-security-isolation.md) - 深入探讨浏览器沙箱（iframe/postMessage/CSP）与云端沙箱（Docker/轻量 VM）的协同实践，掌握前端代码隔离三重防护机制、容器沙箱安全配置（非 root/只读挂载/能力限制）、完整的前后端通信架构，含 iframe 沙箱组件、Docker 执行器、资源泄露防护等生产级示例与部署 Checklist

## 2026-06-06

- [CDN Internals & Cache Invalidation Strategies：内容分发网络的缓存机制与失效策略生产级实践](./2026-06-06-cdn-internals-cache-invalidation.md) - 深入解析 CDN 多层缓存架构（Edge/Regional/Origin）与 Cache-Key 构成逻辑，掌握 Cloudflare Workers/AWS CloudFront/阿里云 CDN 三大平台缓存配置，涵盖 TTL 管理、主动 Purge、版本化方案对比，提供查询参数碎片化/Vary 头缓存爆炸/Cookie 污染等 5 大常见坑排查指南与生产级部署 Checklist

## 2026-06-05

- [Cloud Native Security Posture：Pod Security Standards、Network Policies 与 OPA/Gatekeeper 生产级实践](./2026-06-05-cloud-native-security-pod-network-opa.md) - 构建 Kubernetes 运行时安全三层防御体系：PSS 基线阻止危险配置、Network Policies 实现网络微隔离、OPA/Gatekeeper 策略即代码统一治理，涵盖 privileged 容器逃逸防护、前端→后端→数据库流量隔离、镜像 registry 白名单等生产级场景，含完整 YAML 配置示例、测试脚本与部署 Checklist

## 2026-06-04

- [前端状态管理：从 Context 到 Signals 的现代模式对比](./2026-06-04-frontend-state-management-patterns.md) - 系统对比 React Context、Zustand、Jotai、Solid Signals 四大主流方案，深入解析核心原理与适用场景，提供电商购物车完整实现示例（3 种方案代码对比），涵盖过度重渲染/持久化兼容性/TypeScript 类型推断等 5 大常见坑排查指南与选型决策 Checklist

## 2026-06-03

- [API Gateway 生产级实战：鉴权、限流、灰度发布的完整实现](./2026-06-03-api-gateway-production-implementation.md) - 基于 Kong/Envoy 实现生产级 API Gateway，涵盖 JWT 鉴权配置、多级限流策略（全局/用户/API）、基于权重与 Header 的灰度发布方案，含 Docker Compose 本地开发与 Kubernetes 生产部署完整示例、监控告警规则配置、5 大常见坑排查指南与部署 Checklist

## 2026-06-02

- [Service Mesh Traffic Management：Istio 金丝雀发布与流量切分生产级实践](./2026-06-02-istio-traffic-management-canary.md) - 深入理解 Istio 流量管理核心资源（VirtualService/DestinationRule/Gateway），掌握基于权重的流量切分配置、基于 Header/Cookie 的精准路由，实现完整的金丝雀发布流程（5%→20%→50%→100%），涵盖连接池调优、异常检测配置、Envoy 配置同步排查与生产级部署 Checklist

## 2026-06-01

- [向量数据库选型与实战：RAG 系统的存储引擎](./2026-06-01-vector-database-rag-storage.md) - 深入理解向量数据库核心原理与选型方法，对比 ChromaDB/Qdrant/Weaviate/Milvus/Pinecone 五大主流方案，掌握 HNSW/IVF/PQ 索引调优、余弦相似度配置、批量插入优化，含 Python 完整实现示例、内存爆炸/维度不匹配/查询延迟排查指南与生产级部署 Checklist

## 2026-05-31

- [gRPC for Microservices：Protocol Buffers、Streaming 与负载均衡生产级实践](./2026-05-31-grpc-microservices-protobuf-streaming.md) - 深入理解 gRPC 高性能 RPC 框架核心机制，掌握 Protocol Buffers 接口定义、四种 streaming 模式（一元/服务端流/客户端流/双向流）、客户端负载均衡策略，涵盖 Node.js/TypeScript 完整实现示例、连接超时/内存泄漏/负载均衡排查指南与生产级部署 Checklist

## 2026-05-30

- [Microservices Patterns 实战：Saga、CQRS 与 Event Sourcing 的生产级实践](./2026-05-30-microservices-patterns-saga-cqrs-event-sourcing.md) - 深入理解分布式系统三大核心架构模式，掌握 Saga 分布式事务两种实现策略（编排式/编舞式）、CQRS 读写分离模型设计、Event Sourcing 事件溯源与快照优化，含 Node.js/TypeScript 完整代码示例与生产级部署 Checklist

## 2026-05-29

- [eBPF 云原生可观测性：无需改代码的深度监控](./2026-05-29-ebpf-cloud-native-observability.md) - 深入理解 eBPF 核心原理与云原生可观测性实践，掌握 bpftrace/bcc/Cilium Hubble 工具链，涵盖 HTTP 延迟追踪、TCP 连接分析、K8s 网络可视化完整示例，含内核兼容性、性能优化、权限配置等生产级排障指南

## 2026-05-28

- [Kubernetes Autoscaling 实战：HPA、VPA 与 KEDA 的生产级实践](./2026-05-28-kubernetes-autoscaling-hpa-vpa-keda.md) - 深入理解 Kubernetes 三大自动扩缩容机制，掌握基于 CPU/内存的 HPA 配置、垂直扩缩容 VPA 适用场景、以及基于事件的 KEDA 弹性方案，构建成本优化与高可用并重的生产级自动扩缩容体系

## 2026-05-27

- [GraphQL Subscriptions 实战：实时数据推送与 WebSocket 集成](./2026-05-27-graphql-subscriptions-realtime.md) - 深入理解 GraphQL Subscriptions 核心机制，掌握 Apollo Server + graphql-ws 生产级实现，涵盖连接认证、消息过滤、Redis PubSub 集成、断线重连与性能优化，含完整聊天系统示例代码与部署 Checklist

## 2026-05-26

- [边缘数据库与 Local-First 架构：Cloudflare D1/Turso 实战](./2026-05-26-edge-database-local-first-architecture.md) - 深入解析边缘数据库核心架构与 Local-First 设计原则，掌握 Cloudflare D1 + Workers 边缘博客系统完整实现、Turso 本地同步实战方案，涵盖写后读一致性、多设备冲突处理、连接数限制等生产级排障指南与部署 Checklist

## 2026-05-25

- [API Rate Limiting Algorithms：Token Bucket vs Leaky Bucket vs Sliding Window 实战对比](./2026-05-25-api-rate-limiting-algorithms.md) - 深入解析三种主流限流算法的核心原理、适用场景与生产级实现，涵盖 Redis 分布式限流、Nginx 配置实践与突发流量防护策略

## 2026-05-24

- [数据库迁移实战：生产环境零停机迁移策略](./2026-05-24-database-migration-zero-downtime.md) - 深入解析生产环境数据库 schema 变更的零停机迁移策略，涵盖扩展/收缩模式、向后兼容原则、数据双写迁移、在线 DDL 工具选型（gh-ost/pt-osc）与回滚方案设计，含 MySQL/PostgreSQL 完整示例与生产级迁移 Checklist

## 2026-05-23

- [Progressive Web Apps (PWA)：离线优先的渐进式应用实践](./2026-05-23-pwa-offline-first-progressive-apps.md) - 深入理解 PWA 三大核心技术（Service Worker/Web App Manifest/HTTPS），掌握缓存优先/网络优先/Stale-While-Revalidate 策略，含完整离线示例代码、iOS Safari 兼容性处理、缓存泄漏排查与生产级部署 Checklist

## 2026-05-22

- [LLM Prompt Engineering：结构化提示词与 Few-Shot 实践](./2026-05-22-llm-prompt-engineering-few-shot.md) - 系统掌握提示词工程核心方法论：结构化提示词设计框架（角色/任务/上下文/约束/格式）、Few-Shot Learning 原理与实践，含情感分析/代码生成完整示例、Python 测试脚本与生产级优化 Checklist

## 2026-05-21

- [数据库连接池实战：Serverless 与容器环境的连接管理](./2026-05-21-database-connection-pooling-serverless.md) - 解决云原生应用中最常见的性能瓶颈：数据库连接管理。深入理解连接池核心原理，掌握 Node.js/Python/Go 生产级配置，解决 Serverless 冷启动连接复用难题，含 RDS Proxy 集成方案、连接泄漏排查、Kubernetes 多 Pod 连接数爆炸防护与完整监控告警体系

## 2026-05-19

- [Secrets Management 云原生实践：从环境变量到 HashiCorp Vault](./2026-05-19-secrets-management-cloud-native.md) - 建立云原生密钥管理体系：Secrets 分级分类、Kubernetes External Secrets Operator 集成 AWS Secrets Manager、HashiCorp Vault 动态数据库凭证实战，涵盖 etcd 加密配置、令牌续期监控、多环境隔离等生产级方案与合规审计清单

## 2026-05-18

- [API 设计：REST vs GraphQL vs gRPC — 选型指南与实战对比](./2026-05-18-api-design-rest-graphql-grpc-comparison.md) - 深入对比三种主流 API 风格：REST 资源导向范式、GraphQL 按需查询方案、gRPC 高性能 RPC 框架，涵盖核心概念矩阵、Node.js 完整实现示例（Express/Apollo/gRPC-js）、N+1 查询/深度嵌套/Protobuf 兼容性等常见陷阱排查与生产级选型 Checklist

## 2026-05-17

- [Infrastructure as Code：Terraform 基础与最佳实践](./2026-05-17-infrastructure-as-code-terraform-basics.md) - 掌握 Terraform 声明式基础设施管理核心概念（Provider/Resource/State/Module），含 S3 存储桶完整示例（版本控制/加密/生命周期策略），涵盖状态锁冲突、敏感信息泄露、依赖顺序错误等常见排障场景与生产级部署清单

## 2026-05-16

- [WebAssembly 实战：浏览器与边缘计算的高性能方案](./2026-05-16-wasm-browser-edge-computing.md) - 深入理解 WASM 二进制格式与线性内存模型，掌握 Rust + wasm-pack 工具链，实现浏览器端图像实时滤镜处理（灰度/反色/模糊），性能提升 5-6 倍，涵盖边缘计算平台（Cloudflare Workers/Fastly）部署实践、内存泄漏排查与生产级 Checklist

## 2026-05-15

- [缓存策略全解析：Redis、CDN 与边缘缓存的高性能实践](./2026-05-15-caching-strategies-redis-cdn-edge.md) - 系统掌握三层缓存架构（Redis 应用层/CDN 静态资源/边缘计算），深入理解 Cache-Aside/Write-Through 一致性模型、穿透/击穿/雪崩防护策略，含 Node.js + ioredis 逻辑过期实现、Cloudflare Workers 边缘缓存、Nginx CDN 配置与生产级监控告警清单

## 2026-05-14

- [GitOps 实战：用 ArgoCD 实现 Kubernetes 持续部署](./2026-05-14-gitops-argocd-continuous-deployment.md) - 深入理解 GitOps 四大原则与 ArgoCD 架构，掌握声明式持续部署最佳实践，含 Kustomize 多环境配置、Image Updater 自动镜像更新、同步钩子（Sync Hooks）完整示例与生产级排查清单

## 2026-05-13

- [OAuth2 & OIDC 认证：从协议原理到生产级实践](./2026-05-13-oauth2-oidc-authentication-production.md) - 深入理解 OAuth2 授权框架与 OIDC 身份层核心差异，掌握授权码流程、JWT 验证、令牌刷新、PKCE 安全加固，含 Node.js + Keycloak 完整实现示例、多身份提供商集成方案与生产级排查清单

## 2026-05-12

- [AI Agents：构建自主任务执行器的工程实践](./2026-05-12-ai-agents-task-execution.md) - 从单轮对话到自主执行：掌握 AI Agent 核心架构（规划/记忆/工具调用）、ReAct 模式原理、LangChain 完整实现示例，涵盖网页搜索/代码计算/文件读写工具、无限循环排查、安全加固策略与生产级监控清单

## 2026-05-11

- [前端性能优化：Core Web Vitals 实战指南](./2026-05-11-core-web-vitals-optimization.md) - 深入理解 LCP/INP/CLS 三大核心指标：掌握 Web Vitals 库监控、Lighthouse 性能审计、图片预加载/懒加载优化、长任务拆分与 Web Worker 实践，涵盖字体加载 CLS 优化、性能预算 CI 集成、真实用户监控 (RUM) 与告警体系

## 2026-05-10

- [Testing Pyramid 实战：E2E、集成测试与单元测试的正确分层](./2026-05-10-testing-pyramid-e2e-integration-unit.md) - 建立科学的测试分层体系：掌握测试金字塔核心原则（70% 单元/20% 集成/10% E2E），使用 Vitest/Testing Library/Playwright 编写高质量测试，涵盖 Testcontainers 集成测试、E2E 稳定性优化、常见测试陷阱排查与生产级配置清单

## 2026-05-09

- [WebSocket 实时通信实战：从协议原理到生产级架构](./2026-05-09-websocket-realtime-communication.md) - 深入理解 WebSocket 全双工通信协议：握手流程、数据帧结构、心跳保活机制，掌握 Node.js + ws 库生产级实现，涵盖连接管理、断线重连、Nginx 反向代理配置与安全加固清单

## 2026-05-08

- [Message Queues 异步处理实战：Kafka vs RabbitMQ vs Redis Streams](./2026-05-08-message-queues-async-processing.md) - 深入对比三种主流消息队列架构：RabbitMQ 经典队列、Kafka 分布式日志流、Redis Streams 轻量流处理，涵盖选型决策矩阵、Node.js 完整集成示例、消息丢失/重复/积压排查指南与生产级配置清单

## 2026-05-07

- [Container Networking & Service Mesh 基础：从 Docker 网络到 Istio 服务网格](./2026-05-07-container-networking-service-mesh-basics.md) - 深入理解容器网络模型：Docker bridge/overlay 网络、Kubernetes CNI/Service/NetworkPolicy、Istio 服务网格流量治理，含网络隔离测试、灰度发布配置示例与故障排查清单

## 2026-05-06

- [Feature Flags 与 A/B 测试基础设施：从灰度发布到数据驱动决策](./2026-05-06-feature-flags-ab-testing-infrastructure.md) - 构建生产级功能开关体系：OpenFeature 标准、Flagd 服务部署、一致性哈希算法、A/B 测试统计分析，含 React SDK 集成、Docker Compose 完整部署示例与实验效果分析实战

## 2026-05-05

- [LLM Ops：模型服务化与推理优化实战](./2026-05-05-llm-ops-model-serving-inference.md) - 从实验到生产：掌握 vLLM/TGI/TensorRT-LLM 推理框架选型、KV Cache 优化、量化部署、并发批处理，含 Docker Compose 完整部署示例与 OpenAI 兼容 API 调用指南

## 2026-05-04

- [OpenTelemetry 全栈可观测性：Metrics、Tracing、Logging 统一实践](./2026-05-04-opentelemetry-fullstack-observability.md) - 构建统一可观测性体系：OpenTelemetry 核心架构、Node.js/前端埋点实战、Collector 配置与数据导出，含 Docker Compose 完整部署示例与 Trace-Log 关联方案

## 2026-05-03

- [容器安全：镜像扫描、运行时防护与供应链安全](./2026-05-03-container-security-scanning-supply-chain.md) - 建立完整的容器安全防线：Trivy 漏洞扫描、Cosign 镜像签名验证、Kubernetes 安全上下文配置、NetworkPolicy 网络隔离，含 CI/CD 安全门禁实战与供应链安全最佳实践

## 2026-05-02

- [边缘计算实战：Cloudflare Workers 与 Deno Deploy 对比与迁移指南](./2026-05-02-edge-computing-workers-deno-migration.md) - 边缘计算平台深度对比：Cloudflare Workers vs Deno Deploy，涵盖运行时差异、部署流程、定价模型，含边缘 API 网关完整实现（请求转换 + 地理围栏 + 限流）与双向迁移指南

## 2026-05-01

- [API Gateway 进阶：熔断、重试与超时策略的生产级实践](./2026-05-01-api-gateway-circuit-breaker-retry-timeout.md) - 从基础限流鉴权到高可用架构：掌握熔断器模式（Closed/Open/Half-Open）、指数退避重试、分层超时控制，含 Kong/Envoy 配置示例与 Node.js 完整实现，附重试风暴防护与幂等性设计指南

## 2026-04-30

- [Serverless 容器平台：Cloud Run / Fargate 的零运维部署实践](./2026-04-30-serverless-container-cloud-run-fargate.md) - 从 K8s 运维复杂度中解脱，掌握 Cloud Run 和 Fargate 的架构差异、部署实战与生产级最佳实践，含冷启动优化、数据库连接池、VPC 集成等完整解决方案

## 2026-04-29

- [AI 工程化：RAG 的数据切分、召回与评测](./2026-04-29-ai-rag-chunking-retrieval-eval.md) - 深入 RAG 系统核心：递归切分策略、向量检索优化、Prompt 设计要点，含 LangChain + FAISS 完整可运行示例与性能调优指南

## 2026-04-28

- [API Gateway：鉴权、限流、灰度发布的实现思路](./2026-04-28-api-gateway-auth-rate-limit-canary-practice.md) - Kong Gateway 生产级实践：JWT 鉴权、令牌桶限流、灰度发布流量分流，含完整 Docker 部署示例与故障排查清单

## 2026-04-27

- [Kubernetes 入门：Deployment/Service/Ingress 的最小闭环](./2026-04-27-k8s-minimal-loop-complete.md) - 深入理解 K8s 三大核心资源对象，通过完整示例跑通应用部署、服务发现与 HTTP 路由的完整闭环，含故障排查清单与最佳实践

## 2026-04-26

- [实战入门：用 Docker 构建镜像，并在 Kubernetes 通过 Deployment/Service/Ingress 跑通最小闭环](./2026-04-26-docker-k8s-hands-on.md) - 30 分钟跑通云原生最小闭环：Docker 镜像构建、K8s Deployment/Service/Ingress 完整配置，含 Node.js 应用示例与故障排查清单

## 2026-04-25

- [从 Docker 到 Kubernetes：Deployment/Service/Ingress 的最小闭环](./2026-04-25-docker-to-k8s-loop.md) - 从零跑通 K8s 部署完整链路：Docker 镜像构建、Deployment 副本管理、Service 服务发现、Ingress 对外暴露，含 Node.js 应用完整示例与排查清单

## 2026-04-24

- [容器基础：镜像分层、构建缓存与多阶段 Dockerfile](./2026-04-24-docker-multistage-build.md) - 深入理解 Docker 镜像分层机制，掌握构建缓存策略与多阶段构建技术，将生产镜像体积缩小 50%-90%，含 Node.js/Go 完整优化示例与排查清单

## 2026-04-23

- [容器与 Kubernetes 入门：Docker + Deployment/Service/Ingress 的最小闭环](./2026-04-23-k8s-minimal-loop.md) - 从零跑通 K8s 部署完整链路：Docker 镜像构建、Deployment 副本管理、Service 服务发现、Ingress 对外暴露，含 Node.js 应用完整示例与排查清单

## 2026-04-22

- [Sandbox 组合实践：浏览器隔离与云端沙箱的协同](./2026-04-22-sandbox-combined-practice.md) - 分层沙箱架构实战：前端 iframe+CSP 快速过滤 + 云端容器强隔离执行，含在线代码编辑器完整示例与安全检查清单

## 2026-04-21

- [Next.js App Router：缓存、ISR 与 revalidate 的正确用法](./2026-04-21-nextjs-app-router-cache.md) - 深入理解 Next.js App Router 三层缓存架构，掌握 ISR 增量静态再生与 revalidate 配置策略，含商品列表缓存、按需刷新、复杂计算缓存三大实战示例

## 2026-04-20

- [CI/CD：工程化能力，自动化流水线建设](./2026-04-20-ci-cd-pipeline-automation.md) - 掌握 GitHub Actions CI/CD 流水线构建，涵盖代码检查、单元测试、镜像构建、多环境部署全流程，含完整 YAML 配置与质量门禁实践

## 2026-04-19

- [Bun + Node 工具链：性能与兼容性对比](./2026-04-19-bun-node-toolchain-comparison.md) - 深入对比 Bun 与 Node.js 运行时性能差异，涵盖启动速度、依赖安装、测试运行等核心场景，含 HTTP 服务器性能对比实战与兼容性配置指南

## 2026-04-18

- [Web Worker/Service Worker：离线与并行计算实践](./2026-04-18-web-worker-service-worker.md) - 掌握 Web Worker 并行计算与 Service Worker 离线缓存策略，构建高性能 PWA 应用，含大数据排序、离线缓存、组合使用三大实战示例

## 2026-04-17

- [前端可观测性：Sentry/ARMS 的错误聚合与告警降噪](./2026-04-17-frontend-observability-sentry-arms.md) - 深入理解前端监控核心机制，掌握 Sentry/ARMS 错误聚合策略，建立可持续的告警降噪方案，含完整接入示例与排查清单

## 2026-04-16

- [AI 工程化：RAG 的数据切分、召回与评测](./2026-04-16-ai-rag-data-chunking-retrieval-eval.md) - 深入 RAG 系统三大核心环节：数据切分策略、混合检索优化、效果评测体系，含 LangChain + ChromaDB 完整可运行示例

## 2026-04-15

- [API Gateway：鉴权、限流、灰度发布的实现思路](./2026-04-15-api-gateway-auth-rate-limit-canary.md) - 基于 Node.js + Express 实现生产级 API 网关，涵盖 JWT 鉴权、令牌桶限流、灰度发布三大核心能力，含完整可运行代码

## 2026-04-14

- [Kubernetes 入门：Deployment/Service/Ingress 的最小闭环](./2026/2026-04-14-k8s-deployment-service-ingress.md) - 深入理解 K8s 三大核心资源，用最小配置跑通应用部署、服务发现与对外暴露的完整闭环

## 2026-04-13

- [实战入门：用 Docker 构建镜像，并在 Kubernetes 通过 Deployment/Service/Ingress 跑通最小闭环](./2026-04-13-docker-k8s-hands-on.md) - 完整的 Node.js 应用容器化并部署到 K8s 的实战指南，包含 Dockerfile、Deployment、Service、Ingress 配置

## 2026-04-12

- [从 Docker 到 Kubernetes：Deployment/Service/Ingress 的最小闭环](./2026-04-12-docker-to-k8s.md) - 用最小可运行示例演示从 Docker 镜像到 K8s 对外服务的完整链路

## 2026-04-11

- [容器基础：镜像分层、构建缓存与多阶段 Dockerfile](./2026/2026-04-11-docker-multistage-build.md) - 掌握 Dockerfile 优化技巧，将镜像体积减少 50%-90%

## 2026-04-10

- [容器与 Kubernetes 入门：Docker + Deployment/Service/Ingress 的最小闭环](./2026/2026-04-10-k8s-minimal-loop.md) - 快速跑通从 Docker 镜像到 K8s 部署的完整链路

## 2026-04-09

- [前端 Sandbox：iframe / postMessage / CSP 的组合实践](./2026/2026-04-09-frontend-sandbox.md) - 掌握前端安全隔离的组合方案

## 2026-04-08

- [Next.js 14 Server Components 实战](./2026/2026-04-08-nextjs-server-components.md) - 深入理解 React Server Components 在 Next.js 中的应用

---

*自动更新，最后生成时间：2026-05-21*
