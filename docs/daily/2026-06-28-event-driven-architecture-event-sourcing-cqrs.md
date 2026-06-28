# Event-Driven Architecture：事件溯源、CQRS 与事件风暴生产实践

## 背景与目标

在现代分布式系统中，传统的 CRUD 架构正面临严峻挑战：业务逻辑分散在 Controller、Service、Repository 各层，状态变更历史丢失，审计追踪需要额外埋点，多系统数据同步复杂且容易出错。更关键的是，当业务复杂度达到一定阈值后，"当前状态"本身已不足以支撑决策——我们需要知道"系统是如何到达这个状态的"。

**事件驱动架构（Event-Driven Architecture, EDA）** 正是为了解决这些问题而生。其核心思想是将系统状态变更建模为一系列不可变的事件（Event），通过事件的流转来驱动业务逻辑、同步数据、触发下游系统。相比传统的请求 - 响应模式，EDA 提供了更好的解耦性、可审计性和扩展性。

本文聚焦三个核心主题：

1. **事件溯源（Event Sourcing）**：将状态变更持久化为事件流，而非仅保存最终状态
2. **CQRS（Command Query Responsibility Segregation）**：命令与查询职责分离，独立优化读写路径
3. **事件风暴（Event Storming）**：领域驱动设计（DDD）中的协作建模方法，用于发现事件与聚合

**为什么现在需要 EDA？**

- **审计合规需求**：金融、医疗等行业要求完整的操作历史追溯
- **复杂业务逻辑**：电商订单、支付清算、物流追踪等场景天然适合事件建模
- **系统解耦**：微服务架构中，事件是服务间通信的最佳粘合剂
- **实时数据处理**：事件流支持实时分析、告警、推荐等场景
- **调试与回放**：通过重放事件可以复现生产问题，甚至构建"时间旅行"调试器

通过本文的实践，你将掌握从零构建事件驱动系统的完整方法论，包括事件建模、存储选型、一致性保障、版本演进等生产级考量。

## 核心概念

### 事件溯源（Event Sourcing）

事件溯源是一种架构模式，其核心原则是：**不保存状态的当前快照，而是保存导致状态变更的所有事件序列**。

```
传统 CRUD 模式：
User(id=1, name="Alice", balance=100) → UPDATE users SET balance=90 WHERE id=1

事件溯源模式：
AccountCreated(id=1, name="Alice", balance=100)
MoneyDeposited(id=1, amount=50)
MoneyWithdrawn(id=1, amount=60)
→ 当前余额 = 100 + 50 - 60 = 90
```

**关键特性：**

| 特性 | 传统 CRUD | 事件溯源 |
|------|----------|----------|
| 存储内容 | 当前状态 | 事件日志 |
| 历史追溯 | 需额外审计表 | 天然支持 |
| 状态重建 | 直接读取 | 重放事件 |
| 并发控制 | 乐观锁/悲观锁 | 版本号/期望版本 |
| 调试能力 | 有限 | 可回放任意时间点 |

**事件溯源的四个黄金法则：**

1. **事件不可变**：事件一旦写入，永不修改（只能追加修正事件）
2. **事件命名使用过去时**：`OrderCreated` 而非 `CreateOrder`，表示已发生的事实
3. **事件包含完整上下文**：记录触发事件时的所有相关数据
4. **事件是业务语言**：使用领域术语，让非技术人员也能理解

### CQRS（命令查询职责分离）

CQRS 是 Event Sourcing 的自然搭档，其核心思想是：**读写操作使用不同的模型和数据结构**。

