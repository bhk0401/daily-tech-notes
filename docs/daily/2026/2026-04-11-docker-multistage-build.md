# 容器基础：镜像分层、构建缓存与多阶段 Dockerfile

## 背景与目标

Docker 镜像体积直接影响 CI/CD 效率和运行时成本。本文讲解镜像分层、构建缓存及多阶段构建技巧，帮助你将生产镜像体积减少 50%-90%。

## 核心概念

**镜像分层**：Docker 镜像由多个只读层叠加，每层对应一条指令（RUN/COPY/ADD）。层是增量存储的，相同内容会被复用。

**构建缓存**：Docker 按序执行指令，每层都有缓存。若某层及之前所有层未变化则命中缓存，否则后续层全部重建。

**多阶段构建**：同一 Dockerfile 使用多个 FROM，每个开启新阶段。最终镜像只包含最后阶段产物，中间阶段的编译器等依赖不会进入生产镜像。

## 实战/示例

### Go 应用多阶段构建

传统单阶段（约 800MB）：
```dockerfile
FROM golang:1.21
WORKDIR /app
COPY . .
RUN go build -o server cmd/main.go
CMD ["./server"]
```

多阶段优化（约 15MB，减少 98%）：
```dockerfile
FROM golang:1.21-alpine AS builder
WORKDIR /app
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 GOOS=linux go build -a -o server cmd/main.go

FROM alpine:3.18
RUN apk --no-cache add ca-certificates
WORKDIR /root/
COPY --from=builder /app/server .
CMD ["./server"]
```

### 本地验证
```bash
docker build -t myapp:multistage .
docker run -p 8080:8080 myapp:multistage
curl http://localhost:8080/health
```

完整示例见 `demos/docker-multistage/`。

## 常见坑与排查

**缓存失效过早**：将 COPY . . 放后面，依赖安装放前面，避免每次代码变更都重装依赖。

**层数过多**：合并连续 RUN 指令，用 && 连接，减少元数据开销。

**敏感信息泄露**：不要硬编码密码，即使多阶段构建也不会清除历史层。使用 BuildKit 的 `--secret` 参数。

## Checklist

- [ ] 使用多阶段构建分离编译和运行环境
- [ ] 选择轻量级基础镜像（alpine/distroless）
- [ ] 合并 RUN 指令，减少层数
- [ ] 变化频繁的指令放 Dockerfile 后面
- [ ] 使用 .dockerignore 排除 node_modules、.git 等
- [ ] 定期扫描漏洞（docker scout / trivy）

## 参考资料

1. Docker Multi-stage builds: https://docs.docker.com/build/building/multi-stage/
2. Dockerfile 最佳实践：https://docs.docker.com/develop/develop-images/dockerfile_best-practices/
3. Distroless：https://github.com/GoogleContainerTools/distroless
