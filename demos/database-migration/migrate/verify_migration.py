#!/usr/bin/env python3
"""
迁移验证脚本：检查数据一致性和完整性
"""

import os
import sys
import mysql.connector
from cryptography.fernet import Fernet

DB_CONFIG = {
    'host': os.getenv('DB_HOST', 'localhost'),
    'user': os.getenv('DB_USER', 'readonly_user'),
    'password': os.getenv('DB_PASSWORD', ''),
    'database': os.getenv('DB_NAME', 'users_db'),
}


def get_encryption_key() -> bytes:
    key_file = '/tmp/email_encryption.key'
    if os.path.exists(key_file):
        with open(key_file, 'rb') as f:
            return f.read()
    raise FileNotFoundError(f"Encryption key not found: {key_file}")


def check_fill_rate(conn) -> float:
    """检查新字段填充率"""
    cursor = conn.cursor()
    cursor.execute("""
        SELECT 
            COUNT(*) as total,
            SUM(CASE WHEN encrypted_email IS NOT NULL AND encrypted_email != '' THEN 1 ELSE 0 END) as encrypted,
            SUM(CASE WHEN email IS NOT NULL AND email != '' THEN 1 ELSE 0 END) as has_email
        FROM users
    """)
    total, encrypted, has_email = cursor.fetchone()
    cursor.close()
    
    if has_email == 0:
        return 100.0
    
    return (encrypted / has_email) * 100


def check_consistency(conn, sample_size=1000) -> tuple:
    """抽样检查数据一致性"""
    cursor = conn.cursor()
    cursor.execute("""
        SELECT id, email, encrypted_email 
        FROM users 
        WHERE email IS NOT NULL AND encrypted_email IS NOT NULL
        ORDER BY RAND() 
        LIMIT %s
    """, (sample_size,))
    
    fernet = Fernet(get_encryption_key())
    total = 0
    mismatches = 0
    decryption_errors = 0
    
    for user_id, email, encrypted in cursor.fetchall():
        total += 1
        try:
            decrypted = fernet.decrypt(encrypted.encode('utf-8')).decode('utf-8')
            if decrypted != email:
                mismatches += 1
                print(f"MISMATCH: id={user_id}, original={email}, decrypted={decrypted}")
        except Exception as e:
            decryption_errors += 1
            print(f"DECRYPT_ERROR: id={user_id}, error={e}")
    
    cursor.close()
    return total, mismatches, decryption_errors


def main():
    print("🔍 Starting migration verification...\n")
    
    conn = mysql.connector.connect(**DB_CONFIG)
    
    try:
        # 1. 检查填充率
        fill_rate = check_fill_rate(conn)
        print(f"📊 Fill Rate: {fill_rate:.2f}%")
        
        if fill_rate < 100:
            print(f"⚠️  WARNING: {100 - fill_rate:.2f}% of records not migrated yet")
            return 1
        
        # 2. 检查一致性
        total, mismatches, errors = check_consistency(conn)
        print(f"\n📋 Consistency Check: {total} samples")
        print(f"   - Mismatches: {mismatches}")
        print(f"   - Decryption Errors: {errors}")
        
        if mismatches > 0 or errors > 0:
            print("\n❌ VERIFICATION FAILED")
            return 1
        
        print("\n✅ VERIFICATION PASSED - Migration is complete and consistent!")
        return 0
        
    finally:
        conn.close()


if __name__ == '__main__':
    sys.exit(main())
