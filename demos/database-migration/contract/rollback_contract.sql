-- Contract 阶段回滚脚本
-- 当删除旧字段后发现问题时使用

-- Step 1: 恢复旧字段
ALTER TABLE users ADD COLUMN email VARCHAR(255) NULL;

-- Step 2: 将新字段数据解密回旧字段
-- 注意：需要在应用层实现解密逻辑，或使用存储过程
-- 这里假设有一个 DECRYPT 函数
UPDATE users u
SET u.email = DECRYPT(u.encrypted_email)
WHERE u.encrypted_email IS NOT NULL;

-- 或者使用应用脚本批量回写（推荐）
-- python3 rollback_decrypt_emails.py

-- Step 3: 添加旧索引
ALTER TABLE users ADD INDEX idx_email (email);

-- Step 4: 恢复触发器（如需要）
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

-- Step 5: 验证回滚
SELECT 
    COUNT(*) as total,
    SUM(CASE WHEN email IS NOT NULL THEN 1 ELSE 0 END) as has_email,
    SUM(CASE WHEN encrypted_email IS NOT NULL THEN 1 ELSE 0 END) as has_encrypted
FROM users;

-- 回滚完成后，重新部署旧版本应用代码
