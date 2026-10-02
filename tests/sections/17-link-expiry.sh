#!/usr/bin/env bash
# links end by themselves
source "$(dirname "$0")/../lib.sh"
fx_delta; fx_repos gamma   # S5 in delta directs ends in gamma

NOW=$(date +%s)
L4=$(SWITCHBOARD_SESSION_ID=S5 "$B" link --from "$T/delta:lead" --to "$T/gamma:builder" --scope "expiry test" | awk 'NR==1{print $2}')
u=$(jq -r .until "$SWITCHBOARD_DIR/links/$L4.json"); [ "$u" -gt $((NOW + 7*86400 - 120)) ] && [ "$u" -lt $((NOW + 7*86400 + 120)) ] && ok "a link without --until ends after 7 days" || die "default until: $u"
jq ".until = $((NOW - 1))" "$SWITCHBOARD_DIR/links/$L4.json" > "$T/l4" && mv "$T/l4" "$SWITCHBOARD_DIR/links/$L4.json"
L5=$(SWITCHBOARD_SESSION_ID=S5 "$B" link --from "$T/delta:lead" --to "$T/gamma:builder" --scope "idle test" --until 30d | awk 'NR==1{print $2}')
jq ".created = $((NOW - 4*86400))" "$SWITCHBOARD_DIR/links/$L5.json" > "$T/l5" && mv "$T/l5" "$SWITCHBOARD_DIR/links/$L5.json"
L6=$(SWITCHBOARD_SESSION_ID=S5 "$B" link --from "$T/delta:lead" --to "$T/gamma:builder" --scope "active test" --until 30d | awk 'NR==1{print $2}')
jq ".created = $((NOW - 4*86400))" "$SWITCHBOARD_DIR/links/$L6.json" > "$T/l6" && mv "$T/l6" "$SWITCHBOARD_DIR/links/$L6.json"
echo "{\"ts\": $((NOW - 86400)), \"msg_id\": \"m-l6\", \"text\": \"still talking\"}" >> "$SWITCHBOARD_DIR/links/$L6.log.jsonl"
# D10: task requests and their transitions between a link's ends are activity; other ends keep L5 idle
L7=$(SWITCHBOARD_SESSION_ID=S5 "$B" link --from "$T/delta:lead" --to "$T/gamma:taskee" --scope "task activity test" --until 30d --to-session open | awk 'NR==1{print $2}')
L8=$(SWITCHBOARD_SESSION_ID=S5 "$B" link --from "$T/delta:lead" --to "$T/gamma:oldtask" --scope "old task test" --until 30d --to-session open | awk 'NR==1{print $2}')
for l in $L7 $L8; do jq ".created = $((NOW - 4*86400))" "$SWITCHBOARD_DIR/links/$l.json" > "$T/lx" && mv "$T/lx" "$SWITCHBOARD_DIR/links/$l.json"; done
T7=$(SWITCHBOARD_NOW=$((NOW - 5*86400)) SWITCHBOARD_SESSION_ID=S5 "$B" task request --to "$T/gamma:taskee" --subject "t7" --key l7 --no-sign | awk '{print $1}')
(cd "$T/gamma" && SWITCHBOARD_NOW=$((NOW - 86400)) "$B" task working "$T7" >/dev/null)
SWITCHBOARD_NOW=$((NOW - 4*86400 - 60)) SWITCHBOARD_SESSION_ID=S5 "$B" task request --to "$T/gamma:oldtask" --subject "t8" --key l8 --no-sign >/dev/null
hook UserPromptSubmit "$T/delta" S5 >/dev/null   # a publish reaps links at the real time; the requests above ran on a clock set back
hook PostToolUse "$T/delta" S5 Read '{}' >/dev/null
jq -r .closed_reason "$SWITCHBOARD_DIR/links/$L4.json" | has "^expired" && ok "an expired link is closed by the machine that created it" || die "L4 not closed: $(cat "$SWITCHBOARD_DIR/links/$L4.json")"
[ "$(jq -r .closed_reason "$SWITCHBOARD_DIR/links/$L5.json")" = "idle for 3 days" ] && ok "a link with no message for 3 days is closed as idle" || die "L5 not closed"
[ "$(jq -r '.revoked // 0' "$SWITCHBOARD_DIR/links/$L6.json")" = 0 ] && ok "a link with a message yesterday stays open" || die "L6 closed"
[ "$(jq -r '.revoked // 0' "$SWITCHBOARD_DIR/links/$L7.json")" = 0 ] && [ "$(jq -r .closed_reason "$SWITCHBOARD_DIR/links/$L8.json")" = "idle for 3 days" ] && ok "a link whose only use is tasks stays open while a transition between its ends is recent, and closes when the task is 4 days old" || die "task activity: L7 $(jq -c '{revoked,closed_reason}' "$SWITCHBOARD_DIR/links/$L7.json") L8 $(jq -c '{revoked,closed_reason}' "$SWITCHBOARD_DIR/links/$L8.json")"
"$B" links | grep "^$L7 " | has "last activity 1d ago$" && "$B" links | grep "^$L6 " | has "last activity 1d ago$" && ok "board links shows each link's last activity" || die "links activity: $("$B" links | grep -e "^$L7 " -e "^$L6 ")"
grep -l "link $L4 closed: expired" "$SWITCHBOARD_DIR"/events/*.json >/dev/null && grep -l "link $L5 closed: idle" "$SWITCHBOARD_DIR"/events/*.json >/dev/null && ok "both closings are announced to every repo" || die "closing events missing"
SWITCHBOARD_MACHINE=west hook PostToolUse "$T/delta" S5 Read '{}' >/dev/null 2>&1 || true
[ "$(jq -r '.revoked // 0' "$SWITCHBOARD_DIR/links/$L6.json")" = 0 ] && ok "another machine never closes a link it did not create" || die "L6 closed by west"
"$B" unlink "$L6" --reason "scope done" >/dev/null
[ "$(jq -r .closed_reason "$SWITCHBOARD_DIR/links/$L6.json")" = "ended by Robin's terminal: scope done" ] && [ "$(jq -r .closed_by "$SWITCHBOARD_DIR/links/$L6.json")" = terminal ] && ok "unlink records its reason and who closed it" || die "unlink reason: $(jq -c '{closed_reason,closed_by}' "$SWITCHBOARD_DIR/links/$L6.json")"

finish
