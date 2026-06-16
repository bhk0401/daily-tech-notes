// Vercel Serverless Function - 用户 API
import type { VercelRequest, VercelResponse } from '@vercel/node';

export default async function handler(req: VercelRequest, res: VercelResponse) {
  // 设置 CORS
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'GET, PUT, DELETE, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type, Authorization');
  
  // 处理预检请求
  if (req.method === 'OPTIONS') {
    return res.status(200).end();
  }
  
  const { id } = req.query;
  const userId = Array.isArray(id) ? id[0] : id;
  
  if (!userId) {
    return res.status(400).json({ error: 'User ID is required' });
  }
  
  try {
    if (req.method === 'GET') {
      // 模拟数据库查询
      const user = await fetchUser(userId);
      
      if (!user) {
        return res.status(404).json({ error: 'User not found' });
      }
      
      return res.status(200).json({
        success: true,
        data: user,
        meta: {
          request_id: crypto.randomUUID(),
          timestamp: new Date().toISOString(),
          region: process.env.VERCEL_REGION || 'unknown',
        },
      });
    }
    
    if (req.method === 'PUT') {
      const { name, email } = req.body;
      
      if (!name || !email) {
        return res.status(400).json({ error: 'Name and email are required' });
      }
      
      const updated = await updateUser(userId, { name, email });
      
      return res.status(200).json({
        success: true,
        data: updated,
        meta: {
          request_id: crypto.randomUUID(),
          timestamp: new Date().toISOString(),
        },
      });
    }
    
    if (req.method === 'DELETE') {
      await deleteUser(userId);
      
      return res.status(200).json({
        success: true,
        message: 'User deleted successfully',
      });
    }
    
    return res.status(405).json({ error: 'Method not allowed' });
    
  } catch (error) {
    console.error('[ERROR] User API:', error);
    return res.status(500).json({
      error: 'Internal server error',
      request_id: crypto.randomUUID(),
    });
  }
}

// 模拟数据库操作（生产环境应使用真实数据库）
async function fetchUser(id: string) {
  await delay(50); // 模拟数据库延迟
  return {
    id,
    name: 'Demo User',
    email: `user${id}@example.com`,
    created_at: new Date().toISOString(),
  };
}

async function updateUser(id: string, data: { name: string; email: string }) {
  await delay(30);
  return {
    id,
    ...data,
    updated_at: new Date().toISOString(),
  };
}

async function deleteUser(id: string) {
  await delay(20);
  return true;
}

function delay(ms: number): Promise<void> {
  return new Promise(resolve => setTimeout(resolve, ms));
}
