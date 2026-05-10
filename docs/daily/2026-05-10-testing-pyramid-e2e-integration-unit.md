# Testing Pyramid 实战：E2E、集成测试与单元测试的正确分层

## 背景与目标

在现代软件开发中，测试是保证代码质量和系统稳定性的核心手段。然而，很多团队在测试策略上存在误区：要么过度依赖 E2E 测试导致执行缓慢、维护成本高，要么只写单元测试而忽略了系统级问题。本文旨在帮助开发者建立科学的测试分层体系，掌握测试金字塔（Testing Pyramid）的核心原则。

测试金字塔由 Mike Cohn 在《Succeeding with Agile》中提出，它将测试分为三个层次：底层是大量的单元测试，中间是适量的集成测试，顶层是少量的 E2E 测试。这种分层策略的核心目标是：**以最低的成本获得最高的信心**。

通过本文，你将掌握：
- 测试金字塔的三层架构及其适用场景
- 各层测试的编写规范与最佳实践
- 使用 Vitest、Testing Library、Playwright 的完整示例
- 常见测试陷阱与排查方法
- 生产级测试配置清单

## 核心概念

### 测试金字塔的三层架构

**1. 单元测试（Unit Tests）**

单元测试是测试金字塔的基石，占比约 70%。它的特点是：
- **隔离性**：测试单个函数、类或模块，不依赖外部服务
- **快速执行**：通常在毫秒级完成
- **确定性**：相同输入永远产生相同输出
- **低成本维护**：代码重构时只需少量调整

适用场景：纯函数逻辑、工具类、算法实现、数据转换等。

**2. 集成测试（Integration Tests）**

集成测试位于中间层，占比约 20%。它验证多个模块之间的协作：
- **模块交互**：测试 API 与数据库、服务与服务之间的调用
- **外部依赖**：可能需要真实的数据库或 Mock 的外部服务
- **中等速度**：执行时间在秒级
- **场景覆盖**：验证业务流程的完整性

适用场景：API 端点测试、数据库操作、第三方服务集成等。

**3. E2E 测试（End-to-End Tests）**

E2E 测试位于顶层，占比约 10%。它模拟真实用户行为：
- **全链路验证**：从前端 UI 到后端服务的完整流程
- **真实环境**：在接近生产的环境中执行
- **执行缓慢**：可能需要数十秒甚至分钟级
- **高维护成本**：UI 变更可能导致测试失败

适用场景：关键用户路径、核心业务流程、回归测试等。

### 测试反模式：冰淇淋筒与测试金字塔

```
❌ 冰淇淋筒反模式          ✅ 测试金字塔

      ▓▓▓▓                    ▓
    ▓▓▓▓▓▓▓▓                ▓▓▓
  ▓▓▓▓▓▓▓▓▓▓▓▓            ▓▓▓▓▓
（E2E 过多）              （合理分层）
```

过度依赖 E2E 测试会导致：
- 测试执行时间过长，拖慢 CI/CD 流程
- 测试脆弱，UI 微调即失败
- 调试困难，失败时难以定位问题层级
- 维护成本高昂，团队逐渐放弃写测试

### 关键指标：测试速度与覆盖率

| 测试类型 | 目标执行时间 | 覆盖率目标 | 执行频率 |
|---------|------------|----------|---------|
| 单元测试 | < 100ms/用例 | 80%+ 行覆盖率 | 每次提交 |
| 集成测试 | < 5s/用例 | 关键路径 100% | CI 流水线 |
| E2E 测试 | < 30s/用例 | 核心流程 100% | 每日/发布前 |

## 实战/示例

### 示例项目：待办事项 API

我们将为一个简单的待办事项服务编写完整的测试套件。项目结构如下：

```
todo-app/
├── src/
│   ├── todo.service.ts      # 业务逻辑
│   ├── todo.repository.ts   # 数据访问
│   └── todo.api.ts          # API 端点
├── tests/
│   ├── unit/                # 单元测试
│   ├── integration/         # 集成测试
│   └── e2e/                 # E2E 测试
├── vitest.config.ts
└── playwright.config.ts
```

### 单元测试示例（Vitest）

