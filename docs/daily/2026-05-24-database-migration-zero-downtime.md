# 数据库迁移实战：生产环境零停机迁移策略

> 本文深入解析生产环境数据库 schema 变更的零停机迁移策略，涵盖扩展/收缩模式、向后兼容原则、数据双写迁移、在线 DDL 工具选型与回滚方案设计。适用于 MySQL/PostgreSQL 云数据库及自管集群，帮助团队在不停服的前提下安全完成数据库结构演进。

---

## 背景与目标

在云原生和微服务架构中，数据库迁移（Database Migration）是最常见也最危险的操作之一。传统的迁移方式往往需要停机维护窗口，但在 24/7 服务要求的今天，停机意味着收入损失、用户体验下降和 SLA 违约。

**典型场景：**

- 添加新字段支持新功能上线
- 修改字段类型（如 INT → BIGINT）
- 拆分大表（垂直/水平分表）
- 建立新索引优化查询性能
- 数据格式标准化（如时区统一）

**零停机迁移的核心挑战：**

1. **向后兼容性**：新旧代码必须能同时运行
2. **数据一致性**：迁移过程中数据不能丢失或损坏
3. **性能影响**：DDL 操作不能阻塞线上查询
4. **回滚能力**：出现问题能快速恢复

**本文目标：**

- 掌握扩展/收缩（Expand/Contract）迁移模式
- 理解向后兼容的 schema 变更原则
- 学会使用在线 DDL 工具（pt-online-schema-change、gh-ost）
- 设计可回滚的迁移流程与验证方案
- 获得生产级迁移 Checklist

---

## 核心概念

### 1. 扩展/收缩模式（Expand/Contract Pattern）

这是零停机迁移的标准范式，将迁移拆分为三个独立阶段：

```
┌─────────────┐    ┌─────────────┐    ┌─────────────┐
│   Expand    │ →  │   Migrate   │ →  │  Contract   │
│  (扩展)     │    │  (数据迁移)  │    │  (收缩)     │
└─────────────┘    └─────────────┘    └─────────────┘
   第 1 次部署          后台任务           第 2 次部署
```

**Expand 阶段**：添加新字段/表，保持旧字段，新旧代码兼容
**Migrate 阶段**：后台同步旧数据到新结构（可增量）
**Contract 阶段**：删除旧字段/表，完成迁移

### 2. 向后兼容原则

任何 schema 变更必须满足：**旧代码能在新 schema 上运行，新代码能在旧 schema 上运行**。

| 变更类型 | 是否兼容 | 说明 |
|---------|---------|------|
| 添加可空字段 | ✅ 兼容 | 旧代码忽略新字段 |
| 添加非空字段（有默认值） | ✅ 兼容 | 数据库提供默认值 |
| 添加非空字段（无默认值） | ❌ 不兼容 | 旧代码插入会失败 |
| 删除字段 | ❌ 不兼容 | 新代码读取会失败 |
| 重命名字段 | ❌ 不兼容 | 需要 Expand/Contract 两阶段 |
| 修改字段类型（兼容） | ⚠️ 谨慎 | 如 INT→BIGINT 通常安全 |
| 修改字段类型（不兼容） | ❌ 不兼容 | 如 VARCHAR→INT |

### 3. 在线 DDL（Online DDL）

传统 DDL 操作会锁表，阻塞读写。在线 DDL 工具通过以下策略避免锁表：

- **触发器复制**：在旧表上创建触发器，同步变更到新表
- **日志解析**：解析 binlog/redo log，回放变更到新表
- **影子表**：创建新表结构，逐步切换流量

**主流工具对比：**

| 工具 | 数据库 | 原理 | 特点 |
|-----|-------|------|------|
| pt-online-schema-change | MySQL | 触发器 + 影子表 | Percona 出品，成熟稳定 |
| gh-ost | MySQL | binlog 解析 | GitHub 开源，无触发器开销 |
| pg_repack | PostgreSQL | 日志回放 | 在线重建索引/表 |
| PostgreSQL 11+ | PostgreSQL | 内置在线 DDL | 部分操作原生支持 |

### 4. 数据双写与验证

在迁移期间，需要同时写入新旧两个字段/表，确保数据一致性：

```
应用层双写：
  INSERT INTO users (email, encrypted_email) 
  VALUES ('user@example.com', 'encrypted_value');

数据库触发器双写：
  CREATE TRIGGER sync_encrypted 
  BEFORE INSERT ON users
  FOR EACH ROW 
  SET NEW.encrypted_email = ENCRYPT(NEW.email);
```

**数据验证策略：**

- **抽样比对**：随机抽取 1% 记录比对
- **校验和比对**：计算新旧字段 checksum
- **全量扫描**：后台任务逐行验证（低优先级）

