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

The chart's `releaseBundle` is the normal application-image identity. It maps
`Chart.appVersion` to repository/digest pairs from the Polytope release manifest;
rendering fails if the bundle version differs from `Chart.appVersion`. The
release bundle is therefore digest-pinned by default.

Set `global.imageRegistry` once to mirror all bundle images to another registry.
An explicit component `image.tag` or `image.digest` overrides the bundle;
`digest` takes precedence. This preserves the existing developer one-image
`git-<sha>` loop and supports explicit mixed-component deployments. The
workspace-level `POLYTOPE_RELEASE_BUNDLE_PLAN.md` records the coordinated
server/chart/config release process.

## Ingress affinity

NGINX Inc uses `ingress.stickyHashBy`. Community ingress-nginx uses
`ingress.communityStickyHashBy`, which defaults to `$polytope_frontend_hash_key`.
Define that variable in the ingress controller's `http-snippet` with an NGINX
`map` that selects User-Agent for EODAG and Authorization for other clients; see
the documented example in `values.yaml`.

## Worker pools

Every rendered `workerPools` entry needs a `pool` and resolves from the release
bundle when it has no explicit tag or digest. A location-specific overlay may
deliberately target a pool absent from
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
