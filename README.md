# Polytope Helm chart

Deploys the Polytope frontend, worker pools, NATS, BOBS, and Auth-o-tron.

## Validate

Dependencies are committed under `charts/`, so validation does not need registry
or cross-repository access:

```bash
sha256sum --check .bobs-chart-package.sha256
helm dependency list .
helm lint . --strict
helm template polytope . \
  --set polytope.site=tst \
  --set polytope.env=dev \
  --set bobs.config.host_prefix=polytope \
  --set bobs.config.domain=example.test \
  --set auth-o-tron.enabled=false
./tests/run.sh
```

## Images

Set `global.imageRegistry` once and use unqualified component repositories. Images
accept either `tag` or `digest`; `digest` takes precedence and should be used for
production releases. `Chart.appVersion` is informational and is never an image
fallback.

## Ingress routing

NGINX Inc deployments can opt into `ingress.virtualServer.enabled`. One
`VirtualServer` then owns the frontend and all per-pod BOBS routes; set
`bobs.ingress.enabled: false` so the subchart does not render mergeable minions.
The existing `{release}-ingress` becomes a `dns-only` shim that retains ECMWF DNS
and cert-manager ownership without competing for NGINX host configuration.

NGINX Inc uses `ingress.stickyHashBy`; community ingress-nginx uses
`ingress.communityStickyHashBy`. Both default to consistent hashing over the
Authorization header plus proxy-protocol client address:
`$http_authorization$proxy_protocol_addr`.

## Worker pools

Every rendered `workerPools` entry needs a `pool` and a tagged or digest-pinned
image. A location-specific overlay may deliberately target a pool absent from
another location by setting `overrideOnly: true`; missing pools without that
explicit marker fail rendering.

Worker caches default to disabled. Configure a bounded `cache.emptyDir`, or an
explicit `cache.hostPath` when node-local persistence is required.

## Schedule check

The schedule init container is enabled only when `schedule.enabled: true`. It
requires `schedule.repo`, `schedule.path`, and an SSH key secret named by
`schedule.sshSecretName` (normally `polytope-schedule-ssh`). Set
`schedule.enabled: false` in environments that do not use the schedule check.

## BOBS dependency source

`ecmwf/bobs` `chart/` is the sole editable source. `charts/bobs-*.tgz` is a
generated Helm dependency, not a second source tree. The revision and package
checksum are recorded for CI. Refresh all three together from sibling checkouts:

```bash
./scripts/update-bobs-dependency.sh ../bobs
```

Update `Chart.yaml` and `Chart.lock` when the BOBS chart version changes.
