#!/usr/bin/env python3
"""
数据迁移脚本：将明文邮箱批量加密到新字段
支持断点续跑，适合大表迁移
"""

import os
import sys
import time
import logging
from typing import Tuple, Optional

import mysql.connector
from mysql.connector import Error
from cryptography.fernet import Fernet

# 配置日志
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

# 配置
DB_CONFIG = {
    'host': os.getenv('DB_HOST', 'localhost'),
    'user': os.getenv('DB_USER', 'migrate_user'),
    'password': os.getenv('DB_PASSWORD', ''),
    'database': os.getenv('DB_NAME', 'users_db'),
    'port': int(os.getenv('DB_PORT', '3306')),
}

BATCH_SIZE = 1000  # 每批处理行数
SLEEP_BETWEEN_BATCHES = 0.5  # 批次间休眠时间（秒），避免影响线上查询
STATE_FILE = '/tmp/migrate_email_offset.txt'  # 断点续跑状态文件


def get_encryption_key() -> bytes:
    """获取或生成加密密钥"""
    key_file = '/tmp/email_encryption.key'
    
    if os.path.exists(key_file):
        with open(key_file, 'rb') as f:
            return f.read()
    else:
        key = Fernet.generate_key()
        with open(key_file, 'wb') as f:
            f.write(key)
        logger.info(f"Generated new encryption key: {key_file}")
        return key


def load_offset() -> int:
    """加载上次迁移的偏移量"""
    if os.path.exists(STATE_FILE):
        with open(STATE_FILE, 'r') as f:
            return int(f.read().strip())
    return 0


def save_offset(offset: int) -> None:
    """保存当前偏移量"""
    with open(STATE_FILE, 'w') as f:
        f.write(str(offset))


def encrypt_email(email: str, fernet: Fernet) -> str:
    """加密邮箱地址"""
    return fernet.encrypt(email.encode('utf-8')).decode('utf-8')


def migrate_batch(
    conn: mysql.connector.MySQLConnection,
    fernet: Fernet,
    offset: int,
    batch_size: int
) -> Tuple[int, bool]:
    """
    迁移一批数据
    
    Returns:
        (processed_count, has_more): 处理数量和是否还有更多数据
    """
    cursor = conn.cursor()
    
    try:
        # 读取未加密的记录
        cursor.execute("""
            SELECT id, email FROM users 
            WHERE email IS NOT NULL 
              AND email != ''
              AND (encrypted_email IS NULL OR encrypted_email = '')
            LIMIT %s OFFSET %s
        """, (batch_size, offset))
        
        rows = cursor.fetchall()
        
        if not rows:
            return 0, False
        
        # 批量更新
        update_query = """
            UPDATE users 
            SET encrypted_email = %s 
            WHERE id = %s
        """
        
        for user_id, email in rows:
            try:
                encrypted = encrypt_email(email, fernet)
                cursor.execute(update_query, (encrypted, user_id))
            except Exception as e:
                logger.error(f"Failed to encrypt email for user {user_id}: {e}")
                continue
        
        conn.commit()
        logger.info(f"Migrated {len(rows)} records (offset: {offset})")
        
        return len(rows), True
        
    except Error as e:
        logger.error(f"Database error: {e}")
        conn.rollback()
        raise
    finally:
        cursor.close()


def verify_migration(conn: mysql.connector.MySQLConnection, sample_size: int = 100) -> bool:
    """验证迁移结果"""
    cursor = conn.cursor()
    
    try:
        # 检查填充率
        cursor.execute("""
            SELECT 
                COUNT(*) as total,
                SUM(CASE WHEN encrypted_email IS NOT NULL AND encrypted_email != '' THEN 1 ELSE 0 END) as encrypted,
                SUM(CASE WHEN email IS NOT NULL AND email != '' THEN 1 ELSE 0 END) as has_email
            FROM users
        """)
        
        total, encrypted, has_email = cursor.fetchone()
        
        if has_email == 0:
            logger.info("No email records to migrate")
            return True
        
        fill_rate = (encrypted / has_email * 100) if has_email > 0 else 0
        logger.info(f"Migration fill rate: {fill_rate:.2f}% ({encrypted}/{has_email})")
        
        if fill_rate < 100:
            logger.warning(f"Migration incomplete: {has_email - encrypted} records remaining")
            return False
        
        # 抽样验证解密
        if sample_size > 0:
            cursor.execute("""
                SELECT id, email, encrypted_email 
                FROM users 
                WHERE email IS NOT NULL AND encrypted_email IS NOT NULL
                ORDER BY RAND() 
                LIMIT %s
            """, (sample_size,))
            
            fernet = Fernet(get_encryption_key())
            mismatches = 0
            
            for user_id, email, encrypted in cursor.fetchall():
                try:
                    decrypted = fernet.decrypt(encrypted.encode('utf-8')).decode('utf-8')
                    if decrypted != email:
                        logger.error(f"MISMATCH: user_id={user_id}, email={email}, decrypted={decrypted}")
                        mismatches += 1
                except Exception as e:
                    logger.error(f"Decryption failed for user {user_id}: {e}")
                    mismatches += 1
            
            if mismatches > 0:
                logger.error(f"Verification failed: {mismatches} mismatches")
                return False
            
            logger.info(f"Verification passed: {sample_size} samples decrypted successfully")
        
        return True
        
    finally:
        cursor.close()


def main():
    """主函数"""
    logger.info("Starting email encryption migration...")
    
    # 初始化
    fernet = Fernet(get_encryption_key())
    offset = load_offset()
    logger.info(f"Starting from offset: {offset}")
    
    # 连接数据库
    try:
        conn = mysql.connector.connect(**DB_CONFIG)
        logger.info(f"Connected to {DB_CONFIG['host']}:{DB_CONFIG['port']}")
    except Error as e:
        logger.error(f"Failed to connect to database: {e}")
        sys.exit(1)
    
    try:
        # 批量迁移
        while True:
            processed, has_more = migrate_batch(conn, fernet, offset, BATCH_SIZE)
            
            if not has_more:
                logger.info("Migration completed!")
                break
            
            offset += processed
            save_offset(offset)
            
            # 休眠避免影响线上查询
            time.sleep(SLEEP_BETWEEN_BATCHES)
        
        # 验证
        logger.info("Running verification...")
        if verify_migration(conn):
            logger.info("✅ Migration verified successfully!")
        else:
            logger.error("❌ Verification failed! Please check logs.")
            sys.exit(1)
            
    except KeyboardInterrupt:
        logger.info(f"Migration interrupted. Current offset: {offset}")
        logger.info("Run again to resume from this point.")
    except Exception as e:
        logger.error(f"Migration failed: {e}")
        sys.exit(1)
    finally:
        conn.close()


if __name__ == '__main__':
    main()
