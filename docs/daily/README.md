# 每日技术文档索引

按时间倒序排列的技术文档。

---

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

*自动更新，最后生成时间：2026-05-14*
