#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

helm template rs256 "$ROOT" \
	-f "$ROOT/tests/fixtures/auth-rs256-overlap.yaml" \
	>"$TMP/rendered.yaml"

python3 - "$TMP/rendered.yaml" <<'PY'
import json
import pathlib
import subprocess
import sys
import tempfile

import yaml

with open(sys.argv[1], encoding="utf-8") as stream:
    documents = [document for document in yaml.safe_load_all(stream) if document]


def resource(kind, name):
    matches = [
        document
        for document in documents
        if document.get("kind") == kind
        and document.get("metadata", {}).get("name") == name
    ]
    assert len(matches) == 1, f"expected one {kind}/{name}, got {len(matches)}"
    return matches[0]


def container(deployment, name, section="containers"):
    matches = [
        item
        for item in deployment["spec"]["template"]["spec"].get(section, [])
        if item["name"] == name
    ]
    assert len(matches) == 1, f"expected one {section} entry named {name}"
    return matches[0]


def env_var(container_spec, name):
    matches = [item for item in container_spec.get("env", []) if item["name"] == name]
    assert len(matches) == 1, f"expected one environment variable {name}"
    return matches[0]

frontend_config_map = resource("ConfigMap", "rs256-config")
frontend_base_config = yaml.safe_load(frontend_config_map["data"]["config.yaml"])
assert "authentication" not in frontend_base_config

auth_config_map = resource("ConfigMap", "rs256-auth-o-tron-config")
auth_config = yaml.safe_load(auth_config_map["data"]["config.yaml"])
assert auth_config["jwt"] == {
    "aud": "polytope-server",
    "exp": 3600,
    "iss": "authotron-test",
    "kid": "next",
}

config_maps = [document for document in documents if document.get("kind") == "ConfigMap"]
config_map_text = json.dumps(config_maps)
for forbidden in (
    "AUTH_SECRET",
    "AOT_JWT__PRIVATE_KEY",
    "private-key.pem",
    "BEGIN PRIVATE KEY",
    "BEGIN PUBLIC KEY",
):
    assert forbidden not in config_map_text, f"{forbidden} leaked into a ConfigMap"

auth_deployment = resource("Deployment", "rs256-auth-o-tron")
auth_container = auth_deployment["spec"]["template"]["spec"]["containers"][0]
private_key_env = env_var(auth_container, "AOT_JWT__PRIVATE_KEY")
assert private_key_env["valueFrom"]["secretKeyRef"] == {
    "key": "private-key.pem",
    "name": "auth-o-tron-jwt",
}

frontend_deployment = resource("Deployment", "rs256-frontend")
frontend_container = container(frontend_deployment, "polytope-server")
assert all(item["name"] != "AUTH_SECRET" for item in frontend_container.get("env", []))
assert all(item["name"] != "AOT_JWT__PRIVATE_KEY" for item in frontend_container.get("env", []))
assert {mount["name"] for mount in frontend_container["volumeMounts"]} == {"config-runtime"}

frontend_text = json.dumps(frontend_deployment)
assert "private-key.pem" not in frontend_text
assert "AOT_JWT__PRIVATE_KEY" not in frontend_text
assert "AUTH_SECRET" not in frontend_text

builder = container(frontend_deployment, "build-auth-config", "initContainers")
script = builder["command"][-1]
for expected in (
    'issuer: "authotron-test"',
    'audience: "polytope-server"',
    '- kid: "next"',
    '- kid: "previous"',
    "public_key: |",
    "/keys/public-key.pem",
    "/keys/public-key-0.pem",
):
    assert expected in script, f"runtime keyset builder is missing {expected}"
assert "private" not in script.lower()

