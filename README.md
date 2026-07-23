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

## Ingress affinity

NGINX Inc uses `ingress.stickyHashBy`. Community ingress-nginx uses
`ingress.communityStickyHashBy`, which defaults to `$polytope_frontend_hash_key`.
Define that variable in the ingress controller's `http-snippet` with an NGINX
`map` that selects User-Agent for EODAG and Authorization for other clients; see
the documented example in `values.yaml`.

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
