# Prometheus + Grafana：云原生指标监控生产实践

## 背景与目标

在现代云原生架构中，可观测性（Observability）已成为系统稳定运行的基石。可观测性三大支柱——日志（Logging）、链路追踪（Tracing）和指标（Metrics）——各自承担着不同的监控职责。本文聚焦于**指标监控**，深入探讨 Prometheus + Grafana 这一事实标准的云原生监控组合在生产环境中的最佳实践。

Prometheus 作为 CNCF 毕业项目，以其强大的多维度数据模型、灵活的查询语言 PromQL 和原生 Kubernetes 集成能力，成为了云原生监控的首选。Grafana 则以其丰富的可视化能力和灵活的告警配置，为监控数据提供了直观的展示窗口。

**本文目标**：
- 理解 Prometheus 的核心架构和数据模型
- 掌握 PromQL 查询语言的核心用法
- 学会配置生产级别的监控和告警
- 规避常见的监控陷阱和性能问题
- 提供可直接复用的配置示例和 Checklists

通过本文，你将能够搭建一套完整的、生产就绪的指标监控系统，为你的云原生应用提供可靠的监控保障。

## 核心概念

### Prometheus 架构组件

Prometheus 采用拉取（Pull）模型收集指标，其核心组件包括：

1. **Prometheus Server**：核心服务，负责抓取和存储时间序列数据
2. **Exporters**：将第三方系统指标暴露为 Prometheus 格式
3. **Pushgateway**：支持短期任务的指标推送
4. **Alertmanager**：处理告警路由、去重、静默和分组
5. **Service Discovery**：自动发现 Kubernetes、Consul 等服务目标

### 数据模型：四维一体

Prometheus 的数据模型由四个核心概念构成：

```
指标名称 {标签键="标签值", ...} → 时间序列值
```

- **指标名称（Metric Name）**：描述测量内容，如 `http_requests_total`
- **标签（Labels）**：维度标识，如 `method="POST"`, `status="200"`
- **时间戳（Timestamp）**：UTC 毫秒时间戳
- **样本值（Sample Value）**：浮点数测量值

### 指标类型详解

| 类型 | 说明 | 典型场景 |
|------|------|----------|
| Counter | 单调递增计数器 | 请求总数、错误计数 |
| Gauge | 可增减的瞬时值 | CPU 使用率、内存占用 |
| Histogram | 分布统计（桶） | 请求延迟、响应大小 |
| Summary | 分位数统计 | 延迟的 P95/P99 |

### PromQL 核心语法

PromQL 是 Prometheus 的查询语言，掌握其核心语法是有效监控的关键：

```promql
# 基础查询
http_requests_total

# 带标签过滤
http_requests_total{method="POST", status=~"5.."}

# 速率计算（最重要！）
rate(http_requests_total[5m])

# 聚合操作
sum(rate(http_requests_total[5m])) by (service)

# 同比/环比
http_requests_total / http_requests_total offset 1h
```

**关键原则**：Counter 类型指标必须配合 `rate()` 或 `increase()` 使用，否则无法正确反映变化趋势。

## 实战/示例

### 示例 1：Kubernetes 集群监控配置

以下是一个生产级别的 Prometheus 配置示例，覆盖 Kubernetes 核心组件监控：

