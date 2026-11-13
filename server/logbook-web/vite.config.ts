// `vitest/config` re-exports Vite's defineConfig with the `test` key typed, so
// one file serves both `vite build` and `vitest run`.
import { defineConfig } from 'vitest/config';
import react from '@vitejs/plugin-react';
import path from 'path';

// Served same-origin by the activities-server under /logbook (see main.rs).
// `base` must match so built asset URLs resolve.
export default defineConfig({
  base: '/logbook/',
  plugins: [react()],
  resolve: {
    alias: {
      '@': path.resolve(__dirname, './src'),
    },
  },
  build: {
    outDir: 'dist',
  },
  server: {
    proxy: {
      '/v1': {
        // CW_API_PROXY points dev runs at staging/prod instead of a local
        // activities server (e.g. CW_API_PROXY=https://staging.carrierwave.app).
        target: process.env.CW_API_PROXY ?? 'http://localhost:8080',
        changeOrigin: true,
        // /v1/websdr/stream is a WebSocket (KiwiSDR bridge).
        ws: true,
      },
    },
  },
  test: {
    // Pure-TS unit tests (ADIF formatting etc.); no DOM needed.
    environment: 'node',
    include: ['src/**/*.test.ts'],
  },
});
