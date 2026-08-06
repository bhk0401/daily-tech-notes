# gRPC-Web 实战：浏览器直连 gRPC 服务的完整指南

> 发布日期：2026-08-06  
> 领域：云架构 / 前端 / 网关  
> 字数：约 2800 字

---

## 背景与目标

在现代微服务架构中，gRPC 凭借其高性能、强类型契约和双向流式能力，已成为服务间通信的事实标准。然而，gRPC 基于 HTTP/2 的二进制协议特性，使得浏览器无法直接调用 gRPC 服务——浏览器原生只支持 HTTP/1.1 和部分 HTTP/2 功能，且不支持 gRPC 所需的 Trailers 头部。

这一限制迫使开发者在浏览器与 gRPC 服务之间引入额外的适配层，常见方案包括：

1. **REST API 网关**：将 gRPC 转换为 REST/JSON，但丢失了 gRPC 的类型安全和流式能力
2. **BFF（Backend for Frontend）**：为前端定制聚合层，增加了架构复杂度
3. **gRPC-Web + Envoy Proxy**：官方推荐方案，保持 gRPC 优势的同时支持浏览器调用

本文聚焦第三种方案，深入讲解 gRPC-Web 的工作原理、Envoy 代理配置、以及生产环境中的最佳实践。目标是帮助团队在不牺牲性能的前提下，实现浏览器与 gRPC 服务的直连通信。

**核心收益**：
- 保持前后端使用同一套 Protobuf 契约，消除 API 不一致风险
- 支持双向流式通信，实现真正的实时交互
- 减少 JSON 序列化开销，提升传输效率 30-50%
- 自动生成 TypeScript 类型定义，提升开发体验

---

## 核心概念

### gRPC-Web 协议差异

gRPC-Web 是 gRPC 的变体协议，专为浏览器环境设计。它与标准 gRPC 的关键差异在于：

| 特性 | gRPC (HTTP/2) | gRPC-Web |
|------|---------------|----------|
| 内容类型 | `application/grpc` | `application/grpc-web+proto` |
| Trailers | 原生支持 | 通过特殊帧模拟 |
| 流式支持 | 单向/双向 | 仅服务器流式（双向需特殊处理） |
| 浏览器兼容 | ❌ 不支持 | ✅ 支持 |

gRPC-Web 客户端发送的请求格式：
```
+------------------+------------------+
|   gRPC-Web Frame |   Protobuf Payload |
+------------------+------------------+
|    5 bytes       |    N bytes        |
+------------------+------------------+
```

其中 Frame Header 包含：
- 1 byte：标志位（0=数据，1=Trailers）
- 4 bytes：消息长度（大端序）

### Envoy 代理角色

Envoy 作为 gRPC-Web 与 gRPC 之间的协议转换器，承担以下职责：

1. **协议转换**：将 gRPC-Web 帧转换为标准 gRPC HTTP/2 帧
2. **Trailers 处理**：提取 gRPC-Web 的 trailers 帧并转换为 HTTP/2 trailers
3. **CORS 管理**：处理浏览器的跨域预检请求
4. **负载均衡**：将请求分发到后端 gRPC 服务实例

### 代码生成工作流

gRPC-Web 使用独立的代码生成器 `protoc-gen-grpc-web`，与标准 gRPC 的 `protoc-gen-go` 或 `protoc-gen-java` 并行使用：

```
┌─────────────┐    ┌──────────────────┐    ┌─────────────────┐
│  .proto     │───▶│ protoc + plugins │───▶│ service.ts      │
│  文件        │    │ - grpc-web       │    │ (浏览器客户端)   │
│             │    │ - ts             │    │                 │
└─────────────┘    └──────────────────┘    └─────────────────┘
                          │
                          ▼
                   ┌─────────────────┐
                   │ service_pb.js   │
                   │ (Protobuf 消息)  │
                   └─────────────────┘
```

---

## 实战/示例

### 环境准备

首先安装必要的工具链：

```bash
# 安装 protoc 和插件
brew install protoc
go install github.com/grpc/grpc-web/cmd/protoc-gen-grpc-web@latest
npm install -g ts-protoc-gen

# 验证安装
protoc --version
protoc-gen-grpc-web --version
```

### 定义 Protobuf 契约

创建 `chat.proto`，定义一个简单的聊天服务：

