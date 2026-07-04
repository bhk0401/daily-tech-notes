# TypeScript 高级类型编程：条件类型、映射类型与模板字条量类型实战

## 背景与目标

TypeScript 的类型系统早已超越了简单的"带类型的 JavaScript"范畴，演变成了一门强大的类型级编程语言。在实际工程实践中，我们经常遇到需要编写通用工具库、构建类型安全的 API 客户端、或者实现复杂的状态管理场景。这些场景往往要求我们深入理解 TypeScript 的高级类型特性。

本文的目标是帮助开发者掌握 TypeScript 类型系统的三大核心高级特性：**条件类型（Conditional Types）**、**映射类型（Mapped Types）**和**模板字面量类型（Template Literal Types）**。通过实际案例，我们将学习如何将这些特性组合使用，构建出既灵活又类型安全的抽象。

掌握这些技能后，你将能够：
- 编写可复用的泛型工具类型，减少重复代码
- 实现类型级别的逻辑判断和分支处理
- 自动派生相关类型，保持代码 DRY 原则
- 构建更精确的 API 类型定义，提升开发体验

## 核心概念

### 条件类型（Conditional Types）

条件类型允许在类型层面进行"三元运算"，根据类型条件判断结果选择不同的类型。语法格式为：

```typescript
T extends U ? X : Y
```

这意味着：如果类型 `T` 可以赋值给类型 `U`，则结果为 `X`，否则为 `Y`。

条件类型的强大之处在于它可以与 `infer` 关键字配合使用，在条件分支中推断出类型变量：

```typescript
type UnwrapPromise<T> = T extends Promise<infer U> ? U : T;
// UnwrapPromise<Promise<string>> => string
// UnwrapPromise<number> => number
```

### 映射类型（Mapped Types）

映射类型允许基于现有类型创建新类型，通过遍历原类型的属性键来构建新结构。基本语法：

```typescript
type MappedType<T> = {
  [P in keyof T]: NewType;
};
```

结合条件类型和类型修饰符（`readonly`、`?`），可以实现丰富的类型变换：

```typescript
// 将所有属性变为可选
type Partial<T> = { [P in keyof T]?: T[P] };

// 将所有属性变为只读
type Readonly<T> = { readonly [P in keyof T]: T[P] };

// 排除 null 和 undefined
type NonNullable<T> = T extends null | undefined ? never : T;
```

### 模板字面量类型（Template Literal Types）

模板字面量类型允许在类型层面进行字符串拼接操作，语法与运行时模板字符串相似：

```typescript
type Greeting = `Hello, ${string}!`;
// 可以是 "Hello, World!"、"Hello, TypeScript!" 等

type HttpMethod = "GET" | "POST" | "PUT" | "DELETE";
type ApiEndpoint = `/api/${string}`;
type ApiRequest = `${HttpMethod} ${ApiEndpoint}`;
// "GET /api/users" | "POST /api/users" | ...
```

结合映射类型，可以自动生成相关类型：

```typescript
type EventMap<T extends string> = {
  [K in T as `on${Capitalize<K>}`]: (event: K) => void;
};
type ButtonEvents = EventMap<"click" | "hover" | "focus">;
// { onClick: (e: "click") => void; onHover: (e: "hover") => void; ... }
```

## 实战/示例

### 示例 1：深度 Partial 类型

TypeScript 内置的 `Partial<T>` 只能处理第一层属性，对于嵌套对象无能为力。我们可以使用递归条件类型实现深度 Partial：

```typescript
type DeepPartial<T> = T extends object
  ? { [P in keyof T]?: DeepPartial<T[P]> }
  : T;

interface User {
  id: number;
  profile: {
    name: string;
    contact: {
      email: string;
      phone?: string;
    };
  };
  tags: string[];
}

type UpdateUserPayload = DeepPartial<User>;
// 所有层级的属性都变为可选，适合 PATCH 请求
```

### 示例 2：API 响应类型提取器

在处理 API 响应时，我们经常需要从 Promise 包裹的响应类型中提取实际数据类型：

```typescript
// 提取 Promise 内部的类型
type UnwrapPromise<T> = T extends Promise<infer U> ? U : T;

// 提取 API 响应的数据结构
type ApiResponse<T> = {
  data: T;
  status: number;
  message: string;
};

type ExtractData<T> = T extends ApiResponse<infer U> ? U : never;

// 使用示例
type UserApiResponse = ApiResponse<{ id: number; name: string }>;
type UserData = ExtractData<UserApiResponse>; 
// => { id: number; name: string }
```

### 示例 3：类型安全的状态机

使用模板字面量类型和映射类型，可以构建类型安全的事件驱动状态机：

