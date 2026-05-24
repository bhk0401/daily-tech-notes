-- Expand 阶段：添加加密邮箱字段
-- 此迁移脚本向后兼容，旧代码可继续运行

-- Step 1: 添加新字段（可空，保证向后兼容）
ALTER TABLE users 
ADD COLUMN encrypted_email VARCHAR(255) NULL COMMENT '加密后的邮箱地址';

-- Step 2: 添加索引（使用 CONCURRENTLY 避免锁表，PostgreSQL）
-- MySQL 8.0+ 支持 ALGORITHM=INPLACE, LOCK=NONE
ALTER TABLE users 
ADD INDEX idx_encrypted_email (encrypted_email),
ALGORITHM=INPLACE, LOCK=NONE;

-- Step 3: 添加触发器实现自动双写（可选，如应用层已实现双写可跳过）
DELIMITER $$
CREATE TRIGGER trg_users_encrypt_email_before_insert
BEFORE INSERT ON users
FOR EACH ROW
BEGIN
    IF NEW.email IS NOT NULL AND NEW.encrypted_email IS NULL THEN
        SET NEW.encrypted_email = AES_ENCRYPT(NEW.email, 'your-encryption-key');
    END IF;
END$$
DELIMITER ;

DELIMITER $$
CREATE TRIGGER trg_users_encrypt_email_before_update
BEFORE UPDATE ON users
FOR EACH ROW
BEGIN
    IF NEW.email IS NOT NULL AND (OLD.email != NEW.email OR NEW.encrypted_email IS NULL) THEN
        SET NEW.encrypted_email = AES_ENCRYPT(NEW.email, 'your-encryption-key');
    END IF;
END$$
DELIMITER ;

-- 验证：检查字段是否添加成功
DESCRIBE users;
SHOW INDEX FROM users WHERE Key_name = 'idx_encrypted_email';
