#!/bin/bash
# gh-ost 在线 DDL 示例脚本
# 文档：https://github.com/github/gh-ost

set -e

# 配置
DB_HOST="prod-db.example.com"
DB_USER="migrate_user"
DB_PASS="${GH_OST_PASSWORD}"
DB_NAME="users_db"
TABLE_NAME="users"

# DDL 变更：添加索引
ALTER_STATEMENT="ADD INDEX idx_encrypted_email (encrypted_email)"

# 执行 gh-ost
gh-ost \
  --user="${DB_USER}" \
  --password="${DB_PASS}" \
  --host="${DB_HOST}" \
  --database="${DB_NAME}" \
  --table="${TABLE_NAME}" \
  --alter="${ALTER_STATEMENT}" \
  \
  # 性能调优
  --chunk-size=1000 \
  --max-lag-millis=3000 \
  --throttle-control-replicas="replica1.example.com,replica2.example.com" \
  \
  # 安全选项
  --allow-on-master \
  --initially-drop-ghost-table \
  --initially-drop-old-table \
  \
  # 监控与通知
  --panic-flag-file=/tmp/gh-ost-panic \
  --postpone-cut-over-flag-file=/tmp/gh-ost-cut-over \
  \
  # 执行模式
  --execute

echo "✅ gh-ost completed successfully!"
