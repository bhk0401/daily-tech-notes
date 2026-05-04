# OpenTelemetry 全栈可观测性：Metrics、Tracing、Logging 统一实践

> 日期：2026-05-04 | 领域：云原生可观测性/分布式追踪 | 字数：约 3200 字

## 背景与目标

在现代微服务和云原生架构中，可观测性（Observability）已成为保障系统稳定性的核心能力。根据 CNCF 2025 年调查报告，89% 的生产环境 Kubernetes 集群采用了某种形式的可观测性方案，但其中 67% 的团队仍在使用多套独立工具（Prometheus + Jaeger + ELK），导致数据孤岛、关联分析困难和维护成本高昂。

OpenTelemetry（OTel）作为 CNCF 孵化项目，旨在提供一套统一的、厂商中立的可观测性数据收集标准，覆盖三大支柱：

1. **Metrics（指标）**：系统性能度量（CPU、内存、请求延迟、错误率）
2. **Tracing（追踪）**：分布式请求链路追踪，定位跨服务调用瓶颈
3. **Logging（日志）**：结构化日志收集与关联

本文旨在帮助开发者和 SRE 工程师建立统一的可观测性体系，通过 OpenTelemetry 实现：
- 一次埋点，多后端导出（Prometheus、Jaeger、Datadog 等）
- 自动关联 TraceID 贯穿日志、指标、追踪
- 零侵入或低侵入的自动埋点方案
- 从前端到后端的全链路追踪能力

通过本文，你将掌握：
- OpenTelemetry 核心概念与架构设计
- 后端服务（Node.js/Go/Python）的手动与自动埋点
- 前端（Web/Browser）追踪集成
- 配置 OTel Collector 进行数据聚合与导出
- 实战：构建完整的可观测性 Demo 系统

## 核心概念

### OpenTelemetry 架构组件

OpenTelemetry 由以下核心组件构成：

| 组件 | 职责 | 部署方式 |
|------|------|---------|
| **API** | 语言无关的接口定义 | 代码依赖库 |
| **SDK** | API 的具体实现 | 代码依赖库 |
| **Collector** | 数据接收、处理、导出 | 独立服务（Daemon/Sidecar） |
| **Auto-Instrumentation** | 自动埋点（无需改代码） | Java Agent / eBPF |

### 数据模型：Trace、Span、Context

理解 OTel 的数据模型是有效埋点的关键：

- **Trace（追踪）**：一个完整请求的生命周期，由唯一 TraceID 标识
- **Span（跨度）**：Trace 中的单个操作单元（如 HTTP 请求、DB 查询），包含：
  - SpanID：唯一标识
  - ParentSpanID：指向父 Span，形成树状结构
  - StartTime/EndTime：持续时间
  - Attributes：键值对元数据（HTTP 方法、状态码、DB 语句）
  - Events：时间戳标记的事件（如"重试开始"、"缓存命中"）
  - Status：OK/ERROR + 错误信息
- **Context（上下文）**：在进程内传递 Trace 信息的载体，支持跨线程/异步传播

### 传播格式（Propagation）

分布式追踪依赖上下文在 service 间传递，OTel 支持多种传播格式：

- **W3C Trace Context**（推荐）：`traceparent` + `tracestate` 头部
- **B3**（Zipkin 兼容）：`X-B3-TraceId`、`X-B3-SpanId`、`X-B3-Sampled`
- **Jaeger**：`uber-trace-id` 头部

**W3C 示例**：
```
traceparent: 00-0af7651916cd43dd8448eb211c80319c-b7ad6b7169203331-01
             │  │──────────────────────────────│ │──────────────│ │
             │  │         TraceID              │    SpanID      │ Flags
             Version
```

### OTel Collector 管道模型

Collector 是 OTel 的数据枢纽，采用 Pipeline 架构：