---

## 实战/示例

### 示例 1：添加加密邮箱字段（Expand/Contract 完整流程）

**场景**：合规要求邮箱加密存储，但需零停机迁移。

#### Step 1: Expand - 添加新字段

```sql
-- 迁移脚本：001_add_encrypted_email.sql
ALTER TABLE users 
ADD COLUMN encrypted_email VARCHAR(255) NULL,
ADD INDEX idx_encrypted_email (encrypted_email);
```

**应用代码变更（向后兼容）：**

```javascript
// user-service/src/models/user.js
class User {
  // 读取：优先读新字段，降级读旧字段
  getEmail() {
    return this.encrypted_email 
      ? decrypt(this.encrypted_email) 
      : this.email;
  }

  // 写入：双写新旧字段
  async save() {
    const encrypted = this.email ? encrypt(this.email) : null;
    
    await db.query(`
      INSERT INTO users (email, encrypted_email, created_at)
      VALUES (?, ?, NOW())
      ON DUPLICATE KEY UPDATE 
        email = VALUES(email),
        encrypted_email = VALUES(encrypted_email)
    `, [this.email, encrypted]);
  }
}
```

**部署第 1 次**：新代码上线，开始双写

#### Step 2: Migrate - 后台数据同步

```python
# migrate_encrypted_email.py
import mysql.connector
from cryptography.fernet import Fernet

def migrate_batch(offset, limit=1000):
    conn = mysql.connector.connect(
        host='prod-db.example.com',
        user='migrate_user',
        password='***',
        database='users_db'
    )
    cursor = conn.cursor()
    
    # 读取未加密的记录
    cursor.execute("""
      SELECT id, email FROM users 
      WHERE email IS NOT NULL 
        AND encrypted_email IS NULL
      LIMIT %s OFFSET %s
    """, (limit, offset))
    
    for user_id, email in cursor.fetchall():
        encrypted = Fernet.generate_key().encrypt(email.encode())
        cursor.execute("""
          UPDATE users 
          SET encrypted_email = %s 
          WHERE id = %s
        """, (encrypted, user_id))
    
    conn.commit()
    cursor.close()
    conn.close()
    
    return len(cursor.fetchall())

# 分批执行，避免长事务
offset = 0
while True:
    count = migrate_batch(offset)
    if count == 0:
        break
    offset += 1000
    print(f"Migrated {offset} records...")
```

**运行方式**：

```bash
# 作为后台 Job 运行，可中断续跑
nohup python3 migrate_encrypted_email.py > migration.log 2>&1 &

# 或用 systemd 定时任务
systemctl start email-migration.service
```

#### Step 3: 数据验证

```python
# verify_migration.py
def verify_sample():
    cursor.execute("""
      SELECT id, email, encrypted_email 
      FROM users 
      WHERE email IS NOT NULL 
      ORDER BY RAND() 
      LIMIT 100
    """)
    
    for user_id, email, encrypted in cursor.fetchall():
        decrypted = decrypt(encrypted)
        if decrypted != email:
            print(f"MISMATCH: user_id={user_id}")
            return False
    
    print("Sample verification passed!")
    return True
```

#### Step 4: Contract - 删除旧字段

**确认条件**：

- [ ] 新字段 100% 填充
- [ ] 验证脚本通过
- [ ] 所有应用已切换到读新字段
- [ ] 回滚方案已准备

```sql
-- 迁移脚本：002_remove_plain_email.sql
ALTER TABLE users 
DROP COLUMN email,
DROP INDEX idx_email;

-- 重命名新字段（可选，保持 API 一致）
ALTER TABLE users 
CHANGE COLUMN encrypted_email email VARCHAR(255) NOT NULL;
```

**部署第 2 次**：删除旧字段，完成迁移

### 示例 2：使用 gh-ost 在线修改大表结构

**场景**：orders 表 5000 万行，需添加索引且不能锁表。

```bash
# gh-ost 命令示例
gh-ost \
  --user="migrate_user" \
  --password="***" \
  --host="prod-db.example.com" \
  --database="orders_db" \
  --table="orders" \
  --alter="ADD INDEX idx_created_status (created_at, status)" \
  --chunk-size=1000 \
  --max-lag-millis=3000 \
  --throttle-control-replicas="replica1.example.com,replica2.example.com" \
  --execute
```

**关键参数说明：**

- `--chunk-size`：每批处理行数，避免长事务
- `--max-lag-millis`：允许的最大复制延迟
- `--throttle-control-replicas`：监控从库延迟，超阈值暂停

**监控进度：**

```bash
# gh-ost 输出实时进度
# Copy: 45000000/50000000 90.0%; Applied: 1500; Back: 0; Waiting: 0;
```

