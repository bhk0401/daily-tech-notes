# Temporal Workflow Orchestration: Building Reliable Distributed Workflows

**日期:** 2026-07-22  
**领域:** 云架构 / 分布式系统  
**关键词:** Temporal, Workflow Orchestration, Distributed Systems, State Management

---

## 背景与目标

在现代分布式系统中，构建可靠的长运行工作流是一个普遍挑战。想象以下场景：用户下单后需要扣减库存、调用支付网关、通知物流系统、发送确认邮件——任何一步失败都需要回滚或重试。传统方案依赖消息队列 + 状态机，但代码分散、状态管理复杂、调试困难。

Temporal 是一个开源的工作流编排引擎，通过"代码即工作流"的理念，将分布式工作流简化为普通的函数调用。它的核心承诺是：**即使服务崩溃、网络分区、依赖超时，工作流也能自动恢复并继续执行**。

本文目标：
- 理解 Temporal 的核心概念和工作原理
- 掌握编写可靠工作流的实践模式
- 学会处理故障、重试、超时等生产场景
- 通过完整示例跑通一个电商订单处理工作流

适用场景：
- 多步骤业务流程（订单处理、审批流、数据管道）
- 需要定时/延迟执行的任务
- 跨多个服务的分布式事务
- 需要审计追踪和可观测性的长运行流程

---

## 核心概念

### 1. Workflow（工作流）

Workflow 是 Temporal 的核心抽象，代表一个长运行的业务流程。关键特性：

- **持久化状态**: 工作流的每一步都持久化到数据库，服务重启后可恢复
- **确定性执行**: 工作流代码必须是确定性的（不能有随机数、当前时间等）
- **自动重试**: 活动失败时自动重试，可配置重试策略

```typescript
// 工作流定义示例
import { proxyActivities, sleep } from '@temporalio/workflow';

const { processPayment, reserveInventory, sendNotification } = proxyActivities<typeof activities>({
  startToCloseTimeout: '10 minutes',
  retry: { initialInterval: '1s', maxAttempts: 3 }
});

export async function orderWorkflow(orderId: string, amount: number): Promise<void> {
  // 步骤 1: 预留库存
  await reserveInventory(orderId);
  
  // 步骤 2: 处理支付
  const paymentResult = await processPayment(orderId, amount);
  if (!paymentResult.success) {
    throw new Error('Payment failed');
  }
  
  // 步骤 3: 发送通知
  await sendNotification(orderId, 'completed');
}
```

### 2. Activity（活动）

Activity 是工作流中的单个任务单元，执行实际业务逻辑：

- **非确定性允许**: 可以调用外部 API、生成随机数、访问数据库
- **独立执行**: 每个活动在独立的工作进程中运行
- **超时控制**: 支持启动超时、执行超时、心跳超时

```typescript
// 活动定义示例
import { context } from '@temporalio/activity';

export async function processPayment(orderId: string, amount: number): Promise<PaymentResult> {
  // 调用外部支付网关
  const response = await fetch('https://api.stripe.com/v1/charges', {
    method: 'POST',
    headers: { 'Authorization': `Bearer ${process.env.STRIPE_KEY}` },
    body: new URLSearchParams({ amount: String(amount), order_id: orderId })
  });
  
  if (!response.ok) {
    throw new PaymentError(`Payment failed: ${response.status}`);
  }
  
  return await response.json();
}
```

### 3. Worker（工作器）

Worker 是执行工作流和活动代码的服务：

- **轮询任务**: 从 Temporal Server 轮询待执行的任务
- **并发控制**: 可配置最大并发工作流/活动数
- **优雅关闭**: 支持等待当前任务完成后再关闭

```typescript
// Worker 配置示例
import { Worker } from '@temporalio/worker';

const worker = await Worker.create({
  connection: 'localhost:7233',
  namespace: 'default',
  taskQueue: 'order-queue',
  workflowsPath: require.resolve('./workflows'),
  activitiesPath: require.resolve('./activities'),
  maxConcurrentWorkflowTaskExecutions: 100,
  maxConcurrentActivityTaskExecutions: 50
});

await worker.run();
```

### 4. Temporal Server

Temporal Server 是编排引擎的核心，负责：