```
Receivers → Processors → Exporters
   │           │            │
   │           │            └─> Prometheus/Jaeger/Datadog
   │           └─> 采样/聚合/ enrichment
   └─> OTLP/gRPC, OTLP/HTTP, Jaeger, Zipkin
```

- **Receivers**：接收数据（OTLP、Jaeger、Zipkin、Prometheus）
- **Processors**：处理数据（Batch、MemoryLimiter、ProbabilisticSampler、Resource）
- **Exporters**：导出数据到后端存储

## 实战/示例

### 示例 1：Node.js 后端手动埋点

```bash
# 安装依赖
npm install @opentelemetry/api @opentelemetry/sdk-node @opentelemetry/exporter-trace-otlp-http @opentelemetry/instrumentation-http
```

```javascript
// tracing.js - 初始化 OTel SDK
const { NodeSDK } = require('@opentelemetry/sdk-node');
const { OTLPTraceExporter } = require('@opentelemetry/exporter-trace-otlp-http');
const { HttpInstrumentation } = require('@opentelemetry/instrumentation-http');
const { Resource } = require('@opentelemetry/resources');
const { SEMRESATTRS_SERVICE_NAME } = require('@opentelemetry/semantic-conventions');

const sdk = new NodeSDK({
  resource: new Resource({
    [SEMRESATTRS_SERVICE_NAME]: 'order-service',
    'deployment.environment': 'production',
  }),
  traceExporter: new OTLPTraceExporter({
    url: 'http://otel-collector:4318/v1/traces', // Collector HTTP endpoint
  }),
  instrumentations: [
    new HttpInstrumentation({
      ignoreIncomingRequestHook: (req) => req.url?.startsWith('/health'),
      requireParentforOutgoingSpans: false,
    }),
  ],
});

sdk.start();

// 优雅关闭时刷新数据
process.on('SIGTERM', () => {
  sdk.shutdown().then(() => process.exit(0));
});
```

```javascript
// app.js - 业务代码中创建自定义 Span
const api = require('@opentelemetry/api');
const tracer = api.trace.getTracer('order-service');

app.post('/api/orders', async (req, res) => {
  const span = tracer.startSpan('createOrder');
  
  try {
    // 设置 Span 属性
    span.setAttribute('order.userId', req.body.userId);
    span.setAttribute('order.totalAmount', req.body.totalAmount);
    
    // 模拟数据库操作（自动被 HttpInstrumentation 捕获）
    const order = await db.orders.create(req.body);
    
    // 添加事件标记
    span.addEvent('order.created', { orderId: order.id });
    
    // 调用下游服务（自动继承 TraceContext）
    await fetch('http://payment-service/charge', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ orderId: order.id, amount: req.body.totalAmount }),
    });
    
    span.setStatus({ code: api.SpanStatusCode.OK });
    res.json({ success: true, orderId: order.id });
  } catch (error) {
    span.setStatus({ code: api.SpanStatusCode.ERROR, message: error.message });
    span.recordException(error);
    throw error;
  } finally {
    span.end();
  }
});
```

### 示例 2：前端（Web）自动埋点

```html
<!-- index.html -->
<script>
  window.OTEL_CONFIG = {
    serviceName: 'web-frontend',
    collectorUrl: 'https://otel-collector.example.com/v1/traces',
    sampleRate: 0.1, // 10% 采样率
  };
</script>
<script src="https://cdn.jsdelivr.net/npm/@opentelemetry/instrumentation-web-vitals@0.40.0/build/src/web-vitals.js"></script>
<script src="https://cdn.jsdelivr.net/npm/@opentelemetry/instrumentation-fetch@0.40.0/build/src/fetch.js"></script>
<script src="https://cdn.jsdelivr.net/npm/@opentelemetry/instrumentation-xml-http-request@0.40.0/build/src/xml-http-request.js"></script>
```