```yaml
# prometheus-config.yaml
global:
  scrape_interval: 15s
  evaluation_interval: 15s
  external_labels:
    cluster: 'production'
    region: 'us-east-1'

alerting:
  alertmanagers:
    - static_configs:
        - targets: ['alertmanager:9093']

rule_files:
  - /etc/prometheus/rules/*.yaml

scrape_configs:
  # Prometheus 自监控
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']

  # Kubernetes API Server
  - job_name: 'kubernetes-apiservers'
    kubernetes_sd_configs:
      - role: endpoints
    scheme: https
    tls_config:
      ca_file: /var/run/secrets/kubernetes.io/serviceaccount/ca.crt
    bearer_token_file: /var/run/secrets/kubernetes.io/serviceaccount/token
    relabel_configs:
      - source_labels: [__meta_kubernetes_namespace, __meta_kubernetes_service_name, __meta_kubernetes_endpoint_port_name]
        action: keep
        regex: default;kubernetes;https

  # Kubernetes Nodes
  - job_name: 'kubernetes-nodes'
    scheme: https
    tls_config:
      ca_file: /var/run/secrets/kubernetes.io/serviceaccount/ca.crt
    bearer_token_file: /var/run/secrets/kubernetes.io/serviceaccount/token
    kubernetes_sd_configs:
      - role: node
    relabel_configs:
      - action: labelmap
        regex: __meta_kubernetes_node_label_(.+)

  # Kubernetes Pods
  - job_name: 'kubernetes-pods'
    kubernetes_sd_configs:
      - role: pod
    relabel_configs:
      - source_labels: [__meta_kubernetes_pod_annotation_prometheus_io_scrape]
        action: keep
        regex: true
      - source_labels: [__meta_kubernetes_pod_annotation_prometheus_io_path]
        action: replace
        target_label: __metrics_path__
        regex: (.+)
      - source_labels: [__address__, __meta_kubernetes_pod_annotation_prometheus_io_port]
        action: replace
        regex: ([^:]+)(?::\d+)?;(\d+)
        replacement: $1:$2
        target_label: __address__

  # Application metrics
  - job_name: 'app-metrics'
    kubernetes_sd_configs:
      - role: pod
    relabel_configs:
      - source_labels: [__meta_kubernetes_pod_label_app]
        action: keep
        regex: .+
```

### 示例 2：核心告警规则

```yaml
# alert-rules.yaml
groups:
  - name: application-alerts
    rules:
      # 高错误率告警
      - alert: HighErrorRate
        expr: sum(rate(http_requests_total{status=~"5.."}[5m])) by (service) / sum(rate(http_requests_total[5m])) by (service) > 0.05
        for: 5m
        labels:
          severity: critical
        annotations:
          summary: "服务 {{ $labels.service }} 错误率超过 5%"
          description: "当前错误率：{{ $value | humanizePercentage }}"

      # 高延迟告警
      - alert: HighLatency
        expr: histogram_quantile(0.95, sum(rate(http_request_duration_seconds_bucket[5m])) by (le, service)) > 0.5
        for: 10m
        labels:
          severity: warning
        annotations:
          summary: "服务 {{ $labels.service }} P95 延迟超过 500ms"
          description: "当前 P95 延迟：{{ $value | humanizeDuration }}"

      # 实例宕机告警
      - alert: InstanceDown
        expr: up == 0
        for: 1m
        labels:
          severity: critical
        annotations:
          summary: "实例 {{ $labels.instance }} 已宕机"
          description: "{{ $labels.instance }} 已停止上报指标超过 1 分钟"

      # 内存压力告警
      - alert: HighMemoryUsage
        expr: (node_memory_MemTotal_bytes - node_memory_MemAvailable_bytes) / node_memory_MemTotal_bytes > 0.85
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "节点 {{ $labels.instance }} 内存使用率超过 85%"
          description: "当前内存使用率：{{ $value | humanizePercentage }}"

      # 磁盘空间告警
      - alert: DiskSpaceLow
        expr: (node_filesystem_size_bytes - node_filesystem_free_bytes) / node_filesystem_size_bytes > 0.9
        for: 10m
        labels:
          severity: critical
        annotations:
          summary: "节点 {{ $labels.instance }} 磁盘使用率超过 90%"
          description: "挂载点 {{ $labels.mountpoint }} 可用空间不足"
```

### 示例 3：Grafana 仪表板配置

通过 Terraform 管理 Grafana 仪表板（基础设施即代码）：

