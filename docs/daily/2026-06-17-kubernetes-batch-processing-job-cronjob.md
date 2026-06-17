# Kubernetes 批量处理：Job 与 CronJob 生产实践

## 背景与目标

在云原生架构中，并非所有工作负载都是长期运行的服务。大量场景需要**一次性任务**或**周期性任务**：数据批处理、定时备份、报告生成、模型训练、日志归档等。Kubernetes 提供了 Job 和 CronJob 两种原生资源来管理这类任务。

本文目标：
- 理解 Job/CronJob 的核心概念与适用场景
- 掌握生产环境中的配置最佳实践
- 学会调试失败任务与处理并发控制
- 实现一个可运行的批量数据处理示例

与长期运行的 Deployment 不同，Job 设计的核心是**确保任务完成**——即使 Pod 失败或节点故障，Job 控制器也会重新调度，直到达到指定的成功次数。

## 核心概念

### Job 资源结构

Job 是 Kubernetes 中用于管理**一次性任务**的资源对象。其核心特征是：

```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: data-processor
spec:
  completions: 3          # 需要成功完成的 Pod 总数
  parallelism: 2          # 同时运行的最大 Pod 数
  backoffLimit: 4         # 失败后重试次数
  ttlSecondsAfterFinished: 3600  # 完成后自动清理时间
  template:
    spec:
      containers:
      - name: processor
        image: my-registry/processor:v1
      restartPolicy: Never  # Job 必须使用 Never 或 OnFailure
```

关键字段说明：

| 字段 | 含义 | 默认值 |
|------|------|--------|
| `completions` | 需要成功完成的 Pod 总数 | 1 |
| `parallelism` | 同时运行的最大 Pod 数 | 1 |
| `backoffLimit` | 失败重试次数（指数退避） | 6 |
| `activeDeadlineSeconds` | 任务最长运行时间 | 无限制 |
| `ttlSecondsAfterFinished` | 完成后自动清理延迟 | 不清理 |

### CronJob 周期性调度

CronJob 基于 Linux cron 语法实现周期性任务调度：

```yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: daily-backup
spec:
  schedule: "0 2 * * *"        # 每天凌晨 2 点
  concurrencyPolicy: Forbid    # 并发策略
  successfulJobsHistoryLimit: 3
  failedJobsHistoryLimit: 1
  jobTemplate:
    spec:
      backoffLimit: 3
      template:
        spec:
          containers:
          - name: backup
            image: backup-tool:v1
          restartPolicy: OnFailure
```

**并发策略（concurrencyPolicy）**：
- `Allow`：允许并发运行（前一次未完成，下一次仍启动）
- `Forbid`：禁止并发（默认，前一次未完成则跳过）
- `Replace`：替换正在运行的旧任务

### 重启策略差异

Job 的 Pod 模板必须使用特定重启策略：

| 策略 | 适用场景 | 说明 |
|------|----------|------|
| `Never` | 简单任务 | Pod 失败后不重启，Job 控制器创建新 Pod |
| `OnFailure` | 需要保留现场调试 | 在原有 Pod 内重启容器 |

**重要**：不能使用 `Always`，这是 Deployment/StatefulSet 的专属策略。

## 实战/示例

### 示例 1：批量数据处理 Job

场景：处理 100 个数据文件，每个文件独立处理，允许并行。

```yaml
# docs/daily/demos/batch-processor-job.yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: batch-processor
spec:
  completions: 100
  parallelism: 10
  backoffLimit: 3
  activeDeadlineSeconds: 3600
  template:
    spec:
      containers:
      - name: processor
        image: python:3.11-slim
        command: ["python", "-c"]
        args:
          - |
            import os
            import sys
            import time
            
            # 从环境变量获取任务索引
            index = int(os.environ.get('JOB_COMPLETION_INDEX', 0))
            print(f"Processing file {index}/100")
            
            # 模拟处理逻辑
            time.sleep(2)
            
            # 模拟 10% 失败率
            if index % 10 == 7:
                print(f"File {index} failed!")
                sys.exit(1)
            
            print(f"File {index} completed successfully")
        env:
        - name: JOB_COMPLETION_INDEX
          valueFrom:
            fieldRef:
              fieldPath: metadata.annotations['batch.kubernetes.io/job-completion-index']
      restartPolicy: Never
```