```javascript
// tracing-web.js - 前端初始化
import { WebTracerProvider } from '@opentelemetry/sdk-trace-web';
import { BatchSpanProcessor } from '@opentelemetry/sdk-trace-base';
import { OTLPTraceExporter } from '@opentelemetry/exporter-trace-otlp-http';
import { registerInstrumentations } from '@opentelemetry/instrumentation';
import { FetchInstrumentation } from '@opentelemetry/instrumentation-fetch';
import { UserInteractionInstrumentation } from '@opentelemetry/instrumentation-user-interaction';

const provider = new WebTracerProvider({
  resource: new Resource({
    'service.name': 'web-frontend',
    'deployment.environment': 'production',
  }),
});

provider.addSpanProcessor(
  new BatchSpanProcessor(
    new OTLPTraceExporter({ url: window.OTEL_CONFIG.collectorUrl }),
    { batchTimeout: 5000 }
  )
);

provider.register();

registerInstrumentations({
  instrumentations: [
    new FetchInstrumentation({
      propagateTraceHeaderCorsUrls: ['https://api.example.com'],
      ignoreUrls: [/localhost/, /health/],
    }),
    new UserInteractionInstrumentation(), // 捕获点击事件
  ],
});

// 手动创建 Span（如页面加载）
const tracer = provider.getTracer('web-frontend');
const span = tracer.startSpan('page-load');
span.setAttribute('page.url', window.location.href);
span.setAttribute('page.referrer', document.referrer);
span.end();
```

### 示例 3：OTel Collector 配置

```yaml
# otel-collector-config.yaml
receivers:
  otlp:
    protocols:
      grpc:
        endpoint: 0.0.0.0:4317
      http:
        endpoint: 0.0.0.0:4318
  
  prometheus:
    config:
      scrape_configs:
        - job_name: 'otel-collector'
          scrape_interval: 10s
          static_configs:
            - targets: ['otel-collector:8888']

processors:
  batch:
    timeout: 1s
    send_batch_size: 1024
  
  memory_limiter:
    check_interval: 1s
    limit_mib: 1000
    spike_limit_mib: 200
  
  probabilistic_sampler:
    sampling_percentage: 10  # 10% 采样率
  
  resource:
    attributes:
      - key: deployment.environment
        value: production
        action: upsert

exporters:
  otlp/jaeger:
    endpoint: jaeger:4317
    tls:
      insecure: true
  
  prometheusremotewrite:
    endpoint: "http://prometheus:9090/api/v1/write"
  
  logging:
    verbosity: detailed

service:
  pipelines:
    traces:
      receivers: [otlp]
      processors: [memory_limiter, batch, probabilistic_sampler]
      exporters: [otlp/jaeger, logging]
    
    metrics:
      receivers: [otlp, prometheus]
      processors: [memory_limiter, batch]
      exporters: [prometheusremotewrite, logging]
    
    logs:
      receivers: [otlp]
      processors: [memory_limiter, batch]
      exporters: [logging]
```

### 示例 4：Docker Compose 完整部署

```yaml
# docker-compose.yml
version: '3.8'

services:
  otel-collector:
    image: otel/opentelemetry-collector-contrib:0.95.0
    command: ['--config=/etc/otel-collector-config.yaml']
    volumes:
      - ./otel-collector-config.yaml:/etc/otel-collector-config.yaml
    ports:
      - "4317:4317"  # OTLP gRPC
      - "4318:4318"  # OTLP HTTP
      - "8888:8888"  # Prometheus metrics
    depends_on:
      - jaeger
      - prometheus

  jaeger:
    image: jaegertracing/all-in-one:1.55
    ports:
      - "16686:16686"  # UI
      - "4317:4317"    # OTLP gRPC
    environment:
      - COLLECTOR_OTLP_ENABLED=true

  prometheus:
    image: prom/prometheus:v2.50.0
    ports:
      - "9090:9090"
    volumes:
      - ./prometheus.yml:/etc/prometheus/prometheus.yml
      - prometheus_data:/prometheus

  grafana:
    image: grafana/grafana:10.3.0
    ports:
      - "3000:3000"
    environment:
      - GF_SECURITY_ADMIN_PASSWORD=admin
    volumes:
      - grafana_data:/var/lib/grafana
      - ./grafana-datasources.yml:/etc/grafana/provisioning/datasources/datasources.yml

  # Demo 应用
  order-service:
    build: ./order-service
    environment:
      - OTEL_EXPORTER_OTLP_ENDPOINT=http://otel-collector:4318
      - OTEL_SERVICE_NAME=order-service
    depends_on:
      - otel-collector

volumes:
  prometheus_data:
  grafana_data:
```

