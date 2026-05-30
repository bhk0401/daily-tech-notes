# Microservices Patterns 实战：Saga、CQRS 与 Event Sourcing 的生产级实践

> 深入理解分布式系统三大核心架构模式，掌握事务一致性、读写分离与事件溯源的完整实现方案

---

## 背景与目标

在微服务架构中，单体应用的事务管理被彻底颠覆。传统的 ACID 事务跨服务边界时失效，我们需要新的模式来保证数据一致性与系统可靠性。

**核心挑战：**

1. **分布式事务**：订单服务扣减库存、支付服务扣款、物流服务创建运单——如何保证要么全部成功，要么全部回滚？
2. **读写性能失衡**：电商场景中读操作占 90% 以上，但传统 CRUD 模型读写共用同一数据模型，导致查询性能瓶颈
3. **审计与追溯**：金融、医疗等场景需要完整的数据变更历史，传统覆盖式更新无法满足合规要求

**本文目标：**

- 掌握 Saga 模式的两种实现策略（编排式 vs 编舞式）及适用场景
- 理解 CQRS（命令查询职责分离）的核心原理与读写模型设计
- 学会 Event Sourcing（事件溯源）的实现方式与快照优化策略
- 获得生产级代码示例与部署 Checklist

这三种模式常常组合使用：CQRS + Event Sourcing 构建高可追溯的写模型，Saga 协调跨服务事务。

---

## 核心概念

### Saga 模式：分布式事务的解决方案

Saga 将长事务拆分为一系列本地事务，每个事务有对应的补偿操作。执行失败时，按相反顺序执行补偿操作回滚。

**两种实现策略：**

| 策略 | 描述 | 优点 | 缺点 |
|------|------|------|------|
| **编排式 (Orchestration)** | 中心化协调器控制流程 | 流程清晰、易于监控、循环/条件分支灵活 | 协调器单点、需额外服务 |
| **编舞式 (Choreography)** | 服务间通过事件触发 | 去中心化、服务解耦 | 流程分散、调试困难、易产生循环依赖 |

**状态机示例（订单流程）：**
```
START → 创建订单 → 扣减库存 → 处理支付 → 创建物流 → COMPLETE
                ↓           ↓           ↓           ↓
           补偿：删除   补偿：恢复  补偿：退款  补偿：取消物流
```

### CQRS：命令查询职责分离

CQRS 将读写操作分离为两个独立模型：

- **Command（写模型）**：处理创建/更新/删除，保证业务规则与一致性
- **Query（读模型）**：专为查询优化，可冗余、可 denormalized、可缓存

**典型架构：**
```
┌─────────────┐     ┌──────────────┐     ┌─────────────┐
│   Command   │────▶│  Event Store │────▶│   Query     │
│   (Write)   │     │  (Events)    │     │   (Read)    │
└─────────────┘     └──────────────┘     └─────────────┘
                           │
                           ▼
                    ┌──────────────┐
                    │  Projections │
                    │  (读模型构建) │
                    └──────────────┘
```

**适用场景：**
- 读/写负载差异大（如电商：浏览 vs 下单）
- 多视图需求（同一数据需多种展示格式）
- 高并发查询场景

**注意事项：** CQRS 引入最终一致性，读模型可能滞后于写模型（通常毫秒到秒级）。

### Event Sourcing：事件溯源

传统 CRUD 只存储当前状态，Event Sourcing 存储导致状态变化的所有事件序列。

**核心思想：**
- 状态 = 初始状态 + 所有事件的累积
- 不更新记录，只追加事件
- 可随时重放事件重建历史状态

**事件示例：**
```json
{
  "orderId": "ORD-2026-001",
  "events": [
    { "type": "OrderCreated", "data": { "items": [...], "total": 299 }, "timestamp": "2026-05-30T01:00:00Z" },
    { "type": "PaymentProcessed", "data": { "method": "alipay", "txId": "TX123" }, "timestamp": "2026-05-30T01:01:00Z" },
    { "type": "OrderShipped", "data": { "carrier": "SF", "trackingNo": "SF123456" }, "timestamp": "2026-05-30T10:00:00Z" }
  ]
}
```

**优势：**
- 完整审计日志（合规要求）
- 可回溯任意时间点状态
- 支持新读模型（追加投影器即可）
- 天然支持事件驱动架构

