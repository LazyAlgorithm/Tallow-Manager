#!/usr/bin/env bash
# The release tag this build is for: the pushed tag, or manager-<date>-<commit> for a beta. Written into the Manager
# (src/Data/version.txt) and used as the release's tag, so the Manager knows which release it is.
if [ "${GITHUB_REF_TYPE:-}" = "tag" ]; then
	echo "$GITHUB_REF_NAME"
else
	# The commit's date, not today's, so jobs that run either side of midnight agree.
	dir="$(cd "$(dirname "$0")/../.." && pwd)"
	echo "v0.0.1-beta.${GITHUB_RUN_NUMBER:-1}"
fi