**关键技巧**：
- 使用 `JOB_COMPLETION_INDEX` 环境变量区分不同 Pod 的处理对象
- `parallelism: 10` 确保最多 10 个 Pod 同时运行
- `activeDeadlineSeconds` 防止任务无限期运行

### 示例 2：每日数据备份 CronJob

```yaml
# docs/daily/demos/daily-backup-cronjob.yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: daily-db-backup
  namespace: production
spec:
  schedule: "0 2 * * *"  # 每天凌晨 2 点
  timezone: "Asia/Shanghai"
  concurrencyPolicy: Forbid
  successfulJobsHistoryLimit: 7
  failedJobsHistoryLimit: 3
  startingDeadlineSeconds: 300
  jobTemplate:
    spec:
      backoffLimit: 2
      activeDeadlineSeconds: 1800
      ttlSecondsAfterFinished: 86400
      template:
        spec:
          serviceAccountName: backup-sa
          containers:
          - name: backup
            image: postgres:15
            command:
            - /bin/sh
            - -c
            - |
              set -e
              echo "Starting backup at $(date)"
              pg_dump -h $DB_HOST -U $DB_USER $DB_NAME > /backup/backup-$(date +%Y%m%d).sql
              echo "Backup completed"
            env:
            - name: DB_HOST
              valueFrom:
                secretKeyRef:
                  name: db-credentials
                  key: host
            - name: DB_USER
              valueFrom:
                secretKeyRef:
                  name: db-credentials
                  key: username
            - name: DB_NAME
              value: production_db
            - name: PGPASSWORD
              valueFrom:
                secretKeyRef:
                  name: db-credentials
                  key: password
            volumeMounts:
            - name: backup-volume
              mountPath: /backup
          volumes:
          - name: backup-volume
            persistentVolumeClaim:
              claimName: backup-pvc
          restartPolicy: OnFailure
```

### 示例 3：可运行的本地测试脚本

以下脚本可在本地创建 Kind 集群并测试 Job：

```bash
#!/bin/bash
# docs/daily/demos/test-job.sh

set -e

echo "=== 创建测试集群 ==="
kind create cluster --name job-test --wait 60s

echo "=== 部署 Job ==="
kubectl apply -f batch-processor-job.yaml

echo "=== 监控 Job 状态 ==="
kubectl wait --for=condition=complete job/batch-processor --timeout=3600s

echo "=== 查看结果 ==="
kubectl logs -l job-name=batch-processor --tail=50

echo "=== 清理 ==="
kind delete cluster --name job-test
```

## 常见坑与排查

### 坑 1：Job 一直 Pending

**现象**：Job 创建后 Pod 一直处于 Pending 状态。

**排查步骤**：
```bash
# 查看 Job 状态
kubectl describe job batch-processor

# 查看 Pod 事件
kubectl get pods -l job-name=batch-processor
kubectl describe pod <pod-name>

# 检查资源配额
kubectl describe quota -n <namespace>
```

**常见原因**：
- 集群资源不足（CPU/内存）
- 节点选择器/亲和性配置不当
- 镜像拉取失败（私有镜像缺少 ImagePullSecrets）
- 命名空间 ResourceQuota 限制

### 坑 2：任务失败后无限重试

**现象**：Pod 不断重启，Job 永不完成。

**解决方案**：
```yaml
spec:
  backoffLimit: 3  # 限制重试次数，超过后 Job 标记为 Failed
  activeDeadlineSeconds: 3600  # 设置最大运行时间
```

**调试技巧**：
```bash
# 查看失败 Pod 日志
kubectl logs <failed-pod-name> --previous

# 进入失败 Pod 调试（需修改 restartPolicy 为 OnFailure）
kubectl exec -it <pod-name> -- /bin/sh
```