```
┌─────────────────────────────────────────────────────────────┐
│                        CQRS 架构                             │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│   写侧 (Command)              读侧 (Query)                   │
│   ┌──────────────┐           ┌──────────────┐               │
│   │  Command     │           │   Query      │               │
│   │  Handler     │           │   Handler    │               │
│   └──────┬───────┘           └──────┬───────┘               │
│          │                         │                         │
│          ▼                         ▼                         │
│   ┌──────────────┐           ┌──────────────┐               │
│   │  Event Store │           │  Read Model  │               │
│   │  (事件存储)   │           │  (投影视图)   │               │
│   └──────┬───────┘           └──────┬───────┘               │
│          │                         ▲                         │
│          │    ┌─────────────┐      │                         │
│          └───▶│   Projector │──────┘                         │
│               │  (事件投影器) │                               │
│               └─────────────┘                                 │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

**CQRS 的适用场景：**

- ✅ 读写比例悬殊（如社交媒体的读多写少）
- ✅ 查询复杂度远高于写入（需要多表关联、聚合）
- ✅ 需要多种视图呈现同一数据（列表、详情、统计）
- ✅ 高并发场景，读写资源需要独立扩展

**CQRS 的挑战：**

- ⚠️ 最终一致性：写操作完成后，读侧可能需要毫秒到秒级的同步延迟
- ⚠️ 系统复杂度增加：需要维护事件投影逻辑、处理投影失败
- ⚠️ 调试难度：问题可能出现在命令侧、投影侧或查询侧

### 事件风暴（Event Storming）

事件风暴是一种协作建模工作坊，由 Alberto Brandolini 提出，用于快速发现领域事件、命令、聚合和上下文边界。

**事件风暴的典型流程：**

1. **发现领域事件**（橙色贴纸）：团队头脑风暴，列出所有已发生的业务事实
2. **识别命令**（蓝色贴纸）：触发事件的用户操作或系统行为
3. **定义聚合**（黄色贴纸）：将相关事件和命令分组到业务实体
4. **划定上下文**：识别限界上下文（Bounded Context），明确服务边界
5. **识别外部系统**（粉色贴纸）：第三方服务、遗留系统
6. **识别策略/流程**（紫色贴纸）：自动化业务规则和工作流

**事件风暴的产出物：**

- 领域事件目录（Event Catalog）
- 聚合与上下文映射图
- 业务流程图
- 系统边界定义

## 实战/示例

### 示例：电商订单系统的事件溯源实现

我们将构建一个简化的电商订单系统，支持下单、支付、发货、取消等核心流程。

#### 1. 事件定义（TypeScript）

```typescript
// events/order-events.ts

// 基础事件接口
interface DomainEvent {
  eventId: string;
  aggregateId: string;
  eventType: string;
  timestamp: number;
  version: number;
}

// 订单领域事件
interface OrderCreated extends DomainEvent {
  eventType: 'OrderCreated';
  payload: {
    userId: string;
    items: Array<{ productId: string; quantity: number; price: number }>;
    totalAmount: number;
    shippingAddress: string;
  };
}

interface PaymentCompleted extends DomainEvent {
  eventType: 'PaymentCompleted';
  payload: {
    paymentId: string;
    paymentMethod: 'credit_card' | 'alipay' | 'wechat';
    paidAt: number;
  };
}

interface OrderShipped extends DomainEvent {
  eventType: 'OrderShipped';
  payload: {
    trackingNumber: string;
    carrier: string;
    shippedAt: number;
  };
}

interface OrderCancelled extends DomainEvent {
  eventType: 'OrderCancelled';
  payload: {
    reason: string;
    cancelledAt: number;
    refundAmount: number;
  };
}

type OrderEvent = OrderCreated | PaymentCompleted | OrderShipped | OrderCancelled;
```

#### 2. 事件存储（Event Store）

```typescript
// event-store.ts

import { EventEmitter } from 'events';

interface StoredEvent {
  id: string;
  aggregateId: string;
  aggregateType: string;
  eventType: string;
  eventData: Record<string, unknown>;
  version: number;
  timestamp: number;
  metadata: Record<string, unknown>;
}

class EventStore extends EventEmitter {
  private events: StoredEvent[] = [];
  private subscriptions: Map<string, Function[]> = new Map();

  async append(
    aggregateType: string,
    aggregateId: string,
    expectedVersion: number,
    events: Array<{ eventType: string; eventData: Record<string, unknown> }>
  ): Promise<void> {
    // 乐观并发控制：检查版本号
    const existingEvents = this.events.filter(
      e => e.aggregateId === aggregateId
    );
    
    if (existingEvents.length !== expectedVersion) {
      throw new Error(
        `Concurrency conflict: expected version ${expectedVersion}, ` +
        `but found ${existingEvents.length}`
      );
    }

    // 追加事件
    const newEvents: StoredEvent[] = events.map((event, index) => ({
      id: crypto.randomUUID(),
      aggregateType,
      aggregateId,
      eventType: event.eventType,
      eventData: event.eventData,
      version: expectedVersion + index + 1,
      timestamp: Date.now(),
      metadata: {}
    }));

    this.events.push(...newEvents);

    // 发布事件到订阅者（用于投影、通知等）
    for (const event of newEvents) {
      this.publish(event);
    }
  }

