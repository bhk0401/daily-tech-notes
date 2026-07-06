# Cloud Cost Optimization：Kubernetes 与 Serverless 的 FinOps 生产实践

> 云原生时代，成本优化不再是"可选项"而是"必选项"。本文深入解析 Kubernetes 与 Serverless 环境的成本优化策略，掌握 FinOps 核心方法论、资源右 sizing 实践、Spot 实例应用、自动扩缩容调优与成本监控告警体系，帮助企业在保障稳定性的前提下实现 30%-60% 的云成本节约。

## 背景与目标

随着云原生技术的普及，企业基础设施成本结构发生了根本性变化。传统 IDC 时代的"一次性采购 + 折旧"模式被"按需付费 + 弹性伸缩"取代，这带来了灵活性的同时也引入了新的成本挑战：

**云成本失控的常见场景：**

1. **资源过度配置**：开发环境直接复用生产配置，单 Pod 申请 4C8G 实际使用不足 10%
2. **闲置资源浪费**：测试环境 24 小时运行，夜间和周末零流量仍全额计费
3. **Spot 实例未利用**：无状态服务仍使用按需实例，错失 60%-90% 成本节约机会
4. **存储成本膨胀**：日志永久保存、快照无生命周期管理、对象存储未分层
5. **网络费用盲区**：跨 AZ 流量、NAT 网关处理费、CDN 回源费用未被监控

**FinOps 核心目标：**

- **可见性（Visibility）**：建立成本分账体系，精确到命名空间/服务/团队
- **优化（Optimization）**：通过技术手段实现资源利用率提升
- **运营（Operations）**：将成本意识融入研发流程，建立成本预算与告警机制

本文目标：提供一套可落地的 Kubernetes + Serverless 成本优化方案，涵盖从资源申请、调度策略、自动扩缩容到成本监控的完整闭环，帮助企业在 3 个月内实现 30%+ 成本节约。

## 核心概念

### FinOps 三大支柱

FinOps（Financial Operations）是云财务管理的方法论框架，由 FinOps Foundation 定义：

| 阶段 | 核心活动 | 关键产出 |
|------|---------|---------|
| **Inform（可见性）** | 成本数据采集、标签体系、分账报告 | 成本仪表板、Showback/Chargeback 报告 |
| **Optimize（优化）** | 资源右 sizing、预留实例、Spot 策略 | 资源利用率报告、优化建议清单 |
| **Operate（运营）** | 预算控制、异常告警、流程嵌入 | 成本预算、审批流程、KPI 考核 |

### Kubernetes 成本模型

Kubernetes 集群成本由以下部分构成：

```
总成本 = 节点成本 + 存储成本 + 网络成本 + 托管费用

节点成本 = Σ(节点数量 × 实例单价 × 运行时长)
存储成本 = Σ(PV 容量 × 单价) + IOPS 费用
网络成本 = 跨 AZ 流量 + NAT 网关处理费 + 负载均衡器费用
托管费用 = EKS/GKE/AKS 控制平面费用（约 $0.10/小时）
```

**关键指标：**

- **CPU 利用率**：`request 利用率 = 实际使用 / request`，目标 50%-70%
- **内存利用率**：`request 利用率 = 实际使用 / request`，目标 60%-80%
- **节点利用率**：`可分配资源利用率 = ΣPod request / 节点容量`，目标 70%-85%
- **资源浪费率**：`(request - 实际使用) / request × 100%`，目标 < 30%

### Serverless 成本模型

Serverless（Cloud Functions / Lambda / Cloud Run）采用按量付费模式：

```
总成本 = 计算费用 + 网络费用 + 其他服务费用

计算费用 = Σ(调用次数 × 单价) + Σ(GB-秒 × 单价)
GB-秒 = 内存 (GB) × 执行时长 (秒)
```

**成本优化杠杆：**

- **内存配置**：内存增加会线性增加成本，但可能减少执行时间
- **冷启动优化**：预留实例（Provisioned Concurrency）减少延迟但增加成本
- **超时设置**：合理设置超时避免"僵尸函数"持续计费

