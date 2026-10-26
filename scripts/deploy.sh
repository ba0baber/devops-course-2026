#!/usr/bin/env bash
# Usage: scripts/deploy.sh [--dry-run]
set -euo pipefail

fail() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
DRY_RUN=false
case "$#:${1-}" in
    0:) ;;
    1:--dry-run) DRY_RUN=true ;;
    *) fail 'Usage: scripts/deploy.sh [--dry-run]' ;;
esac

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel) || fail 'Cannot locate repository'
LOCAL_DIR="$REPO_ROOT/site/"
REMOTE=devops
REMOTE_DIR=/var/www/devops-site
SITE_URL=https://devops.local
CA_CERT="${HOME}/devops.crt"

[[ -f "${LOCAL_DIR}index.html" ]] || fail 'site/index.html is missing; transfer cancelled'
STATUS=$(git -C "$REPO_ROOT" status --porcelain --untracked-files=all) || fail 'Cannot read repository status'
[[ -z "$STATUS" ]] || fail 'Uncommitted changes (including staged or untracked files); transfer cancelled'
COMMIT=$(git -C "$REPO_ROOT" rev-parse --short HEAD) || fail 'Cannot identify commit'
command -v rsync >/dev/null || fail 'rsync is required'
if ! "$DRY_RUN"; then
    command -v curl >/dev/null || fail 'curl is required'
    [[ -r "$CA_CERT" ]] || fail "CA certificate not readable: $CA_CERT"
fi

OPTIONS=(-avz --delete --chmod=D755,F644 -e 'ssh -o BatchMode=yes -o ConnectTimeout=5 -o ConnectionAttempts=1')
if "$DRY_RUN"; then OPTIONS+=(--dry-run); fi
rsync "${OPTIONS[@]}" "$LOCAL_DIR" "${REMOTE}:${REMOTE_DIR}/" || fail 'rsync transfer failed'
if "$DRY_RUN"; then
    printf 'DRY RUN OK: commit %s; server unchanged\n' "$COMMIT"
    exit 0
fi
curl --noproxy '*' --fail --silent --show-error --connect-timeout 5 --max-time 15 \
    --cacert "$CA_CERT" --output /dev/null "${SITE_URL}/" || fail 'HTTPS availability or certificate check failed'
printf 'DEPLOY OK: commit %s\n' "$COMMIT"
