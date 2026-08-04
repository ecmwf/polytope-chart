#!/usr/bin/env bash
set -euo pipefail

CHART_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
FIXTURES="$CHART_DIR/tests/fixtures"
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

COMMON=(
	--set polytope.site=tst
	--set polytope.env=dev
	--set nats.enabled=false
	--set bobs.enabled=false
	--set auth-o-tron.enabled=false
)

fail() {
	printf 'FAIL: %s\n' "$*" >&2
	exit 1
}

assert_contains() {
	local file=$1 expected=$2
	grep -Fq -- "$expected" "$file" || fail "expected '$expected' in $file"
}

assert_not_contains() {
	local file=$1 unexpected=$2
	if grep -Fq -- "$unexpected" "$file"; then
		fail "did not expect '$unexpected' in $file"
	fi
}

expect_failure() {
	local expected=$1
	shift
	local output
	if output=$(helm template test "$CHART_DIR" "${COMMON[@]}" "$@" 2>&1); then
		fail "helm template unexpectedly succeeded (wanted: $expected)"
	fi
	grep -Fq -- "$expected" <<<"$output" || fail "failure did not contain '$expected': $output"
}

runtime="$TMP_DIR/runtime.yaml"
helm template test "$CHART_DIR" "${COMMON[@]}" -f "$FIXTURES/runtime.yaml" >"$runtime"

# Frontend default and configurable frontend/worker/pool Rust logging.
assert_contains "$runtime" 'image: "example/frontend:2.0.0"'
assert_contains "$runtime" 'completed_redirect_ttl_secs: 600'
assert_contains "$runtime" 'value: "debug"'
assert_contains "$runtime" 'value: "warn"'
assert_contains "$runtime" 'value: "trace"'

# Community ingress uses the controller-defined EODAG-aware map; NGINX Inc keeps
# the portable Authorization/client-address hash key.
community_ingress="$TMP_DIR/community-ingress.yaml"
helm template test "$CHART_DIR" "${COMMON[@]}" \
  --set global.ingress.controller=nginx-community \
  --set ingress.enabled=true --set ingress.domain=example.test >"$community_ingress"
assert_contains "$community_ingress" 'nginx.ingress.kubernetes.io/upstream-hash-by: $polytope_frontend_hash_key'

inc_ingress="$TMP_DIR/inc-ingress.yaml"
helm template test "$CHART_DIR" "${COMMON[@]}" \
  --set global.ingress.controller=nginx-inc \
  --set ingress.enabled=true --set ingress.domain=example.test >"$inc_ingress"
assert_contains "$inc_ingress" 'nginx.org/lb-method: "hash $http_authorization$proxy_protocol_addr consistent"'
assert_not_contains "$inc_ingress" '$polytope_frontend_hash_key'

digest="$TMP_DIR/digest.yaml"
helm template test "$CHART_DIR" "${COMMON[@]}" -f "$FIXTURES/runtime.yaml" \
	--set-string frontend.image.digest=sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa \
	--set-string workerPools.empty-cache.image.digest=sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb \
	>"$digest"
assert_contains "$digest" 'image: "example/frontend@sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"'
assert_contains "$digest" 'image: "example/worker@sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"'

# A release bundle resolves default application images by digest and must have
# the same product version as Chart.AppVersion. An explicit dev tag overrides
# the matching bundle entry for a single image.
bundle="$TMP_DIR/release-bundle.yaml"
helm template test "$CHART_DIR" "${COMMON[@]}" -f "$FIXTURES/release-bundle.yaml" >"$bundle"
assert_contains "$bundle" 'image: "registry.example/polytope/frontend@sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"'
assert_contains "$bundle" 'image: "registry.example/polytope/mars-worker@sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"'

bundle_mirror="$TMP_DIR/release-bundle-mirror.yaml"
helm template test "$CHART_DIR" "${COMMON[@]}" -f "$FIXTURES/release-bundle.yaml" \
	--set-string global.imageRegistry=mirror.example/polytope >"$bundle_mirror"
assert_contains "$bundle_mirror" 'image: "mirror.example/polytope/frontend@sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"'

bundle_override="$TMP_DIR/release-bundle-override.yaml"
helm template test "$CHART_DIR" "${COMMON[@]}" -f "$FIXTURES/release-bundle-override.yaml" >"$bundle_override"
assert_contains "$bundle_override" 'image: "frontend:git-47c44cfd66119ace6b8d55fc85cf7c497638f283"'
assert_not_contains "$bundle_override" 'registry.example/polytope/frontend@sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'