### Spot 实例与抢占式 VM

Spot 实例（AWS）/ Preemptible VM（GCP）/ Spot VM（Azure）提供 60%-90% 折扣，但可能被回收：

| 特性 | 按需实例 | Spot 实例 |
|------|---------|----------|
| 价格折扣 | 0% | 60%-90% |
| SLA 保障 | 有 | 无（可能随时回收） |
| 回收通知 | 无 | 2 分钟（AWS）/ 30 秒（GCP） |
| 适用场景 | 有状态服务、数据库 | 无状态服务、批处理、CI/CD |

**Spot 实例适用性评估：**

```yaml
适合 Spot 的服务特征：
  - 无状态（Stateless）
  - 可水平扩展（Horizontally Scalable）
  - 支持优雅终止（Graceful Shutdown）
  - 有健康检查与自愈机制
  - 非关键路径服务（可接受短暂不可用）

不适合 Spot 的服务特征：
  - 有状态服务（数据库、缓存）
  - 单实例部署
  - 长连接服务（WebSocket）
  - 严格 SLA 要求的核心服务
```

## 实战/示例

### 示例 1：Kubernetes 资源右 Sizing 实践

**步骤 1：收集历史资源使用数据**

使用 Prometheus 查询过去 7 天的资源使用情况：

```bash
# 查询 Pod CPU 使用率（P95）
kubectl top pods --all-namespaces --sort-by=cpu

# Prometheus 查询：过去 7 天 CPU 使用率 P95
query='quantile_over_time(0.95, rate(container_cpu_usage_seconds_total{namespace="production"}[7d]))'

# Prometheus 查询：过去 7 天内存使用率 P95
query='quantile_over_time(0.95, container_memory_working_set_bytes{namespace="production"})'
```

**步骤 2：计算推荐资源配置**

基于 P95 使用量，设置 request = P95 × 1.2，limit = P95 × 1.5：

```python
# rightsizing_calculator.py
import json

def calculate_recommendations(metrics_data):
    """
    基于 Prometheus 指标计算推荐资源配置
    """
    recommendations = []
    
    for pod in metrics_data['pods']:
        cpu_p95 = pod['cpu_p95_cores']  # 例如 0.25
        mem_p95 = pod['mem_p95_bytes']  # 例如 268435456 (256MB)
        
        # 设置 request 为 P95 的 1.2 倍，limit 为 1.5 倍
        cpu_request = round(cpu_p95 * 1.2, 2)
        cpu_limit = round(cpu_p95 * 1.5, 2)
        mem_request = int(mem_p95 * 1.2 / (1024*1024))  # 转换为 MB
        mem_limit = int(mem_p95 * 1.5 / (1024*1024))
        
        recommendations.append({
            'pod': pod['name'],
            'current': {
                'cpu_request': pod['current_cpu_request'],
                'cpu_limit': pod['current_cpu_limit'],
                'mem_request': pod['current_mem_request'],
                'mem_limit': pod['current_mem_limit']
            },
            'recommended': {
                'cpu_request': f"{cpu_request}m",
                'cpu_limit': f"{cpu_limit * 1000}m",
                'mem_request': f"{mem_request}Mi",
                'mem_limit': f"{mem_limit}Mi"
            },
            'savings': {
                'cpu_reduction': round((pod['current_cpu_request'] - cpu_request) / pod['current_cpu_request'] * 100, 1),
                'mem_reduction': round((pod['current_mem_request'] - mem_request) / pod['current_mem_request'] * 100, 1)
            }
        })
    
    return recommendations

# 使用示例
if __name__ == "__main__":
    # 模拟指标数据
    metrics = {
        'pods': [{
            'name': 'api-gateway-7d8f9c',
            'cpu_p95_cores': 0.15,
            'mem_p95_bytes': 134217728,
            'current_cpu_request': 500,  # millicores
            'current_cpu_limit': 1000,
            'current_mem_request': 512,  # MB
            'current_mem_limit': 1024
        }]
    }
    
    result = calculate_recommendations(metrics)
    print(json.dumps(result, indent=2))
```

**步骤 3：应用推荐配置**