  async getEvents(aggregateId: string, fromVersion?: number): Promise<StoredEvent[]> {
    let events = this.events.filter(e => e.aggregateId === aggregateId);
    if (fromVersion !== undefined) {
      events = events.filter(e => e.version > fromVersion);
    }
    return events;
  }

  private publish(event: StoredEvent): void {
    // 发布到全局
    this.emit('event', event);
    // 发布到特定事件类型
    this.emit(`event:${event.eventType}`, event);
    // 发布到特定聚合
    this.emit(`event:${event.aggregateType}:${event.aggregateId}`, event);
  }

  subscribe(eventType: string, handler: (event: StoredEvent) => void): void {
    const key = `event:${eventType}`;
    if (!this.subscriptions.has(key)) {
      this.subscriptions.set(key, []);
    }
    this.subscriptions.get(key)!.push(handler);
  }
}

export const eventStore = new EventStore();
```

#### 3. 聚合根（Order Aggregate）

```typescript
// aggregates/order.ts

import { eventStore } from '../event-store';
import type { OrderEvent } from '../events/order-events';

interface OrderState {
  id: string;
  status: 'created' | 'paid' | 'shipped' | 'cancelled';
  userId: string;
  items: Array<{ productId: string; quantity: number; price: number }>;
  totalAmount: number;
  paymentId?: string;
  trackingNumber?: string;
  version: number;
}

class OrderAggregate {
  private state: OrderState | null = null;
  private uncommittedEvents: OrderEvent[] = [];

  constructor(private readonly orderId: string) {}

  static async load(orderId: string): Promise<OrderAggregate> {
    const aggregate = new OrderAggregate(orderId);
    const events = await eventStore.getEvents('order', orderId);
    
    for (const event of events) {
      aggregate.applyEvent(event.eventType, event.eventData);
    }
    
    aggregate.state!.version = events.length;
    return aggregate;
  }

  static create(
    orderId: string,
    userId: string,
    items: Array<{ productId: string; quantity: number; price: number }>,
    shippingAddress: string
  ): OrderAggregate {
    const aggregate = new OrderAggregate(orderId);
    const totalAmount = items.reduce((sum, item) => sum + item.price * item.quantity, 0);
    
    aggregate.apply({
      eventId: crypto.randomUUID(),
      aggregateId: orderId,
      eventType: 'OrderCreated',
      timestamp: Date.now(),
      version: 1,
      payload: { userId, items, totalAmount, shippingAddress }
    });

    return aggregate;
  }

  private applyEvent(eventType: string, eventData: Record<string, unknown>): void {
    if (!this.state) {
      this.state = {
        id: this.orderId,
        status: 'created',
        userId: '',
        items: [],
        totalAmount: 0,
        version: 0
      };
    }

    switch (eventType) {
      case 'OrderCreated': {
        const payload = eventData as OrderCreated['payload'];
        this.state.status = 'created';
        this.state.userId = payload.userId;
        this.state.items = payload.items;
        this.state.totalAmount = payload.totalAmount;
        break;
      }
      case 'PaymentCompleted': {
        const payload = eventData as PaymentCompleted['payload'];
        this.state.status = 'paid';
        this.state.paymentId = payload.paymentId;
        break;
      }
      case 'OrderShipped': {
        const payload = eventData as OrderShipped['payload'];
        this.state.status = 'shipped';
        this.state.trackingNumber = payload.trackingNumber;
        break;
      }
      case 'OrderCancelled': {
        this.state.status = 'cancelled';
        break;
      }
    }
  }

  private apply(event: OrderEvent): void {
    this.applyEvent(event.eventType, event.payload);
    this.uncommittedEvents.push(event);
  }

