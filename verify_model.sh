#!/usr/bin/env bash
# Verify a downloaded ModelScope model against the repo manifest.
#
# Usage:
#   verify_model.sh <model-id> [dest-dir] [--quick]
#
#   <model-id>   e.g. deepseek-ai/DeepSeek-V4-Flash
#   [dest-dir]   default: /data/models/<model-basename>
#   --quick      size-only check (fast); default also verifies sha256 (slow, reads every byte)
#
# Exit 0 = all files present, right size, (and sha256 match unless --quick).
# Exit 1 = something missing / wrong size / hash mismatch (details printed).
set -u

MODEL="${1:?usage: verify_model.sh <model-id> [dest-dir] [--quick]}"; shift
QUICK=0
DEST=""
for a in "$@"; do
  case "$a" in
    --quick) QUICK=1 ;;
    *) DEST="$a" ;;
  esac
done
DEST="${DEST:-/data/models/$(basename "$MODEL")}"
HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

. "$HERE/.venv/bin/activate"
unset http_proxy https_proxy HTTP_PROXY HTTPS_PROXY ALL_PROXY all_proxy
export NO_PROXY='*'
export no_proxy='*'
export MODELSCOPE_DOMAIN='modelscope.cn'

MODEL="$MODEL" DEST="$DEST" QUICK="$QUICK" python - <<'PY'
import os, sys, hashlib
from modelscope.hub.api import HubApi
MODEL=os.environ['MODEL']; DEST=os.environ['DEST']; QUICK=os.environ['QUICK']=='1'

def sha256(path):
    h=hashlib.sha256()
    with open(path,'rb') as fh:
        for b in iter(lambda: fh.read(8<<20), b''): h.update(b)
    return h.hexdigest()

api=HubApi()
files=[f for f in api.get_model_files(model_id=MODEL, recursive=True) if f.get('Type')!='tree']
print(f"verifying {len(files)} files in {DEST}  ({'size-only' if QUICK else 'size + sha256'})")
bad=[]
for i,f in enumerate(sorted(files,key=lambda x:x['Path']),1):
    p=f['Path']; exp=f.get('Size',-1); fp=os.path.join(DEST,p)
    if not os.path.isfile(fp):
        bad.append((p,'MISSING')); print(f"  [{i}/{len(files)}] MISSING  {p}"); continue
    sz=os.path.getsize(fp)
    if sz!=exp:
        bad.append((p,f'SIZE {sz}!={exp}')); print(f"  [{i}/{len(files)}] SIZE✗   {p} ({sz} != {exp})"); continue
    if QUICK:
        continue
    got=sha256(fp); ok = got==f.get('Sha256')
    print(f"  [{i}/{len(files)}] {'OK   ' if ok else 'HASH✗'}  {p}")
    if not ok: bad.append((p,'SHA256 mismatch'))

print("-"*50)
if bad:
    print(f"FAIL: {len(bad)} problem(s):")
    for p,why in bad: print(f"  - {p}: {why}")
    sys.exit(1)
print(f"OK: all {len(files)} files present and verified.")
PY