### 示例 3：PostgreSQL 在线创建索引

PostgreSQL 11+ 支持 `CREATE INDEX CONCURRENTLY`：

```sql
-- 传统方式（锁表，阻塞写入）
CREATE INDEX idx_orders_created ON orders(created_at);

-- 在线方式（不阻塞写入，但耗时更长）
CREATE INDEX CONCURRENTLY idx_orders_created ON orders(created_at);
```

**注意事项：**

- 不能在事务块内运行
- 需要两次表扫描，耗时约为传统方式的 2 倍
- 失败后需手动清理 `pg_index` 中的无效索引

---

## 常见坑与排查

### 坑 1：Expand 阶段添加非空字段无默认值

**现象**：旧代码插入数据失败，报错 `Column 'new_field' cannot be null`

**错误示例：**

```sql
-- ❌ 会导致旧代码插入失败
ALTER TABLE users ADD COLUMN age INT NOT NULL;
```

**正确做法：**

```sql
-- ✅ 添加可空字段或带默认值
ALTER TABLE users ADD COLUMN age INT NULL DEFAULT 0;

-- 或分两步走
ALTER TABLE users ADD COLUMN age INT NULL;
-- 后台填充数据
UPDATE users SET age = 0 WHERE age IS NULL;
-- 最后修改为 NOT NULL
ALTER TABLE users MODIFY COLUMN age INT NOT NULL DEFAULT 0;
```

### 坑 2：大表 DDL 导致主从复制延迟

**现象**：迁移期间从库延迟飙升，读流量切换到从库的业务报错

**排查：**

```sql
-- 检查复制延迟
SHOW SLAVE STATUS\G
-- 关注 Seconds_Behind_Master

-- 检查正在运行的 DDL
SHOW PROCESSLIST;
```

**解决方案：**

1. 使用在线 DDL 工具（gh-ost/pt-osc）而非原生 ALTER
2. 调小 chunk-size，降低单批处理量
3. 设置 throttle，当从库延迟超阈值时暂停
4. 在业务低峰期执行

### 坑 3：数据双写不一致

**现象**：迁移完成后，新旧字段数据对不上

**常见原因：**

- 双写逻辑有 bug（如事务未提交）
- 后台迁移任务中断未续跑
- 迁移期间有直接 SQL 更新绕过应用层

**排查脚本：**

```sql
-- 查找不一致的记录
SELECT id, email, encrypted_email
FROM users
WHERE email IS NOT NULL
  AND encrypted_email IS NOT NULL
  AND DECRYPT(encrypted_email) != email
LIMIT 100;

-- 统计不一致比例
SELECT 
  COUNT(*) as total,
  SUM(CASE WHEN DECRYPT(encrypted_email) != email THEN 1 ELSE 0 END) as mismatch,
  SUM(CASE WHEN DECRYPT(encrypted_email) != email THEN 1 ELSE 0 END) * 100.0 / COUNT(*) as mismatch_rate
FROM users
WHERE email IS NOT NULL AND encrypted_email IS NOT NULL;
```

**修复方案：**

```sql
-- 重新同步不一致的记录
UPDATE users u
SET encrypted_email = ENCRYPT(u.email)
WHERE u.email IS NOT NULL
  AND (u.encrypted_email IS NULL OR DECRYPT(u.encrypted_email) != u.email);
```

### 坑 4：回滚时数据丢失

**现象**：迁移失败回滚后，新字段写入的数据丢失

**根本原因**：Contract 阶段直接 DROP 字段，未保留新数据

**正确回滚策略：**

1. **Expand 失败**：直接回滚 DDL，无数据损失
2. **Migrate 失败**：停止迁移任务，保持双写，修复后继续
3. **Contract 失败**：
   - 先恢复旧代码（仍双写）
   - 将新字段数据同步回旧字段
   - 再执行回滚 DDL

```sql
-- Contract 失败回滚脚本
-- Step 1: 确保旧字段存在（如已删除需先恢复）
ALTER TABLE users ADD COLUMN email VARCHAR(255) NULL;

-- Step 2: 将新数据同步回旧字段
UPDATE users SET email = DECRYPT(encrypted_email) 
WHERE encrypted_email IS NOT NULL;

-- Step 3: 删除新字段
ALTER TABLE users DROP COLUMN encrypted_email;
```

### 坑 5：索引创建导致磁盘空间爆炸

**现象**：创建索引期间磁盘空间不足，迁移失败

**原因**：在线 DDL 工具需要影子表，临时占用约 2 倍空间

**预防措施：**