  async completePayment(paymentId: string, paymentMethod: string): Promise<void> {
    if (!this.state || this.state.status !== 'created') {
      throw new Error(`Cannot pay order in status: ${this.state?.status}`);
    }

    this.apply({
      eventId: crypto.randomUUID(),
      aggregateId: this.orderId,
      eventType: 'PaymentCompleted',
      timestamp: Date.now(),
      version: this.state.version + 1,
      payload: { paymentId, paymentMethod, paidAt: Date.now() }
    });

    await this.commit();
  }

  async ship(trackingNumber: string, carrier: string): Promise<void> {
    if (!this.state || this.state.status !== 'paid') {
      throw new Error(`Cannot ship order in status: ${this.state?.status}`);
    }

    this.apply({
      eventId: crypto.randomUUID(),
      aggregateId: this.orderId,
      eventType: 'OrderShipped',
      timestamp: Date.now(),
      version: this.state.version + 1,
      payload: { trackingNumber, carrier, shippedAt: Date.now() }
    });

    await this.commit();
  }

  async cancel(reason: string): Promise<void> {
    if (!this.state || this.state.status === 'shipped') {
      throw new Error(`Cannot cancel order in status: ${this.state?.status}`);
    }

    const refundAmount = this.state.status === 'paid' ? this.state.totalAmount : 0;

    this.apply({
      eventId: crypto.randomUUID(),
      aggregateId: this.orderId,
      eventType: 'OrderCancelled',
      timestamp: Date.now(),
      version: this.state.version + 1,
      payload: { reason, cancelledAt: Date.now(), refundAmount }
    });

    await this.commit();
  }

  private async commit(): Promise<void> {
    if (this.uncommittedEvents.length === 0) return;

    await eventStore.append(
      'order',
      this.orderId,
      this.state!.version,
      this.uncommittedEvents.map(e => ({
        eventType: e.eventType,
        eventData: e.payload
      }))
    );

    this.uncommittedEvents = [];
  }

  getState(): OrderState | null {
    return this.state;
  }
}

export { OrderAggregate, OrderState };
```

#### 4. 投影器（Projector）- 构建读模型

```typescript
// projectors/order-list.ts

import { eventStore } from '../event-store';
import type { StoredEvent } from '../event-store';

interface OrderListItem {
  orderId: string;
  userId: string;
  status: string;
  totalAmount: number;
  createdAt: number;
  updatedAt: number;
}

class OrderListProjector {
  private orders: Map<string, OrderListItem> = new Map();
  private lastProcessedPosition = 0;

  constructor() {
    // 订阅所有订单事件
    eventStore.subscribe('OrderCreated', (event) => this.handleOrderCreated(event));
    eventStore.subscribe('PaymentCompleted', (event) => this.handlePaymentCompleted(event));
    eventStore.subscribe('OrderShipped', (event) => this.handleOrderShipped(event));
    eventStore.subscribe('OrderCancelled', (event) => this.handleOrderCancelled(event));
  }

  private handleOrderCreated(event: StoredEvent): void {
    const data = event.eventData as OrderCreated['payload'];
    this.orders.set(event.aggregateId, {
      orderId: event.aggregateId,
      userId: data.userId,
      status: 'created',
      totalAmount: data.totalAmount,
      createdAt: event.timestamp,
      updatedAt: event.timestamp
    });
  }

  private handlePaymentCompleted(event: StoredEvent): void {
    const order = this.orders.get(event.aggregateId);
    if (order) {
      order.status = 'paid';
      order.updatedAt = event.timestamp;
    }
  }

  private handleOrderShipped(event: StoredEvent): void {
    const order = this.orders.get(event.aggregateId);
    if (order) {
      order.status = 'shipped';
      order.updatedAt = event.timestamp;
    }
  }

  private handleOrderCancelled(event: StoredEvent): void {
    const order = this.orders.get(event.aggregateId);
    if (order) {
      order.status = 'cancelled';
      order.updatedAt = event.timestamp;
    }
  }

  async getOrders(userId?: string): Promise<OrderListItem[]> {
    let result = Array.from(this.orders.values());
    if (userId) {
      result = result.filter(o => o.userId === userId);
    }
    return result.sort((a, b) => b.createdAt - a.createdAt);
  }

  async getOrder(orderId: string): Promise<OrderListItem | undefined> {
    return this.orders.get(orderId);
  }
}

export const orderListProjector = new OrderListProjector();
```

#### 5. 使用示例

```typescript
// main.ts