```typescript
type State = "idle" | "loading" | "success" | "error";
type Event = "FETCH" | "RESOLVE" | "REJECT" | "RESET";

// 定义状态转换规则
type StateTransition = {
  [K in State]: {
    [E in Event]?: State;
  };
};

const stateMachine: StateTransition = {
  idle: { FETCH: "loading" },
  loading: { RESOLVE: "success", REJECT: "error" },
  success: { RESET: "idle" },
  error: { RESET: "idle", FETCH: "loading" },
};

// 类型安全的状态转换函数
function transition<S extends State, E extends Event>(
  currentState: S,
  event: E
): StateTransition[S][E] | undefined {
  return stateMachine[currentState][event];
}

// 使用：TypeScript 会提示可用的事件
const nextState = transition("idle", "FETCH"); // "loading"
```

### 示例 4：自动派生 API Hook 类型

在 React 项目中，我们可以使用高级类型自动生成 Hook 的返回类型：

```typescript
// 定义 API 端点配置
type ApiConfig = {
  getUser: {
    params: { id: string };
    response: { id: string; name: string; email: string };
  };
  listUsers: {
    params: { page: number; limit: number };
    response: { users: Array<{ id: string; name: string }>; total: number };
  };
  createUser: {
    params: { name: string; email: string };
    response: { id: string; name: string };
  };
};

// 提取所有端点名称
type ApiEndpoints = keyof ApiConfig;

// 根据端点名称提取参数类型
type ApiParams<T extends ApiEndpoints> = ApiConfig[T]["params"];

// 根据端点名称提取响应类型
type ApiResult<T extends ApiEndpoints> = ApiConfig[T]["response"];

// 生成 Hook 类型
type UseApiHook<T extends ApiEndpoints> = (
  params: ApiParams<T>
) => Promise<ApiResult<T>>;

// 自动生成所有 Hook 的类型映射
type ApiHooks = {
  [K in ApiEndpoints as `use${Capitalize<K>}`]: UseApiHook<K>;
};

// 使用示例
type ApiHooksInstance = {
  useGetUser: (params: { id: string }) => Promise<{ id: string; name: string; email: string }>;
  useListUsers: (params: { page: number; limit: number }) => Promise<{ users: Array<{ id: string; name: string }>; total: number }>;
  useCreateUser: (params: { name: string; email: string }) => Promise<{ id: string; name: string }>;
};
```

### 示例 5：可运行的完整 Demo

创建一个可运行的 TypeScript 工具类型库：

```typescript
// utils/types.ts - 可复用的类型工具

// 1. 深度只读
type DeepReadonly<T> = T extends object
  ? { readonly [P in keyof T]: DeepReadonly<T[P]> }
  : T;

// 2. 提取函数参数类型
type FirstParameter<T extends (...args: any[]) => any> = 
  T extends (arg: infer P, ...rest: any[]) => any ? P : never;

// 3. 提取函数返回类型（内置 ReturnType 的替代实现）
type MyReturnType<T extends (...args: any[]) => any> = 
  T extends (...args: any[]) => infer R ? R : never;

// 4. 可选属性变为必需，必需属性变为可选
type SwapOptionalRequired<T> = {
  [P in keyof T as P extends keyof Required<T> ? never : P]: T[P];
} & {
  [P in keyof T as P extends keyof Required<T> ? P : never]?: T[P];
};

// 5. 字符串操作方法类型
type TrimLeft<S extends string> = S extends ` ${infer Rest}` ? TrimLeft<Rest> : S;
type TrimRight<S extends string> = S extends `${infer Rest} ` ? TrimRight<Rest> : S;
type Trim<S extends string> = TrimLeft<TrimRight<S>>;

// 使用演示
const example = {
  user: {
    profile: {
      name: "Alice",
      settings: { theme: "dark" }
    }
  }
};

type ExampleType = DeepReadonly<typeof example>;
// 所有层级都变为 readonly

const fetchUser = (id: string) => Promise.resolve({ id, name: "User" });
type UserIdParam = FirstParameter<typeof fetchUser>; // string
type FetchResult = MyReturnType<typeof fetchUser>; // Promise<{ id: string; name: string }>

type Trimmed = Trim<"  hello world  ">; // "hello world"
```

## 常见坑与排查

### 坑 1：条件类型中的分布式行为

条件类型在裸类型参数（naked type parameter）上具有分布式特性，可能导致意外结果：

```typescript
// 问题：分布式条件类型
type ToArray<T> = T extends any ? T[] : never;
type Result = ToArray<string | number>; 
// 实际结果：string[] | number[]（不是预期的 (string | number)[]）

// 解决：用元组包裹消除分布式
type ToArrayFixed<T> = [T] extends [any] ? T[] : never;
type ResultFixed = ToArrayFixed<string | number>; 
// 正确结果：(string | number)[]
```

**排查方法**：当条件类型产生联合类型而非预期结果时，考虑使用 `[T] extends [U]` 包裹。

