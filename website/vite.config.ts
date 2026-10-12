import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'

// 5174/4174 so it can run next to the portfolio (5173/4173).
export default defineConfig({
  plugins: [react()],
  server: { host: '127.0.0.1', port: 5174, strictPort: true },
  preview: { host: '127.0.0.1', port: 4174, strictPort: true },
})