**挑战：**
- 事件模式演进（schema migration）
- 查询复杂（需投影到读模型）
- 事件流过长影响性能（需快照优化）

---

## 实战/示例

### 示例 1：Saga 编排式实现（Node.js + TypeScript）

```typescript
// saga/orchestrator.ts
import { EventEmitter } from 'events';

interface SagaStep {
  name: string;
  execute: (ctx: any) => Promise<void>;
  compensate: (ctx: any) => Promise<void>;
}

class SagaOrchestrator {
  private steps: SagaStep[] = [];
  private executedSteps: SagaStep[] = [];
  private context: any = {};

  addStep(step: SagaStep): this {
    this.steps.push(step);
    return this;
  }

  async execute(): Promise<{ success: boolean; error?: string }> {
    try {
      for (const step of this.steps) {
        console.log(`Executing: ${step.name}`);
        await step.execute(this.context);
        this.executedSteps.push(step);
      }
      return { success: true };
    } catch (error) {
      console.error(`Step failed: ${error}`);
      await this.compensate();
      return { success: false, error: String(error) };
    }
  }

  private async compensate(): Promise<void> {
    console.log('Starting compensation...');
    // 反向执行已完成的步骤
    for (const step of this.executedSteps.reverse()) {
      try {
        console.log(`Compensating: ${step.name}`);
        await step.compensate(this.context);
      } catch (err) {
        console.error(`Compensation failed for ${step.name}: ${err}`);
        // 补偿失败需人工介入（记录告警）
      }
    }
  }
}

// 订单 Saga 示例
export function createOrderSaga(orderId: string, userId: string, amount: number) {
  const saga = new SagaOrchestrator();
  
  saga
    .addStep({
      name: 'CreateOrder',
      execute: async (ctx) => {
        // 调用订单服务 API
        ctx.orderId = orderId;
        console.log(`Order ${orderId} created`);
      },
      compensate: async (ctx) => {
        console.log(`Order ${ctx.orderId} cancelled`);
      }
    })
    .addStep({
      name: 'ReserveInventory',
      execute: async (ctx) => {
        // 调用库存服务 API
        console.log(`Inventory reserved for ${orderId}`);
      },
      compensate: async (ctx) => {
        console.log(`Inventory released for ${orderId}`);
      }
    })
    .addStep({
      name: 'ProcessPayment',
      execute: async (ctx) => {
        // 调用支付服务 API
        console.log(`Payment ${amount} processed for ${orderId}`);
      },
      compensate: async (ctx) => {
        console.log(`Payment refunded for ${orderId}`);
      }
    })
    .addStep({
      name: 'CreateShipment',
      execute: async (ctx) => {
        // 调用物流服务 API
        console.log(`Shipment created for ${orderId}`);
      },
      compensate: async (ctx) => {
        console.log(`Shipment cancelled for ${orderId}`);
      }
    });

  return saga;
}

// 使用示例
async function placeOrder() {
  const saga = createOrderSaga('ORD-001', 'USER-123', 299.00);
  const result = await saga.execute();
  
  if (!result.success) {
    console.error(`Order failed: ${result.error}`);
    // 通知用户、记录日志、触发告警
  }
}
```

### 示例 2：CQRS + Event Sourcing 完整实现

