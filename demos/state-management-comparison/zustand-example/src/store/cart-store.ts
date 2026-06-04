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
