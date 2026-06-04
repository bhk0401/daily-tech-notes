# 前端状态管理：从 Context 到 Signals 的现代模式对比

## 背景与目标

前端应用复杂度持续增长，状态管理成为架构设计的核心挑战。从早期的全局变量、jQuery 时代的 DOM 状态，到 Redux 一统天下，再到如今 Context、Zustand、Jotai、Signals 百花齐放，开发者面临"选择困难症"。

本文目标：
- 系统对比主流状态管理方案的核心原理与适用场景
- 提供可落地的选型决策框架
- 通过完整代码示例展示各方案的实现差异
- 帮助团队根据项目规模、技术栈、性能需求做出合理选择

**适用场景**：React/Vue/Solid 项目技术选型、遗留系统重构评估、性能瓶颈优化、团队协作规范制定。

## 核心概念

### 状态管理的本质

状态管理解决三个核心问题：
1. **状态存储**：数据存放在哪里（组件本地/全局/服务端）
2. **状态更新**：如何修改数据（直接赋值/不可变更新/代理拦截）
3. **状态同步**：如何通知 UI 刷新（手动订阅/自动追踪/响应式系统）

### 主流方案分类

| 方案类型 | 代表库 | 核心机制 | 更新粒度 |
|---------|--------|---------|---------|
| Context + Reducer | React 内置 | Provider 树 + 不可变更新 | 组件级 |
| 原子状态 | Zustand, Jotai | 独立原子 + 订阅通知 | 原子级 |
| 响应式系统 | Solid Signals, Vue Ref, Preact Signals | Proxy/Getter-Setter 依赖追踪 | 表达式级 |
| 全局状态容器 | Redux, MobX | 单一 Store + 中间件 | Store 级 |

### 关键指标对比

- **渲染效率**：Context 触发整树重渲染，原子状态仅更新订阅组件，Signals 精确到表达式
- **代码复杂度**：Redux > Context > Zustand ≈ Signals > Jotai
- **学习曲线**：Signals（新概念）> Redux（样板代码）> Zustand（最直观）
- **TypeScript 支持**：Zustand/Jotai/Signals 均为原生 TS，Redux 需额外配置
- **生态成熟度**：Redux（最成熟）> Context（官方支持）> Zustand（快速增长）> Signals（新兴标准）

## 实战/示例

### 示例场景：电商购物车

实现功能：添加商品、修改数量、计算总价、优惠券应用。

#### 方案一：React Context + useReducer

```tsx
// store/cart-context.tsx
import React, { createContext, useContext, useReducer, ReactNode } from 'react';

interface CartItem {
  id: string;
  name: string;
  price: number;
  quantity: number;
}

interface CartState {
  items: CartItem[];
  couponCode: string | null;
  discount: number;
}

type Action =
  | { type: 'ADD_ITEM'; payload: Omit<CartItem, 'quantity'> }
  | { type: 'UPDATE_QUANTITY'; payload: { id: string; quantity: number } }
  | { type: 'REMOVE_ITEM'; payload: string }
  | { type: 'APPLY_COUPON'; payload: { code: string; discount: number } };

function cartReducer(state: CartState, action: Action): CartState {
  switch (action.type) {
    case 'ADD_ITEM': {
      const existing = state.items.find(item => item.id === action.payload.id);
      if (existing) {
        return {
          ...state,
          items: state.items.map(item =>
            item.id === action.payload.id
              ? { ...item, quantity: item.quantity + 1 }
              : item
          ),
        };
      }
      return { ...state, items: [...state.items, { ...action.payload, quantity: 1 }] };
    }
    case 'UPDATE_QUANTITY':
      return {
        ...state,
        items: state.items.map(item =>
          item.id === action.payload.id
            ? { ...item, quantity: action.payload.quantity }
            : item
        ),
      };
    case 'REMOVE_ITEM':
      return { ...state, items: state.items.filter(item => item.id !== action.payload) };
    case 'APPLY_COUPON':
      return { ...state, couponCode: action.payload.code, discount: action.payload.discount };
    default:
      return state;
  }
}

const CartContext = createContext<{ state: CartState; dispatch: React.Dispatch<Action> } | null>(null);

export function CartProvider({ children }: { children: ReactNode }) {
  const [state, dispatch] = useReducer(cartReducer, { items: [], couponCode: null, discount: 0 });
  return <CartContext.Provider value={{ state, dispatch }}>{children}</CartContext.Provider>;
}

export function useCart() {
  const context = useContext(CartContext);
  if (!context) throw new Error('useCart must be used within CartProvider');
  return context;
}
```

**使用示例**：
```tsx
function CartDisplay() {
  const { state, dispatch } = useCart();
  const total = state.items.reduce((sum, item) => sum + item.price * item.quantity, 0);
  const finalTotal = total * (1 - state.discount / 100);
  
  return (
    <div>
      {state.items.map(item => (
        <div key={item.id}>
          {item.name} × {item.quantity}
          <button onClick={() => dispatch({ type: 'UPDATE_QUANTITY', payload: { id: item.id, quantity: item.quantity + 1 } })}>+</button>
        </div>
      ))}
      <p>总计：¥{finalTotal.toFixed(2)}</p>
    </div>
  );
}
```

