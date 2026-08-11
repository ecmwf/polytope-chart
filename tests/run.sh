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
assert_contains "$runtime" 'image: "frontend:2.0.0"'
assert_contains "$runtime" 'completed_redirect_ttl_secs: 600'
assert_contains "$runtime" 'value: "debug"'
assert_contains "$runtime" 'value: "warn"'
assert_contains "$runtime" 'value: "trace"'

# Both ingress controllers use the same Authorization/client-address hash key.
community_ingress="$TMP_DIR/community-ingress.yaml"
helm template test "$CHART_DIR" "${COMMON[@]}" \
	--set global.ingress.controller=nginx-community \
	--set ingress.enabled=true --set ingress.domain=example.test >"$community_ingress"
assert_contains "$community_ingress" 'nginx.ingress.kubernetes.io/upstream-hash-by: $http_authorization$proxy_protocol_addr'
assert_not_contains "$community_ingress" '$polytope_frontend_hash_key'

inc_ingress="$TMP_DIR/inc-ingress.yaml"
helm template test "$CHART_DIR" "${COMMON[@]}" \
	--set global.ingress.controller=nginx-inc \
	--set ingress.enabled=true --set ingress.domain=example.test >"$inc_ingress"
assert_contains "$inc_ingress" 'nginx.org/lb-method: "hash $http_authorization$proxy_protocol_addr consistent"'
assert_not_contains "$inc_ingress" '$polytope_frontend_hash_key'

virtual_server="$TMP_DIR/virtual-server.yaml"
helm template test "$CHART_DIR" "${COMMON[@]}" \
	-f "$FIXTURES/virtual-server.yaml" --set bobs.enabled=true >"$virtual_server"
assert_contains "$virtual_server" 'kind: VirtualServer'
assert_contains "$virtual_server" 'ingressClassName: "dns-only"'
assert_contains "$virtual_server" 'dns.operators.ecmwf.int/on-transport-server: vs-transport-https'
assert_contains "$virtual_server" 'secret: "polytope-test-example-test-tls"'
assert_contains "$virtual_server" 'lb-method: "hash $http_authorization$proxy_protocol_addr consistent"'
assert_contains "$virtual_server" 'service: test-bobs-0'
assert_contains "$virtual_server" 'service: test-bobs-1'
assert_contains "$virtual_server" 'path: "/download-0"'
assert_contains "$virtual_server" 'proxy_set_header X-Forwarded-Prefix /download-1;'
assert_contains "$virtual_server" 'rewrite ^/download-1/api/v1/read/([^/]+)$ /api/v1/read/$1 break;'
assert_not_contains "$virtual_server" 'nginx.org/mergeable-ingress-type'
assert_not_contains "$virtual_server" 'name: test-ingress-frontend'

expect_failure 'bobs.ingress.enabled must be false when ingress.virtualServer.enabled=true' \
	-f "$FIXTURES/virtual-server.yaml" --set bobs.enabled=true --set bobs.ingress.enabled=true
expect_failure 'ingress.virtualServer.enabled requires global.ingress.controller=nginx-inc' \
	-f "$FIXTURES/virtual-server.yaml" --set global.ingress.controller=nginx-community

digest="$TMP_DIR/digest.yaml"
helm template test "$CHART_DIR" "${COMMON[@]}" -f "$FIXTURES/runtime.yaml" \
	--set-string frontend.image.digest=sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa \
	--set-string workerPools.empty-cache.image.digest=sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb \
	>"$digest"
assert_contains "$digest" 'image: "frontend@sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"'
assert_contains "$digest" 'image: "example/worker@sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"'

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
assert_contains "$runtime" 'verbs: ["create", "get", "delete", "patch"]'

# Missing pools fail consistently in both worker resource templates; override-only skips.
expect_failure 'workerPools.malformed.pool is required unless overrideOnly is true' \
	-f "$FIXTURES/missing-pool.yaml" --show-only templates/worker-pool.yaml
expect_failure 'workerPools.malformed.pool is required unless overrideOnly is true' \
	-f "$FIXTURES/missing-pool.yaml" --show-only templates/worker-configmaps.yaml
expect_failure 'workerPools.untagged.image.tag or image.digest is required for a rendered worker' \
	-f "$FIXTURES/missing-tag.yaml"
expect_failure 'workerPools.conflict.cache must configure exactly one of hostPath or emptyDir' \
	-f "$FIXTURES/cache-conflict.yaml"
expect_failure 'workerPools.host-cache.cache and deprecated cacheDir cannot both be set' \
	-f "$FIXTURES/runtime.yaml" --set-string workerPools.host-cache.cacheDir=/legacy
expect_failure 'image.tag or image.digest is required; Chart.AppVersion is not an image fallback' \
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
