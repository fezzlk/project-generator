#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TEMPLATE="$ROOT/templates/cloudbuild.yaml.tmpl"

for file in "$TEMPLATE" "$ROOT/templates/Dockerfile.tmpl" "$ROOT/templates/docker-compose.yml.tmpl" "$ROOT/scaffold.sh"; do
  test -s "$file" || { echo "Missing required template: $file" >&2; exit 1; }
done

require() {
  grep -Fq -- "$1" "$TEMPLATE" || { echo "Required Cloud Run guard missing: $1" >&2; exit 1; }
}

forbid() {
  if grep -Fq -- "$1" "$TEMPLATE"; then
    echo "Unsafe Cloud Run option found: $1" >&2
    exit 1
  fi
}

require "--image="
require "--region={{REGION}}"
require "--min-instances=0"
require "--memory=512Mi"
require "--cpu=1"
forbid " deploy --source"
forbid "--no-cpu-throttling"
forbid "startup-cpu-boost"
forbid "--session-affinity"

echo "Template contract verification passed"
