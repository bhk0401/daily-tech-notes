# Distributed Locking Patterns: Redis、etcd 与数据库方案生产实践

## 背景与目标

在分布式系统中，多个服务实例经常需要协调对共享资源的访问。无论是防止重复订单处理、确保定时任务单实例执行、还是控制并发库存扣减，**分布式锁**都是解决这类问题的核心机制。

本文深入解析三种主流分布式锁实现方案：**Redis 锁**（高性能场景）、**etcd 锁**（强一致性场景）、**数据库锁**（简单场景），涵盖核心原理、完整代码实现、生产级容错机制与选型指南。通过本文，你将掌握：

- 分布式锁的核心属性：互斥性、防死锁、容错性、可重入性
- Redis 锁的 Redlock 算法与 Lua 脚本原子操作
- etcd 锁的 Lease 机制与 Watch 监听
- 数据库锁的乐观锁与悲观锁实现
- 生产环境常见坑排查与选型决策树

**适用场景**：订单去重、库存扣减、定时任务防并发、配置变更同步、资源配额控制

## 核心概念

### 分布式锁的四大核心属性

一个可靠的分布式锁必须满足以下属性：

| 属性 | 说明 | 实现方式 |
|------|------|----------|
| **互斥性** | 任意时刻只有一个客户端持有锁 | 原子操作（SETNX/CAS/Lease） |
| **防死锁** | 锁持有者崩溃后锁能自动释放 | TTL 过期机制 + Lease |
| **容错性** | 部分节点故障不影响锁服务 | 多节点部署 + 多数派确认 |
| **可重入性** | 同一客户端可重复获取已持有的锁 | 客户端标识 + 计数器 |

### 三种锁方案对比

| 特性 | Redis 锁 | etcd 锁 | 数据库锁 |
|------|----------|---------|----------|
| **一致性模型** | 最终一致性 | 强一致性 (线性化) | 取决于隔离级别 |
| **性能** | 高 (单节点 10w+ QPS) | 中 (万级 QPS) | 低 (千级 QPS) |
| **可用性** | 高 (AP 系统) | 中 (CP 系统) | 取决于主库 |
| **实现复杂度** | 中 | 高 | 低 |
| **适用场景** | 缓存层/高性能 | 配置中心/强一致 | 简单业务/已有 DB |

### Redlock 算法原理

Redis 分布式锁的标准实现是 **Redlock 算法**，核心步骤：

1. 获取当前时间戳 T1
2. 依次向 N 个独立 Redis 节点发起锁请求（TTL 通常较小，如 50-200ms）
3. 计算获取锁耗时 T2 = 当前时间 - T1
4. 成功条件：≥ (N/2 + 1) 个节点成功 + T2 < TTL
5. 锁有效期 = TTL - T2

```
客户端 A                          Redis 集群
   |                                 |
   |--(1) SET lock_A T1 100ms NX -->| Node 1 ✓
   |--(2) SET lock_A T1 100ms NX -->| Node 2 ✓
   |--(3) SET lock_A T1 100ms NX -->| Node 3 ✓
   |--(4) SET lock_A T1 100ms NX -->| Node 4 ✗ (超时)
   |--(5) SET lock_A T1 100ms NX -->| Node 5 ✓
   |                                 |
   |<-- 4/5 成功，锁获取成功 ---------|
```

### etcd Lease 机制

etcd 通过 **Lease（租约）** 实现分布式锁，核心优势：

- Lease 绑定 Key，Lease 过期自动删除 Key
- 支持 Watch 监听，锁释放时立即通知等待者
- 线性化一致性，适合强一致场景

```
客户端 A                          etcd 集群
   |                                 |
   |-- Lease Grant(30s) ------------>| 返回 LeaseID=0x1234
   |-- Txn: PUT /lock (Lease=0x1234) >| 原子操作
   |                                 |
   |-- KeepAlive(0x1234) ----------->| 每 10s 续期
   |                                 |
   |-- 崩溃/网络断开 ---------------->| Lease 30s 后过期，Key 自动删除
```

## 实战/示例

### 示例 1：Redis 分布式锁（Python + redis-py）