```hcl
# grafana-dashboard.tf
resource "grafana_dashboard" "application_overview" {
  config_json = jsonencode({
    title = "应用概览"
    uid = "app-overview"
    timezone = "browser"
    refresh = "30s"
    panels = [
      {
        id = 1
        title = "请求速率"
        type = "graph"
        targets = [
          {
            expr = "sum(rate(http_requests_total[5m])) by (service)"
            legendFormat = "{{service}}"
          }
        ]
        gridPos = { x = 0, y = 0, w = 12, h = 8 }
      },
      {
        id = 2
        title = "错误率"
        type = "stat"
        targets = [
          {
            expr = "sum(rate(http_requests_total{status=~\"5..\"}[5m])) / sum(rate(http_requests_total[5m])) * 100"
          }
        ]
        gridPos = { x = 12, y = 0, w = 12, h = 8 }
        thresholds = [
          { value = 0, color = "green" },
          { value = 1, color = "yellow" },
          { value = 5, color = "red" }
        ]
      }
    ]
  })
}
```

### 示例 4：应用侧指标埋点

Python 应用使用 `prometheus_client` 暴露指标：

```python
# app.py
from prometheus_client import Counter, Histogram, generate_latest, CONTENT_TYPE_LATEST
from flask import Flask, Response
import time

app = Flask(__name__)

# 定义指标
REQUEST_COUNT = Counter(
    'http_requests_total',
    'Total HTTP requests',
    ['method', 'endpoint', 'status']
)

REQUEST_LATENCY = Histogram(
    'http_request_duration_seconds',
    'HTTP request latency',
    ['method', 'endpoint'],
    buckets=[0.01, 0.05, 0.1, 0.25, 0.5, 1.0, 2.5, 5.0, 10.0]
)

ACTIVE_REQUESTS = Gauge(
    'http_requests_active',
    'Active HTTP requests',
    ['method', 'endpoint']
)

@app.route('/metrics')
def metrics():
    return Response(generate_latest(), mimetype=CONTENT_TYPE_LATEST)

@app.route('/api/<endpoint>')
def handle_request(endpoint):
    start_time = time.time()
    ACTIVE_REQUESTS.labels(method='GET', endpoint=endpoint).inc()
    
    try:
        # 业务逻辑
        time.sleep(0.1)  # 模拟处理
        status = 200
    except Exception as e:
        status = 500
        raise
    finally:
        elapsed = time.time() - start_time
        ACTIVE_REQUESTS.labels(method='GET', endpoint=endpoint).dec()
        REQUEST_COUNT.labels(method='GET', endpoint=endpoint, status=status).inc()
        REQUEST_LATENCY.labels(method='GET', endpoint=endpoint).observe(elapsed)
    
    return {'status': 'ok'}
```

## 常见坑与排查

### 坑 1：Counter 未使用 rate() 导致图表异常

**现象**：Counter 指标图表显示为阶梯状或突然归零

**原因**：Counter 是累积值，直接展示无法反映变化趋势；Prometheus 重启后 Counter 会重置

**解决**：
```promql
# ❌ 错误用法
http_requests_total

# ✅ 正确用法
rate(http_requests_total[5m])
increase(http_requests_total[1h])
```

### 坑 2：高基数标签导致内存爆炸

**现象**：Prometheus 内存持续增长，最终 OOM

**原因**：将用户 ID、请求 ID 等高基数数据作为标签，导致时间序列数量爆炸

**解决**：
```promql
# ❌ 危险：每个用户产生独立时间序列
http_requests_total{user_id="12345"}

# ✅ 安全：聚合到合理维度
sum(rate(http_requests_total[5m])) by (service, endpoint)
```

**最佳实践**：
- 标签值基数控制在 10000 以内
- 避免将用户 ID、邮箱、IP 等作为标签
- 使用 `label_drop` 或 `label_keep` 过滤不必要的标签

### 坑 3：抓取超时导致数据缺口

