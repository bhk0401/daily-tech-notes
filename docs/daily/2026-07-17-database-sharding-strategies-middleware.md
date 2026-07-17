# Database Sharding：分库分表策略与中间件选型生产实践

> 当单表数据量突破千万级、写入 QPS 超过 5000 时，垂直扩展已无法满足需求。本文深入解析数据库水平拆分（Sharding）的核心策略、中间件选型与生产级落地方案。

## 背景与目标

### 为什么需要分库分表

在云原生架构中，数据库往往是系统扩展的最大瓶颈。当业务快速增长时，单实例数据库会面临以下挑战：

1. **存储容量瓶颈**：单表超过 5000 万行后，B+ 树索引深度增加，查询性能显著下降
2. **写入性能瓶颈**：单机写入 QPS 超过 5000 后，锁竞争加剧，延迟飙升
3. **备份恢复困难**：大库备份时间长，恢复窗口超出 RTO 要求
4. **资源隔离缺失**：核心业务与边缘业务共享实例，相互影响

**分库分表的核心目标**：
- 水平扩展存储容量和写入能力
- 实现业务隔离，降低故障爆炸半径
- 支持按业务维度的独立扩缩容
- 为未来迁移到 NewSQL/分布式数据库铺路

### 本文涵盖内容

- 分片策略详解（Range/Hash/Geo/Composite）
- 中间件选型对比（ShardingSphere/MyCat/Vitess/Citus）
- 分布式 ID 生成方案（Snowflake/Leaf/UUID）
- 跨分片查询与聚合优化
- 数据迁移与扩容实战
- 生产级避坑指南

## 核心概念

### 分片策略（Sharding Strategies）

#### 1. Range Sharding（范围分片）

按字段范围划分数据，适合时序数据和范围查询场景。

```
用户 ID 范围      →   数据库实例
0 - 999,999      →   db_user_0
1,000,000 - 1,999,999  →   db_user_1
2,000,000 - 2,999,999  →   db_user_2
```

**优点**：
- 范围查询高效（`WHERE user_id BETWEEN 1000 AND 2000`）
- 便于数据归档和冷热分离
- 扩容时可定向迁移特定范围

**缺点**：
- 数据分布可能不均匀（热点区间问题）
- 需要预规划范围边界

**适用场景**：订单表（按时间）、日志表、监控数据

#### 2. Hash Sharding（哈希分片）

对分片键进行哈希运算，均匀分布数据。

```python
# 分片路由计算
def get_shard_id(user_id, shard_count):
    return hash(user_id) % shard_count

# 示例：user_id = 12345, shard_count = 8
# shard_id = hash(12345) % 8 = 3 → db_3
```

**优点**：
- 数据分布均匀，避免热点
- 实现简单，路由快速

**缺点**：
- 范围查询需要跨所有分片（Scatter-Gather）
- 扩容时需要重新哈希，数据迁移成本高

**适用场景**：用户表、配置表、随机访问场景

#### 3. Geo Sharding（地理位置分片）

按地理位置或区域划分，适合全球化业务。

```
用户所在区域    →   数据库集群
Asia-Pacific   →   db-ap-singapore
Europe         →   db-eu-frankfurt
North America  →   db-us-east
```

**优点**：
- 降低访问延迟（数据靠近用户）
- 符合数据主权要求（GDPR 等）
- 区域故障隔离

**缺点**：
- 跨区域查询复杂
- 全球统计数据需要聚合

**适用场景**：跨境电商、全球化 SaaS、内容分发

#### 4. Composite Sharding（复合分片）

结合多个字段进行分片，解决数据倾斜问题。

```python
# 复合分片键：tenant_id + user_id
def get_shard_key(tenant_id, user_id):
    # 先按租户分库，再按用户哈希分表
    db_id = hash(tenant_id) % db_count
    table_id = hash(f"{tenant_id}:{user_id}") % table_count
    return f"db_{db_id}.user_{table_id}"
```

**适用场景**：多租户 SaaS、电商平台（商家 + 商品）

### 分布式 ID 生成

分库分表后，自增 ID 不再适用，需要全局唯一 ID。

#### Snowflake 算法（推荐）

64 位 ID 结构：`1 位符号 + 41 位时间戳 + 10 位机器 ID + 12 位序列号`