```yaml
# deployment-optimized.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: api-gateway
  namespace: production
spec:
  template:
    spec:
      containers:
      - name: api-gateway
        image: myapp/api-gateway:v2.1.0
        resources:
          requests:
            cpu: "180m"      # P95 × 1.2
            memory: "160Mi"  # P95 × 1.2
          limits:
            cpu: "225m"      # P95 × 1.5
            memory: "200Mi"  # P95 × 1.5
```

### 示例 2：Spot 实例混合部署策略

使用 Karpenter 或 Cluster Autoscaler 实现 Spot + 按需混合部署：

```yaml
# karpenter-nodepool-spot.yaml
apiVersion: karpenter.sh/v1beta1
kind: NodePool
metadata:
  name: spot-pool
spec:
  template:
    spec:
      requirements:
        - key: karpenter.sh/capacity-type
          operator: In
          values: ["spot"]
        - key: kubernetes.io/arch
          operator: In
          values: ["amd64"]
        - key: node.kubernetes.io/instance-type
          operator: In
          values: ["m5.large", "m5.xlarge", "m6i.large", "m6i.xlarge"]
      nodeClassRef:
        name: default
  limits:
    cpu: 1000  # 限制 Spot 节点最大 CPU 总量
  disruption:
    consolidationPolicy: WhenUnderutilized
    expireAfter: 720h  # 30 天后强制轮换，避免长期运行 Spot 实例
```

```yaml
# deployment-spot-tolerant.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: stateless-worker
spec:
  replicas: 10
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxSurge: 25%
      maxUnavailable: 25%
  template:
    spec:
      affinity:
        nodeAffinity:
          preferredDuringSchedulingIgnoredDuringExecution:
          - weight: 1
            preference:
              matchExpressions:
              - key: karpenter.sh/capacity-type
                operator: In
                values: ["spot"]
      tolerations:
      - key: karpenter.sh/capacity-type
        operator: Equal
        value: spot
        effect: NoSchedule
      containers:
      - name: worker
        image: myapp/worker:v1.0.0
        lifecycle:
          preStop:
            exec:
              command: ["/bin/sh", "-c", "sleep 30"]  # 优雅终止，等待任务完成
```

### 示例 3：非生产环境自动缩容

使用 KubeDownscaler 在夜间和周末自动缩容非生产环境：

```yaml
# kubedownscaler-deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: kubedownscaler
  namespace: kube-system
spec:
  template:
    spec:
      containers:
      - name: kubedownscaler
        image: codeberg.org/hjacobs/kube-downscaler:23.3
        args:
          - --interval=30
          - --downtime=night,weekend
          - --namespace-selector=environment!=production
          - --exclude-deployments=kube-downscaler,coredns
        env:
        - name: DOWNTIME_NIGHT
          value: "19:00-07:00 UTC"  # 夜间缩容时段
        - name: DOWNTIME_WEEKEND
          value: "Sat-Sun"          # 周末缩容
```

**预期效果：**

| 环境 | 运行时间 | 成本节约 |
|------|---------|---------|
| 开发环境 | 工作日 07:00-19:00 | 65% |
| 测试环境 | 工作日 07:00-19:00 | 65% |
| Staging | 24/7（缩容到 1 副本） | 80% |

### 示例 4：Serverless 成本优化配置

Cloud Functions 成本优化配置示例：

```yaml
# cloud-function-config.yaml
# 基于实际测试数据选择最优内存配置

测试场景：图像处理函数（ resize + compress ）

内存配置 | 执行时间 | 单次成本 | 月成本 (100 万次调用)
--------|---------|---------|-------------------
128 MB  | 2.5s    | $0.0000042 | $4.20
256 MB  | 1.2s    | $0.0000040 | $4.00  ← 最优
512 MB  | 0.7s    | $0.0000047 | $4.70
1024 MB | 0.5s    | $0.0000067 | $6.70

结论：256 MB 内存配置在成本与性能之间取得最佳平衡
```