#### 方案二：Zustand（推荐）

```tsx
// store/cart-store.ts
import { create } from 'zustand';
import { persist } from 'zustand/middleware';

interface CartItem {
  id: string;
  name: string;
  price: number;
  quantity: number;
}

interface CartStore {
  items: CartItem[];
  couponCode: string | null;
  discount: number;
  addItem: (item: Omit<CartItem, 'quantity'>) => void;
  updateQuantity: (id: string, quantity: number) => void;
  removeItem: (id: string) => void;
  applyCoupon: (code: string, discount: number) => void;
  getTotal: () => number;
}

export const useCartStore = create<CartStore>()(
  persist(
    (set, get) => ({
      items: [],
      couponCode: null,
      discount: 0,
      
      addItem: (item) => set((state) => {
        const existing = state.items.find(i => i.id === item.id);
        if (existing) {
          return {
            items: state.items.map(i =>
              i.id === item.id ? { ...i, quantity: i.quantity + 1 } : i
            ),
          };
        }
        return { items: [...state.items, { ...item, quantity: 1 }] };
      }),
      
      updateQuantity: (id, quantity) => set((state) => ({
        items: state.items.map(item =>
          item.id === id ? { ...item, quantity } : item
        ),
      })),
      
      removeItem: (id) => set((state) => ({
        items: state.items.filter(item => item.id !== id),
      })),
      
      applyCoupon: (code, discount) => set({ couponCode: code, discount }),
      
      getTotal: () => {
        const { items, discount } = get();
        const total = items.reduce((sum, item) => sum + item.price * item.quantity, 0);
        return total * (1 - discount / 100);
      },
    }),
    { name: 'cart-storage' }
  )
);
```

**使用示例**（无需 Provider 包裹）：
```tsx
function CartDisplay() {
  const { items, updateQuantity, getTotal } = useCartStore();
  
  return (
    <div>
      {items.map(item => (
        <div key={item.id}>
          {item.name} × {item.quantity}
          <button onClick={() => updateQuantity(item.id, item.quantity + 1)}>+</button>
        </div>
      ))}
      <p>总计：¥{getTotal().toFixed(2)}</p>
    </div>
  );
}
```

#### 方案三：SolidJS Signals（响应式范式）

```tsx
// store/cart-signal.ts
import { createSignal, createMemo } from 'solid-js';

interface CartItem {
  id: string;
  name: string;
  price: number;
  quantity: number;
}

let itemsSignal: ReturnType<typeof createSignal<CartItem[]>>;
let couponSignal: ReturnType<typeof createSignal<string | null>>;
let discountSignal: ReturnType<typeof createSignal<number>>;

export function initCart() {
  itemsSignal = createSignal([]);
  couponSignal = createSignal(null);
  discountSignal = createSignal(0);
}

export function getItems() { return itemsSignal![0](); }
export function getCoupon() { return couponSignal![0](); }
export function getDiscount() { return discountSignal![0](); }

export function addItem(item: Omit<CartItem, 'quantity'>) {
  const [items] = itemsSignal!;
  const existing = items().find(i => i.id === item.id);
  if (existing) {
    itemsSignal![1](items().map(i =>
      i.id === item.id ? { ...i, quantity: i.quantity + 1 } : i
    ));
  } else {
    itemsSignal![1]([...items(), { ...item, quantity: 1 }]);
  }
}

export function updateQuantity(id: string, quantity: number) {
  const [items, setItems] = itemsSignal!;
  setItems(items().map(item => item.id === id ? { ...item, quantity } : item));
}

export function applyCoupon(code: string, discount: number) {
  couponSignal![1](code);
  discountSignal![1](discount);
}

export const getTotal = createMemo(() => {
  const items = getItems();
  const discount = getDiscount();
  const total = items.reduce((sum, item) => sum + item.price * item.quantity, 0);
  return total * (1 - discount / 100);
});
```

**使用示例**（自动依赖追踪）：
```tsx
function CartDisplay() {
  return (
    <div>
      <For each={getItems()}>{item => (
        <div>
          {item.name} × {item.quantity}
          <button onClick={() => updateQuantity(item.id, item.quantity + 1)}>+</button>
        </div>
      )}</For>
      <p>总计：¥{getTotal().toFixed(2)}</p> {/* 仅当 items/discount 变化时更新 */}
    </div>
  );
}
```

### demos/目录示例

完整可运行项目已放入 `demos/state-management-comparison/`，包含：
- `context-example/` - Context + useReducer 实现
- `zustand-example/` - Zustand 实现（推荐）
- `solid-signals/` - SolidJS Signals 实现
- `benchmark/` - 性能对比测试（渲染次数/内存占用）

运行方式：
```bash
cd demos/state-management-comparison/zustand-example
npm install && npm dev
```

## 常见坑与排查

### 坑 1：Context 导致的过度重渲染

**现象**：修改购物车中一个商品数量，整个应用组件树都重新渲染。

**原因**：Context value 变化会触发所有 Consumer 重渲染，即使组件只使用部分数据。