### 示例 5：日志与 Trace 关联

```javascript
// 使用 pino + OTel 实现日志关联
const pino = require('pino');
const api = require('@opentelemetry/api');

const logger = pino({
  mixin() {
    const span = api.trace.getSpan(api.context.active());
    if (!span) return {};
    
    const spanContext = span.spanContext();
    return {
      trace_id: spanContext.traceId,
      span_id: spanContext.spanId,
      trace_flags: spanContext.traceFlags,
    };
  },
});

// 日志输出自动包含 TraceID
logger.info({ userId: 123 }, 'Order created');
// 输出：{"level":30,"time":1714800000000,"trace_id":"0af7651916cd43dd8448eb211c80319c","span_id":"b7ad6b7169203331","userId":123,"msg":"Order created"}
```

## 常见坑与排查

### 坑 1：Trace 数据不完整（断链）

**问题**：下游服务的 Span 没有关联到上游 Trace，形成孤立的 Trace。

**排查步骤**：
```bash
# 1. 检查传播头是否正确传递
curl -v http://order-service/api/orders \
  -H "traceparent: 00-0af7651916cd43dd8448eb211c80319c-b7ad6b7169203331-01"

# 2. 确认下游服务提取了上下文
# Node.js: 检查是否调用了 api.propagation.extract()
# Go: 检查是否使用了 propagation.ExtractHTTP()

# 3. 验证 Collector 收到数据
docker logs otel-collector | grep -i "trace"
```

**解决方案**：
```javascript
// 确保 HTTP 客户端自动传播上下文（HttpInstrumentation 已内置）
// 手动传播示例：
const propagation = api.propagation;
const headers = {};
propagation.inject(api.context.active(), headers);
// headers 现在包含 traceparent，添加到下游请求
```

### 坑 2：采样率过高导致存储爆炸

**问题**：生产环境 100% 采样，Jaeger/Prometheus 存储迅速占满。

**解决方案**：
```yaml
# Collector 配置概率采样
processors:
  probabilistic_sampler:
    sampling_percentage: 5  # 5% 采样
  
  # 或基于 TraceID 的一致性采样（同一 Trace 要么全采要么不采）
  probabilistic_sampler:
    hash_seed: 42
    sampling_percentage: 10

# 或基于 QPS 的尾部采样（高级）
  tail_sampling:
    decision_wait: 10s
    num_traces: 10000
    policies:
      - name: error-policy
        type: status_code
        status_code:
          status_codes: [ERROR]
      - name: slow-policy
        type: latency
        latency:
          threshold_ms: 1000
```

### 坑 3：CORS 问题导致前端数据无法上报

**问题**：浏览器控制台报错 `Access-Control-Allow-Origin`，Trace 数据无法发送到 Collector。

**排查**：
```bash
# 检查 Collector 是否配置 CORS
curl -v -X OPTIONS https://otel-collector.example.com/v1/traces \
  -H "Origin: https://your-frontend.com" \
  -H "Access-Control-Request-Method: POST"
```

**解决方案**：
```yaml
# Collector 配置 CORS
receivers:
  otlp:
    protocols:
      http:
        endpoint: 0.0.0.0:4318
        cors:
          allowed_origins:
            - https://your-frontend.com
            - https://*.your-domain.com
          allowed_headers:
            - Content-Type
            - traceparent
            - tracestate
```