```python
import time

class Snowflake:
    def __init__(self, worker_id: int):
        self.worker_id = worker_id
        self.sequence = 0
        self.last_timestamp = -1
        self.sequence_bits = 12
        self.worker_bits = 10
        
    def next_id(self) -> int:
        timestamp = int(time.time() * 1000)
        
        # 时钟回拨处理
        if timestamp < self.last_timestamp:
            raise Exception("Clock moved backwards")
        
        if timestamp == self.last_timestamp:
            self.sequence = (self.sequence + 1) & ((1 << self.sequence_bits) - 1)
            if self.sequence == 0:
                # 序列号溢出，等待下一毫秒
                timestamp = self.wait_next_millis()
        else:
            self.sequence = 0
        
        self.last_timestamp = timestamp
        
        # 组合 ID: 时间戳 | 机器 ID | 序列号
        return ((timestamp - 1288834974657) << (self.worker_bits + self.sequence_bits)) | \
               (self.worker_id << self.sequence_bits) | \
               self.sequence
    
    def wait_next_millis(self) -> int:
        timestamp = int(time.time() * 1000)
        while timestamp <= self.last_timestamp:
            timestamp = int(time.time() * 1000)
        return timestamp

# 使用示例
sf = Snowflake(worker_id=1)
order_id = sf.next_id()  # 759847293847562849
```

**优点**：
- 全局唯一，趋势递增（利于索引）
- 不依赖外部服务，性能高
- 64 位整数，存储友好

**缺点**：
- 需要协调机器 ID（可用 ZooKeeper/Etcd）
- 时钟回拨问题需处理

#### 其他方案对比

| 方案 | 优点 | 缺点 | 适用场景 |
|------|------|------|----------|
| Snowflake | 高性能、趋势递增 | 需协调机器 ID | 通用推荐 |
|美团 Leaf | 支持号段模式、容灾 | 依赖 DB/Redis | 高并发订单 |
| UUID | 无需协调、去中心化 | 无序、128 位过长 | 临时 ID、非索引场景 |
| 数据库自增 | 简单 | 单点瓶颈、无法跨库 | 不推荐用于分片 |

### 分片中间件架构

```
┌─────────────────────────────────────────────────────┐
│                    Application                       │
└─────────────────────────────────────────────────────┘
                          │
                          ▼
┌─────────────────────────────────────────────────────┐
│              Sharding Middleware                     │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐          │
│  │ SQL Parse│  │ Route    │  │ Merge    │          │
│  │ & Rewrite│  │ Engine   │  │ Result   │          │
│  └──────────┘  └──────────┘  └──────────┘          │
└─────────────────────────────────────────────────────┘
                          │
        ┌─────────────────┼─────────────────┐
        ▼                 ▼                 ▼
   ┌─────────┐      ┌─────────┐      ┌─────────┐
   │  db_0   │      │  db_1   │      │  db_2   │
   │ table_0 │      │ table_0 │      │ table_0 │
   │ table_1 │      │ table_1 │      │ table_1 │
   └─────────┘      └─────────┘      └─────────┘
```

**中间件核心功能**：
1. **SQL 解析与改写**：识别分片键，改写路由 SQL
2. **路由引擎**：根据分片策略计算目标分片
3. **结果合并**：跨分片查询的结果聚合、排序、分页
4. **事务管理**：分布式事务协调（XA/TCC/Saga）

## 实战/示例

### 示例 1：ShardingSphere-JDBC 配置实战

Apache ShardingSphere 是最流行的开源分库分表中间件，支持 JDBC 和 Proxy 两种模式。

#### Maven 依赖

```xml
<dependencies>
    <dependency>
        <groupId>org.apache.shardingsphere</groupId>
        <artifactId>shardingsphere-jdbc-core</artifactId>
        <version>5.5.0</version>
    </dependency>
    <dependency>
        <groupId>org.apache.shardingsphere</groupId>
        <artifactId>shardingsphere-jdbc-core-spring-boot-starter</artifactId>
        <version>5.5.0</version>
    </dependency>
</dependencies>
```

#### application.yml 配置