```protobuf
syntax = "proto3";

package chat;

// 请求消息
message ChatRequest {
  string user_id = 1;
  string message = 2;
  int64 timestamp = 3;
}

// 响应消息
message ChatResponse {
  string response_id = 1;
  string content = 2;
  int64 timestamp = 3;
  bool is_stream_end = 4;
}

// 聊天服务定义
service ChatService {
  // 单向 RPC：发送消息并等待响应
  rpc SendMessage(ChatRequest) returns (ChatResponse);
  
  // 服务器流式 RPC：发送消息后接收流式响应
  rpc StreamMessage(ChatRequest) returns (stream ChatResponse);
}
```

### 生成 TypeScript 客户端代码

使用 protoc 生成浏览器可用的 TypeScript 代码：

```bash
protoc -I=. \
  --grpc-web_out=import_style=typescript,mode=grpcwebtext:. \
  --ts_out=service=true:. \
  chat.proto
```

生成的文件：
- `chat_pb.ts`：Protobuf 消息类的 TypeScript 定义
- `ChatServiceClientPb.ts`：gRPC-Web 客户端封装

### 浏览器客户端实现

创建 `chat-client.ts`：

```typescript
import { ChatServiceClient } from './ChatServiceClientPb';
import { ChatRequest, ChatResponse } from './chat_pb';

// 初始化客户端（指向 Envoy 代理地址）
const client = new ChatServiceClient(
  'https://api.example.com', // Envoy 地址
  null, // 凭证（可选）
  { /* 自定义选项 */ }
);

// 单向 RPC 调用
async function sendMessage(userId: string, message: string): Promise<string> {
  const request = new ChatRequest();
  request.setUserId(userId);
  request.setMessage(message);
  request.setTimestamp(Date.now());

  return new Promise((resolve, reject) => {
    client.sendMessage(request, { customHeader: 'value' }, (err, response) => {
      if (err) {
        reject(err);
      } else {
        resolve(response.getContent());
      }
    });
  });
}

// 服务器流式调用
function streamMessage(userId: string, message: string) {
  const request = new ChatRequest();
  request.setUserId(userId);
  request.setMessage(message);
  request.setTimestamp(Date.now());

  const stream = client.streamMessage(request, { customHeader: 'value' });
  
  stream.on('data', (response: ChatResponse) => {
    console.log('收到响应:', response.getContent());
    if (response.getIsStreamEnd()) {
      console.log('流式传输结束');
    }
  });
  
  stream.on('error', (err: Error) => {
    console.error('流式传输错误:', err);
  });
  
  stream.on('status', (status: { code: number; details: string }) => {
    console.log('状态码:', status.code, '详情:', status.details);
  });
  
  return stream;
}
```

### Envoy 代理配置

创建 `envoy.yaml` 配置文件：

```yaml
admin:
  address:
    socket_address:
      address: 0.0.0.0
      port_value: 9901

static_resources:
  listeners:
  - name: grpc-web-listener
    address:
      socket_address:
        address: 0.0.0.0
        port_value: 8080
    filter_chains:
    - filters:
      - name: envoy.filters.network.http_connection_manager
        typed_config:
          "@type": type.googleapis.com/envoy.extensions.filters.network.http_connection_manager.v3.HttpConnectionManager
          codec_type: AUTO
          stat_prefix: ingress_http
          route_config:
            name: local_route
            virtual_hosts:
            - name: local_service
              domains: ["*"]
              routes:
              - match:
                  prefix: "/"
                route:
                  cluster: grpc-backend
                  max_stream_duration:
                    grpc_timeout_header_max: 0s
              cors:
                allow_origin_string_match:
                - prefix: "*"
                allow_methods: GET, PUT, DELETE, POST, OPTIONS
                allow_headers: keep-alive,user-agent,cache-control,content-type,content-transfer-encoding,custom-header-1,x-accept-content-transfer-encoding,x-accept-response-streaming,x-user-agent,x-grpc-web,grpc-timeout
                max_age: "1728000"
                expose_headers: custom-header-1,grpc-status,grpc-message
          http_filters:
          - name: envoy.filters.http.grpc_web
            typed_config:
              "@type": type.googleapis.com/envoy.extensions.filters.http.grpc_web.v3.GrpcWeb
          - name: envoy.filters.http.cors
            typed_config:
              "@type": type.googleapis.com/envoy.extensions.filters.http.cors.v3.Cors
          - name: envoy.filters.http.router
            typed_config:
              "@type": type.googleapis.com/envoy.extensions.filters.http.router.v3.Router

  clusters:
  - name: grpc-backend
    type: STRICT_DNS
    lb_policy: ROUND_ROBIN
    load_assignment:
      cluster_name: grpc-backend
      endpoints:
      - lb_endpoints:
        - endpoint:
            address:
              socket_address:
                address: chat-service
                port_value: 50051
    http2_protocol_options: {}
```

