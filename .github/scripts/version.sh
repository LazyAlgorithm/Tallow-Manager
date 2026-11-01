#!/usr/bin/env bash
# Tag names match displayed Manager releases. SHA remains separate.
set -euo pipefail
if [[ "${GITHUB_REF_TYPE:-}" == "tag" ]]; then
  echo "$GITHUB_REF_NAME"
  exit 0
fi
# Beta patch numbers advance after each published beta.
dir="$(cd "$(dirname "$0")/../.." && pwd)"
last="$(git -C "$dir" ls-remote --tags origin 'refs/tags/v0.1.*-beta' |
  sed -n 's|.*refs/tags/v0\.1\.\([0-9][0-9]*\)-beta$|\1|p' |
  sort -n | tail -1)"
next=$(("${last:--1}" + 1))
echo "v0.1.${next}-beta"