with tempfile.TemporaryDirectory() as temporary_directory:
    root = pathlib.Path(temporary_directory)
    for directory in ("config", "runtime", "keys"):
        (root / directory).mkdir()
    (root / "config/config.yaml").write_text(
        frontend_config_map["data"]["config.yaml"], encoding="utf-8"
    )
    for filename, marker in (
        ("public-key.pem", "active"),
        ("public-key-0.pem", "previous"),
    ):
        (root / "keys" / filename).write_text(
            f"-----BEGIN PUBLIC KEY-----\n{marker}\n-----END PUBLIC KEY-----",
            encoding="utf-8",
        )
    runnable_script = (
        script.replace("/config/config.yaml", str(root / "config/config.yaml"))
        .replace("/runtime/config.yaml", str(root / "runtime/config.yaml"))
        .replace("/keys/", f"{root / 'keys'}/")
    )
    subprocess.run(["sh", "-c", runnable_script], check=True)
    runtime_config = yaml.safe_load(
        (root / "runtime/config.yaml").read_text(encoding="utf-8")
    )
    public_keys = runtime_config["authentication"]["public_keys"]
    assert [key["kid"] for key in public_keys] == ["next", "previous"]
    assert all(key["public_key"].startswith("-----BEGIN") for key in public_keys)

pod_spec = frontend_deployment["spec"]["template"]["spec"]
key_volume = next(volume for volume in pod_spec["volumes"] if volume["name"] == "auth-public-keys")
secret_sources = [source["secret"] for source in key_volume["projected"]["sources"]]
assert secret_sources == [
    {
        "name": "auth-o-tron-jwt",
        "items": [{"key": "public-key.pem", "path": "public-key.pem"}],
    },
    {
        "name": "auth-o-tron-jwt-previous",
        "items": [{"key": "public-key.pem", "path": "public-key-0.pem"}],
    },
]

all_text = json.dumps(documents)
assert "AUTH_SECRET" not in all_text
PY

expect_failure() {
	local fixture=$1
	local expected=$2
	local output="$TMP/$(basename "$fixture").log"
	if helm template invalid "$ROOT" -f "$fixture" >"$output" 2>&1; then
		echo "expected Helm rendering to fail for $fixture" >&2
		exit 1
	fi
	if ! grep -Fq "$expected" "$output"; then
		echo "missing expected failure '$expected' for $fixture" >&2
		cat "$output" >&2
		exit 1
	fi
}

expect_failure \
	"$ROOT/tests/fixtures/auth-missing-public-key-secret.yaml" \
	"authentication.publicKeySecret.name is required"
expect_failure \
	"$ROOT/tests/fixtures/auth-missing-additional-key-reference.yaml" \
	"authentication.additionalPublicKeys[0].secretKey is required"
expect_failure \
	"$ROOT/tests/fixtures/auth-missing-private-key-reference.yaml" \
	"auth-o-tron.extraEnv must reference Secret auth-o-tron-jwt key private-key.pem"
expect_failure \
	"$ROOT/tests/fixtures/auth-configmap-private-key.yaml" \
	"auth-o-tron.config.jwt.private_key is forbidden"
expect_failure \
	"$ROOT/tests/fixtures/auth-configmap-shared-secret.yaml" \
	"auth-o-tron.config.jwt.secret is forbidden"

helm template no-auth "$ROOT" \
	--set polytope.site=bol \
	--set polytope.env=tst \
	--set nats.enabled=false \
	--set bobs.enabled=false \
	--set auth-o-tron.enabled=false \
	>"$TMP/no-auth.yaml"

python3 - "$TMP/no-auth.yaml" <<'PY'
import sys
import yaml

with open(sys.argv[1], encoding="utf-8") as stream:
    documents = [document for document in yaml.safe_load_all(stream) if document]

config_map = next(
    document
    for document in documents
    if document.get("kind") == "ConfigMap"
    and document.get("metadata", {}).get("name") == "no-auth-config"
)
assert "authentication" not in yaml.safe_load(config_map["data"]["config.yaml"])

deployment = next(
    document
    for document in documents
    if document.get("kind") == "Deployment"
    and document.get("metadata", {}).get("name") == "no-auth-frontend"
)
pod_spec = deployment["spec"]["template"]["spec"]
assert all(item["name"] != "build-auth-config" for item in pod_spec.get("initContainers", []))
container = pod_spec["containers"][0]
assert any(mount["name"] == "config" for mount in container["volumeMounts"])
assert all(volume["name"] != "auth-public-keys" for volume in pod_spec["volumes"])
PY

echo "RS256 Helm render tests passed"
