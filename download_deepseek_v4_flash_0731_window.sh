#!/usr/bin/env bash
# Download DeepSeek-V4.1-Flash only during the Beijing-time night window.
# Intended for a daily 22:00 Asia/Shanghai cron. If invoked manually, it also
# refuses daytime runs and computes the exact remaining time until 08:00.
set -u

export TZ='Asia/Shanghai'

HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
MODEL='deepseek-ai/DeepSeek-V4.1-Flash'
DEST='/srv/models/DeepSeek-V4.1-Flash'
WINDOW_LOG="$HERE/download-deepseek-ai_DeepSeek-V4.1-Flash-window.log"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S %Z')] $*" >>"$WINDOW_LOG"; }

hour=$(date +%H)
hour=$((10#$hour))
if [ "$hour" -ge 22 ]; then
  end_epoch=$(date -d 'tomorrow 08:00:00' +%s)
elif [ "$hour" -lt 8 ]; then
  end_epoch=$(date -d 'today 08:00:00' +%s)
else
  log 'outside allowed Beijing-time window (22:00-08:00); exiting.'
  exit 0
fi

now_epoch=$(date +%s)
remaining=$((end_epoch - now_epoch))
if [ "$remaining" -le 0 ]; then
  log 'no time remains before 08:00 CST; exiting.'
  exit 0
fi

log "starting $MODEL -> $DEST; hard stop at $(date -d "@$end_epoch" '+%Y-%m-%d %H:%M:%S %Z')"

# One worker plus low CPU/disk priority minimizes impact on other users.
# timeout ends the whole download at 08:00; ModelScope resumes partial files
# on the next nightly run. SIGKILL is only a fallback if TERM is ignored.
timeout --signal=TERM --kill-after=10s "${remaining}s" \
  nice -n 10 ionice -c 3 \
  env MODELSCOPE_MAX_WORKERS=1 \
  "$HERE/download_model.sh" "$MODEL" "$DEST"
rc=$?

if [ "$rc" -eq 124 ] || [ "$rc" -eq 137 ]; then
  log '08:00 CST window closed; downloader stopped, partial files retained for resume.'
  exit 0
fi

log "downloader exited rc=$rc"
exit "$rc"
