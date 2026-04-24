# 容器基础：镜像分层、构建缓存与多阶段 Dockerfile

## 背景与目标

在容器化应用部署中，Docker 镜像的质量直接影响构建速度、存储成本和生产环境的安全性。许多团队在初期往往只关注"能跑起来"，忽略了镜像优化，导致生产镜像动辄数百 MB 甚至上 GB，包含大量不必要的构建工具和源码。

本文目标是通过理解 Docker 镜像分层机制、利用构建缓存、掌握多阶段构建（Multi-stage Builds）三大核心技术，帮助你将生产镜像体积缩小 50%-90%，同时提升构建效率和安全性。最终产出是一个可直接用于生产环境的优化实践方案。

## 核心概念

**镜像分层（Layer）**：Docker 镜像由多个只读层叠加而成，每个 Dockerfile 指令（如 RUN、COPY、ADD）都会创建新层。分层机制支持复用和缓存，但层数过多会影响性能。理解分层原理是优化的基础。

**构建缓存（Build Cache）**：Docker 会缓存每一层的构建结果。当某层及其之前所有层都未变化时，直接复用缓存。缓存失效的常见原因是指令顺序不当或使用了动态内容（如 COPY . .过早）。

**多阶段构建（Multi-stage Builds）**：Docker 17.05+ 引入的革命性特性。允许在一个 Dockerfile 中使用多个 FROM 指令，每个阶段可以有不同的基础镜像。最终镜像只包含最后一个阶段的内容，完美解决"构建依赖"与"运行时依赖"的分离问题。

关键原则：层缓存从上到下逐层匹配；多阶段构建中只有最后阶段被保留；每个阶段可以命名（AS 关键字段）便于引用。

## 实战/示例

### 示例 1：传统单阶段构建（优化前）

```dockerfile
# Dockerfile.naive
FROM node:20-alpine

WORKDIR /app

# 问题：先 COPY 所有文件，任何改动都会使后续 npm install 缓存失效
COPY . .

RUN npm install && npm run build

EXPOSE 3000
CMD ["node", "dist/server.js"]
```

**问题**：
- 镜像包含 node_modules 中的 devDependencies
- 包含 TypeScript 源码和构建工具
- 任何文件改动都导致 npm install 重新执行
- 最终镜像约 500MB+

### 示例 2：多阶段构建（优化后）

```dockerfile
# Dockerfile.optimized
# ========== 构建阶段 ==========
FROM node:20-alpine AS builder

WORKDIR /app

# 先复制依赖声明文件，利用缓存
COPY package*.json ./

# 仅安装生产依赖（可选：构建时需要全部依赖）
RUN npm ci --only=production

# 再复制源码，此时 npm install 层已缓存
COPY . .

RUN npm run build

# ========== 生产阶段 ==========
FROM node:20-alpine AS production

WORKDIR /app

# 只复制构建产物和生产依赖
COPY --from=builder /app/node_modules ./node_modules
COPY --from=builder /app/dist ./dist
COPY --from=builder /app/package.json ./

# 创建非 root 用户运行（安全最佳实践）
RUN addgroup -g 1001 -S nodejs && \
    adduser -S nodejs -u 1001

USER nodejs

EXPOSE 3000
CMD ["node", "dist/server.js"]
```

**优化效果**：
- 镜像体积：500MB → 150MB（减少 70%）
- 构建缓存命中率显著提升
- 生产镜像不包含构建工具和源码
- 非 root 用户运行，安全性提升

### 示例 3：Go 语言多阶段构建（极致优化）

```dockerfile
# Go 多阶段构建示例
FROM golang:1.21-alpine AS builder

WORKDIR /app
COPY go.mod go.sum ./
RUN go mod download

COPY . .
RUN CGO_ENABLED=0 GOOS=linux go build -a -installsuffix cgo -o main .

# 使用 scratch 或 alpine 作为最终镜像
FROM alpine:latest AS production

RUN apk --no-cache add ca-certificates

WORKDIR /root/
COPY --from=builder /app/main .

CMD ["./main"]
```

**极致效果**：使用 scratch 基础镜像时，最终镜像可小于 20MB。

## 常见坑与排查

**坑 1：COPY . . 位置不当导致缓存失效**
- 现象：每次构建都重新执行 npm install/pip install
- 解决：先复制依赖声明文件（package.json/requirements.txt），执行安装后再复制源码

**坑 2：层数过多影响性能**
- 现象：镜像层数超过 50 层，pull/push 缓慢
- 解决：合并 RUN 指令，如 `RUN apt-get update && apt-get install -y xxx && rm -rf /var/lib/apt/lists/*`

**坑 3：多阶段引用错误**
- 现象：COPY --from=xxx 失败，提示阶段不存在
- 解决：确保阶段名称正确，或使用数字索引（COPY --from=0）

**坑 4：.dockerignore 缺失导致上下文过大**
- 现象：构建前发送数 GB 到 Docker daemon
- 解决：创建 .dockerignore 文件，排除 node_modules、.git、dist 等

**排查命令**：
```bash
# 查看镜像层信息
docker history <image-name>

# 查看构建缓存使用情况
docker build --progress=plain -t myapp .

# 分析镜像各层大小
docker images --format "{{.Repository}}:{{.Tag}} - Size: {{.Size}}"
```

## Checklist

- [ ] 使用多阶段构建分离构建环境和运行环境
- [ ] 依赖安装指令在 COPY 源码之前执行
- [ ] 使用 .dockerignore 排除不必要的文件
- [ ] 合并 RUN 指令减少层数
- [ ] 生产镜像使用非 root 用户运行
- [ ] 移除不必要的文件和缓存（如 apt cache、npm cache）
- [ ] 选择合适的基础镜像（alpine/distroless 优先）
- [ ] 最终镜像体积 < 200MB（Node.js 应用参考）
- [ ] 至少 2 条参考链接已添加到文档

## 参考资料

1. Docker 官方文档 - 多阶段构建：https://docs.docker.com/build/building/multi-stage/
2. Docker 最佳实践指南：https://docs.docker.com/develop/develop-images/dockerfile_best-practices/
3. Google Distroless 镜像（极简生产镜像）：https://github.com/GoogleContainerTools/distroless
4. Docker 镜像层分析工具 - Dive：https://github.com/wagoodman/dive