```typescript
// cqrs-eventstore/order.ts
import { EventEmitter } from 'events';

// ============ 事件定义 ============
type OrderEvent =
  | { type: 'OrderCreated'; orderId: string; items: OrderItem[]; total: number; timestamp: Date }
  | { type: 'OrderPaid'; orderId: string; paymentMethod: string; txId: string; timestamp: Date }
  | { type: 'OrderShipped'; orderId: string; carrier: string; trackingNo: string; timestamp: Date }
  | { type: 'OrderCancelled'; orderId: string; reason: string; timestamp: Date };

interface OrderItem {
  productId: string;
  quantity: number;
  price: number;
}

// ============ 事件存储 ============
class EventStore extends EventEmitter {
  private events: Map<string, OrderEvent[]> = new Map();

  append(orderId: string, event: OrderEvent): void {
    if (!this.events.has(orderId)) {
      this.events.set(orderId, []);
    }
    this.events.get(orderId)!.push(event);
    this.emit('event', event); // 发布事件供投影器消费
  }

  getHistory(orderId: string): OrderEvent[] {
    return this.events.get(orderId) || [];
  }
}

// ============ 聚合根（写模型） ============
class OrderAggregate {
  constructor(
    public readonly orderId: string,
    private events: OrderEvent[] = []
  ) {}

  static create(orderId: string, items: OrderItem[], total: number): OrderAggregate {
    const order = new OrderAggregate(orderId);
    order.apply({
      type: 'OrderCreated',
      orderId,
      items,
      total,
      timestamp: new Date()
    });
    return order;
  }

  pay(paymentMethod: string, txId: string): void {
    if (this.isPaid()) {
      throw new Error('Order already paid');
    }
    this.apply({
      type: 'OrderPaid',
      orderId: this.orderId,
      paymentMethod,
      txId,
      timestamp: new Date()
    });
  }

  ship(carrier: string, trackingNo: string): void {
    if (!this.isPaid()) {
      throw new Error('Cannot ship unpaid order');
    }
    this.apply({
      type: 'OrderShipped',
      orderId: this.orderId,
      carrier,
      trackingNo,
      timestamp: new Date()
    });
  }

  cancel(reason: string): void {
    if (this.isShipped()) {
      throw new Error('Cannot cancel shipped order');
    }
    this.apply({
      type: 'OrderCancelled',
      orderId: this.orderId,
      reason,
      timestamp: new Date()
    });
  }

  private apply(event: OrderEvent): void {
    this.events.push(event);
  }

  getUncommittedEvents(): OrderEvent[] {
    return this.events;
  }

  // 状态查询（基于事件重放）
  isPaid(): boolean {
    return this.events.some(e => e.type === 'OrderPaid');
  }

  isShipped(): boolean {
    return this.events.some(e => e.type === 'OrderShipped');
  }

  isCancelled(): boolean {
    return this.events.some(e => e.type === 'OrderCancelled');
  }

  getStatus(): 'created' | 'paid' | 'shipped' | 'cancelled' {
    if (this.isCancelled()) return 'cancelled';
    if (this.isShipped()) return 'shipped';
    if (this.isPaid()) return 'paid';
    return 'created';
  }
}

// ============ 投影器（构建读模型） ============
interface OrderReadModel {
  orderId: string;
  status: string;
  items: OrderItem[];
  total: number;
  paymentMethod?: string;
  txId?: string;
  carrier?: string;
  trackingNo?: string;
  cancelledReason?: string;
  createdAt: Date;
  updatedAt: Date;
}

class OrderProjection {
  private readModels: Map<string, OrderReadModel> = new Map();

  constructor(eventStore: EventStore) {
    eventStore.on('event', (event: OrderEvent) => this.handleEvent(event));
  }

  private handleEvent(event: OrderEvent): void {
    const { orderId } = event;
    let model = this.readModels.get(orderId);

    switch (event.type) {
      case 'OrderCreated':
        model = {
          orderId,
          status: 'created',
          items: event.items,
          total: event.total,
          createdAt: event.timestamp,
          updatedAt: event.timestamp
        };
        break;
      case 'OrderPaid':
        if (model) {
          model.status = 'paid';
          model.paymentMethod = event.paymentMethod;
          model.txId = event.txId;
          model.updatedAt = event.timestamp;
        }
        break;
      case 'OrderShipped':
        if (model) {
          model.status = 'shipped';
          model.carrier = event.carrier;
          model.trackingNo = event.trackingNo;
          model.updatedAt = event.timestamp;
        }
        break;
      case 'OrderCancelled':
        if (model) {
          model.status = 'cancelled';
          model.cancelledReason = event.reason;
          model.updatedAt = event.timestamp;
        }
        break;
    }

    if (model) {
      this.readModels.set(orderId, model);
    }
  }

  getOrder(orderId: string): OrderReadModel | undefined {
    return this.readModels.get(orderId);
  }

  getOrdersByStatus(status: string): OrderReadModel[] {
    return Array.from(this.readModels.values()).filter(o => o.status === status);
  }
}

// ============ 使用示例 ============
async function demo() {
  const eventStore = new EventStore();
  const projection = new OrderProjection(eventStore);

  // 创建订单
  const order = OrderAggregate.create('ORD-001', [
    { productId: 'P1', quantity: 2, price: 99 },
    { productId: 'P2', quantity: 1, price: 101 }
  ], 299);

  // 提交事件到存储
  order.getUncommittedEvents().forEach(e => eventStore.append('ORD-001', e));

  // 支付
  order.pay('alipay', 'TX123456');
  order.getUncommittedEvents().forEach(e => eventStore.append('ORD-001', e));

  // 发货
  order.ship('SF', 'SF123456789');
  order.getUncommittedEvents().forEach(e => eventStore.append('ORD-001', e));

  // 查询读模型（毫秒级响应）
  console.log('Order status:', projection.getOrder('ORD-001')?.status); // 'shipped'
  console.log('All shipped orders:', projection.getOrdersByStatus('shipped'));
}

demo();
```