**现象**：监控图表出现数据空洞，`up` 指标频繁波动

**原因**：`scrape_interval` 设置过短或目标响应过慢

**解决**：
```yaml
scrape_configs:
  - job_name: 'slow-app'
    scrape_interval: 30s  # 延长抓取间隔
    scrape_timeout: 25s   # 设置合理的超时
    static_configs:
      - targets: ['slow-app:8080']
```

### 坑 4：告警风暴

**现象**：一次故障触发数百条告警，淹没关键信息

**原因**：告警规则过于细粒度，缺少分组和去重

**解决**：
```yaml
# alertmanager-config.yaml
route:
  group_by: ['alertname', 'cluster', 'service']
  group_wait: 30s
  group_interval: 5m
  repeat_interval: 4h
  receiver: 'default'

receivers:
  - name: 'default'
    webhook_configs:
      - url: 'http://slack-webhook'
```

### 坑 5：存储 retention 配置不当

**现象**：磁盘爆满或历史数据不足

**解决**：
```bash
# 启动参数
prometheus \
  --storage.tsdb.path=/prometheus \
  --storage.tsdb.retention.time=15d \
  --storage.tsdb.retention.size=50GB
```

**排查命令**：
```bash
# 检查存储使用情况
curl http://localhost:9090/api/v1/status/tsdb

# 检查目标健康状态
curl http://localhost:9090/api/v1/targets

# 查询慢查询日志
grep "slow query" /var/log/prometheus.log
```

## Checklist

### 部署前检查

- [ ] 确定监控范围（集群、应用、基础设施）
- [ ] 评估指标基数，避免高基数标签
- [ ] 规划存储容量（15-30 天保留期）
- [ ] 配置高可用（至少 2 个 Prometheus 实例）
- [ ] 设置合理的抓取间隔（15s-60s）

### 配置检查

- [ ] 所有关键服务已配置抓取
- [ ] 告警规则经过测试验证
- [ ] 告警通知渠道已配置并测试
- [ ] 仪表板已创建并分享给团队
- [ ] 配置已纳入版本控制（Git）

### 运行检查

- [ ] `up` 指标显示所有目标健康
- [ ] 无持续告警（告警疲劳）
- [ ] 存储使用率在安全范围内（<80%）
- [ ] 查询延迟 < 5s（P95）
- [ ] 备份策略已配置（规则、仪表板）

### 告警检查

- [ ] 告警分级明确（critical/warning/info）
- [ ] 每条告警有清晰的 action 指引
- [ ] 告警路由正确（on-call 轮值）
- [ ] 静默规则已配置（维护窗口）
- [ ] 告警抑制规则避免风暴

### 安全加固

- [ ] Prometheus 不直接暴露公网
- [ ] 启用基本认证或 OAuth
- [ ] 配置 TLS 加密传输
- [ ] 网络策略限制访问来源
- [ ] 定期更新 Prometheus 版本

## 参考资料

1. **Prometheus 官方文档** - 最权威的参考资料，涵盖架构、配置、PromQL 完整语法
   https://prometheus.io/docs/

2. **Grafana 官方文档** - 仪表板配置、告警设置、数据源集成指南
   https://grafana.com/docs/

3. **CNCF Prometheus 最佳实践** - 云原生环境下的部署和运维指南
   https://github.com/prometheus/prometheus/wiki/Default-configuration-for-prometheus

4. **Awesome Prometheus** - 社区维护的规则、仪表板、工具集合
   https://awesome-prometheus-alerts.grep.to/

5. **Kubernetes Monitoring with Prometheus** - O'Reilly 出版，深入讲解 K8s 监控实践
   https://www.oreilly.com/library/view/kubernetes-monitoring-with/9781492047018/

---

*本文档为 daily-tech-notes 系列第 47 篇，聚焦云原生指标监控生产实践。配套代码示例见仓库 demos/prometheus-grafana/ 目录。*
