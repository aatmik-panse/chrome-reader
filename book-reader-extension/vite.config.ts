import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";
import tailwindcss from "@tailwindcss/vite";
import { resolve } from "path";

export default defineConfig({
  plugins: [react(), tailwindcss()],
  build: {
    outDir: "dist",
    emptyDirBeforeWrite: true,
    rollupOptions: {
      input: {
        newtab: resolve(__dirname, "src/newtab/index.html"),
      },
    },
  },
});
