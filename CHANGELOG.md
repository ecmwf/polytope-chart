# Changelog

## 2.1.5

- Route community-ingress EODAG requests by User-Agent and other clients by Authorization, using a controller-defined NGINX map variable.
- Keep the Polytope server application version and image defaults unchanged.

## 2.1.4

- Add a configurable completed-redirect cache TTL and update for Polytope server 2.1.3.

## 2.1.3

- Update the chart application version for the Polytope server 2.1.2 patch release.

## 2.1.2

- Update the chart application version for the Polytope server 2.1.1 patch release.

## 2.1.1

- Update the chart application version for the Polytope server 2.1.0 release.

## 2.1.0

- Add explicit schedule enablement, validated worker-pool overrides, configurable Rust logging, and bounded or host-backed worker caches.
- Roll workers when MARS configuration changes and require explicit image tags for rendered workloads.
- Keep legacy truthy schedule maps and `cacheDir` host paths renderable for the transition release.
- Allow immutable digest image references and consume the BOBS 0.1.2 chart contract.
- Add chart CI and verify the vendored BOBS package against its pinned source revision.
