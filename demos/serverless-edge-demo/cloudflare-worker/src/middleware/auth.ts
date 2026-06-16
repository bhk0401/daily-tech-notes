// 认证中间件 - JWT 验证
import { Env } from '../index';

export async function authMiddleware(request: Request, env: Env): Promise<Response | null> {
  const url = new URL(request.url);
  
  // 跳过健康检查和公开端点
  if (url.pathname === '/health' || url.pathname === '/public') {
    return null; // 继续处理
  }
  
  const authHeader = request.headers.get('Authorization');
  
  if (!authHeader || !authHeader.startsWith('Bearer ')) {
    return new Response(JSON.stringify({ error: 'Missing or invalid authorization' }), {
      status: 401,
      headers: { 'Content-Type': 'application/json' },
    });
  }
  
  const token = authHeader.split(' ')[1];
  
  try {
    // 简单的 JWT 验证（生产环境应使用完整 JWT 库）
    const payload = JSON.parse(atob(token.split('.')[1]));
    
    // 检查过期时间
    if (payload.exp && payload.exp < Date.now() / 1000) {
      return new Response(JSON.stringify({ error: 'Token expired' }), {
        status: 401,
        headers: { 'Content-Type': 'application/json' },
      });
    }
    
    // 验证签名（简化示例）
    if (payload.iss !== env.JWT_SECRET) {
      return new Response(JSON.stringify({ error: 'Invalid token signature' }), {
        status: 401,
        headers: { 'Content-Type': 'application/json' },
      });
    }
    
    // 将用户信息添加到请求头传递给下游
    const modifiedRequest = new Request(request, {
      headers: {
        ...request.headers,
        'X-User-Id': payload.sub,
        'X-User-Role': payload.role || 'user',
      },
    });
    
    return modifiedRequest;
  } catch (error) {
    return new Response(JSON.stringify({ error: 'Invalid token format' }), {
      status: 401,
      headers: { 'Content-Type': 'application/json' },
    });
  }
}