```python
# demos/distributed-lock/redis_lock.py
import redis
import time
import uuid
from typing import Optional
from contextlib import contextmanager

class RedisDistributedLock:
    """生产级 Redis 分布式锁实现"""
    
    def __init__(self, redis_client: redis.Redis, lock_name: str, 
                 ttl_ms: int = 10000, retry_times: int = 3, retry_delay_ms: int = 200):
        self.client = redis_client
        self.lock_name = f"lock:{lock_name}"
        self.ttl_ms = ttl_ms
        self.retry_times = retry_times
        self.retry_delay_ms = retry_delay_ms
        self.lock_id = str(uuid.uuid4())
        
        # Lua 脚本：原子释放锁（防止误删其他客户端的锁）
        self.release_script = self.client.register_script("""
            if redis.call("get", KEYS[1]) == ARGV[1] then
                return redis.call("del", KEYS[1])
            else
                return 0
            end
        """)
    
    def acquire(self) -> bool:
        """获取锁，支持重试"""
        for attempt in range(self.retry_times):
            # SET key value NX EX milliseconds - 原子操作
            acquired = self.client.set(
                self.lock_name,
                self.lock_id,
                nx=True,
                ex=self.ttl_ms // 1000
            )
            if acquired:
                return True
            if attempt < self.retry_times - 1:
                time.sleep(self.retry_delay_ms / 1000)
        return False
    
    def release(self) -> bool:
        """释放锁（Lua 脚本保证原子性）"""
        try:
            return bool(self.release_script(keys=[self.lock_name], args=[self.lock_id]))
        except redis.exceptions.RedisError as e:
            print(f"释放锁失败：{e}")
            return False
    
    @contextmanager
    def lock(self):
        """上下文管理器用法"""
        if self.acquire():
            try:
                yield True
            finally:
                self.release()
        else:
            yield False

# 使用示例
if __name__ == "__main__":
    redis_client = redis.Redis(host='localhost', port=6379, db=0)
    
    # 方式 1：手动获取/释放
    lock = RedisDistributedLock(redis_client, "order-dedup-12345")
    if lock.acquire():
        try:
            print("获取锁成功，处理订单...")
            # 处理业务逻辑
        finally:
            lock.release()
    
    # 方式 2：上下文管理器（推荐）
    with RedisDistributedLock(redis_client, "inventory-decrement").lock() as acquired:
        if acquired:
            print("获取锁成功，扣减库存...")
        else:
            print("获取锁失败，跳过或重试")
```

### 示例 2：etcd 分布式锁（Python + etcd3）

```python
# demos/distributed-lock/etcd_lock.py
import etcd3
import time
import threading
from contextlib import contextmanager
from typing import Optional, Callable

class EtcdDistributedLock:
    """生产级 etcd 分布式锁实现"""
    
    def __init__(self, etcd_client: etcd3.Etcd3Client, lock_name: str,
                 lease_ttl: int = 30, acquire_timeout: int = 10):
        self.client = etcd_client
        self.lock_name = f"/locks/{lock_name}"
        self.lease_ttl = lease_ttl
        self.acquire_timeout = acquire_timeout
        self.lease = None
        self.lock_key = None
    
    def acquire(self, blocking: bool = True) -> bool:
        """获取锁，支持阻塞等待"""
        start_time = time.time()
        
        # 创建 Lease
        self.lease = self.client.lease(self.lease_ttl)
        
        while True:
            # 尝试获取锁：在 lock_name 下创建顺序 Key
            lock_key = f"{self.lock_name}/{self.lease.id}"
            
            # 使用事务原子创建
            success, _ = self.client.transaction(
                compare=[
                    self.client.transactions.version(self.lock_name) == 0
                ],
                success=[
                    self.client.transactions.put(lock_key, self.lease.id, lease=self.lease)
                ],
                failure=[]
            )
            
            if success:
                self.lock_key = lock_key
                return True
            
            if not blocking:
                return False
            
            # 检查超时
            if time.time() - start_time > self.acquire_timeout:
                self.lease.revoke()
                return False
            
            # 等待锁释放（Watch 机制）
            self._wait_for_lock()
    
    def _wait_for_lock(self):
        """Watch 锁 Key，等待释放通知"""
        events_iterator, cancel = self.client.watch(self.lock_name)
        try:
            # 等待 5 秒或直到有事件
            for event in events_iterator:
                break
        finally:
            cancel()
    
    def release(self) -> bool:
        """释放锁"""
        try:
            if self.lock_key:
                self.client.delete(self.lock_key)
            if self.lease:
                self.lease.revoke()
            return True
        except Exception as e:
            print(f"释放锁失败：{e}")
            return False
    
    @contextmanager
    def lock(self, blocking: bool = True):
        """上下文管理器用法"""
        if self.acquire(blocking=blocking):
            try:
                yield True
            finally:
                self.release()
        else:
            yield False

# 使用示例
if __name__ == "__main__":
    etcd_client = etcd3.client(host='localhost', port=2379)
    
    with EtcdDistributedLock(etcd_client, "config-sync").lock() as acquired:
        if acquired:
            print("获取锁成功，同步配置...")
            # 同步配置逻辑
```

### 示例 3：数据库乐观锁（MySQL）

