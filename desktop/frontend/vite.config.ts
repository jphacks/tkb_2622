import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';

export default defineConfig({
  plugins: [react()],
  server: { port: 5173, strictPort: true, fs: { allow: ['..'] } },
  build: { target: 'es2022' },
});
