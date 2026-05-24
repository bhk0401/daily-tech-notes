/**
 * User 模型 - 双写实现示例
 * 支持 Expand/Contract 迁移模式
 */

const crypto = require('crypto');

const ENCRYPTION_KEY = process.env.EMAIL_ENCRYPTION_KEY || 'default-key-change-in-prod';
const ALGORITHM = 'aes-256-gcm';

class User {
  constructor(data) {
    this.id = data.id;
    this.email = data.email;
    this.encrypted_email = data.encrypted_email;
    this.created_at = data.created_at;
  }

  /**
   * 读取邮箱：优先读新字段，降级读旧字段
   * 向后兼容：旧代码只读 email 字段也能工作
   */
  getEmail() {
    // 优先使用加密字段
    if (this.encrypted_email) {
      try {
        return this.decrypt(this.encrypted_email);
      } catch (err) {
        console.error('Failed to decrypt email:', err);
        // 降级到明文
        return this.email;
      }
    }
    // 降级到明文字段
    return this.email;
  }

  /**
   * 写入：双写新旧字段
   * 确保迁移期间数据一致性
   */
  async save(db) {
    const encrypted = this.email ? this.encrypt(this.email) : null;

    const query = `
      INSERT INTO users (email, encrypted_email, created_at)
      VALUES (?, ?, NOW())
      ON DUPLICATE KEY UPDATE 
        email = VALUES(email),
        encrypted_email = VALUES(encrypted_email),
        updated_at = NOW()
    `;

    const [result] = await db.execute(query, [this.email, encrypted]);
    this.id = result.insertId;
    this.encrypted_email = encrypted;

    return this;
  }

  /**
   * 静态方法：向后兼容的查找
   * 旧代码调用 findAll() 仍能正常工作
   */
  static async findAll(db, options = {}) {
    const query = `
      SELECT id, email, encrypted_email, created_at 
      FROM users 
      WHERE ? 
      ORDER BY created_at DESC 
      LIMIT ? OFFSET ?
    `;

    const whereClause = options.where || '1=1';
    const limit = options.limit || 100;
    const offset = options.offset || 0;

    const [rows] = await db.execute(query, [whereClause, limit, offset]);

    return rows.map(row => new User(row));
  }

  /**
   * 加密邮箱
   */
  encrypt(plainText) {
    const iv = crypto.randomBytes(16);
    const cipher = crypto.createCipheriv(
      ALGORITHM,
      Buffer.from(ENCRYPTION_KEY, 'hex'),
      iv
    );

    let encrypted = cipher.update(plainText, 'utf8', 'hex');
    encrypted += cipher.final('hex');

    const authTag = cipher.getAuthTag();

    // 格式：iv:encrypted:authTag
    return `${iv.toString('hex')}:${encrypted}:${authTag.toString('hex')}`;
  }

  /**
   * 解密邮箱
   */
  decrypt(encryptedData) {
    const [ivHex, encrypted, authTagHex] = encryptedData.split(':');

    const decipher = crypto.createDecipheriv(
      ALGORITHM,
      Buffer.from(ENCRYPTION_KEY, 'hex'),
      Buffer.from(ivHex, 'hex')
    );

    decipher.setAuthTag(Buffer.from(authTagHex, 'hex'));

    let decrypted = decipher.update(encrypted, 'hex', 'utf8');
    decrypted += decipher.final('utf8');

    return decrypted;
  }
}

// 使用示例
async function example() {
  // 模拟数据库连接
  const db = {
    execute: async (sql, params) => {
      console.log('Executing:', sql, params);
      return [{ insertId: 1 }];
    }
  };

  // 创建新用户（双写）
  const user = new User({ email: 'test@example.com' });
  await user.save(db);

  // 读取用户（自动解密）
  const users = await User.findAll(db);
  users.forEach(u => {
    console.log('User email:', u.getEmail());
  });
}

module.exports = { User };

// 运行示例
if (require.main === module) {
  example().catch(console.error);
}