- **状态持久化**: 将工作流状态存储到数据库（支持 PostgreSQL、MySQL、Cassandra）
- **任务调度**: 管理任务队列，分发任务给 Worker
- **定时器管理**: 处理延迟任务、 cron 任务
- **历史追踪**: 记录完整的工作流执行历史

部署选项：
- **本地开发**: Docker Compose 一键启动
- **生产环境**: Kubernetes Helm Chart 或 Temporal Cloud（托管服务）

---

## 实战/示例

### 电商订单处理工作流

下面是一个完整的订单处理示例，包含库存预留、支付处理、通知发送，以及失败回滚逻辑。

#### 工作流代码

```typescript
// workflows/order-workflow.ts
import { 
  proxyActivities, 
  sleep, 
  CancellationScope, 
  ApplicationFailure 
} from '@temporalio/workflow';

const { 
  reserveInventory, 
  releaseInventory,
  processPayment, 
  refundPayment,
  sendEmail,
  notifyWarehouse 
} = proxyActivities<typeof activities>({
  startToCloseTimeout: '5 minutes',
  retry: { 
    initialInterval: '2s', 
    maximumInterval: '30s', 
    backoffCoefficient: 2,
    maxAttempts: 5 
  }
});

export interface OrderInput {
  orderId: string;
  userId: string;
  items: Array<{ sku: string; quantity: number }>;
  amount: number;
  email: string;
}

export async function orderWorkflow(input: OrderInput): Promise<OrderResult> {
  const { orderId, userId, items, amount, email } = input;
  const steps: string[] = [];
  
  try {
    // Step 1: 预留库存（支持补偿）
    steps.push('reserving_inventory');
    await reserveInventory(orderId, items);
    
    // Step 2: 处理支付（支持补偿）
    steps.push('processing_payment');
    const paymentId = await processPayment(orderId, userId, amount);
    
    // Step 3: 通知仓库发货
    steps.push('notifying_warehouse');
    await notifyWarehouse(orderId, items);
    
    // Step 4: 发送确认邮件
    steps.push('sending_confirmation');
    await sendEmail(email, 'order_confirmed', { orderId, amount });
    
    return { 
      status: 'completed', 
      orderId, 
      paymentId,
      completedAt: new Date().toISOString() 
    };
    
  } catch (error) {
    // 补偿逻辑（Saga 模式）
    console.error(`Workflow failed at step: ${steps[steps.length - 1]}`, error);
    
    // 逆向补偿：已执行的步骤需要回滚
    if (steps.includes('processing_payment')) {
      try {
        await refundPayment(orderId);
      } catch (refundError) {
        // 记录需要人工介入
        console.error('Refund failed, manual intervention required', refundError);
      }
    }
    
    if (steps.includes('reserving_inventory')) {
      await releaseInventory(orderId, items);
    }
    
    // 发送失败通知
    await sendEmail(email, 'order_failed', { orderId, reason: error.message });
    
    throw ApplicationFailure.fromError(error);
  }
}
```

#### 活动实现

```typescript
// activities/order-activities.ts
import { context } from '@temporalio/activity';

export interface InventoryItem {
  sku: string;
  quantity: number;
}

export async function reserveInventory(
  orderId: string, 
  items: InventoryItem[]
): Promise<void> {
  // 检查库存并预留
  const response = await fetch('http://inventory-service/api/reserve', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ orderId, items })
  });
  
  if (!response.ok) {
    const error = await response.text();
    throw new InventoryError(`Failed to reserve inventory: ${error}`);
  }
}

export async function releaseInventory(
  orderId: string, 
  items: InventoryItem[]
): Promise<void> {
  // 释放预留库存（补偿操作）
  await fetch('http://inventory-service/api/release', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ orderId, items })
  });
}

export async function processPayment(
  orderId: string, 
  userId: string, 
  amount: number
): Promise<string> {
  // 调用支付网关
  const response = await fetch('https://api.stripe.com/v1/charges', {
    method: 'POST',
    headers: { 
      'Authorization': `Bearer ${process.env.STRIPE_SECRET_KEY}`,
      'Content-Type': 'application/x-www-form-urlencoded'
    },
    body: new URLSearchParams({
      amount: String(amount * 100), // 分
      currency: 'usd',
      customer: userId,
      metadata: JSON.stringify({ orderId })
    })
  });
  
  if (!response.ok) {
    throw new PaymentError(`Payment failed: ${response.status}`);
  }
  
  const result = await response.json();
  return result.id;
}

export async function refundPayment(orderId: string): Promise<void> {
  // 退款操作（补偿）
  await fetch(`https://api.stripe.com/v1/charges/${orderId}/refunds`, {
    method: 'POST',
    headers: { 'Authorization': `Bearer ${process.env.STRIPE_SECRET_KEY}` }
  });
}