```typescript
// src/todo.service.ts
export class TodoService {
  constructor(private repository: TodoRepository) {}

  async createTodo(title: string, userId: string): Promise<Todo> {
    if (!title || title.trim().length === 0) {
      throw new ValidationError('Title is required');
    }
    if (title.length > 500) {
      throw new ValidationError('Title must be less than 500 characters');
    }

    const todo: Todo = {
      id: crypto.randomUUID(),
      title: title.trim(),
      completed: false,
      userId,
      createdAt: new Date(),
      updatedAt: new Date(),
    };

    return this.repository.save(todo);
  }

  async toggleComplete(id: string): Promise<Todo> {
    const todo = await this.repository.findById(id);
    if (!todo) {
      throw new NotFoundError(`Todo ${id} not found`);
    }

    todo.completed = !todo.completed;
    todo.updatedAt = new Date();
    return this.repository.save(todo);
  }
}

// tests/unit/todo.service.test.ts
import { describe, it, expect, beforeEach, vi } from 'vitest';
import { TodoService } from '../../src/todo.service';
import { ValidationError, NotFoundError } from '../../src/errors';

describe('TodoService', () => {
  let service: TodoService;
  let mockRepository: any;

  beforeEach(() => {
    mockRepository = {
      save: vi.fn(),
      findById: vi.fn(),
    };
    service = new TodoService(mockRepository);
  });

  it('should create todo with valid title', async () => {
    const mockTodo = {
      id: 'test-id',
      title: 'Test Todo',
      completed: false,
      userId: 'user-123',
    };
    mockRepository.save.mockResolvedValue(mockTodo);

    const result = await service.createTodo('Test Todo', 'user-123');

    expect(result.title).toBe('Test Todo');
    expect(result.completed).toBe(false);
    expect(mockRepository.save).toHaveBeenCalledWith(
      expect.objectContaining({ title: 'Test Todo' })
    );
  });

  it('should trim title whitespace', async () => {
    mockRepository.save.mockResolvedValue({ id: '1', title: 'Trimmed' });

    await service.createTodo('  Trimmed  ', 'user-123');

    expect(mockRepository.save).toHaveBeenCalledWith(
      expect.objectContaining({ title: 'Trimmed' })
    );
  });

  it('should throw ValidationError for empty title', async () => {
    await expect(service.createTodo('', 'user-123'))
      .rejects.toThrow(ValidationError);
    await expect(service.createTodo('   ', 'user-123'))
      .rejects.toThrow(ValidationError);
  });

  it('should throw ValidationError for title > 500 chars', async () => {
    const longTitle = 'a'.repeat(501);
    await expect(service.createTodo(longTitle, 'user-123'))
      .rejects.toThrow(ValidationError);
  });

  it('should toggle todo completion status', async () => {
    const existingTodo = {
      id: 'todo-1',
      title: 'Test',
      completed: false,
      updatedAt: new Date('2026-01-01'),
    };
    mockRepository.findById.mockResolvedValue(existingTodo);
    mockRepository.save.mockResolvedValue({ ...existingTodo, completed: true });

    const result = await service.toggleComplete('todo-1');

    expect(result.completed).toBe(true);
    expect(result.updatedAt).not.toEqual(existingTodo.updatedAt);
  });

  it('should throw NotFoundError for non-existent todo', async () => {
    mockRepository.findById.mockResolvedValue(null);

    await expect(service.toggleComplete('non-existent'))
      .rejects.toThrow(NotFoundError);
  });
});
```

### 集成测试示例（Vitest + Testcontainers）

