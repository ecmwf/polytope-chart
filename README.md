# Polytope Helm chart

Deploys the Polytope frontend, worker pools, NATS, BOBS, and Auth-o-tron.

## Validate

The BOBS chart is resolved from a sibling checkout. Build dependencies before
validation when `charts/` is empty:

```bash
helm dependency update .
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

`ecmwf/bobs` `chart/` is the sole source of truth. This chart consumes it through
`file://../bobs/chart`; no second editable chart copy is maintained here.
`.bobs-chart-revision` pins the release source used by CI and config render
validation. Update the pin and BOBS dependency version together.