import { OrderAggregate } from './aggregates/order';
import { orderListProjector } from './projectors/order-list';

async function demo() {
  // 1. 创建订单
  const order = OrderAggregate.create(
    'order-001',
    'user-123',
    [
      { productId: 'prod-A', quantity: 2, price: 99.99 },
      { productId: 'prod-B', quantity: 1, price: 199.99 }
    ],
    '北京市朝阳区 xx 路 xx 号'
  );

  console.log('订单创建:', order.getState());

  // 2. 完成支付
  await order.completePayment('pay-001', 'alipay');
  console.log('支付完成:', order.getState());

  // 3. 查询订单列表（读模型）
  const orders = await orderListProjector.getOrders();
  console.log('订单列表:', orders);

  // 4. 发货
  await order.ship('SF123456789', '顺丰速运');
  console.log('已发货:', order.getState());

  // 5. 重放事件重建状态（演示事件溯源的核心能力）
  const rebuiltOrder = await OrderAggregate.load('order-001');
  console.log('重建后的状态:', rebuiltOrder.getState());
}

demo().catch(console.error);
```

### 生产级事件存储选型

| 方案 | 适用场景 | 优点 | 缺点 |
|------|----------|------|------|
| **PostgreSQL + JSONB** | 中小规模，已有 PG 技术栈 | 成熟稳定、事务支持、查询灵活 | 事件量大时性能下降 |
| **EventStoreDB** | 专业事件溯源场景 | 原生事件存储、内置投影、订阅机制 | 学习曲线、运维成本 |
| **Apache Kafka** | 高吞吐、流式处理 | 高可用、水平扩展、生态丰富 | 复杂度高、需要 ZooKeeper/KRaft |
| **MongoDB** | 文档型事件、灵活 Schema | 写入性能好、Schema 灵活 | 事务支持较弱（4.0+ 改善） |
| **Redis Streams** | 低延迟、内存存储 | 极低延迟、简单部署 | 持久化能力弱、内存成本高 |

## 常见坑与排查

### 1. 事件版本演进问题

**问题**：业务迭代后，旧事件格式与新代码不兼容，导致重放失败。

**解决方案**：

```typescript
// 事件升级器模式
class EventUpgrader {
  private upgraders: Map<string, (event: any) => any> = new Map();

  register(eventType: string, version: number, upgrader: (event: any) => any): void {
    this.upgraders.set(`${eventType}:v${version}`, upgrader);
  }

  upgrade(eventType: string, version: number, eventData: any): any {
    let currentVersion = version;
    let currentData = eventData;

    while (true) {
      const key = `${eventType}:v${currentVersion}`;
      const upgrader = this.upgraders.get(key);
      if (!upgrader) break;
      
      currentData = upgrader(currentData);
      currentVersion++;
    }

    return currentData;
  }
}

// 注册升级逻辑
const upgrader = new EventUpgrader();
upgrader.register('OrderCreated', 1, (v1) => ({
  ...v1,
  currency: v1.currency || 'CNY' // 添加默认币种
}));
upgrader.register('OrderCreated', 2, (v2) => ({
  ...v2,
  items: v2.items.map((item: any) => ({
    ...item,
    tax: item.tax || 0 // 添加税额字段
  }))
}));
```

### 2. 投影一致性问题

**问题**：写操作完成后，读侧查询不到最新数据（最终一致性延迟）。

**排查步骤**：

1. 检查事件是否成功发布到事件总线
2. 检查投影器是否正常运行（无异常退出）
3. 检查投影处理是否有积压（消费 lag）
4. 考虑在读请求中增加重试或等待机制

```typescript
// 带等待的查询
async function getOrderWithWait(
  orderId: string, 
  expectedVersion: number,
  maxWaitMs = 5000
): Promise<OrderListItem | null> {
  const startTime = Date.now();
  
  while (Date.now() - startTime < maxWaitMs) {
    const order = await orderListProjector.getOrder(orderId);
    if (order && order.version >= expectedVersion) {
      return order;
    }
    await sleep(100);
  }
  
  throw new Error(`Timeout waiting for order ${orderId} to reach version ${expectedVersion}`);
}
```

### 3. 事件重复消费问题

**问题**：由于网络重试、消费者重启等原因，同一事件被处理多次。

**解决方案**：实现幂等性处理器

```typescript
class IdempotentHandler {
  private processedEvents = new Set<string>();