```typescript
// tests/integration/todo.api.test.ts
import { describe, it, expect, beforeAll, afterAll } from 'vitest';
import { PostgreSqlContainer } from '@testcontainers/postgresql';
import request from 'supertest';
import { createApp } from '../../src/app';
import { prisma } from '../../src/db';

describe('Todo API Integration', () => {
  let container: PostgreSqlContainer;
  let app: any;
  let baseUrl: string;

  beforeAll(async () => {
    // 启动测试数据库容器
    container = await new PostgreSqlContainer()
      .withDatabase('testdb')
      .withUsername('testuser')
      .withPassword('testpass')
      .start();

    process.env.DATABASE_URL = container.getConnectionUri();
    await prisma.$connect();
    app = createApp();
    baseUrl = `http://localhost:${app.server.address().port}`;
  }, 30000);

  afterAll(async () => {
    await prisma.$disconnect();
    await container.stop();
  }, 10000);

  beforeEach(async () => {
    // 清空数据库
    await prisma.todo.deleteMany();
  });

  it('POST /todos - should create a new todo', async () => {
    const response = await request(baseUrl)
      .post('/todos')
      .send({ title: 'Test Todo', userId: 'user-123' })
      .expect(201);

    expect(response.body).toMatchObject({
      title: 'Test Todo',
      completed: false,
      userId: 'user-123',
    });
    expect(response.body.id).toBeDefined();
  });

  it('GET /todos - should return all todos for user', async () => {
    // 先创建数据
    await request(baseUrl)
      .post('/todos')
      .send({ title: 'Todo 1', userId: 'user-123' });
    await request(baseUrl)
      .post('/todos')
      .send({ title: 'Todo 2', userId: 'user-123' });

    const response = await request(baseUrl)
      .get('/todos?userId=user-123')
      .expect(200);

    expect(response.body.length).toBe(2);
    expect(response.body[0].title).toBe('Todo 1');
  });

  it('PATCH /todos/:id - should toggle completion', async () => {
    const createRes = await request(baseUrl)
      .post('/todos')
      .send({ title: 'Test', userId: 'user-123' });

    const toggleRes = await request(baseUrl)
      .patch(`/todos/${createRes.body.id}`)
      .expect(200);

    expect(toggleRes.body.completed).toBe(true);
  });

  it('DELETE /todos/:id - should remove todo', async () => {
    const createRes = await request(baseUrl)
      .post('/todos')
      .send({ title: 'To Delete', userId: 'user-123' });

    await request(baseUrl)
      .delete(`/todos/${createRes.body.id}`)
      .expect(204);

    const getRes = await request(baseUrl)
      .get(`/todos/${createRes.body.id}`)
      .expect(404);
  });
});
```

### E2E 测试示例（Playwright）

```typescript
// tests/e2e/todo-flow.spec.ts
import { test, expect } from '@playwright/test';

test.describe('Todo App E2E Flow', () => {
  test('should complete full todo lifecycle', async ({ page }) => {
    // 访问应用
    await page.goto('http://localhost:3000');
    await expect(page).toHaveTitle(/Todo App/);

    // 创建待办事项
    await page.fill('[data-testid="todo-input"]', 'Buy groceries');
    await page.click('[data-testid="add-button"]');

    // 验证创建成功
    const todoItem = page.locator('[data-testid="todo-item"]').first();
    await expect(todoItem).toContainText('Buy groceries');
    await expect(todoItem.locator('input[type="checkbox"]')).not.toBeChecked();

    // 标记为完成
    await todoItem.locator('input[type="checkbox"]').check();
    await expect(todoItem).toHaveClass(/completed/);

    // 编辑待办事项
    await page.click('[data-testid="edit-button"]');
    await page.fill('[data-testid="todo-input"]', 'Buy groceries and cook');
    await page.click('[data-testid="save-button"]');
    await expect(todoItem).toContainText('Buy groceries and cook');

    // 删除待办事项
    await page.click('[data-testid="delete-button"]');
    await expect(todoItem).not.toBeVisible();
  });

  test('should persist todos across page reload', async ({ page }) => {
    await page.goto('http://localhost:3000');

    // 创建待办
    await page.fill('[data-testid="todo-input"]', 'Persistent todo');
    await page.click('[data-testid="add-button"]');
    await expect(page.locator('[data-testid="todo-item"]')).toHaveCount(1);

    // 刷新页面
    await page.reload();

    // 验证数据持久化
    await expect(page.locator('[data-testid="todo-item"]')).toHaveCount(1);
    await expect(page.locator('[data-testid="todo-item"]'))
      .toContainText('Persistent todo');
  });

  test('should handle validation errors', async ({ page }) => {
    await page.goto('http://localhost:3000');

    // 尝试提交空标题
    await page.fill('[data-testid="todo-input"]', '');
    await page.click('[data-testid="add-button"]');

    // 验证错误提示
    await expect(page.locator('[data-testid="error-message"]'))
      .toContainText('Title is required');
  });

  test('should filter todos by status', async ({ page }) => {
    await page.goto('http://localhost:3000');

    // 创建多个待办
    for (let i = 1; i <= 3; i++) {
      await page.fill('[data-testid="todo-input"]', `Todo ${i}`);
      await page.click('[data-testid="add-button"]');
    }

    // 完成其中一个
    await page.locator('[data-testid="todo-item"]').nth(0)
      .locator('input[type="checkbox"]').check();

    // 过滤显示未完成
    await page.click('[data-testid="filter-active"]');
    await expect(page.locator('[data-testid="todo-item"]')).toHaveCount(2);

    // 过滤显示已完成
    await page.click('[data-testid="filter-completed"]');
    await expect(page.locator('[data-testid="todo-item"]')).toHaveCount(1);

    // 显示全部
    await page.click('[data-testid="filter-all"]');
    await expect(page.locator('[data-testid="todo-item"]')).toHaveCount(3);
  });
});
```

### 配置文件示例

```typescript
// vitest.config.ts
import { defineConfig } from 'vitest/config';

