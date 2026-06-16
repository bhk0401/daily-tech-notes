// Cloudflare Workers 主入口
import { authMiddleware } from './middleware/auth';
import { rateLimitMiddleware } from './middleware/rate-limit';
import { corsMiddleware } from './middleware/cors';
import { apiHandler } from './handlers/api';

export interface Env {
  JWT_SECRET: string;
  RATE_LIMIT_MAX: string;
  KV_STORE: KVNamespace;
}

export default {
  async fetch(request: Request, env: Env, ctx: ExecutionContext): Promise<Response> {
    const requestId = crypto.randomUUID();
    const startTime = Date.now();
    
    try {
      // CORS 预检请求处理
      if (request.method === 'OPTIONS') {
        const corsHandler = corsMiddleware(request);
        return corsHandler(async () => new Response(null, { status: 204 }));
      }
      
      // 健康检查端点（无需认证）
      const url = new URL(request.url);
      if (url.pathname === '/health') {
        return Response.json({
          status: 'healthy',
          timestamp: new Date().toISOString(),
          request_id: requestId,
        });
      }
      
      // 中间件链：认证 → 限流 → CORS
      const authResult = await authMiddleware(request, env);
      if (authResult instanceof Response) {
        return authResult; // 认证失败，直接返回
      }
      
      const rateLimitResult = await rateLimitMiddleware(authResult as Request, env);
      if (rateLimitResult instanceof Response) {
        return rateLimitResult; // 限流触发，直接返回
      }
      
      const corsHandler = corsMiddleware(rateLimitResult as Request);
      
      // 路由分发
      let response: Response;
      if (url.pathname.startsWith('/api/')) {
        response = await apiHandler(rateLimitResult as Request, env);
      } else {
        response = new Response(JSON.stringify({ error: 'Not found' }), {
          status: 404,
          headers: { 'Content-Type': 'application/json' },
        });
      }
      
      // 应用 CORS
      const corsResponse = await corsHandler(async () => response);
      
      // 添加通用 Header
      corsResponse.headers.set('X-Request-Id', requestId);
      corsResponse.headers.set('X-Response-Time', `${Date.now() - startTime}ms`);
      corsResponse.headers.set('X-Served-By', 'cloudflare-worker');
      
      return corsResponse;
      
    } catch (error) {
      // 全局错误处理
      console.error(`[ERROR] ${requestId}:`, error);
      
      return new Response(JSON.stringify({
        error: 'Internal server error',
        request_id: requestId,
      }), {
        status: 500,
        headers: {
          'Content-Type': 'application/json',
          'X-Request-Id': requestId,
        },
      });
    }
  },
};