### 示例 3：快照优化（解决事件流过长问题）

```typescript
// 当事件数量超过阈值时创建快照
interface OrderSnapshot {
  orderId: string;
  version: number;
  state: {
    status: string;
    items: OrderItem[];
    total: number;
    paymentMethod?: string;
    carrier?: string;
  };
  snapshotAt: Date;
}

class OrderWithSnapshot extends OrderAggregate {
  private snapshot?: OrderSnapshot;
  private static SNAPSHOT_THRESHOLD = 100;

  static async loadFromHistory(
    orderId: string,
    events: OrderEvent[],
    snapshot?: OrderSnapshot
  ): Promise<OrderWithSnapshot> {
    const order = new OrderWithSnapshot(orderId);
    order.snapshot = snapshot;

    // 从快照版本开始重放事件
    const startVersion = snapshot?.version || 0;
    const eventsToReplay = events.slice(startVersion);

    eventsToReplay.forEach(e => order.apply(e));
    return order;
  }

  shouldCreateSnapshot(): boolean {
    return this.events.length >= OrderWithSnapshot.SNAPSHOT_THRESHOLD;
  }

  createSnapshot(): OrderSnapshot {
    return {
      orderId: this.orderId,
      version: this.events.length,
      state: {
        status: this.getStatus(),
        items: this.getCurrentItems(),
        total: this.getTotal(),
        paymentMethod: this.getPaymentMethod(),
        carrier: this.getCarrier()
      },
      snapshotAt: new Date()
    };
  }
}
```

---

## 常见坑与排查

### Saga 模式陷阱

**问题 1：补偿操作失败**
- **现象**：Saga 回滚时补偿操作也失败，系统处于不一致状态
- **排查**：
  - 检查补偿操作的幂等性（重复执行是否安全）
  - 添加补偿重试机制（指数退避）
  - 补偿失败时记录告警，需人工介入
- **解决**：补偿操作必须设计为幂等，如退款前检查是否已退

**问题 2：编舞式 Saga 的循环依赖**
- **现象**：服务 A 触发 B，B 触发 C，C 又触发 A，形成死循环
- **排查**：绘制事件流程图，检查是否存在环
- **解决**：改用编排式 Saga，由协调器控制流程

**问题 3：Saga 超时未处理**
- **现象**：某步骤卡住，Saga 既不成功也不回滚
- **排查**：
  - 检查各服务健康状态
  - 查看协调器日志确认卡在哪一步
- **解决**：
  - 为每个步骤设置超时时间
  - 超时自动触发补偿
  - 使用定时任务扫描"悬挂"Saga

### CQRS 常见问题

**问题 1：读写不一致（读模型滞后）**
- **现象**：用户下单后立即查询订单列表看不到新订单
- **排查**：检查投影器延迟、消息队列积压
- **解决**：
  - 前端增加"加载中"提示，延迟查询
  - 关键场景读主库（牺牲部分性能）
  - 优化投影器性能（批量处理、并行投影）

**问题 2：读模型构建失败**
- **现象**：事件消费失败导致读模型缺失
- **排查**：检查投影器日志、事件格式兼容性
- **解决**：
  - 投影器需支持重试
  - 事件 schema 需向后兼容
  - 提供手动重建读模型的工具

### Event Sourcing 挑战

**问题 1：事件模式演进**
- **现象**：旧事件缺少新字段，投影器报错
- **排查**：检查事件 schema 变更记录
- **解决**：
  - 事件追加字段（不删除/修改旧字段）
  - 投影器处理缺失字段时用默认值
  - 重大变更时创建新事件类型（如 OrderCreatedV2）