### 坑 3：CronJob 不按时执行

**现象**：CronJob 定义的调度时间到了，但没有创建 Job。

**排查**：
```bash
# 查看 CronJob 状态
kubectl describe cronjob daily-backup

# 检查控制器日志
kubectl logs -n kube-system -l controller=cronjob-controller
```

**常见原因**：
- `startingDeadlineSeconds` 设置过短，错过调度窗口
- kube-controller-manager 异常
- 时区配置错误（Kubernetes 1.27+ 支持 timezone 字段）

### 坑 4：并发导致数据竞争

**现象**：多个 Pod 同时处理相同数据，导致重复或冲突。

**解决方案**：
```yaml
spec:
  concurrencyPolicy: Forbid  # 禁止并发
  # 或使用分布式锁
```

对于必须并发的场景，在应用层实现分布式锁：
```python
# 使用 Redis 实现分布式锁
import redis
from contextlib import contextmanager

@contextmanager
def distributed_lock(key, timeout=300):
    r = redis.Redis()
    lock = r.lock(key, timeout=timeout)
    try:
        lock.acquire()
        yield
    finally:
        lock.release()
```

### 坑 5：日志丢失

**现象**：Job 完成后 Pod 被清理，无法查看历史日志。

**解决方案**：
1. 设置 `ttlSecondsAfterFinished` 延迟清理
2. 配置日志收集（Loki/ELK）
3. 将日志输出到持久化存储

```yaml
spec:
  ttlSecondsAfterFinished: 86400  # 保留 24 小时
  template:
    spec:
      containers:
      - name: app
        # 同时输出到 stdout 和文件
        command: ["/bin/sh", "-c"]
        args: ["exec > >(tee /var/log/app.log) 2>&1; python app.py"]
        volumeMounts:
        - name: log-volume
          mountPath: /var/log
      volumes:
      - name: log-volume
        emptyDir: {}
```

## Checklist

部署生产级 Job/CronJob 前，请确认以下事项：

### 配置检查
- [ ] `restartPolicy` 设置为 `Never` 或 `OnFailure`
- [ ] `backoffLimit` 设置合理值（避免无限重试）
- [ ] `activeDeadlineSeconds` 设置超时保护
- [ ] `ttlSecondsAfterFinished` 配置自动清理
- [ ] 资源请求/限制（requests/limits）已定义

### 可靠性检查
- [ ] 镜像版本已固定（避免使用 latest）
- [ ] 私有镜像配置了 ImagePullSecrets
- [ ] 敏感信息使用 Secret 而非环境变量明文
- [ ] 配置了适当的并发策略（concurrencyPolicy）

### 可观测性检查
- [ ] 应用输出结构化日志到 stdout/stderr
- [ ] 配置了日志收集系统
- [ ] 关键指标已接入监控（任务成功率、耗时等）
- [ ] 设置了失败告警

### 安全检查
- [ ] 使用最小权限 ServiceAccount
- [ ] 禁用了不必要的 RBAC 权限
- [ ] 网络策略限制出站连接
- [ ] 容器以非 root 用户运行

### 备份与恢复
- [ ] 关键任务配置已纳入 GitOps 管理
- [ ] 定期测试 Job 恢复流程
- [ ] 数据输出有持久化保障

## 参考资料

1. **Kubernetes 官方文档 - Jobs**
   https://kubernetes.io/docs/concepts/workloads/controllers/job/

2. **Kubernetes 官方文档 - CronJobs**
   https://kubernetes.io/docs/concepts/workloads/controllers/cron-jobs/

3. **Kubernetes Batch 最佳实践**
   https://kubernetes.io/docs/tasks/job/automated-tasks-with-cron-jobs/

4. **Google SRE 手册 - 批量处理**
   https://sre.google/sre-book/handling-loads/

5. **Kubernetes Patterns 书籍 - Job 模式**
   https://kubernetes-patterns.com/patterns/job-pattern/
