# API Gateway Demo

配套 2026-06-03 技术文档的完整示例代码。

## 快速开始

```bash
# 1. 启动环境
docker compose up -d

# 2. 等待 Kong 就绪
sleep 30

# 3. 运行测试
./test_gateway.sh
```

## 文件说明

- `docker-compose.yml` - 本地开发环境（Kong + Postgres + 后端服务）
- `generate_jwt.py` - JWT Token 生成脚本
- `test_gateway.sh` - 完整测试脚本
- `k8s/` - Kubernetes 生产部署配置

## 清理

```bash
docker compose down -v
```