expect_failure 'releaseBundle.version "2.1.9" must match Chart.AppVersion "2.2.0"' \
	-f "$FIXTURES/release-bundle-override.yaml" --set-string releaseBundle.version=2.1.9
expect_failure 'releaseBundle.enabled must be a boolean' \
	-f "$FIXTURES/runtime.yaml" --set-string releaseBundle.enabled=not-a-boolean
expect_failure 'releaseBundle.images.mars-worker.digest is required' \
	-f "$FIXTURES/release-bundle.yaml" --set-string workerPools.mars.image.component=mars-worker --set-string releaseBundle.images.mars-worker.digest=

# Bounded emptyDir, explicit hostPath, and the one-release cacheDir bridge.
assert_contains "$runtime" 'mountPath: "/cache/empty"'
assert_contains "$runtime" 'sizeLimit: "10Gi"'
assert_contains "$runtime" 'path: "/var/lib/polytope/cache"'
assert_contains "$runtime" 'type: Directory'
assert_contains "$runtime" 'path: "/var/lib/polytope/legacy-cache"'
assert_contains "$runtime" 'type: DirectoryOrCreate'
assert_not_contains "$runtime" 'worker-optional-tuning'

# A MARS ConfigMap input must contribute to the worker pod checksum.
checksum_before=$(grep -F 'checksum/worker-config:' "$runtime")
changed="$TMP_DIR/runtime-changed.yaml"
helm template test "$CHART_DIR" "${COMMON[@]}" -f "$FIXTURES/runtime.yaml" \
	--set-string 'workerPools.empty-cache.marsConfig.databases[0].name=second' >"$changed"
checksum_after=$(grep -F 'checksum/worker-config:' "$changed")
[[ "$checksum_before" != "$checksum_after" ]] || fail 'marsConfig did not change the worker checksum'

# Missing pools fail consistently in both worker resource templates; override-only skips.
expect_failure 'workerPools.malformed.pool is required unless overrideOnly is true' \
	-f "$FIXTURES/missing-pool.yaml" --show-only templates/worker-pool.yaml
expect_failure 'workerPools.malformed.pool is required unless overrideOnly is true' \
	-f "$FIXTURES/missing-pool.yaml" --show-only templates/worker-configmaps.yaml
expect_failure 'image.tag or image.digest is required when releaseBundle is disabled' \
	-f "$FIXTURES/missing-tag.yaml"
expect_failure 'workerPools.conflict.cache must configure exactly one of hostPath or emptyDir' \
	-f "$FIXTURES/cache-conflict.yaml"
expect_failure 'workerPools.host-cache.cache and deprecated cacheDir cannot both be set' \
	-f "$FIXTURES/runtime.yaml" --set-string workerPools.host-cache.cacheDir=/legacy
expect_failure 'image.tag or image.digest is required when releaseBundle is disabled' \
	-f "$FIXTURES/frontend-missing-tag.yaml"

# Explicit schedule state is authoritative; null/omitted retains legacy truthy maps.
schedule_enabled="$TMP_DIR/schedule-enabled.yaml"
helm template test "$CHART_DIR" "${COMMON[@]}" -f "$FIXTURES/schedule-enabled.yaml" >"$schedule_enabled"
assert_contains "$schedule_enabled" 'name: fetch-schedule'
assert_contains "$schedule_enabled" 'name: schedule-ssh'
assert_contains "$schedule_enabled" 'secretName: schedule-test-key'
assert_contains "$schedule_enabled" 'path: /etc/polytope/schedule.xml'

schedule_disabled="$TMP_DIR/schedule-disabled.yaml"
helm template test "$CHART_DIR" "${COMMON[@]}" -f "$FIXTURES/schedule-disabled.yaml" >"$schedule_disabled"
assert_not_contains "$schedule_disabled" 'name: fetch-schedule'
assert_not_contains "$schedule_disabled" 'name: schedule-ssh'
assert_not_contains "$schedule_disabled" '/etc/polytope/schedule.xml'

schedule_legacy="$TMP_DIR/schedule-legacy.yaml"
helm template test "$CHART_DIR" "${COMMON[@]}" -f "$FIXTURES/schedule-legacy-null.yaml" >"$schedule_legacy"
assert_contains "$schedule_legacy" 'name: fetch-schedule'

expect_failure 'schedule.repo is required when schedule is enabled' \
	-f "$FIXTURES/schedule-invalid.yaml"

printf 'All polytope chart runtime tests passed.\n'