```yaml
spring:
  shardingsphere:
    datasource:
      names: ds0,ds1
      ds0:
        type: com.zaxxer.hikari.HikariDataSource
        driver-class-name: com.mysql.cj.jdbc.Driver
        jdbc-url: jdbc:mysql://db0:3306/order_db?useSSL=false
        username: root
        password: password123
      ds1:
        type: com.zaxxer.hikari.HikariDataSource
        driver-class-name: com.mysql.cj.jdbc.Driver
        jdbc-url: jdbc:mysql://db1:3306/order_db?useSSL=false
        username: root
        password: password123
    
    rules:
      sharding:
        tables:
          t_order:
            actual-data-nodes: ds$->{0..1}.t_order$->{0..3}
            table-strategy:
              standard:
                sharding-column: order_id
                sharding-algorithm-name: t_order_table_algorithm
            database-strategy:
              standard:
                sharding-column: user_id
                sharding-algorithm-name: t_order_database_algorithm
        
        sharding-algorithms:
          t_order_database_algorithm:
            type: HASH_MOD
            props:
              sharding-count: 2
          t_order_table_algorithm:
            type: HASH_MOD
            props:
              sharding-count: 4
    
    props:
      sql-show: true
      check-table-metadata-enabled: true
```

#### Java 代码示例

```java
@Service
public class OrderService {
    
    @Autowired
    private OrderMapper orderMapper;
    
    /**
     * 创建订单 - 自动路由到对应分片
     */
    public Long createOrder(Order order) {
        // 生成分布式 ID
        long orderId = snowflake.nextId();
        order.setOrderId(orderId);
        order.setCreateTime(LocalDateTime.now());
        
        // 插入时，ShardingSphere 根据 user_id 路由到 db_0 或 db_1
        // 根据 order_id 路由到 t_order_0 ~ t_order_3
        orderMapper.insert(order);
        
        return orderId;
    }
    
    /**
     * 查询订单 - 自动路由 + 结果合并
     */
    public Order getOrder(Long orderId, Long userId) {
        // 精确查询：直接路由到单个分片
        return orderMapper.selectById(orderId, userId);
    }
    
    /**
     * 范围查询 - 跨分片查询，自动合并结果
     */
    public List<Order> getUserOrders(Long userId, LocalDateTime startTime, LocalDateTime endTime) {
        // 根据 user_id 路由到单个库，但需要扫描该库的所有 4 张表
        return orderMapper.selectByUserIdAndTimeRange(userId, startTime, endTime);
    }
    
    /**
     * 跨用户查询 - 全路由，性能较差，需避免
     */
    public List<Order> getAllOrders(LocalDateTime startTime, LocalDateTime endTime) {
        // 缺少分片键，需要查询所有 2*4=8 个分片
        // 生产环境应禁止此类查询，或走 ES/ClickHouse 等 OLAP 引擎
        return orderMapper.selectByTimeRange(startTime, endTime);
    }
}
```

### 示例 2：数据迁移脚本（双写 + 校验 + 切换）

