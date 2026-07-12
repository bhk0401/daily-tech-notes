# BFF Pattern Demo

本目录包含 Backend for Frontend (BFF) 模式的完整可运行示例。

## 快速启动

```bash
# 使用 Docker Compose 启动所有服务
docker-compose up -d

# 测试 BFF 端点
curl http://localhost:3000/api/homepage \
  -H "x-user-id: user-001" | jq

# 查看日志
docker-compose logs -f bff
```

## 架构说明

```
┌─────────────┐     ┌─────────────────────────────────────────┐
│   Client    │────▶│              BFF (Port 3000)            │
│             │     │  - 并行调用下游服务                       │
└─────────────┘     │  - 聚合响应数据                           │
                    │  - 处理部分失败                           │
                    └─────────────────────────────────────────┘
                                         │
         ┌───────────────────────────────┼───────────────────────────────┐
         ▼                               ▼                               ▼
┌─────────────────┐           ┌─────────────────┐           ┌─────────────────┐
│ User Service    │           │ Product Service │           │ Cart Service    │
│ (Port 3001)     │           │ (Port 3002)     │           │ (Port 3004)     │
└─────────────────┘           └─────────────────┘           └─────────────────┘
```

## 文件结构

```
demos/bff-pattern/
├── docker-compose.yml      # Docker Compose 配置
├── Dockerfile              # BFF 服务镜像
├── package.json            # Node.js 依赖
├── gateway-aggregator.ts   # BFF 聚合逻辑（TypeScript）
├── README.md               # 本文件
└── mocks/                  # Mock 下游服务数据
    ├── user/
    ├── product/
    ├── promotion/
    └── cart/
```

## 测试场景

1. **正常请求**：所有服务正常响应
2. **部分失败**：模拟某个服务宕机，验证降级逻辑
3. **超时测试**：调整服务响应时间，验证超时处理
