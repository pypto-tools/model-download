#!/usr/bin/env bash
# Generic ModelScope downloader/resumer — reusable for any model.
#
# Usage:
#   download_model.sh <model-id> [dest-dir]
#
#   <model-id>   e.g. deepseek-ai/DeepSeek-V4-Flash
#   [dest-dir]   default: /data/models/<model-basename>
#
# Idempotent: skips already-downloaded files, retries on network failure,
# single-instance per model (flock), writes <dest>/.download_complete when done.
# Schedule nightly with e.g.:
#   0 2 * * * /path/to/model-download/download_model.sh some-org/Some-Model
set -u

# Models live in a shared directory: keep downloaded directories traversable
# and files readable by every local user.
umask 0022

MODEL="${1:?usage: download_model.sh <model-id> [dest-dir]}"
DEST="${2:-/data/models/$(basename "$MODEL")}"
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
SLUG="$(echo "$MODEL" | tr '/ ' '__')"
LOG="$HERE/download-$SLUG.log"
LOCK="$HERE/.download-$SLUG.lock"
DONE_MARKER="$DEST/.download_complete"
MAX_ATTEMPTS=20
MAX_WORKERS="${MODELSCOPE_MAX_WORKERS:-1}"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >>"$LOG"; }

exec 9>"$LOCK"
if ! flock -n 9; then
  log "another instance for $MODEL is running; exiting."
  exit 0
fi

[ -f "$DONE_MARKER" ] && exit 0

mkdir -p "$DEST"
chmod a+rX "$DEST"
# A stale .msc owned by another user (mode 0600) blocks our progress index;
# drop it so modelscope can persist its own (it re-validates existing files).
if [ -e "$DEST/.msc" ] && [ ! -w "$DEST/.msc" ]; then
  rm -f "$DEST/.msc" && log "removed stale unwritable .msc"
fi

. "$HERE/.venv/bin/activate"
# modelscope.cn is domestic — direct is faster and more reliable than the
# overseas proxy (measured ~3x). Force-direct regardless of inherited env.
unset http_proxy https_proxy HTTP_PROXY HTTPS_PROXY ALL_PROXY all_proxy
export NO_PROXY='*'
export no_proxy='*'
export MODELSCOPE_DOMAIN='modelscope.cn'

log "=== run start: $MODEL -> $DEST (max_workers=$MAX_WORKERS) ==="
attempt=0
while [ "$attempt" -lt "$MAX_ATTEMPTS" ]; do
  attempt=$((attempt + 1))
  log "attempt $attempt/$MAX_ATTEMPTS: modelscope download $MODEL"
  env -u http_proxy -u https_proxy -u HTTP_PROXY -u HTTPS_PROXY \
    -u ALL_PROXY -u all_proxy \
    modelscope download --endpoint https://modelscope.cn \
      --max-workers "$MAX_WORKERS" \
      --model "$MODEL" --local_dir "$DEST" >>"$LOG" 2>&1
  rc=$?
  log "attempt $attempt finished rc=$rc"
  if [ "$rc" -eq 0 ]; then
    chmod -R a+rX "$DEST"
    touch "$DONE_MARKER"
    log "=== COMPLETE: $MODEL. marker written. ==="
    exit 0
  fi
  log "incomplete (rc=$rc); backing off 60s before retry."
  sleep 60
done

log "=== gave up after $MAX_ATTEMPTS attempts; will retry next scheduled run. ==="
exit 1
