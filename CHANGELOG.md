# Changelog

## 2.1.0

- Add explicit schedule enablement, validated worker-pool overrides, configurable Rust logging, and bounded or host-backed worker caches.
- Roll workers when MARS configuration changes and require explicit image tags for rendered workloads.
- Keep legacy truthy schedule maps and `cacheDir` host paths renderable for the transition release.