### 坑 4：资源属性未正确设置

**问题**：Jaeger/Grafana 中无法按服务名过滤 Trace。

**排查**：
```bash
# 检查 SDK 初始化时的 Resource 配置
# Node.js 示例
const sdk = new NodeSDK({
  resource: new Resource({
    [SEMRESATTRS_SERVICE_NAME]: 'order-service', // 必须使用语义约定
  }),
});

# 验证导出的数据
docker logs otel-collector | grep "service.name"
```

**常见错误**：
```javascript
// ❌ 错误：使用自定义键名
resource: { serviceName: 'order-service' }

// ✅ 正确：使用语义约定常量
resource: { [SEMRESATTRS_SERVICE_NAME]: 'order-service' }
```

## Checklist

### SDK 初始化
- [ ] 配置正确的 Service Name（使用语义约定）
- [ ] 设置 Deployment Environment（dev/staging/production）
- [ ] 配置 OTLP Exporter 地址（Collector endpoint）
- [ ] 添加优雅关闭逻辑（SDK.shutdown()）
- [ ] 配置合适的采样率（生产环境建议 1-10%）

### 埋点实践
- [ ] 为关键业务操作创建自定义 Span
- [ ] 设置有意义的 Span 名称（动词 + 名词，如 `createOrder`）
- [ ] 添加业务相关的 Attributes（避免 PII 敏感数据）
- [ ] 记录异常事件（span.recordException()）
- [ ] 确保异步操作正确传递 Context

### 前端追踪
- [ ] 配置 CORS 允许前端上报
- [ ] 使用 BatchSpanProcessor 批量发送（减少网络请求）
- [ ] 忽略健康检查等噪音请求
- [ ] 捕获 Web Vitals 指标（LCP、FID、CLS）
- [ ] 关联用户交互事件（点击、导航）

### Collector 配置
- [ ] 启用 MemoryLimiter 防止 OOM
- [ ] 配置 BatchProcessor 优化吞吐
- [ ] 设置合理的采样策略（概率/尾部采样）
- [ ] 验证 Exporter 连接（Jaeger/Prometheus）
- [ ] 开启 Logging Exporter 调试（仅开发环境）

### 后端存储
- [ ] Jaeger 配置保留策略（默认 72h）
- [ ] Prometheus 配置存储大小限制
- [ ] 配置告警规则（错误率 > 1%、P99 延迟 > 1s）
- [ ] Grafana 配置标准 Dashboard（延迟、错误、流量、饱和度）

### 安全与合规
- [ ] 不在 Attributes 中记录 PII（个人身份信息）
- [ ] 生产环境禁用 Logging Exporter
- [ ] Collector 启用 TLS（生产环境）
- [ ] 配置访问控制（仅允许信任服务上报）

## 参考资料

1. **OpenTelemetry 官方文档** - 完整的 API、SDK、Collector 指南  
   https://opentelemetry.io/docs/

2. **OpenTelemetry 语义约定** - 标准化的属性和 Span 命名  
   https://opentelemetry.io/docs/specs/semconv/

3. **CNCF OpenTelemetry 深度指南** - 架构设计与最佳实践  
   https://www.cncf.io/blog/2023/09/05/opentelemetry-deep-dive/

4. **OpenTelemetry Collector 配置参考**  
   https://github.com/open-telemetry/opentelemetry-collector-contrib

5. **Jaeger 官方文档** - 分布式追踪后端  
   https://www.jaegertracing.io/docs/

6. **Google SRE 可观测性章节** - 监控、告警、可视化最佳实践  
   https://sre.google/sre-book/monitoring-distributed-systems/

---

*本文档由自动化流程生成 | GitHub: https://github.com/bhk0401/daily-tech-notes*