**问题 2：事件流过长导致加载慢**
- **现象**：订单有数千个事件，重放耗时过长
- **排查**：统计各聚合的事件数量
- **解决**：
  - 实现快照机制（每 N 个事件存一次状态）
  - 加载时从最近快照开始重放
  - 归档冷数据事件到对象存储

**问题 3：事件删除（GDPR 合规）**
- **现象**：用户要求删除个人数据，但事件不可变
- **排查**：确认合规要求范围
- **解决**：
  - 事件中的个人数据加密存储
  - 删除时销毁解密密钥（数据变乱码）
  - 或创建"数据擦除"事件覆盖敏感字段

---

## Checklist

### Saga 实施清单

- [ ] 识别需要跨服务事务的业务场景
- [ ] 选择编排式或编舞式（复杂流程推荐编排式）
- [ ] 为每个步骤定义补偿操作
- [ ] 确保补偿操作幂等（可重复执行）
- [ ] 实现 Saga 协调器（或事件驱动逻辑）
- [ ] 添加步骤超时机制
- [ ] 实现悬挂 Saga 检测与告警
- [ ] 记录完整 Saga 执行日志（审计用）
- [ ] 测试各种失败场景（每步失败 + 补偿失败）

### CQRS 实施清单

- [ ] 评估读写负载比例（读>>写适合 CQRS）
- [ ] 设计命令模型（写侧，保证一致性）
- [ ] 设计查询模型（读侧，优化查询性能）
- [ ] 实现事件发布机制（同步/异步）
- [ ] 开发投影器（事件→读模型）
- [ ] 处理投影失败重试
- [ ] 监控读写延迟差（通常<1s）
- [ ] 提供读模型重建工具
- [ ] 前端处理短暂不一致（UI 提示/轮询）

### Event Sourcing 实施清单

- [ ] 确定需要事件溯源的聚合根
- [ ] 设计事件命名规范（过去时，如 OrderCreated）
- [ ] 定义事件 schema（含版本号）
- [ ] 实现事件存储（追加写、按聚合查询）
- [ ] 实现聚合根的事件重放逻辑
- [ ] 设计快照策略（阈值 + 定时）
- [ ] 处理事件模式演进（向后兼容）
- [ ] 实现事件导出工具（分析/迁移）
- [ ] 敏感数据加密或脱敏
- [ ] 监控事件存储增长（容量规划）

### 生产部署清单

- [ ] 事件存储高可用（多副本/集群）
- [ ] 消息队列持久化（防丢失）
- [ ] 投影器水平扩展能力
- [ ] 完整监控指标（Saga 成功率、投影延迟、事件吞吐量）
- [ ] 告警配置（补偿失败、投影滞后、存储告急）
- [ ] 灾难恢复预案（数据重建流程）
- [ ] 文档化事件字典（所有事件类型说明）

---

## 参考资料

1. **Microsoft Architecture Guide - Saga Pattern**  
   https://learn.microsoft.com/en-us/azure/architecture/reference-architectures/saga/saga  
   官方详解 Saga 模式，含编排式与编舞式对比、Azure 实现示例

2. **Martin Fowler - CQRS**  
   https://martinfowler.com/bliki/CQRS.html  
   CQRS 概念起源与核心思想，理解读写分离的本质

3. **Event Sourcing Pattern (Microsoft)**  
   https://learn.microsoft.com/en-us/azure/architecture/patterns/event-sourcing  
   事件溯源模式详解，含快照优化与版本管理策略

4. **Greg Young - CQRS and Event Sourcing (YouTube)**  
   https://www.youtube.com/watch?v=JHGkaShoyNs  
   CQRS 与 Event Sourcing 提出者 Greg Young 的经典演讲

5. **Axon Framework Reference**  
   https://docs.axoniq.io/reference-guide/  
   Java 领域驱动设计框架，CQRS/Event Sourcing 生产级实现参考

6. **EventStoreDB Documentation**  
   https://developers.eventstore.com/  
   专用事件存储数据库，支持流式事件查询与投影

---

**文档信息**
- 创建时间：2026-05-30
- 字数：约 4200 字
- 领域：云架构 / 微服务 / 分布式系统
- 难度：中高级