```sql
-- demos/distributed-lock/database_lock.sql

-- 方案 1：乐观锁（version 字段）
CREATE TABLE inventory (
    id INT PRIMARY KEY,
    product_name VARCHAR(100),
    stock INT NOT NULL,
    version INT NOT NULL DEFAULT 0
);

-- 扣减库存（带版本号检查）
UPDATE inventory 
SET stock = stock - 1, version = version + 1
WHERE id = 123 
  AND stock >= 1 
  AND version = :current_version;

-- 应用层伪代码
def decrement_inventory(product_id: int, quantity: int) -> bool:
    max_retries = 3
    for attempt in range(max_retries):
        # 1. 读取当前库存和版本号
        row = db.query(
            "SELECT stock, version FROM inventory WHERE id = ?", 
            product_id
        )
        
        # 2. 检查库存是否充足
        if row.stock < quantity:
            return False
        
        # 3. 乐观锁更新
        updated = db.execute(
            """UPDATE inventory 
               SET stock = stock - ?, version = version + 1
               WHERE id = ? AND version = ?""",
            quantity, product_id, row.version
        )
        
        if updated > 0:
            return True  # 更新成功
        
        # 4. 更新失败，重试
        time.sleep(0.1 * (attempt + 1))  # 退避
    
    return False  # 重试耗尽

-- 方案 2：悲观锁（SELECT ... FOR UPDATE）
START TRANSACTION;

-- 锁定行（其他事务无法读取/更新）
SELECT stock FROM inventory 
WHERE id = 123 
FOR UPDATE;

-- 执行业务逻辑
UPDATE inventory SET stock = stock - 1 WHERE id = 123;

COMMIT;
```

### Demo 项目结构

```
demos/distributed-lock/
├── redis_lock.py          # Redis 锁实现
├── etcd_lock.py           # etcd 锁实现
├── database_lock.py       # 数据库锁实现
├── docker-compose.yml     # 本地测试环境
├── requirements.txt       # Python 依赖
└── test_locks.py          # 并发测试脚本
```

```yaml
# demos/distributed-lock/docker-compose.yml
version: '3.8'
services:
  redis:
    image: redis:7-alpine
    ports:
      - "6379:6379"
    command: redis-server --appendonly yes
  
  etcd:
    image: quay.io/coreos/etcd:v3.5.9
    ports:
      - "2379:2379"
      - "2380:2380"
    environment:
      - ETCD_LISTEN_CLIENT_URLS=http://0.0.0.0:2379
      - ETCD_ADVERTISE_CLIENT_URLS=http://0.0.0.0:2379
  
  mysql:
    image: mysql:8.0
    ports:
      - "3306:3306"
    environment:
      - MYSQL_ROOT_PASSWORD=test123
      - MYSQL_DATABASE=lock_demo
```

## 常见坑与排查

### 坑 1：Redis 锁误删其他客户端的锁

**问题现象**：客户端 A 的锁过期后，客户端 B 获取锁。但 A 恢复后执行释放操作，误删了 B 的锁。

**错误代码**：
```python
# ❌ 错误：直接 DEL 可能删除其他客户端的锁
redis.delete("lock:order-123")
```

**解决方案**：使用 Lua 脚本原子检查 + 删除
```python
# ✅ 正确：只有锁 ID 匹配才删除
release_script = """
    if redis.call("get", KEYS[1]) == ARGV[1] then
        return redis.call("del", KEYS[1])
    else
        return 0
    end
"""
```

### 坑 2：锁过期但业务未完成（TTL 设置不当）

**问题现象**：业务逻辑执行时间超过锁 TTL，锁自动释放，其他客户端获取锁导致并发问题。

**排查步骤**：
```bash
# 1. 监控锁持有时间
redis-cli --latency -h localhost

# 2. 检查慢查询日志
redis-cli slowlog get 10

# 3. 分析业务耗时分布
# 在锁获取/释放处打点监控
```

**解决方案**：
- 合理设置 TTL（业务最大耗时的 1.5-2 倍）
- 实现锁续期机制（Watchdog 模式）
- 业务设计为幂等，允许并发时安全重试

```python
# 锁续期实现（Watchdog）
class RedisLockWithWatchdog(RedisDistributedLock):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        self._stop_watchdog = threading.Event()
    
    def _watchdog(self):
        """后台线程自动续期"""
        while not self._stop_watchdog.is_set():
            if self._stop_watchdog.wait(self.ttl_ms / 3000):
                break
            # 原子续期（同样需要 Lua 脚本）
            self._extend_lock()
    
    def acquire(self) -> bool:
        if super().acquire():
            self._stop_watchdog.clear()
            threading.Thread(target=self._watchdog, daemon=True).start()
            return True
        return False
    
    def release(self) -> bool:
        self._stop_watchdog.set()
        return super().release()
```

### 坑 3：etcd 锁 Watch 连接断开

**问题现象**：客户端 Watch 锁释放时，网络抖动导致连接断开，错过锁释放通知。

**解决方案**：
- 实现 Watch 重连机制
- 设置合理的 acquire_timeout
- 使用阻塞式 acquire 而非纯 Watch