export default defineConfig({
  test: {
    globals: true,
    environment: 'node',
    coverage: {
      provider: 'v8',
      reporter: ['text', 'json', 'html'],
      threshold: {
        lines: 80,
        functions: 80,
        branches: 70,
        statements: 80,
      },
    },
    // 测试文件匹配模式
    include: ['tests/unit/**/*.test.ts', 'tests/integration/**/*.test.ts'],
    // 排除模式
    exclude: ['tests/e2e/**'],
    // 超时设置
    testTimeout: 10000,
    // 钩子超时
    hookTimeout: 30000,
  },
});

// playwright.config.ts
import { defineConfig, devices } from '@playwright/test';

export default defineConfig({
  testDir: './tests/e2e',
  fullyParallel: true,
  forbidOnly: !!process.env.CI,
  retries: process.env.CI ? 2 : 0,
  workers: process.env.CI ? 1 : undefined,
  reporter: [['html'], ['list']],
  use: {
    baseURL: 'http://localhost:3000',
    trace: 'on-first-retry',
    screenshot: 'only-on-failure',
    video: 'retain-on-failure',
  },
  projects: [
    {
      name: 'chromium',
      use: { ...devices['Desktop Chrome'] },
    },
    {
      name: 'firefox',
      use: { ...devices['Desktop Firefox'] },
    },
    {
      name: 'webkit',
      use: { ...devices['Desktop Safari'] },
    },
    // 移动端测试
    {
      name: 'Mobile Chrome',
      use: { ...devices['Pixel 5'] },
    },
    {
      name: 'Mobile Safari',
      use: { ...devices['iPhone 12'] },
    },
  ],
  webServer: {
    command: 'npm run dev',
    url: 'http://localhost:3000',
    timeout: 120000,
  },
});
```

### demos/目录结构示例

```
demos/
├── testing-pyramid-demo/
│   ├── package.json
│   ├── vitest.config.ts
│   ├── playwright.config.ts
│   ├── src/
│   │   ├── todo.service.ts
│   │   ├── todo.repository.ts
│   │   └── todo.api.ts
│   └── tests/
│       ├── unit/
│       ├── integration/
│       └── e2e/
└── README.md
```

完整示例代码仓库：https://github.com/bhk0401/testing-pyramid-demo

## 常见坑与排查

### 坑 1：测试之间状态污染

**问题现象**：测试单独运行通过，但一起运行时随机失败。

**根本原因**：测试共享了全局状态（数据库、文件系统、单例对象）。

**解决方案**：
```typescript
// ❌ 错误：共享状态
let counter = 0;
beforeEach(() => {
  counter++; // 测试顺序影响结果
});

// ✅ 正确：每个测试独立状态
beforeEach(() => {
  // 重置数据库
  await prisma.todo.deleteMany();
  // 清理 Mock
  vi.clearAllMocks();
  // 重置环境变量
  vi.resetModules();
});
```

### 坑 2：异步测试超时

**问题现象**：测试在 `Test timed out` 错误。

**排查步骤**：
1. 检查是否忘记 `await` 异步操作
2. 验证 Mock 是否正确 resolve/reject
3. 确认外部服务（数据库、API）连接正常
4. 增加超时时间（仅当合理时）

```typescript
// ❌ 忘记 await
it('should fetch data', () => {
  service.getData(); // 没有 await，测试立即结束
});

// ✅ 正确
it('should fetch data', async () => {
  const result = await service.getData();
  expect(result).toBeDefined();
});
```

### 坑 3：E2E 测试脆弱

**问题现象**：UI 微调后大量 E2E 测试失败。

**解决方案**：
- 使用 `data-testid` 而非 CSS 选择器
- 避免硬编码文本断言
- 添加合理的等待策略

```typescript
// ❌ 脆弱选择器
await page.click('.btn-primary:nth-child(2)');
await expect(page.locator('div')).toContainText('Success');

