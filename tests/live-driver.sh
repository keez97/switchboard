#!/usr/bin/env bash
# drv.sh start <name> <dir> | say <name> <text> | last <name>
S="$(cd "$(dirname "$0")" && pwd)"; n="$2"
case "$1" in
 start) mkdir -p "$S/$n"; rm -f "$S/$n/in" "$S/$n/out.jsonl"; mkfifo "$S/$n/in"; cd "$3" || exit 1
   ( python3 -c "import time; time.sleep(5400)" > "$S/$n/in" ) >/dev/null 2>&1 & echo $! > "$S/$n/holder.pid"
   ( claude -p --input-format stream-json --output-format stream-json --verbose < "$S/$n/in" > "$S/$n/out.jsonl" 2>"$S/$n/err.log" ) >/dev/null 2>&1 & echo $! > "$S/$n/claude.pid" ;;
 say) python3 -c "import json,sys; print(json.dumps({'type':'user','message':{'role':'user','content':sys.argv[1]}}))" "$3" > "$S/$n/in" ;;
 last) python3 - "$S/$n/out.jsonl" <<'PY'
import json,sys
res=[json.loads(l) for l in open(sys.argv[1]) if l.startswith('{"') and '"type":"result"' in l]
for r in res[-int(sys.argv[2]) if len(sys.argv)>2 else -1:]: print("RESULT:", (r.get("result") or "")[:900]); print("---")
print("turns so far:", len(res))
PY
 ;;
esac