```python
# function_optimizer.py - 自动测试不同内存配置
import time
import subprocess

def benchmark_function(memory_mb):
    """
    测试不同内存配置下的函数执行时间和成本
    """
    # 部署函数（使用 gcloud CLI）
    subprocess.run([
        'gcloud', 'functions', 'deploy', 'image-processor',
        '--memory', str(memory_mb),
        '--timeout', '10s',
        '--trigger-http'
    ])
    
    # 等待部署完成
    time.sleep(30)
    
    # 执行 10 次测试调用
    times = []
    for i in range(10):
        start = time.time()
        subprocess.run(['curl', '-X', 'POST', 'https://FUNCTION_URL'])
        times.append(time.time() - start)
    
    avg_time = sum(times) / len(times)
    
    # 计算成本（基于 GCP 定价）
    gb_seconds = (memory_mb / 1024) * avg_time
    cost_per_invocation = gb_seconds * 0.0000166667  # GCP 单价
    
    return {
        'memory_mb': memory_mb,
        'avg_time_s': round(avg_time, 3),
        'gb_seconds': round(gb_seconds, 4),
        'cost_per_invocation': round(cost_per_invocation, 7)
    }

# 测试不同内存配置
for mem in [128, 256, 512, 1024, 2048]:
    result = benchmark_function(mem)
    print(f"{result['memory_mb']}MB: {result['avg_time_s']}s, ${result['cost_per_invocation']}/call")
```

### 示例 5：成本监控与告警

使用 Prometheus + Grafana 建立成本监控仪表板：

```yaml
# cost-alerts.yaml
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: cost-alerts
  namespace: monitoring
spec:
  groups:
  - name: cost-alerts
    rules:
    # 告警 1：命名空间成本超预算
    - alert: NamespaceCostOverBudget
      expr: |
        sum(kube_pod_container_resource_requests{resource="cpu", namespace=~"dev|staging"}) 
        > 10  # CPU 超过 10 核
      for: 1h
      labels:
        severity: warning
      annotations:
        summary: "命名空间 {{ $labels.namespace }} CPU 请求超过预算"
        description: "当前 CPU 请求：{{ $value }} 核，预算：10 核"
    
    # 告警 2：资源利用率过低
    - alert: LowResourceUtilization
      expr: |
        avg(rate(container_cpu_usage_seconds_total[1h])) 
        / avg(kube_pod_container_resource_requests{resource="cpu"}) 
        < 0.3
      for: 24h
      labels:
        severity: info
      annotations:
        summary: "CPU 利用率低于 30%"
        description: "过去 24 小时平均 CPU 利用率：{{ $value | humanizePercentage }}"
    
    # 告警 3：Spot 实例回收率异常
    - alert: HighSpotInterruptionRate
      expr: |
        rate(karpenter_node_interruptions_total[1h]) > 0.1
      for: 15m
      labels:
        severity: warning
      annotations:
        summary: "Spot 实例回收率异常"
        description: "过去 1 小时回收率：{{ $value }}/分钟"
```

