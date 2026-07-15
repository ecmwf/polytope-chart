#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
bobs_repo=${1:-"$repo_root/../bobs"}
chart="$bobs_repo/chart"

if [[ ! -d "$chart" ]]; then
  echo "BOBS chart not found: $chart" >&2
  exit 1
fi

rm -f "$repo_root"/charts/bobs-*.tgz
helm package "$chart" --destination "$repo_root/charts" >/dev/null
git -C "$bobs_repo" rev-parse HEAD >"$repo_root/.bobs-chart-revision"
(
  cd "$repo_root"
  sha256sum charts/bobs-*.tgz >.bobs-chart-package.sha256
)
printf 'Updated BOBS dependency from %s\n' "$(cat "$repo_root/.bobs-chart-revision")"