  async handle(event: StoredEvent, handler: () => Promise<void>): Promise<void> {
    if (this.processedEvents.has(event.id)) {
      console.log(`Event ${event.id} already processed, skipping`);
      return;
    }

    await handler();
    this.processedEvents.add(event.id);
  }
}
```

### 4. 聚合加载性能问题

**问题**：长生命周期聚合的事件数量过多，导致每次加载都需要重放大量事件。

**解决方案**：快照（Snapshotting）

```typescript
// 每 N 个事件创建一个快照
const SNAPSHOT_INTERVAL = 100;

async function loadAggregateWithSnapshot(aggregateId: string): Promise<OrderAggregate> {
  // 1. 查找最新快照
  const snapshot = await snapshotStore.get('order', aggregateId);
  const fromVersion = snapshot ? snapshot.version : 0;

  // 2. 获取快照之后的事件
  const events = await eventStore.getEvents(aggregateId, fromVersion);

  // 3. 从快照或空状态开始重放
  const aggregate = snapshot 
    ? OrderAggregate.fromSnapshot(snapshot.state)
    : new OrderAggregate(aggregateId);

  for (const event of events) {
    aggregate.applyEvent(event.eventType, event.eventData);
  }

  // 4. 如果需要，创建新快照
  if (fromVersion + events.length >= SNAPSHOT_INTERVAL * Math.floor((fromVersion + events.length) / SNAPSHOT_INTERVAL)) {
    await snapshotStore.save('order', aggregateId, {
      version: fromVersion + events.length,
      state: aggregate.getState()
    });
  }

  return aggregate;
}
```

## Checklist

在将事件驱动架构投入生产前，请确保完成以下检查：

### 设计与建模
- [ ] 已完成事件风暴工作坊，明确领域事件目录
- [ ] 事件命名使用过去时（`OrderCreated` 而非 `CreateOrder`）
- [ ] 事件包含完整的业务上下文，不依赖外部状态
- [ ] 已识别聚合边界和限界上下文
- [ ] 已定义事件版本演进策略

### 技术实现
- [ ] 事件存储支持追加写入和按聚合查询
- [ ] 实现乐观并发控制（版本号检查）
- [ ] 投影器支持断点续传和错误恢复
- [ ] 事件处理器实现幂等性
- [ ] 已配置事件监控和告警（积压、失败率）

### 运维与监控
- [ ] 事件存储有备份和恢复策略
- [ ] 配置事件保留策略（归档或清理）
- [ ] 监控投影延迟（写后读一致性）
- [ ] 日志记录关键事件（审计需求）
- [ ] 有事件重放工具用于调试和数据修复

### 安全与合规
- [ ] 敏感数据在事件中脱敏或加密
- [ ] 事件访问有权限控制
- [ ] 满足行业审计要求（如金融、医疗）
- [ ] GDPR 等隐私法规合规（被遗忘权处理）

## 参考资料

1. **Martin Fowler - Event Sourcing** - 事件溯源经典入门文章
   https://martinfowler.com/eaaDev/EventSourcing.html

2. **EventStoreDB Documentation** - 专业事件存储数据库官方文档
   https://www.eventstore.com/docs

3. **Greg Young - CQRS Documents** - CQRS 创始人原始文档
   https://cqrs.files.wordpress.com/2010/11/cqrs_documents.pdf

4. **Alberto Brandolini - Event Storming** - 事件风暴方法创始人
   https://www.eventstorming.com

5. **Microsoft - CQRS Pattern** - 微软架构中心 CQRS 模式详解
   https://learn.microsoft.com/en-us/azure/architecture/patterns/cqrs

6. **Apache Kafka Documentation** - 事件流平台官方文档
   https://kafka.apache.org/documentation

7. **eShop Reference Application** - 微软开源的电商参考架构（含 EDA 实现）
   https://github.com/dotnet/eShop

8. **Axon Framework** - Java 事件溯源/CQRS 框架
   https://axoniq.io/product-overview/axon-framework

---

*本文示例代码可在 demos/event-driven-architecture 目录找到完整实现，包含 Docker Compose 一键启动环境。*
