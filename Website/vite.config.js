import { defineConfig } from 'vite';
import { fileURLToPath } from 'node:url';
export default defineConfig({
  define: { 'process.env.NODE_ENV': JSON.stringify('production') },
  esbuild: { jsx: 'automatic' },
  build: {
    outDir: '../docs/assets/demo',
    emptyOutDir: true,
    lib: { entry: fileURLToPath(new URL('./demo.tsx', import.meta.url)), formats: ['es'], fileName: () => 'demo.js' },
    cssCodeSplit: false,
    rollupOptions: { output: { assetFileNames: 'demo.[ext]' } }
  }
});