```python
#!/usr/bin/env python3
"""
数据库分片迁移脚本：双写 → 数据校验 → 读切换 → 写切换
"""

import mysql.connector
from typing import List, Dict
import hashlib
import time

class ShardingMigration:
    def __init__(self, old_db: mysql.connector.MySQLConnection, 
                 new_dbs: List[mysql.connector.MySQLConnection]):
        self.old_db = old_db
        self.new_dbs = new_dbs
    
    def get_shard_db(self, user_id: int) -> mysql.connector.MySQLConnection:
        """根据 user_id 路由到目标分片"""
        shard_id = user_id % len(self.new_dbs)
        return self.new_dbs[shard_id]
    
    def dual_write(self, table: str, records: List[Dict]):
        """双写阶段：同时写入旧库和新分片"""
        old_cursor = self.old_db.cursor()
        
        for record in records:
            user_id = record['user_id']
            new_db = self.get_shard_db(user_id)
            new_cursor = new_db.cursor()
            
            # 写入旧库
            old_sql = f"INSERT INTO {table} ({','.join(record.keys())}) VALUES ({','.join(['%s'] * len(record))})"
            old_cursor.execute(old_sql, list(record.values()))
            
            # 写入新分片
            new_cursor.execute(old_sql, list(record.values()))
        
        self.old_db.commit()
        for db in self.new_dbs:
            db.commit()
        
        print(f"Dual write completed: {len(records)} records")
    
    def verify_data(self, table: str, sample_size: int = 1000) -> bool:
        """数据校验：抽样对比旧库与新分片"""
        old_cursor = self.old_db.cursor(dictionary=True)
        old_cursor.execute(f"SELECT * FROM {table} ORDER BY RAND() LIMIT {sample_size}")
        sample_records = old_cursor.fetchall()
        
        mismatch_count = 0
        for record in sample_records:
            user_id = record['user_id']
            new_db = self.get_shard_db(user_id)
            new_cursor = new_db.cursor(dictionary=True)
            
            # 按主键查询对比
            primary_key = record.get('id') or record.get('order_id')
            new_cursor.execute(f"SELECT * FROM {table} WHERE id = %s", (primary_key,))
            new_record = new_cursor.fetchone()
            
            if not new_record:
                print(f"Missing record in new shard: {primary_key}")
                mismatch_count += 1
                continue
            
            # 对比关键字段
            for key in ['user_id', 'amount', 'status', 'create_time']:
                if str(record[key]) != str(new_record.get(key)):
                    print(f"Mismatch for {primary_key}.{key}: {record[key]} vs {new_record.get(key)}")
                    mismatch_count += 1
                    break
        
        error_rate = mismatch_count / sample_size
        print(f"Verification completed: {mismatch_count}/{sample_size} mismatches ({error_rate:.2%})")
        return error_rate < 0.001  # 允许 0.1% 误差
    
    def switch_read(self):
        """切换读流量到新分片"""
        print("Switching read traffic to new shards...")
        # 实际场景：更新配置中心/注册中心的读路由配置
        # 这里仅做示例
        time.sleep(2)
        print("Read traffic switched successfully")
    
    def switch_write(self):
        """切换写流量到新分片（停止双写）"""
        print("Switching write traffic to new shards...")
        # 实际场景：更新应用配置，停止双写逻辑
        time.sleep(2)
        print("Write traffic switched successfully")
    
    def migrate(self, table: str, batch_size: int = 10000):
        """完整迁移流程"""
        print(f"Starting migration for table: {table}")
        
        # Step 1: 历史数据迁移
        print("Step 1: Migrating historical data...")
        old_cursor = self.old_db.cursor(dictionary=True)
        old_cursor.execute(f"SELECT COUNT(*) as cnt FROM {table}")
        total_count = old_cursor.fetchone()['cnt']
        
        offset = 0
        while offset < total_count:
            old_cursor.execute(f"SELECT * FROM {table} LIMIT {offset}, {batch_size}")
            records = old_cursor.fetchall()
            self.dual_write(table, records)
            offset += batch_size
            print(f"Progress: {offset}/{total_count} ({offset/total_count:.1%})")
        
        # Step 2: 数据校验
        print("\nStep 2: Verifying data consistency...")
        if not self.verify_data(table):
            raise Exception("Data verification failed, aborting migration")
        
        # Step 3: 切换读流量
        print("\nStep 3: Switching read traffic...")
        self.switch_read()
        
        # Step 4: 观察期（建议 24-48 小时）
        print("\nStep 4: Observation period (24-48 hours recommended)")
        # time.sleep(24 * 60 * 60)  # 实际场景等待 24 小时
        
        # Step 5: 切换写流量
        print("\nStep 5: Switching write traffic...")
        self.switch_write()
        
        print("\n✅ Migration completed successfully!")

# 使用示例
if __name__ == "__main__":
    old_db = mysql.connector.connect(host="old-db", user="root", password="pwd", database="orders")
    new_dbs = [
        mysql.connector.connect(host="new-db-0", user="root", password="pwd", database="orders_db_0"),
        mysql.connector.connect(host="new-db-1", user="root", password="pwd", database="orders_db_1"),
    ]
    
    migrator = ShardingMigration(old_db, new_dbs)
    migrator.migrate("t_order")
```

### 示例 3：跨分片查询优化（走 ES 聚合）

```python
# 方案：分库分表存储明细，Elasticsearch 存储索引用于复杂查询

from elasticsearch import Elasticsearch

class OrderQueryService:
    def __init__(self, es: Elasticsearch, order_mapper):
        self.es = es
        self.order_mapper = order_mapper
    
    def search_orders(self, user_id: int = None, 
                      status: str = None,
                      start_time: str = None,
                      end_time: str = None,
                      page: int = 1,
                      page_size: int = 20) -> Dict:
        """
        复杂查询走 ES，获取 ID 列表后再查分库分表获取详情
        """
        # Step 1: ES 查询获取匹配的订单 ID 列表
        query = {
            "query": {
                "bool": {
                    "must": [],
                    "filter": []
                }
            },
            "sort": [{"create_time": {"order": "desc"}}],
            "from": (page - 1) * page_size,
            "size": page_size,
            "_source": ["order_id"]
        }
        
        if user_id:
            query["query"]["bool"]["must"].append({"term": {"user_id": user_id}})
        if status:
            query["query"]["bool"]["filter"].append({"term": {"status": status}})
        if start_time and end_time:
            query["query"]["bool"]["filter"].append({
                "range": {"create_time": {"gte": start_time, "lte": end_time}}
            })
        
        es_result = self.es.search(index="orders", body=query)
        order_ids = [hit["_source"]["order_id"] for hit in es_result["hits"]["hits"]]
        total = es_result["hits"]["total"]["value"]
        
        # Step 2: 根据 ID 列表从分库分表查询详情（批量查询）
        if not order_ids:
            return {"orders": [], "total": 0}
        
        orders = self.order_mapper.batch_select_by_ids(order_ids)
        
        return {
            "orders": orders,
            "total": total,
            "page": page,
            "page_size": page_size
        }
    
    def sync_to_es(self, order: Dict):
        """订单变更后同步到 ES（异步）"""
        doc = {
            "order_id": order["order_id"],
            "user_id": order["user_id"],
            "status": order["status"],
            "amount": order["amount"],
            "create_time": order["create_time"]
        }
        self.es.index(index="orders", id=order["order_id"], document=doc)
```

