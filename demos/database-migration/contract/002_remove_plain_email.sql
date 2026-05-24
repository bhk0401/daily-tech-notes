-- Contract 阶段：删除旧字段
-- 执行前确认：
-- 1. 新字段 encrypted_email 100% 填充
-- 2. 所有应用已切换到读新字段
-- 3. 验证脚本通过
-- 4. 已备份数据

-- Step 1: 删除旧索引（如存在）
ALTER TABLE users DROP INDEX IF EXISTS idx_email;

-- Step 2: 删除旧字段
ALTER TABLE users DROP COLUMN email;

-- Step 3: （可选）重命名新字段保持 API 一致
-- 如果应用层已经切换到读 encrypted_email，可跳过此步
-- ALTER TABLE users CHANGE COLUMN encrypted_email email VARCHAR(255) NOT NULL;

-- Step 4: 添加 NOT NULL 约束（如需要）
ALTER TABLE users MODIFY COLUMN encrypted_email VARCHAR(255) NOT NULL;

-- Step 5: 删除触发器（如 Expand 阶段创建了触发器）
DROP TRIGGER IF EXISTS trg_users_encrypt_email_before_insert;
DROP TRIGGER IF EXISTS trg_users_encrypt_email_before_update;

-- 验证：检查表结构
DESCRIBE users;
SHOW INDEX FROM users;

-- 统计：确认记录数未变
SELECT COUNT(*) as total_records FROM users;