使用 Docker 运行 Envoy：

```bash
docker run -d \
  -p 8080:8080 \
  -p 9901:9901 \
  -v $(pwd)/envoy.yaml:/etc/envoy/envoy.yaml \
  envoyproxy/envoy:v1.28-latest \
  -c /etc/envoy/envoy.yaml --log-level info
```

### 后端 gRPC 服务（Go 示例）

```go
package main

import (
    "context"
    "fmt"
    "net"
    "time"

    "google.golang.org/grpc"
    pb "your-module/proto/chat"
)

type chatServer struct {
    pb.UnimplementedChatServiceServer
}

func (s *chatServer) SendMessage(ctx context.Context, req *pb.ChatRequest) (*pb.ChatResponse, error) {
    fmt.Printf("收到消息：用户=%s, 内容=%s\n", req.GetUserId(), req.GetMessage())
    
    return &pb.ChatResponse{
        ResponseId:   fmt.Sprintf("resp-%d", time.Now().UnixNano()),
        Content:      fmt.Sprintf("Echo: %s", req.GetMessage()),
        Timestamp:    time.Now().UnixMilli(),
        IsStreamEnd:  true,
    }, nil
}

func (s *chatServer) StreamMessage(req *pb.ChatRequest, stream pb.ChatService_StreamMessageServer) error {
    fmt.Printf("开始流式响应：用户=%s\n", req.GetUserId())
    
    // 模拟流式输出
    for i := 1; i <= 5; i++ {
        response := &pb.ChatResponse{
            ResponseId:  fmt.Sprintf("stream-%d", i),
            Content:     fmt.Sprintf("第 %d 条响应", i),
            Timestamp:   time.Now().UnixMilli(),
            IsStreamEnd: i == 5,
        }
        
        if err := stream.Send(response); err != nil {
            return err
        }
        time.Sleep(500 * time.Millisecond)
    }
    
    return nil
}

func main() {
    lis, err := net.Listen("tcp", ":50051")
    if err != nil {
        panic(err)
    }
    
    server := grpc.NewServer()
    pb.RegisterChatServiceServer(server, &chatServer{})
    
    fmt.Println("gRPC 服务启动在 :50051")
    server.Serve(lis)
}
```

---

## 常见坑与排查

### 1. CORS 预检失败

**症状**：浏览器控制台报错 `Access to fetch at '...' from origin '...' has been blocked by CORS policy`

**原因**：Envoy 的 CORS 配置未正确设置 `allow_headers` 或 `expose_headers`

**解决方案**：
```yaml
cors:
  allow_origin_string_match:
  - prefix: "https://your-frontend.com"
  allow_methods: GET, PUT, DELETE, POST, OPTIONS
  allow_headers: content-type,x-grpc-web,grpc-timeout,x-user-agent
  expose_headers: grpc-status,grpc-message
  max_age: "1728000"
```

**验证**：
```bash
curl -X OPTIONS https://api.example.com/chat.ChatService/SendMessage \
  -H "Origin: https://your-frontend.com" \
  -H "Access-Control-Request-Method: POST" \
  -H "Access-Control-Request-Headers: content-type,x-grpc-web" \
  -v | grep -i "access-control"
```

### 2. 流式响应中断

**症状**：服务器流式调用在中途断开，客户端收到 `cancelled` 错误

**原因**：
- Envoy 的 `max_stream_duration` 设置过短
- 后端服务未正确设置 `content-type: application/grpc-web+proto`
- 网络代理（如 Nginx）缓冲了流式响应

**解决方案**：
```yaml
# Envoy 配置
routes:
- match:
    prefix: "/"
  route:
    cluster: grpc-backend
    max_stream_duration:
      grpc_timeout_header_max: 0s  # 禁用超时
      max_stream_duration: 0s      # 无限制
```