### 坑 2：infer 的位置限制

`infer` 只能在条件类型的 true 分支中使用，且必须出现在 extends 子句的类型模式中：

```typescript
// 错误：infer 在 false 分支
type Wrong<T> = T extends Promise<infer U> ? never : infer U; // ❌

// 错误：infer 不在 extends 模式中
type AlsoWrong<T> = infer U extends T ? U : never; // ❌

// 正确用法
type Correct<T> = T extends Promise<infer U> ? U : T; // ✅
```

### 坑 3：映射类型中的 as 子句与可选性

使用 `as` 子句重命名键时，需要注意可选性的处理：

```typescript
// 问题：as 子句可能改变可选性
type Original = { a?: number; b: string };

// 可能丢失可选性
type Mapped1 = { [K in keyof Original as K]: Original[K] };

// 保留可选性
type Mapped2 = { [K in keyof Original as K]?: Original[K] };
```

### 坑 4：模板字面量类型的性能问题

过于复杂的模板字面量类型组合可能导致类型检查变慢：

```typescript
// 避免：过度嵌套的模板类型
type Bad = `${"a" | "b"}${"c" | "d"}${"e" | "f"}${"g" | "h"}`; // 16 种组合

// 优化：限制组合数量或提前收敛
type Better = `${"a" | "b"}-${string}`; // 保持简洁
```

**排查方法**：当 VSCode 类型提示变慢或卡顿时，检查是否有过度复杂的模板字面量类型，考虑简化或拆分。

### 坑 5：递归类型深度限制

TypeScript 对递归类型有深度限制（默认 50 层），过深的递归会导致类型错误：

```typescript
// 问题：深度递归可能触发限制
type DeepNest<T, N extends number = 0> = 
  N extends 100 ? T : DeepNest<{ child: T }, N extends number ? N + 1 : never>;

// 解决：限制递归深度或使用迭代方式
type SafeDeepNest<T, N extends number = 0> = 
  N extends 10 ? T : DeepNest<{ child: T }, N extends number ? N + 1 : never>;
```

### 坑 6：条件类型与联合类型的交互

条件类型与联合类型结合时，需要理解分配律：

```typescript
// 问题：条件类型分配到联合类型的每个成员
type Check<T> = T extends string ? "yes" : "no";
type Result = Check<string | number>; // "yes" | "no"

// 解决：根据需求选择是否利用分配律
type CheckNoDistribute<T> = [T] extends [string] ? "yes" : "no";
type Result2 = CheckNoDistribute<string | number>; // "no"
```

## Checklist

在应用 TypeScript 高级类型时，请确保：

- [ ] **条件类型设计**
  - [ ] 明确是否需要分布式行为（裸类型参数 vs 元组包裹）
  - [ ] `infer` 关键字仅出现在条件类型的 true 分支
  - [ ] 考虑联合类型输入时的行为是否符合预期

- [ ] **映射类型设计**
  - [ ] 正确使用 `keyof T` 遍历属性键
  - [ ] 明确属性的可选性（`?`）和只读性（`readonly`）
  - [ ] 使用 `as` 子句时注意键名转换的正确性

- [ ] **模板字面量类型设计**
  - [ ] 避免过度复杂的组合导致性能问题
  - [ ] 确保字符串字面量联合类型数量可控
  - [ ] 结合 `Capitalize`/`Uppercase` 等内置类型工具

- [ ] **递归类型安全**
  - [ ] 设置合理的递归深度限制
  - [ ] 确保有明确的终止条件
  - [ ] 测试边界情况避免类型检查超时

- [ ] **代码可维护性**
  - [ ] 为复杂类型添加注释说明意图
  - [ ] 将通用工具类型提取到独立文件
  - [ ] 使用类型别名提高可读性
  - [ ] 编写类型测试用例验证行为

- [ ] **开发体验**
  - [ ] 确保 IDE 类型提示响应及时
  - [ ] 错误信息清晰易懂
  - [ ] 避免过度抽象导致类型难以理解

## 参考资料

1. [TypeScript 官方文档 - 高级类型](https://www.typescriptlang.org/docs/handbook/2/conditional-types.html) - 条件类型、映射类型、模板字面量类型的官方权威文档

2. [TypeScript Deep Dive - 类型系统](https://basarat.gitbook.io/typescript/type-system) - 深入理解 TypeScript 类型系统的开源书籍

3. [Type Challenges](https://github.com/type-challenges/type-challenges) - 通过实际挑战练习 TypeScript 类型编程的 GitHub 项目

4. [Utility Types](https://utilitytypes.xyz/) - TypeScript 内置工具类型的交互式文档和实现源码

5. [Total TypeScript](https://www.totaltypescript.com/) - Matt Pocock 的 TypeScript 高级教程，包含大量类型编程实战技巧