```python
# cost_reporter.py - 每日成本报告
import requests
from datetime import datetime

def generate_daily_cost_report():
    """
    生成每日成本报告并发送到 Slack/飞书
    """
    # 从 Prometheus 查询昨日成本数据
    prometheus_url = "http://prometheus:9090/api/v1/query"
    
    # 查询各命名空间 CPU 请求总量
    cpu_query = 'sum(kube_pod_container_resource_requests{resource="cpu"}) by (namespace)'
    cpu_response = requests.get(prometheus_url, params={'query': cpu_query})
    
    # 查询各命名空间内存请求总量
    mem_query = 'sum(kube_pod_container_resource_requests{resource="memory"}) by (namespace)'
    mem_response = requests.get(prometheus_url, params={'query': mem_query})
    
    # 估算成本（基于云厂商定价）
    cpu_price_per_core_day = 0.50  # $/core/day
    mem_price_per_gb_day = 0.05    # $/GB/day
    
    report = f"""
## 📊 每日云成本报告 - {datetime.now().strftime('%Y-%m-%d')}

### 按命名空间成本估算

| 命名空间 | CPU 请求 | 内存请求 | 估算日成本 |
|---------|---------|---------|-----------|
"""
    
    # 解析数据并生成表格
    for ns_data in cpu_response.json()['data']['result']:
        namespace = ns_data['metric']['namespace']
        cpu_cores = float(ns_data['value'][1]) / 1000  # 转换为核
        # 查找对应内存数据
        mem_data = next((m for m in mem_response.json()['data']['result'] 
                        if m['metric']['namespace'] == namespace), None)
        mem_gb = float(mem_data['value'][1]) / (1024**3) if mem_data else 0
        
        daily_cost = cpu_cores * cpu_price_per_core_day + mem_gb * mem_price_per_gb_day
        
        report += f"| {namespace} | {cpu_cores:.2f} 核 | {mem_gb:.2f} GB | ${daily_cost:.2f} |\n"
    
    total_cost = sum(float(r.split('|')[-1].replace('$', '').strip()) 
                    for r in report.split('\n') if r.startswith('|'))
    
    report += f"\n**总计估算日成本：${total_cost:.2f}**\n"
    report += f"**预估月成本：${total_cost * 30:.2f}**\n"
    
    # 发送到飞书
    send_feishu_notification(report)
    
    return report

def send_feishu_notification(message):
    """发送飞书通知"""
    webhook_url = "https://open.feishu.cn/open-apis/bot/v2/hook/YOUR_WEBHOOK"
    requests.post(webhook_url, json={
        "msg_type": "text",
        "content": {"text": message}
    })
```

## 常见坑与排查

### 坑 1：过度右 Sizing 导致 OOMKilled

**现象：** 应用频繁被 OOMKilled，重启后恢复正常

**根因：** 内存 limit 设置过低，未考虑峰值流量或内存泄漏

**排查步骤：**

```bash
# 1. 检查 Pod 重启原因
kubectl get pod <pod-name> -o jsonpath='{.status.containerStatuses[0].lastState}'

# 2. 查看 OOMKilled 事件
kubectl describe pod <pod-name> | grep -A5 "OOMKilled"

# 3. 查看内存使用趋势
kubectl top pod <pod-name> --containers

# 4. Prometheus 查询内存使用峰值
query='max_over_time(container_memory_working_set_bytes{pod="<pod-name>"}[24h])'
```

**解决方案：**

```yaml
# 设置合理的 limit，保留 30%-50% 缓冲
resources:
  requests:
    memory: "256Mi"   # P95 使用量
  limits:
    memory: "384Mi"   # P95 × 1.5，保留缓冲

# 添加 Vertical Pod Autoscaler 自动调整
apiVersion: autoscaling.k8s.io/v1
kind: VerticalPodAutoscaler
metadata:
  name: api-gateway-vpa
spec:
  targetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: api-gateway
  updatePolicy:
    updateMode: "Auto"  # 自动更新资源配置
```

### 坑 2：Spot 实例回收导致服务中断

**现象：** Pod 频繁被驱逐，用户请求失败

**根因：** 应用未实现优雅终止，Spot 实例回收时正在处理请求

**排查步骤：**

```bash
# 1. 检查 Pod 驱逐事件
kubectl get events --field-selector reason=Preempting

# 2. 查看终止宽限期配置
kubectl get pod <pod-name> -o jsonpath='{.spec.terminationGracePeriodSeconds}'

# 3. 检查应用是否处理 SIGTERM
kubectl logs <pod-name> | grep -i "shutdown\|terminating"
```

**解决方案：**

```yaml
# 1. 设置足够的终止宽限期
spec:
  terminationGracePeriodSeconds: 60  # 默认 30 秒，建议 60 秒

# 2. 实现优雅终止
# Node.js 示例
process.on('SIGTERM', async () => {
  console.log('收到 SIGTERM，开始优雅关闭...');
  
  // 1. 停止接收新请求
  server.close();
  
  // 2. 等待正在处理的请求完成
  await waitForPendingRequests();
  
  // 3. 关闭数据库连接
  await db.disconnect();
  
  // 4. 退出进程
  process.exit(0);
});

# 3. 使用 PodDisruptionBudget 保证最小可用副本
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: worker-pdb
spec:
  minAvailable: 5  # 至少保持 5 个副本可用
  selector:
    matchLabels:
      app: worker
```