export async function sendEmail(
  to: string, 
  template: string, 
  data: Record<string, any>
): Promise<void> {
  // 调用邮件服务
  await fetch('http://email-service/api/send', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ to, template, data })
  });
}

export async function notifyWarehouse(
  orderId: string, 
  items: InventoryItem[]
): Promise<void> {
  // 通知仓库系统
  await fetch('http://warehouse-service/api/notify', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ orderId, items })
  });
}
```

#### 启动工作流

```typescript
// client/start-order.ts
import { Client } from '@temporalio/client';

async function startOrder() {
  const client = await Client.connect('localhost:7233');
  
  const handle = await client.workflow.start(orderWorkflow, {
    args: [{
      orderId: 'ORD-2026-001',
      userId: 'USR-12345',
      items: [
        { sku: 'SKU-001', quantity: 2 },
        { sku: 'SKU-002', quantity: 1 }
      ],
      amount: 19900, // $199.00
      email: 'customer@example.com'
    }],
    taskQueue: 'order-queue',
    workflowId: 'order-ORD-2026-001',
    workflowExecutionTimeout: '24 hours',
    workflowRunTimeout: '1 hour'
  });
  
  console.log(`Workflow started: ${handle.workflowId}`);
  
  // 等待结果（可选）
  const result = await handle.result();
  console.log('Order completed:', result);
}

startOrder().catch(console.error);
```

### 运行示例

完整示例代码仓库：[github.com/temporalio/samples-typescript](https://github.com/temporalio/samples-typescript)

```bash
# 1. 启动 Temporal Server（Docker）
git clone https://github.com/temporalio/docker-compose.git
cd docker-compose
docker compose up -d

# 2. 安装依赖
npm install @temporalio/workflow @temporalio/activity @temporalio/worker @temporalio/client

# 3. 启动 Worker
npx ts-node worker.ts

# 4. 启动工作流
npx ts-node client/start-order.ts

# 5. 查看 Web UI
open http://localhost:8233
```

---

## 常见坑与排查

### 1. 非确定性代码导致工作流卡住

**问题**: 在工作流中使用 `Date.now()`、`Math.random()` 或外部 API 调用，导致重放时状态不一致。

**症状**: 工作流在某个步骤后不再前进，日志显示 "Non-deterministic workflow error"。

**解决方案**:
```typescript
// ❌ 错误：非确定性代码
export async function myWorkflow() {
  const now = Date.now(); // 每次重放结果不同
  const random = Math.random();
  await callExternalAPI(); // 可能返回不同结果
}

// ✅ 正确：使用 Temporal 提供的确定性 API
import { sleep } from '@temporalio/workflow';

export async function myWorkflow() {
  await sleep(5000); // 使用 Temporal 的 sleep
  // 外部调用移到 Activity 中
  await myActivity();
}
```

### 2. 活动超时配置不当

**问题**: 活动执行时间超过 `startToCloseTimeout`，导致不必要的重试。

**症状**: 活动实际执行成功，但工作流收到超时错误并重复执行。

**解决方案**:
```typescript
// 根据实际业务场景设置合理的超时
const activities = proxyActivities<typeof activities>({
  startToCloseTimeout: '10 minutes',  // 活动最大执行时间
  scheduleToCloseTimeout: '1 hour',   // 包含排队时间的总超时
  heartbeatTimeout: '1 minute',       // 长任务需要定期心跳
  
  retry: {
    initialInterval: '1s',
    maximumInterval: '5m',
    backoffCoefficient: 2,
    maxAttempts: 3,
    nonRetryableErrorTypes: ['ValidationError', 'InsufficientFunds']
  }
});
```

### 3. 工作流无法终止

**问题**: 长运行工作流（如等待用户审批）占用资源，需要手动终止。

**解决方案**:
```typescript
// 使用 CancellationScope 支持优雅取消
import { CancellationScope } from '@temporalio/workflow';