```nginx
# 如果使用 Nginx 作为前置代理
location / {
    proxy_http_version 1.1;
    proxy_set_header Connection "";
    proxy_buffering off;      # 关键：禁用缓冲
    proxy_cache off;
    proxy_set_header Host $host;
}
```

### 3. TypeScript 类型不匹配

**症状**：编译错误 `Property 'setUserId' does not exist on type 'ChatRequest'`

**原因**：生成的代码使用了 CommonJS 模块系统，但项目配置为 ES Modules

**解决方案**：
```json
// tsconfig.json
{
  "compilerOptions": {
    "module": "commonjs",
    "esModuleInterop": true,
    "allowSyntheticDefaultImports": true
  }
}
```

或者使用 `import_style=commonjs+dts` 重新生成代码。

### 4. Trailers 丢失导致状态码错误

**症状**：客户端始终收到 `code: 2` (UNKNOWN) 错误，即使服务端返回成功

**原因**：Envoy 未正确提取 gRPC-Web 的 trailers 帧

**排查步骤**：
```bash
# 启用 Envoy 详细日志
docker logs <envoy-container> | grep -i "grpc"

# 检查响应头部
curl -v https://api.example.com/chat.ChatService/SendMessage \
  -H "content-type: application/grpc-web+proto" \
  -H "x-grpc-web: 1" \
  --data-binary @request.bin | grep -i "grpc-status"
```

**确保 Envoy 配置包含 grpc_web 过滤器**（顺序很重要）：
```yaml
http_filters:
- name: envoy.filters.http.grpc_web  # 必须在 cors 之前
- name: envoy.filters.http.cors
- name: envoy.filters.http.router
```

---

## Checklist

部署前逐项检查：

**Protobuf 契约**
- [ ] `.proto` 文件使用 `syntax = "proto3"`
- [ ] 服务定义同时兼容 gRPC 和 gRPC-Web
- [ ] 避免使用 gRPC-Web 不支持的特性（如双向流式）

**代码生成**
- [ ] 安装 `protoc-gen-grpc-web` 插件
- [ ] 使用 `--grpc-web_out=import_style=typescript,mode=grpcwebtext` 生成客户端
- [ ] 验证生成的 TypeScript 类型定义正确

**Envoy 配置**
- [ ] 监听器端口正确（通常 8080）
- [ ] CORS 配置覆盖前端域名
- [ ] `grpc_web` 过滤器在 `cors` 之前
- [ ] 后端 cluster 启用 `http2_protocol_options`
- [ ] 设置合理的 `max_stream_duration`

**网络安全**
- [ ] 生产环境启用 TLS（Envoy 或前置负载均衡器）
- [ ] 配置适当的 CORS 白名单（避免 `*`）
- [ ] 启用请求认证（JWT/mTLS）

**监控与日志**
- [ ] Envoy 访问日志记录 gRPC 状态码
- [ ] 配置 gRPC 指标导出（Prometheus）
- [ ] 设置流式超时告警

**性能优化**
- [ ] 启用连接池（Envoy `http2_protocol_options`）
- [ ] 配置合理的重试策略
- [ ] 考虑启用 gRPC 压缩（`grpc-accept-encoding: gzip`）

---

## 参考资料

1. **gRPC-Web 官方文档** - https://grpc.io/docs/platforms/web/basics/
   - 官方入门指南，包含协议说明和基础示例

2. **Envoy gRPC-Web 过滤器配置** - https://www.envoyproxy.io/docs/envoy/latest/configuration/http/http_filters/grpc_web_filter
   - 详细的 Envoy 配置参数和最佳实践

3. **grpc-web GitHub 仓库** - https://github.com/grpc/grpc-web
   - 源代码、示例项目和社区讨论

4. **Protobuf TypeScript 代码生成** - https://github.com/improbable-eng/grpc-web/tree/master/packages/grpc-web
   - improbable-eng 维护的 TypeScript 客户端库

5. **Envoy 官方示例** - https://github.com/grpc/grpc-web/tree/master/net/grpc/gateway/examples/helloworld
   - 完整的 HelloWorld 示例，包含前后端和 Envoy 配置

---

*本文档遵循 CC BY-SA 4.0 协议，欢迎转载和修改。*
