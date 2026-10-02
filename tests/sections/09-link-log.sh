#!/usr/bin/env bash
# link log ids
source "$(dirname "$0")/../lib.sh"
fx_delta; mkrepo "$T/theta"
# shellcheck disable=SC2034  # THETA is read by lib.sh's remote()
THETA=$("$B" register "$T/theta" | tail -1 | awk '{print $NF}')
remote R2 "theta @runner" 60   # S5 directs a session on the other machine through link "remote test"
SWITCHBOARD_SESSION_ID=S5 "$B" link --from "$T/delta:lead" --to "$T/theta:runner" --scope "remote test" --to-session bridge:session_R2 >/dev/null || die "setup: remote link"

python3 - "$T/delta" "bridge:session_R2" <<'PY' | "$B" hook >/dev/null
import json,sys; print(json.dumps({"hook_event_name":"PostToolUse","cwd":sys.argv[1],"session_id":"S5","tool_name":"SendMessage","tool_input":{"to":sys.argv[2],"message":"run it"},"tool_response":{"success":True,"msg_id":"aaaaaaaa-1111-2222-3333-444444444444"}}))
PY
LR=$(ls -t "$SWITCHBOARD_DIR"/links/*.log.jsonl | head -1)
tail -1 "$LR" | python3 -c "import json,sys; e=json.loads(sys.stdin.read()); sys.exit(0 if (e['msg_id'],e['from_session'],e['to_session'],e['to_machine'])==('aaaaaaaa-1111-2222-3333-444444444444','S5','R2','west') else 1)" && ok "a logged send carries msg_id, both session ids and the recipient's machine" || die "log ids missing: $(tail -1 "$LR")"
before=$("$B" links | grep "remote test" | sed 's/.*today \([0-9]*\).*/\1/')
echo "{\"dir\": \"down\", \"from\": \"lead\", \"line\": \"old format\", \"machine\": \"east\", \"to\": \"runner\", \"ts\": $(date +%s)}" >> "$LR"
[ "$("$B" links | grep "remote test" | sed 's/.*today \([0-9]*\).*/\1/')" -eq $((before+1)) ] && ok "a log with old-format lines still counts correctly" || die "old-format line broke the count"

finish
