/// <reference types="vite/client" />

// wasm-pack emits the .wasm alongside the JS glue; we import it as a URL and
// hand it to init(). Vite resolves `?url` imports to the fingerprinted asset.
declare module '*.wasm?url' {
  const url: string;
  export default url;
}