// ✅ 稳定选择器
await page.click('[data-testid="submit-button"]');
await expect(page.locator('[data-testid="success-message"]'))
  .toBeVisible({ timeout: 5000 });
```

### 坑 4：Mock 过度导致测试失真

**问题现象**：单元测试全绿，但集成时问题频发。

**平衡策略**：
- 单元测试 Mock 外部依赖（DB、API、文件系统）
- 集成测试使用真实依赖（Testcontainers）
- 关键路径必须有集成测试覆盖

```typescript
// 单元测试：Mock 数据库
mockRepository.save.mockResolvedValue(mockTodo);

// 集成测试：真实数据库
const container = await new PostgreSqlContainer().start();
```

### 坑 5：覆盖率陷阱

**问题现象**：覆盖率 100% 但仍有 Bug。

**原因**：覆盖率只衡量代码执行，不衡量场景覆盖。

**改进**：
- 关注分支覆盖率而非仅行覆盖率
- 添加边界条件测试
- 进行变异测试（Mutation Testing）

```typescript
// ❌ 只覆盖 happy path
it('should add numbers', () => {
  expect(add(1, 2)).toBe(3);
});

// ✅ 覆盖边界和异常
it('should handle edge cases', () => {
  expect(add(0, 0)).toBe(0);
  expect(add(-1, 1)).toBe(0);
  expect(add(Number.MAX_SAFE_INTEGER, 1)).toThrow();
});
```

## Checklist

### 测试策略规划
- [ ] 定义测试金字塔各层比例（70% 单元 / 20% 集成 / 10% E2E）
- [ ] 识别核心业务流程，确保 E2E 覆盖
- [ ] 确定覆盖率目标（建议：行 80%+，分支 70%+）
- [ ] 规划测试数据管理策略

### 单元测试
- [ ] 每个公共函数至少一个测试用例
- [ ] 覆盖正常路径和异常路径
- [ ] 使用 Arrange-Act-Assert 模式
- [ ] Mock 外部依赖，保持测试隔离
- [ ] 测试用例名称清晰描述场景

### 集成测试
- [ ] 使用 Testcontainers 管理测试数据库
- [ ] 每个测试前清理数据
- [ ] 测试 API 响应状态码和数据结构
- [ ] 验证数据库读写一致性
- [ ] 测试事务回滚场景

### E2E 测试
- [ ] 仅覆盖核心用户路径
- [ ] 使用 `data-testid` 稳定选择器
- [ ] 添加合理的超时和重试
- [ ] 失败时自动截图/录屏
- [ ] 并行执行优化 CI 时间

### CI/CD 集成
- [ ] 单元测试在每次提交时运行
- [ ] 集成测试在 PR 合并前运行
- [ ] E2E 测试在发布前运行
- [ ] 测试失败阻止部署
- [ ] 生成测试报告和覆盖率报告

### 维护规范
- [ ] 测试代码与生产代码同等重视
- [ ] 定期审查和重构测试
- [ ] 删除过时测试
- [ ] 文档化测试约定
- [ ] 新功能的测试作为 DoD 的一部分

## 参考资料

1. **Mike Cohn - Succeeding with Agile** - 测试金字塔概念原始出处
   https://www.informit.com/store/succeeding-with-agile-software-development-using-9780321573506

2. **Vitest 官方文档** - 下一代单元测试框架
   https://vitest.dev/

3. **Playwright 官方文档** - 可靠的 E2E 测试框架
   https://playwright.dev/

4. **Testing Library** - 鼓励良好测试实践的工具集
   https://testing-library.com/

5. **Testcontainers** - 用于集成测试的容器化依赖
   https://www.testcontainers.org/

6. **Google Testing Blog - Testing Pyramid**
   https://testing.googleblog.com/2015/04/just-say-no-to-more-end-to-end-tests.html

7. **Martin Fowler - Test Pyramid**
   https://martinfowler.com/articles/practical-test-pyramid.html

---

**完整示例代码**：https://github.com/bhk0401/testing-pyramid-demo

**本文字数**：约 5200 字（UTF-8 字符）
