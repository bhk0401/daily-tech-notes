// Vercel Serverless Function - 产品列表 API
import type { VercelRequest, VercelResponse } from '@vercel/node';

export const config = {
  runtime: 'edge', // 使用 Edge Runtime
};

export default async function handler(req: VercelRequest, res: VercelResponse) {
  // CORS 设置
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type, Authorization');
  
  if (req.method === 'OPTIONS') {
    return res.status(200).end();
  }
  
  try {
    if (req.method === 'GET') {
      const { page = '1', limit = '10', category } = req.query;
      
      const products = await fetchProducts({
        page: parseInt(page as string),
        limit: parseInt(limit as string),
        category: category as string,
      });
      
      return res.status(200).json({
        success: true,
        data: products,
        meta: {
          page: parseInt(page as string),
          limit: parseInt(limit as string),
          total: products.length,
          region: process.env.VERCEL_REGION || 'unknown',
          edge: true,
        },
      });
    }
    
    if (req.method === 'POST') {
      const { name, price, category } = req.body;
      
      if (!name || !price) {
        return res.status(400).json({ error: 'Name and price are required' });
      }
      
      const product = await createProduct({ name, price, category });
      
      return res.status(201).json({
        success: true,
        data: product,
      });
    }
    
    return res.status(405).json({ error: 'Method not allowed' });
    
  } catch (error) {
    console.error('[ERROR] Products API:', error);
    return res.status(500).json({
      error: 'Internal server error',
    });
  }
}

interface Product {
  id: string;
  name: string;
  price: number;
  category?: string;
  created_at: string;
}

async function fetchProducts({ page, limit, category }: { page: number; limit: number; category?: string }): Promise<Product[]> {
  // 模拟产品数据
  const allProducts: Product[] = [
    { id: '1', name: 'Widget A', price: 29.99, category: 'electronics', created_at: new Date().toISOString() },
    { id: '2', name: 'Widget B', price: 49.99, category: 'electronics', created_at: new Date().toISOString() },
    { id: '3', name: 'Gadget X', price: 99.99, category: 'accessories', created_at: new Date().toISOString() },
  ];
  
  let filtered = category ? allProducts.filter(p => p.category === category) : allProducts;
  const start = (page - 1) * limit;
  return filtered.slice(start, start + limit);
}

async function createProduct(data: { name: string; price: number; category?: string }): Promise<Product> {
  return {
    id: crypto.randomUUID(),
    ...data,
    created_at: new Date().toISOString(),
  };
}
