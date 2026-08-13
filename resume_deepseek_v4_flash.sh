#!/usr/bin/env bash
# Resume the partial ModelScope download of deepseek-ai/DeepSeek-V4-Flash.
# Idempotent: skips already-downloaded shards, retries on network failure,
# and self-noops once all 46 shards are present (writes .download_complete).
# Wired to cron nightly until complete; remove the cron line afterwards.
set -u

MODEL="deepseek-ai/DeepSeek-V4-Flash"
DEST="/data/models/DeepSeek-V4-Flash"
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
LOG="$HERE/download.log"            # timestamped events only — a few lines/run, bounded
PROGRESS="$HERE/download.progress.log"  # live modelscope/tqdm output — truncated each attempt
LOCK="$HERE/.download.lock"
DONE_MARKER="$DEST/.download_complete"
TOTAL_SHARDS=46
MAX_ATTEMPTS=20

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >>"$LOG"; }

# Single-instance: bail if a previous night's run is still going.
exec 9>"$LOCK"
if ! flock -n 9; then
  log "another instance is running; exiting."
  exit 0
fi

# Already finished on a prior run -> nothing to do (keeps cron a cheap no-op).
if [ -f "$DONE_MARKER" ]; then
  exit 0
fi

# Count fully-present, non-empty shards in the final dir.
count_done_shards() {
  local n=0 i f
  for i in $(seq -w 1 "$TOTAL_SHARDS"); do
    f="$DEST/model-000${i}-of-000${TOTAL_SHARDS}.safetensors"
    [ -s "$f" ] && n=$((n + 1))
  done
  echo "$n"
}

. "$HERE/.venv/bin/activate"
# modelscope.cn is domestic — direct is faster and more reliable than the
# overseas proxy (measured ~3x). Force-direct regardless of inherited env.
unset http_proxy https_proxy HTTP_PROXY HTTPS_PROXY ALL_PROXY all_proxy
export NO_PROXY='*'
export no_proxy='*'
export MODELSCOPE_DOMAIN='modelscope.cn'

log "=== run start: $(count_done_shards)/$TOTAL_SHARDS shards present ==="

attempt=0
while [ "$attempt" -lt "$MAX_ATTEMPTS" ]; do
  attempt=$((attempt + 1))
  log "attempt $attempt/$MAX_ATTEMPTS: modelscope download $MODEL (progress -> $PROGRESS)"
  # Stream modelscope/tqdm output through a rolling-snapshot writer so the
  # progress file is bounded *within* an attempt too (always ~last 40 lines),
  # not just truncated between attempts. PIPESTATUS[0] keeps modelscope's rc.
  : >"$PROGRESS"
  env -u http_proxy -u https_proxy -u HTTP_PROXY -u HTTPS_PROXY \
    -u ALL_PROXY -u all_proxy \
    modelscope download --endpoint https://modelscope.cn \
      --model "$MODEL" --local_dir "$DEST" 2>&1 \
    | python "$HERE/_progress_writer.py" "$PROGRESS"
  rc=${PIPESTATUS[0]}
  have=$(count_done_shards)
  log "attempt $attempt finished rc=$rc, shards=$have/$TOTAL_SHARDS"

  if [ "$rc" -eq 0 ] && [ "$have" -eq "$TOTAL_SHARDS" ]; then
    touch "$DONE_MARKER"
    log "=== COMPLETE: all $TOTAL_SHARDS shards present. marker written. ==="
    exit 0
  fi
  log "incomplete; backing off 60s before retry."
  sleep 60
done

log "=== gave up after $MAX_ATTEMPTS attempts; $(count_done_shards)/$TOTAL_SHARDS shards. will retry next scheduled run. ==="
exit 1