export async function workflowWithTimeout() {
  const scope = new CancellationScope();
  
  // 启动一个并行任务用于超时
  const timeoutPromise = sleep(3600000).then(() => scope.cancel());
  
  // 主逻辑
  const mainPromise = scope.run(async () => {
    await longRunningTask();
  });
  
  await Promise.race([mainPromise, timeoutPromise]);
}

// 从客户端终止
await handle.cancel();
```

### 4. 状态增长过大

**问题**: 工作流执行历史过大，导致性能下降。

**症状**: Temporal Server 数据库增长过快，工作流加载变慢。

**解决方案**:
- 避免在工作流中传递大对象
- 使用 `continueAsNew` 重置长运行工作流
- 定期归档已完成的工作流

```typescript
import { continueAsNew } from '@temporalio/workflow';

export async function periodicWorkflow(state: State): Promise<void> {
  // 处理一批数据
  const newState = await processBatch(state);
  
  // 如果还有更多数据，重新开始（重置历史）
  if (newState.hasMoreData) {
    await continueAsNew<typeof periodicWorkflow>(newState);
  }
}
```

### 5. 调试技巧

```bash
# 查看工作流历史
temporal workflow show --workflow-id order-ORD-2026-001

# 查看工作流状态
temporal workflow describe --workflow-id order-ORD-2026-001

# 重放工作流（本地调试）
temporal workflow replay --input-file history.json

# 使用 Web UI 可视化追踪
# http://localhost:8233/namespaces/default/workflows
```

---

## Checklist

### 开发前准备
- [ ] 安装 Temporal Server（本地 Docker 或云服务）
- [ ] 配置 Worker 连接参数（namespace, taskQueue）
- [ ] 定义工作流接口和输入/输出类型
- [ ] 识别需要作为 Activity 的外部调用

### 工作流设计
- [ ] 确保工作流代码确定性（无随机数、当前时间、外部调用）
- [ ] 为每个 Activity 配置合理的超时和重试策略
- [ ] 设计补偿逻辑（Saga 模式处理分布式事务）
- [ ] 考虑使用 `continueAsNew` 处理长运行工作流

### 错误处理
- [ ] 标记不可重试的错误类型（如参数校验失败）
- [ ] 实现完整的补偿/回滚逻辑
- [ ] 添加失败通知机制（邮件/告警）
- [ ] 记录足够的上下文用于排查

### 生产部署
- [ ] 配置 Worker 的并发数和资源限制
- [ ] 设置监控告警（工作流失败率、延迟）
- [ ] 规划数据库备份和归档策略
- [ ] 实施访问控制和审计日志

### 可观测性
- [ ] 启用 Temporal Web UI
- [ ] 集成日志系统（结构化日志）
- [ ] 配置指标导出（Prometheus/Grafana）
- [ ] 设置分布式追踪（OpenTelemetry）

---

## 参考资料

1. **Temporal 官方文档** - 完整的工作流开发指南和 API 参考  
   https://docs.temporal.io

2. **Temporal TypeScript SDK** - TypeScript 开发者的快速入门和示例  
   https://docs.temporal.io/dev-guide/typescript

3. **GitHub Samples** - 官方示例代码仓库，包含多种场景的完整实现  
   https://github.com/temporalio/samples-typescript

4. **Saga Pattern 详解** - 理解分布式事务的补偿模式  
   https://microservices.io/patterns/data/saga.html

5. **Temporal Cloud** - 托管服务，适合生产环境快速部署  
   https://temporal.io/cloud

6. **工作流最佳实践** - 官方整理的生产环境经验和反模式  
   https://docs.temporal.io/dev-guide/typescript/foundations#workflows

---

**总结**: Temporal 通过将分布式工作流的状态管理抽象化，让开发者能够专注于业务逻辑而非基础设施。掌握其核心概念（Workflow、Activity、Worker）和设计模式（Saga、补偿、超时控制），可以显著提升分布式系统的可靠性和可维护性。
