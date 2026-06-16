// Vercel Serverless Function - 健康检查端点
import type { VercelRequest, VercelResponse } from '@vercel/node';

export const config = {
  runtime: 'edge',
};

export default async function handler(req: VercelRequest, res: VercelResponse) {
  const health = {
    status: 'healthy',
    timestamp: new Date().toISOString(),
    uptime: process.uptime(),
    region: process.env.VERCEL_REGION || 'unknown',
    runtime: process.env.VERCEL_EDGE ? 'edge' : 'nodejs',
    node_version: process.version,
    memory_usage: process.memoryUsage(),
  };
  
  res.setHeader('Content-Type', 'application/json');
  res.setHeader('Cache-Control', 'no-cache');
  
  return res.status(200).json(health);
}
