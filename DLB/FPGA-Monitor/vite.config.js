/**
 * Responsibility: Reproducible local build configuration.
 * Allowed dependencies: Vite.
 * Forbidden responsibilities: Application logic.
 * Public API: Vite configuration.
 * Architecture invariants: ECharts is bundled locally; no CDN dependency.
 */
import { defineConfig } from 'vite';
export default defineConfig({
  base: './',
  build: { rollupOptions: { output: { manualChunks: { echarts: ['echarts/core', 'echarts/charts', 'echarts/components', 'echarts/renderers'] } } } },
});
