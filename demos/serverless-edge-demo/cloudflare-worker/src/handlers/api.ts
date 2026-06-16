// API 路由处理
import { Env } from '../index';

export async function apiHandler(request: Request, env: Env): Promise<Response> {
  const url = new URL(request.url);
  const path = url.pathname;
  
  // 路由分发
  if (path === '/api/echo') {
    return handleEcho(request);
  }
  
  if (path === '/api/time') {
    return handleTime(request);
  }
  
  if (path.startsWith('/api/users/')) {
    return handleUsers(request, path);
  }
  
  return new Response(JSON.stringify({ error: 'Not found' }), {
    status: 404,
    headers: { 'Content-Type': 'application/json' },
  });
}

async function handleEcho(request: Request): Promise<Response> {
  const body = request.method !== 'GET' ? await request.text() : null;
  
  return Response.json({
    method: request.method,
    url: request.url,
    headers: Object.fromEntries(request.headers.entries()),
    body: body,
    timestamp: new Date().toISOString(),
  });
}

async function handleTime(request: Request): Promise<Response> {
  const url = new URL(request.url);
  const timezone = url.searchParams.get('tz') || 'UTC';
  
  try {
    const now = new Date();
    const timeInTz = new Date(now.toLocaleString('en-US', { timeZone: timezone }));
    
    return Response.json({
      timezone: timezone,
      iso: timeInTz.toISOString(),
      local: timeInTz.toLocaleString(),
      unix: Math.floor(timeInTz.getTime() / 1000),
    });
  } catch (error) {
    return Response.json({ error: `Invalid timezone: ${timezone}` }, { status: 400 });
  }
}

async function handleUsers(request: Request, path: string): Promise<Response> {
  const userId = path.split('/').pop();
  
  if (request.method === 'GET') {
    // 模拟获取用户
    return Response.json({
      id: userId,
      name: 'Demo User',
      email: `user${userId}@example.com`,
      created_at: new Date().toISOString(),
    });
  }
  
  if (request.method === 'PUT' || request.method === 'PATCH') {
    const body = await request.json();
    return Response.json({
      id: userId,
      ...body,
      updated_at: new Date().toISOString(),
    });
  }
  
  return Response.json({ error: 'Method not allowed' }, { status: 405 });
}