## 常见坑与排查

### 坑 1：跨分片查询性能雪崩

**现象**：缺少分片键的查询导致全路由，8 个分片变 8 倍延迟。

```sql
-- ❌ 禁止：缺少分片键 user_id，需要查询所有分片
SELECT * FROM t_order WHERE status = 'PAID' AND create_time > '2026-07-01';

-- ✅ 推荐：包含分片键，精确路由到单个分片
SELECT * FROM t_order WHERE user_id = 12345 AND status = 'PAID';

-- ✅ 替代方案：复杂查询走 ES/ClickHouse
```

**排查方法**：
```yaml
# ShardingSphere 开启 SQL 日志
spring:
  shardingsphere:
    props:
      sql-show: true

# 日志输出会显示实际路由的分片
# Actual SQL: ds_0 ::: SELECT * FROM t_order_0 WHERE ...
# Actual SQL: ds_1 ::: SELECT * FROM t_order_1 WHERE ...
```

**解决方案**：
1. 应用层强制要求查询必须包含分片键
2. 复杂查询走 ES/ClickHouse 等 OLAP 引擎
3. 建立异构索引（MySQL → ES 同步）

### 坑 2：分布式事务数据不一致

**现象**：跨分片更新时，部分成功部分失败。

```java
// ❌ 错误：跨分片更新未使用事务
orderMapper.updateStatus(orderId1, "PAID");  // db_0
inventoryMapper.decrease(productId, 1);       // db_1，可能失败

// ✅ 方案 1：本地消息表 + 最终一致性
@Transactional
public void payOrder(Long orderId) {
    orderMapper.updateStatus(orderId, "PAID");
    // 写入本地消息表（同库事务）
    messageMapper.insert(new Message("DECREASE_INVENTORY", productId));
}

// 定时任务扫描消息表，调用库存服务
@Scheduled(fixedDelay = 5000)
public void processMessages() {
    List<Message> messages = messageMapper.findUnprocessed();
    for (Message msg : messages) {
        inventoryService.decrease(msg.getPayload());
        messageMapper.markProcessed(msg.getId());
    }
}

// ✅ 方案 2：Seata AT 模式（强一致性，性能较低）
@GlobalTransactional
public void payOrder(Long orderId) {
    orderMapper.updateStatus(orderId, "PAID");
    inventoryMapper.decrease(productId, 1);
}
```

**解决方案**：
- 优先使用最终一致性（本地消息表/事务消息）
- 强一致性场景使用 Seata/XA（接受性能损失）
- 业务设计尽量避免跨分片事务

### 坑 3：扩容时数据迁移导致服务不可用

**现象**：2 分片扩容到 4 分片时，全量数据迁移锁表。

**解决方案**：
1. **双写迁移法**（推荐）：
   - 阶段 1：开启双写（旧库 + 新分片同时写）
   - 阶段 2：后台迁移历史数据
   - 阶段 3：数据校验
   - 阶段 4：切换读流量
   - 阶段 5：观察 24-48 小时
   - 阶段 6：切换写流量（停双写）

2. **在线 DDL 工具**：
   - 使用 `pt-online-schema-change` 或 `gh-ost`
   - 基于 trigger 的增量同步，避免锁表

3. **分片键设计预留**：
   - 初期按较大分片数部署（如 8 库 32 表）
   - 逻辑分片映射到物理分片，扩容只需调整映射

### 坑 4：分布式 ID 时钟回拨

**现象**：服务器时间同步导致 Snowflake 生成重复 ID。

