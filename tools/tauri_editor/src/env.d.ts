/// <reference types="vite/client" />

interface ImportMetaEnv {
  readonly VITE_EDITOR_START_SURFACE?: string;
}

interface ImportMeta {
  readonly env: ImportMetaEnv;
}
