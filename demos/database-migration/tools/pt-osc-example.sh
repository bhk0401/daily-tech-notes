#!/bin/bash
# Percona pt-online-schema-change 示例脚本
# 文档：https://www.percona.com/doc/percona-toolkit/LATEST/pt-online-schema-change.html

set -e

# 配置
DB_HOST="prod-db.example.com"
DB_USER="migrate_user"
DB_PASS="${PT_OSC_PASSWORD}"
DB_NAME="users_db"
TABLE_NAME="users"

# DDL 变更：添加字段和索引
ALTER_STATEMENT="ADD COLUMN encrypted_email VARCHAR(255) NULL, ADD INDEX idx_encrypted_email (encrypted_email)"

# 执行 pt-osc
pt-online-schema-change \
  --user="${DB_USER}" \
  --password="${DB_PASS}" \
  --host="${DB_HOST}" \
  --alter="${ALTER_STATEMENT}" \
  D=${DB_NAME},t=${TABLE_NAME} \
  \
  # 性能调优
  --chunk-size=1000 \
  --chunk-time=0.5 \
  --max-lag=30s \
  \
  # 安全选项
  --no-drop-old-table \
  --recursion-method=processlist \
  \
  # 执行
  --execute

echo "✅ pt-online-schema-change completed successfully!"

# 清理（确认无误后手动执行）
# pt-online-schema-change --drop-old-table D=${DB_NAME},t=${TABLE_NAME}