### 坑 3：自动缩容影响开发效率

**现象：** 开发人员早上上班发现环境不可用，需等待 5-10 分钟扩容

**根因：** KubeDownscaler 缩容到 0 副本，首次访问触发冷启动

**解决方案：**

```yaml
# 方案 1：保留最小副本数而非缩容到 0
# kubedownscaler 配置
args:
  - --default-replicas=1  # 保留 1 个副本而非 0

# 方案 2：使用 KEDA 基于事件驱动扩缩容
apiVersion: keda.sh/v1alpha1
kind: ScaledObject
metadata:
  name: api-scaler
spec:
  scaleTargetRef:
    name: api-gateway
  minReplicaCount: 1  # 最小 1 副本
  maxReplicaCount: 10
  triggers:
  - type: http
    metadata:
      gatewayAddress: "http://ingress-nginx"
      metricName: "requests-per-second"
      targetValue: "10"

# 方案 3：上班时间前预热
# CronJob 定时扩容
apiVersion: batch/v1
kind: CronJob
metadata:
  name: morning-scale-up
spec:
  schedule: "0 7 * * 1-5"  # 工作日 7:00
  jobTemplate:
    spec:
      template:
        spec:
          containers:
          - name: kubectl
            image: bitnami/kubectl:latest
            command:
            - /bin/sh
            - -c
            - |
              kubectl scale deployment --all --replicas=2 -n dev
              kubectl scale deployment --all --replicas=2 -n staging
```

### 坑 4：Serverless 冷启动延迟

**现象：** 函数首次调用延迟 2-5 秒，用户体验差

**根因：** 函数长时间无调用，容器被回收

**解决方案：**

```yaml
# 方案 1：预留实例（Provisioned Concurrency）
# Cloud Functions
gcloud functions deploy my-function \
  --provisioned-concurrency=2  # 保持 2 个实例预热

# 方案 2：定时心跳保持活跃
# CronJob 每 5 分钟调用一次
apiVersion: batch/v1
kind: CronJob
metadata:
  name: function-heartbeat
spec:
  schedule: "*/5 * * * *"
  jobTemplate:
    spec:
      template:
        spec:
          containers:
          - name: curl
            image: curlimages/curl
            command:
            - /bin/sh
            - -c
            - |
              curl -X POST https://FUNCTION_URL/health

# 方案 3：使用支持快照启动的平台
# Cloud Run 支持快速启动（<100ms）
gcloud run deploy my-service \
  --min-instances=1  # 保持至少 1 个实例
```

### 坑 5：成本监控数据滞后

**现象：** 收到成本告警时已超预算 50%

**根因：** 云厂商账单数据延迟 24-48 小时，无法实时监控

**解决方案：**

```python
# 基于资源使用量实时估算成本（而非等待账单）
def estimate_realtime_cost():
    """
    基于 Prometheus 指标实时估算成本
    """
    # CPU 成本估算
    cpu_cores = prometheus_query('sum(kube_pod_container_resource_requests{resource="cpu"})')
    cpu_cost_per_hour = cpu_cores * 0.05  # $/core/hour
    
    # 内存成本估算
    mem_gb = prometheus_query('sum(kube_pod_container_resource_requests{resource="memory"})') / (1024**3)
    mem_cost_per_hour = mem_gb * 0.01  # $/GB/hour
    
    # 节点成本（基于实际运行节点数）
    node_count = prometheus_query('count(kube_node_info)')
    node_cost_per_hour = node_count * 0.10  # $/node/hour（含托管费）
    
    total_hourly_cost = cpu_cost_per_hour + mem_cost_per_hour + node_cost_per_hour
    
    # 预测月成本
    projected_monthly = total_hourly_cost * 24 * 30
    
    return {
        'hourly_cost': round(total_hourly_cost, 2),
        'daily_cost': round(total_hourly_cost * 24, 2),
        'projected_monthly': round(projected_monthly, 2),
        'budget_remaining': BUDGET - projected_monthly
    }
```

