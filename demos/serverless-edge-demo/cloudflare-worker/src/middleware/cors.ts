// CORS 中间件 - 跨域资源共享处理
export function corsMiddleware(request: Request, allowedOrigins: string[] = ['*']): (handler: () => Promise<Response>) => Promise<Response> {
  const origin = request.headers.get('Origin') || '';
  const isAllowed = allowedOrigins.includes('*') || allowedOrigins.includes(origin);
  const allowedOrigin = isAllowed ? origin : allowedOrigins[0] || '*';
  
  // 处理预检请求
  if (request.method === 'OPTIONS') {
    return async () => new Response(null, {
      status: 204,
      headers: {
        'Access-Control-Allow-Origin': allowedOrigin,
        'Access-Control-Allow-Methods': 'GET, POST, PUT, DELETE, PATCH, OPTIONS',
        'Access-Control-Allow-Headers': 'Content-Type, Authorization, X-Requested-With, X-User-Id',
        'Access-Control-Max-Age': '86400',
        'Access-Control-Allow-Credentials': 'true',
      },
    });
  }
  
  // 返回包装函数
  return async (handler: () => Promise<Response>) => {
    const response = await handler();
    
    // 添加 CORS Header
    response.headers.set('Access-Control-Allow-Origin', allowedOrigin);
    response.headers.set('Access-Control-Allow-Credentials', 'true');
    response.headers.set('Access-Control-Expose-Headers', 'X-RateLimit-Limit, X-RateLimit-Remaining, X-Request-Id');
    
    return response;
  };
}
