import path from "node:path";
import { fileURLToPath } from "node:url";
import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";

const rootDir = fileURLToPath(new URL(".", import.meta.url));
const reactPackagePath = path.resolve(rootDir, "node_modules/react");
const reactDomPackagePath = path.resolve(rootDir, "node_modules/react-dom");

export default defineConfig(({ command }) => ({
  plugins: [react()],
  base: command === "serve" ? "/" : "./",
  resolve: {
    alias: {
      react: reactPackagePath,
      "react/jsx-runtime": path.resolve(reactPackagePath, "jsx-runtime.js"),
      "react/jsx-dev-runtime": path.resolve(reactPackagePath, "jsx-dev-runtime.js"),
      "react-dom": reactDomPackagePath,
      "react-dom/client": path.resolve(reactDomPackagePath, "client.js"),
    },
    dedupe: ["react", "react-dom"],
    preserveSymlinks: true,
  },
  clearScreen: false,
  server: {
    port: 1421,
    strictPort: true,
  },
  envPrefix: ["VITE_", "TAURI_"],
  build: {
    target: ["es2020", "chrome105", "safari13"],
    minify: !process.env.TAURI_DEBUG ? "esbuild" : false,
    sourcemap: !!process.env.TAURI_DEBUG,
  },
}));