## Checklist

### 资源优化

- [ ] 完成所有生产服务资源使用率分析（过去 7 天 P95 数据）
- [ ] 应用右 Sizing 建议，CPU/内存 request 利用率目标 50%-70%
- [ ] 移除所有未使用的 LimitRange 和 ResourceQuota 过度配置
- [ ] 为无状态服务配置 Horizontal Pod Autoscaler
- [ ] 为有状态服务配置 Vertical Pod Autoscaler（Auto 模式）

### Spot 实例策略

- [ ] 识别所有适合 Spot 的无状态服务工作负载
- [ ] 配置 Karpenter 或 Cluster Autoscaler Spot 节点池
- [ ] 实现优雅终止逻辑（SIGTERM 处理 + terminationGracePeriodSeconds）
- [ ] 配置 PodDisruptionBudget 保证最小可用副本
- [ ] 建立 Spot 回收监控告警（回收率 > 10%/小时告警）

### 非生产环境治理

- [ ] 部署 KubeDownscaler，配置夜间/周末缩容策略
- [ ] 开发/测试环境缩容时段：19:00-07:00 UTC + 周末
- [ ] Staging 环境保留最小 1 副本（而非 0）
- [ ] 配置上班时间前自动扩容 CronJob（工作日 07:00）
- [ ] 建立环境资源预算（开发环境 < 生产环境 20%）

### Serverless 优化

- [ ] 完成函数内存配置基准测试（128MB-2048MB）
- [ ] 选择成本最优的内存配置（通常 256MB-512MB）
- [ ] 为关键函数配置预留实例（Provisioned Concurrency）
- [ ] 设置合理的超时时间（避免僵尸函数）
- [ ] 配置函数调用监控与成本告警

### 成本监控体系

- [ ] 部署 Prometheus + Grafana 成本监控仪表板
- [ ] 配置命名空间级成本预算告警（超 80% 预警）
- [ ] 配置资源利用率告警（<30% 持续 24 小时）
- [ ] 实现每日成本报告自动发送（飞书/Slack）
- [ ] 建立成本优化周会机制（Review 优化建议清单）

### 流程嵌入

- [ ] 在 CI/CD 流水线中添加资源配置检查（超过预算拒绝部署）
- [ ] 建立新服务资源申请审批流程（需说明预估流量与资源需求）
- [ ] 将成本指标纳入团队 OKR（季度成本降低 10%）
- [ ] 建立成本优化最佳实践文档（内部 Wiki）
- [ ] 定期（季度）Review 云厂商定价变化与优化机会

## 参考资料

1. **FinOps Foundation** - 云财务管理官方框架与认证体系  
   https://www.finops.org/

2. **Kubernetes Resource Management 官方文档** - Requests/Limits/QoS 详解  
   https://kubernetes.io/docs/concepts/configuration/manage-resources-containers/

3. **AWS Spot Instances 最佳实践** - Spot 实例架构设计与故障处理  
   https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/spot-best-practices.html

4. **GCP Cloud Run 定价与优化** - Serverless 容器成本模型分析  
   https://cloud.google.com/run/pricing

5. **Karpenter 官方文档** - Kubernetes 自动扩缩容与 Spot 集成  
   https://karpenter.sh/docs/

6. **KubeDownscaler 项目** - 非生产环境自动缩容工具  
   https://codeberg.org/hjacobs/kube-downscaler

7. **Vertical Pod Autoscaler 官方文档** - 自动资源调整实践  
   https://github.com/kubernetes/autoscaler/tree/master/vertical-pod-autoscaler

8. **Cloud FinOps: An Operational Framework for Cloud Financial Management** - O'Reilly 出版 FinOps 权威指南  
   https://www.oreilly.com/library/view/cloud-finops/9781492080220/

---

*本文档遵循 FinOps Foundation 方法论，结合 Kubernetes 与 Serverless 实战经验，提供可落地的成本优化方案。建议企业建立专门的 FinOps 团队或指定成本负责人，将成本优化纳入研发流程，实现持续改进。*
