// 限流中间件 - 基于 IP 的速率限制
import { Env } from '../index';

export async function rateLimitMiddleware(request: Request | null, env: Env): Promise<Response | Request> {
  if (!request) return new Response('Internal error', { status: 500 });
  
  const url = new URL(request.url);
  
  // 跳过健康检查
  if (url.pathname === '/health') {
    return request;
  }
  
  // 获取客户端 IP
  const clientIP = request.headers.get('CF-Connecting-IP') || 'unknown';
  const key = `rate-limit:${clientIP}:${url.pathname}`;
  
  // 从环境变量获取限流配置
  const maxRequests = parseInt(env.RATE_LIMIT_MAX || '100');
  const windowMs = 60 * 1000; // 1 分钟窗口
  
  // 使用 KV 存储计数（需要配置 KV namespace）
  // 简化示例：使用内存计数（生产环境应使用 KV 或 Redis）
  const currentCount = await incrementCounter(key, windowMs);
  
  if (currentCount > maxRequests) {
    return new Response(JSON.stringify({
      error: 'Rate limit exceeded',
      retry_after: Math.ceil(windowMs / 1000),
    }), {
      status: 429,
      headers: {
        'Content-Type': 'application/json',
        'Retry-After': String(Math.ceil(windowMs / 1000)),
        'X-RateLimit-Limit': String(maxRequests),
        'X-RateLimit-Remaining': '0',
      },
    });
  }
  
  // 添加限流 Header
  const modifiedRequest = new Request(request, {
    headers: {
      ...request.headers,
      'X-RateLimit-Limit': String(maxRequests),
      'X-RateLimit-Remaining': String(maxRequests - currentCount),
    },
  });
  
  return modifiedRequest;
}

// 简单的计数器实现（生产环境应使用 KV/Redis）
const counters = new Map<string, { count: number; resetTime: number }>();

async function incrementCounter(key: string, windowMs: number): Promise<number> {
  const now = Date.now();
  const existing = counters.get(key);
  
  if (!existing || now > existing.resetTime) {
    // 新窗口
    counters.set(key, { count: 1, resetTime: now + windowMs });
    return 1;
  }
  
  // 现有窗口
  existing.count++;
  return existing.count;
}