```bash
# 迁移前检查空间
df -h /var/lib/mysql

# 预估所需空间（表大小 × 2 + 20% 缓冲）
# 例：100GB 表需要约 240GB 可用空间

# 清理不必要的数据
OPTIMIZE TABLE old_logs;
PURGE BINARY LOGS BEFORE '2026-05-01';
```

---

## Checklist

### 迁移前准备

- [ ] **影响评估**：确认变更类型（兼容/不兼容）、影响范围（表大小、QPS）
- [ ] **工具选型**：小表用原生 DDL，大表用 gh-ost/pt-osc
- [ ] **空间检查**：确保磁盘空间 ≥ 表大小 × 2.5
- [ ] **备份策略**：迁移前全量备份 + binlog 开启
- [ ] **监控准备**：配置复制延迟、锁等待、慢查询告警
- [ ] **回滚方案**：编写回滚脚本并测试
- [ ] **时间窗口**：选择业务低峰期（如凌晨 2-5 点）
- [ ] **通知相关方**：告知运维、开发、业务方迁移时间

### Expand 阶段

- [ ] 新字段添加为 NULL 或带默认值
- [ ] 应用代码实现双写逻辑
- [ ] 灰度发布验证（1% → 10% → 50% → 100%）
- [ ] 监控错误率、延迟无异常

### Migrate 阶段

- [ ] 后台任务分批执行（每批 ≤ 1000 行）
- [ ] 设置速率限制，避免影响线上查询
- [ ] 监控从库复制延迟 < 30 秒
- [ ] 数据验证脚本通过（抽样 + 全量）
- [ ] 新字段填充率 100%

### Contract 阶段

- [ ] 确认所有应用已切换到读新字段
- [ ] 确认无旧字段读取依赖
- [ ] 准备快速回滚方案
- [ ] 灰度删除（先删除索引，再删除字段）
- [ ] 迁移完成后监控 24 小时

### 应急处理

- [ ] 发现数据不一致 → 停止迁移，修复双写逻辑
- [ ] 从库延迟 > 60 秒 → 降低 chunk-size 或暂停
- [ ] 磁盘空间不足 → 清理 binlog/临时文件
- [ ] 应用报错率上升 → 立即回滚到上一版本
- [ ] DDL 卡死 → kill 会话，检查锁等待

---

## 参考资料

1. **GitHub - gh-ost**: GitHub 开源的在线 schema 迁移工具，无触发器开销，支持实时暂停/恢复
   - https://github.com/github/gh-ost

2. **Percona pt-online-schema-change**: Percona Toolkit 的在线 DDL 工具，基于触发器实现，成熟稳定
   - https://www.percona.com/doc/percona-toolkit/LATEST/pt-online-schema-change.html

3. **MySQL 8.0 Reference Manual - Online DDL**: MySQL 官方文档，详解原生在线 DDL 支持的操作类型
   - https://dev.mysql.com/doc/refman/8.0/en/online-ddl.html

4. **PostgreSQL Documentation - CREATE INDEX CONCURRENTLY**: PostgreSQL 官方文档，介绍在线创建索引的用法与限制
   - https://www.postgresql.org/docs/current/sql-createindex.html#SQL-CREATEINDEX-CONCURRENTLY

5. **Expand/Contract Pattern by Martin Fowler**: 零停机数据库重构的经典模式说明
   - https://martinfowler.com/articles/expand-contract-pattern.html

6. **Database Migration Best Practices (AWS)**: AWS 官方数据库迁移最佳实践指南
   - https://docs.aws.amazon.com/prescriptive-guidance/latest/database-migration-best-practices/welcome.html

---

**附录：demos/ 目录示例**

本文配套示例代码位于：`demos/database-migration/`

```
demos/database-migration/
├── expand/
│   ├── 001_add_encrypted_email.sql    # Expand 阶段 DDL
│   └── user_model_dual_write.js       # 双写应用代码
├── migrate/
│   ├── migrate_encrypted_email.py     # 数据同步脚本
│   └── verify_migration.py            # 数据验证脚本
├── contract/
│   ├── 002_remove_plain_email.sql     # Contract 阶段 DDL
│   └── rollback_contract.sql          # 回滚脚本
└── tools/
    ├── gh-ost-example.sh              # gh-ost 命令示例
    └── pt-osc-example.sh              # pt-osc 命令示例
```

运行示例：

```bash
# 1. 执行 Expand
mysql -h prod-db -u admin -p < demos/database-migration/expand/001_add_encrypted_email.sql

# 2. 运行数据迁移（后台）
nohup python3 demos/database-migration/migrate/migrate_encrypted_email.py &

# 3. 验证数据
python3 demos/database-migration/migrate/verify_migration.py

# 4. 执行 Contract（确认无误后）
mysql -h prod-db -u admin -p < demos/database-migration/contract/002_remove_plain_email.sql
```
