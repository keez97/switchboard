#!/usr/bin/env bash
# presence, roles, links and messages between sessions
source "$(dirname "$0")/../lib.sh"
fx_repos alpha beta gamma

P1=$(fake S1 "$T/alpha" road); P2=$(fake S2 "$T/beta" impl); P3=$(fake S3 "$T/gamma" other)
for s in "S1 alpha" "S2 beta" "S3 gamma"; do set -- $s; hook SessionStart "$T/$2" $1 >/dev/null; done
"$B" who | has "to=uds:$T/sock.$P2" && ok "presence publishes the exact address from Claude's session file" || die "who has no address: $("$B" who)"
python3 -c "import time; time.sleep(0.2)" >/dev/null 2>&1 & DP=$!; wait $DP
python3 - "$DP" <<PY
import json,os,sys; json.dump({"pid":int(sys.argv[1]),"sessionId":"SD","cwd":"$T/alpha","name":"dead","procStart":"x","messagingSocketPath":"$T/nosock","peerProtocol":1},open(os.path.expanduser("~/.claude/sessions/%s.json"%sys.argv[1]),"w"))
PY
hook SessionStart "$T/alpha" SD >/dev/null; "$B" who | has dead && die "dead pid listed as live" || ok "a session whose process is gone is never offered as a recipient"
seat SF "$T/alpha" newformat 2; hook SessionStart "$T/alpha" SF >/dev/null
"$B" who | has newformat && die "unknown format trusted" || ok "unknown session-file format is ignored"
! grep -lq "session file" "$SWITCHBOARD_DIR"/events/*.json 2>/dev/null && ok "an unknown format raises no event" || die "format event"

SWITCHBOARD_SESSION_ID=S1 "$B" role roadmap >/dev/null; SWITCHBOARD_SESSION_ID=S2 "$B" role implementer >/dev/null
SWITCHBOARD_SESSION_ID=S3 "$B" role implementer 2>/dev/null | has "now holds" && true
LID=$(SWITCHBOARD_SESSION_ID=S1 "$B" link --from "$T/alpha:roadmap" --to "$T/beta:implementer" --scope "order the next work items" --cap 2 | awk 'NR==1{print $2}')
hook SessionStart "$T/gamma" sG7 | has "link $LID created" && ok "link creation is announced to every repo" || die "link not announced"
up "$T/beta" S2 "$(peer "$T/sock.$P1" road "next: build X")" | has "Robin authorised alpha:roadmap" && ok "direction over a link arrives with an authority header" || die "no authority header"
up "$T/alpha" S1 "$(peer "$T/sock.$P2" impl "X is done")" | has "report from your linked counterpart" && ok "the reverse direction is a report, not a direction" || die "reverse not a report"
up "$T/beta" S2 "$(peer "$T/sock.$P3" other "do Y")" | has "no link covers this sender" && ok "an unlinked sender is information only" || die "unlinked sender got authority"
for i in 1 2; do [ -z "$(send PreToolUse "$T/alpha" S1 "$T/sock.$P2" "next $i")" ] || die "linked send $i refused"; post "$T/alpha" S1 "$T/sock.$P2" "next $i" >/dev/null; done
send PreToolUse "$T/alpha" S1 "$T/sock.$P2" "next 3" | has "reached its cap of 2" && ok "the link's daily cap refuses the next message" || die "cap not enforced"
"$B" link-cap "$LID" 100 >/dev/null; [ -z "$(send PreToolUse "$T/alpha" S1 "$T/sock.$P2" "next 3")" ] && ok "raising the cap is one command" || die "cap raise failed"
[ "$(wc -l < "$SWITCHBOARD_DIR/links/$LID.log.jsonl")" -eq 2 ] && ok "every linked message is logged" || die "link log wrong"
for i in 1 2 3; do [ -z "$(send PreToolUse "$T/gamma" S3 "$T/sock.$P2" "hi $i")" ] || die "unlinked send $i refused"; post "$T/gamma" S3 "$T/sock.$P2" "hi $i" >/dev/null; done
send PreToolUse "$T/gamma" S3 "$T/sock.$P2" "hi 4" | has "no link covers the pair" && ok "outside a link the fourth message in 30 minutes is refused" || die "pair limit not enforced"
resid "$P2" S2b
out=$(python3 -c "import json; print(json.dumps({'hook_event_name':'SessionStart','source':'clear','cwd':'$T/beta','session_id':'S2b'}))" | "$B" hook)
echo "$out" | has "holds role implementer in link $LID" && echo "$out" | has "next 2" && ok "a cleared session keeps its role and gets the link, scope and last exchanges back" || die "clear lost the role: $out"
[ -z "$(send PreToolUse "$T/alpha" S1 "$T/sock.$P2" "after clear")" ] && "$B" who --role implementer | has "to=uds:$T/sock.$P2" && ok "the counterpart still reaches it at the same address" || die "address lost after clear"

hook PostToolUse "$T/gamma" S3 Edit "{\"file_path\":\"$T/beta/lib.py\"}" | has "to: \\\\\"uds:$T/sock.$P2" && ok "a cross-boundary write tells the writer exactly whom to message" || die "no obligation"
[ -z "$(hook PostToolUse "$T/gamma" S3 Edit "{\"file_path\":\"$T/beta/lib2.py\"}" | grep "Message it now")" ] && ok "a burst of writes wakes the other session once" || die "second wake issued"
hook Stop "$T/gamma" S3 | has '"decision": "block"' && ok "ending the turn without sending gets one reminder" || die "no reminder"
[ -z "$(hook Stop "$T/gamma" S3)" ] && ok "the reminder is not repeated" || die "reminder repeated"

python3 -c "import json; print(json.dumps({'hook_event_name':'SessionEnd','reason':'exit','cwd':'$T/alpha','session_id':'S1'}))" | "$B" hook
"$B" who --role roadmap | has "no live session" && ok "a closed session vacates its role" || die "role still held after close"
seat S4 "$T/alpha" fresh; hook SessionStart "$T/alpha" S4 | has "open end roadmap" && ok "the next session in that repo is offered the open end" || die "open end not offered"

finish
