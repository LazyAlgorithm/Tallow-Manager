#!/usr/bin/env bash
# Stable tags use the pushed version; beta patches use first-parent release commits.
# The baseline is the main commit before beta semantic versioning began.
set -euo pipefail
if [[ "${GITHUB_REF_TYPE:-}" == "tag" ]]; then
  echo "$GITHUB_REF_NAME"
  exit 0
fi
dir="$(cd "$(dirname "$0")/../.." && pwd)"
baseline=eb4c3af7dbcfcac2db5a7ce76ff86156c11c0975
commits="$(git -C "$dir" rev-list --first-parent --count "$baseline"..HEAD)"
if (( commits < 1 )); then
  echo "Unable to derive beta version from main history" >&2
  exit 1
fi
echo "v0.1.$((commits - 1))-beta"