```python
# ❌ 未处理时钟回拨
def next_id(self):
    timestamp = int(time.time() * 1000)
    # 如果 timestamp < last_timestamp，会生成重复 ID！

# ✅ 处理时钟回拨
def next_id(self):
    timestamp = int(time.time() * 1000)
    
    if timestamp < self.last_timestamp:
        # 方案 1：等待直到时间追上
        time.sleep((self.last_timestamp - timestamp) / 1000 + 0.1)
        timestamp = int(time.time() * 1000)
        
        # 方案 2（推荐）：使用备用 worker_id
        # 时钟回拨期间切换到备用 ID，避免冲突
        if self.clock_backwards_count < 5:
            self.worker_id = self.backup_worker_id
            self.clock_backwards_count += 1
        else:
            raise Exception("Clock backwards too many times")
    
    # ... 正常逻辑
```

**解决方案**：
- 使用美团 Leaf 等成熟方案（内置时钟回拨处理）
- 部署 NTP 服务，确保时间同步
- 监控时钟回拨事件，及时告警

### 坑 5：分片键选择错误导致数据倾斜

**现象**：按 `status` 分片，导致 `PAID` 分片过大，`CANCELLED` 分片几乎为空。

```python
# ❌ 错误：按状态分片，数据严重倾斜
# status='PAID' 占 80%，status='CANCELLED' 占 5%
shard_id = hash(order.status) % shard_count

# ✅ 正确：按用户 ID 或订单 ID 分片，分布均匀
shard_id = hash(order.user_id) % shard_count
```

**分片键选择原则**：
1. **高基数**：分片键值域足够大（用户 ID > 状态）
2. **均匀分布**：避免热点（如按时间分片需注意新数据集中）
3. **查询友好**：分片键应出现在高频查询条件中
4. **业务稳定**：避免频繁变更的分片策略

## Checklist

### 分片策略设计

- [ ] 分片键选择：高基数、均匀分布、查询友好
- [ ] 分片数量规划：预留 2-3 倍扩容空间
- [ ] 分片算法选择：Hash（均匀）vs Range（范围查询）vs Geo（地域）
- [ ] 分布式 ID 方案：Snowflake/Leaf，避免 UUID

### 中间件选型

- [ ] ShardingSphere-JDBC：Java 应用、代码侵入低
- [ ] ShardingSphere-Proxy：多语言、独立部署
- [ ] Vitess：MySQL 原生、YouTube 验证
- [ ] Citus：PostgreSQL 扩展、分析场景

### 查询优化

- [ ] 强制查询包含分片键（应用层校验）
- [ ] 复杂查询走 ES/ClickHouse 异构索引
- [ ] 避免跨分片 JOIN（应用层组装或宽表冗余）
- [ ] 分页查询优化（游标分页替代 offset）

### 数据迁移

- [ ] 双写方案：旧库 + 新分片同时写
- [ ] 历史数据迁移：后台批处理，限流保护
- [ ] 数据校验：抽样对比 + 全量 checksum
- [ ] 灰度切换：读切换 → 观察 → 写切换

### 监控告警

- [ ] 分片数据量监控（避免倾斜）
- [ ] 跨分片查询比例告警（>5% 需优化）
- [ ] 分布式 ID 生成延迟监控
- [ ] 数据同步延迟监控（MySQL → ES）

### 容灾备份

- [ ] 每个分片独立备份策略
- [ ] 跨可用区部署（db_0 在 AZ1，db_1 在 AZ2）
- [ ] 故障自动切换（VIP 或 DNS 切换）
- [ ] 定期恢复演练

## 参考资料

1. **Apache ShardingSphere 官方文档** - 最全面的分库分表中间件文档，涵盖 JDBC/Proxy/侧车模式完整配置
   https://shardingsphere.apache.org/document/current/en/overview/

2. **美团数据库架构演进实践** - 从单库到分库分表再到 NewSQL 的完整演进路径，含 Leaf 分布式 ID 方案
   https://tech.meituan.com/2020/10/22/database-architecture-evolution.html

3. **Vitess: Horizontal Scaling for MySQL** - YouTube 开源的 MySQL 水平扩展方案，生产验证超过 10 年
   https://vitess.io/

4. **Citus Documentation** - PostgreSQL 分布式扩展，适合分析型负载
   https://docs.citusdata.com/

5. **《数据密集型应用系统设计》第 6 章** - 分区与复制的理论与实践，深入解析分片策略选择
   https://book.douban.com/subject/26197294/
