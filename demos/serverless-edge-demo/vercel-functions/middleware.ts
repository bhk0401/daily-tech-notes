// Vercel Middleware - 边缘中间件
import type { NextRequest, NextResponse } from 'next/server';

export function middleware(request: NextRequest) {
  const { pathname } = request.nextUrl;
  const startTime = Date.now();
  
  // 添加请求 ID
  const requestId = crypto.randomUUID();
  const requestHeaders = new Headers(request.headers);
  requestHeaders.set('X-Request-Id', requestId);
  requestHeaders.set('X-Start-Time', startTime.toString());
  
  // 地理位置信息（Vercel Edge 提供）
  const geo = request.geo;
  if (geo) {
    requestHeaders.set('X-Country', geo.country || 'unknown');
    requestHeaders.set('X-City', geo.city || 'unknown');
    requestHeaders.set('X-Region', geo.region || 'unknown');
  }
  
  // 速率限制检查（简化示例）
  const ip = request.headers.get('x-forwarded-for') || 'unknown';
  const rateLimitKey = `rate-limit:${ip}`;
  
  // 这里可以使用 Vercel KV 进行真正的限流
  // const count = await kv.incr(rateLimitKey);
  // if (count > 100) {
  //   return new Response('Rate limit exceeded', { status: 429 });
  // }
  
  // 继续处理请求
  const response = NextResponse.next({
    request: {
      headers: requestHeaders,
    },
  });
  
  // 添加响应 Header
  response.headers.set('X-Request-Id', requestId);
  response.headers.set('X-Served-By', 'vercel-edge');
  
  // 计算响应时间（在响应中设置，实际值在响应完成后更新）
  response.headers.set('X-Response-Time-Start', startTime.toString());
  
  return response;
}

export const config = {
  matcher: [
    /*
     * 匹配所有 API 路由
     */
    '/api/:path*',
  ],
};