```python
def acquire_with_retry(self, max_retries: int = 3) -> bool:
    for attempt in range(max_retries):
        try:
            if self.acquire(blocking=True):
                return True
        except etcd3.exceptions.ConnectionFailedError:
            if attempt == max_retries - 1:
                raise
            time.sleep(2 ** attempt)  # 指数退避
    return False
```

### 坑 4：数据库死锁

**问题现象**：两个事务互相等待对方释放锁，导致永久阻塞。

**排查步骤**：
```sql
-- MySQL 查看死锁信息
SHOW ENGINE INNODB STATUS;

-- 查看当前锁等待
SELECT * FROM information_schema.INNODB_LOCK_WAITS;

-- 查看事务状态
SELECT * FROM information_schema.INNODB_TRX;
```

**解决方案**：
- 固定锁获取顺序（如按 ID 排序）
- 设置合理的锁超时（innodb_lock_wait_timeout）
- 使用乐观锁替代悲观锁

### 坑 5：Redis 主从切换导致锁丢失

**问题现象**：客户端 A 在 Master 节点获取锁，但锁未同步到 Slave。Master 宕机后，Slave 晋升为新 Master，锁丢失。

**解决方案**：
1. 使用 **Redlock 算法**（多独立节点，多数派确认）
2. 启用 Redis **AOF + RDB** 持久化
3. 业务层实现**幂等性**，容忍锁丢失

```python
# Redlock 实现（多节点）
class Redlock:
    def __init__(self, redis_nodes: list, lock_name: str, ttl_ms: int = 10000):
        self.nodes = [redis.Redis(**node) for node in redis_nodes]
        self.lock_name = f"lock:{lock_name}"
        self.ttl_ms = ttl_ms
    
    def acquire(self) -> bool:
        start_time = time.time()
        successful_nodes = 0
        
        for node in self.nodes:
            try:
                if node.set(self.lock_name, self.lock_id, nx=True, ex=self.ttl_ms//1000):
                    successful_nodes += 1
            except redis.exceptions.RedisError:
                continue
        
        elapsed_ms = (time.time() - start_time) * 1000
        quorum = len(self.nodes) // 2 + 1
        
        return successful_nodes >= quorum and elapsed_ms < self.ttl_ms
```

## Checklist

### 选型决策

- [ ] **高性能/缓存层场景** → 选择 Redis 锁（Redlock 算法）
- [ ] **强一致性/配置中心场景** → 选择 etcd 锁
- [ ] **简单业务/已有数据库** → 选择数据库乐观锁
- [ ] **跨数据中心部署** → 避免 Redis 锁，选择 etcd 或数据库

### Redis 锁实施检查

- [ ] 使用 Lua 脚本原子释放锁（防止误删）
- [ ] 设置合理 TTL（业务耗时 1.5-2 倍）
- [ ] 实现锁续期机制（长任务场景）
- [ ] 部署至少 3 个独立 Redis 节点（Redlock）
- [ ] 业务逻辑实现幂等性

### etcd 锁实施检查

- [ ] 使用 Lease 绑定 Key（自动过期）
- [ ] 实现 Watch 重连机制
- [ ] 设置合理的 acquire_timeout
- [ ] 部署至少 3 个 etcd 节点
- [ ] 监控 Lease 续期状态

### 数据库锁实施检查

- [ ] 乐观锁：添加 version 字段
- [ ] 悲观锁：固定锁获取顺序（防死锁）
- [ ] 设置合理的锁超时时间
- [ ] 实现重试机制（指数退避）
- [ ] 监控死锁日志

### 监控与告警

- [ ] 锁获取失败率监控（>5% 告警）
- [ ] 锁持有时间监控（>TTL 80% 告警）
- [ ] 锁等待时间监控（P99 > 1s 告警）
- [ ] 锁服务可用性监控（多节点健康检查）

## 参考资料

1. **Redis 官方文档 - Distributed Locks** - https://redis.io/docs/manual/distributed-locks/
   - Redlock 算法官方说明与实现细节

2. **etcd 官方文档 - Concurrency** - https://etcd.io/docs/v3.5/learning/concurrency/
   - Lease 机制与分布式锁实现

3. **Martin Kleppmann - How to do distributed locking** - https://martin.kleppmann.com/2016/02/08/how-to-do-distributed-locking.html
   - 分布式锁深度分析文章（Redlock 争议讨论）

4. **MySQL 官方文档 - InnoDB Locking** - https://dev.mysql.com/doc/refman/8.0/en/innodb-locking.html
   - 悲观锁/乐观锁/死锁处理官方指南

5. **GitHub - redis/redis-py** - https://github.com/redis/redis-py
   - Python Redis 客户端官方实现

6. **GitHub - etcd-io/etcd** - https://github.com/etcd-io/etcd
   - etcd 官方仓库与客户端库