**解决方案**：
```tsx
// ❌ 错误：整个 state 作为 value
<CartContext.Provider value={{ state, dispatch }}>

// ✅ 正确：拆分多个 Context
const CartItemsContext = createContext<CartItem[]>([]);
const CartTotalContext = createContext<number>(0);

// 或使用 useMemo 稳定引用
const value = useMemo(() => ({ state, dispatch }), [state.items, state.discount]);
```

### 坑 2：Zustand 选择器未优化

**现象**：组件订阅了整个 store，任何状态变化都触发重渲染。

**解决方案**：
```tsx
// ❌ 错误：订阅整个 store
const { items, updateQuantity } = useCartStore();

// ✅ 正确：使用选择器精确订阅
const items = useCartStore(state => state.items);
const updateQuantity = useCartStore(state => state.updateQuantity);
```

### 坑 3：Signals 在 React 中的误用

**现象**：在 React 组件中直接使用 Solid Signals，导致响应式失效。

**原因**：Signals 依赖框架的渲染系统追踪依赖，React 无法自动追踪。

**解决方案**：
- React 项目使用 `preact-signals/react` 或 `@preact/signals-react`
- 或使用 Zustand（更成熟的 React 生态）
- Solid Signals 仅在 SolidJS 项目中使用

### 坑 4：持久化导致的状态不一致

**现象**：本地存储的旧状态与新版本 schema 不兼容，应用崩溃。

**解决方案**：
```tsx
// Zustand persist 配置版本迁移
persist(cartReducer, {
  name: 'cart-storage',
  version: 2,
  migrate: (persistedState, version) => {
    if (version === 1) {
      // 添加新字段
      persistedState.discount = 0;
    }
    return persistedState as CartState;
  },
});
```

### 坑 5：TypeScript 类型推断失败

**现象**：Zustand/Jotai 的类型推断复杂，需要手动标注。

**解决方案**：
```tsx
// 明确定义 Store 类型
interface CartStore {
  items: CartItem[];
  addItem: (item: Omit<CartItem, 'quantity'>) => void;
}

// 使用泛型参数
export const useCartStore = create<CartStore>()(...);
```

## Checklist

### 选型决策清单

- [ ] **项目规模评估**
  - [ ] 小型项目（<10 个组件）：优先使用组件本地状态 + Context
  - [ ] 中型项目（10-50 个组件）：Zustand 或 Jotai
  - [ ] 大型项目（>50 个组件）：Zustand + 领域拆分 或 Signals（Solid/Vue）

- [ ] **技术栈匹配**
  - [ ] React 项目：Zustand（首选）或 Context（简单场景）
  - [ ] SolidJS 项目：原生 Signals
  - [ ] Vue 项目：原生 Ref/Reactive
  - [ ] 多框架共享：Zustand（框架无关）

- [ ] **性能要求**
  - [ ] 高频更新场景（实时数据/动画）：Signals 或 Jotai 原子状态
  - [ ] 一般业务场景：Zustand 足够
  - [ ] 极端性能要求：基准测试对比（使用 demos/benchmark）

- [ ] **团队因素**
  - [ ] 团队成员熟悉 Redux：考虑 Zustand（更简单的 Redux 替代）
  - [ ] 团队愿意学习新范式：Signals（未来趋势）
  - [ ] 需要快速上手：Zustand（文档完善，API 直观）

### 实施检查清单

- [ ] 定义清晰的状态边界（哪些放全局，哪些放本地）
- [ ] 配置 TypeScript 类型（避免 any）
- [ ] 设置持久化策略（localStorage/IndexedDB）
- [ ] 配置状态持久化的版本迁移
- [ ] 添加 DevTools 调试支持（Zustand Devtools / Redux DevTools）
- [ ] 编写单元测试（状态更新逻辑）
- [ ] 配置性能监控（渲染次数/内存占用）

### 上线前验证

- [ ] 压力测试：大量数据下的渲染性能
- [ ] 内存泄漏检测：长时间运行后内存占用
- [ ] 持久化兼容性：跨版本状态迁移
- [ ] SSR 兼容性：服务端渲染场景验证
- [ ] 并发更新测试：多用户/多标签页场景

## 参考资料

1. **Zustand 官方文档** - https://zustand-demo.pmnd.rs/ - 简洁强大的 React 状态管理库，无需 Provider 包裹，支持中间件与持久化
2. **SolidJS Signals 文档** - https://www.solidjs.com/guides/reactivity - 细粒度响应式系统原理与最佳实践
3. **React Context 官方文档** - https://react.dev/learn/passing-data-deeply-with-context - React 内置状态共享方案
4. **Jotai 官方文档** - https://jotai.org/ - 原子化状态管理，适合复杂依赖场景
5. **State of JS 2024 - State Management** - https://2024.stateofjs.com/en-US/libraries/state-management/ - 前端状态管理库流行度与技术满意度调研
6. **Fine-Grained Reactivity 技术解析** - https://alexanderson.tech/blog/fine-grained-reactivity - 深入解析 Signals 响应式原理与性能优势
