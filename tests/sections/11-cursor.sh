#!/usr/bin/env bash
# cursor: seen per address and machine
source "$(dirname "$0")/../lib.sh"
fx_delta_eps; fx_repos zeta; fx_holder SE2b   # SE2b holds eps:builder
seat SE3 "$T/eps" "eps third"; hook SessionStart "$T/eps" SE3 >/dev/null; SWITCHBOARD_SESSION_ID=SE3 "$B" role reviewer >/dev/null
M3=$(SWITCHBOARD_SESSION_ID=S5 "$B" task request --to "$T/zeta:builder" --subject "unrelated" --key m3 | awk '{print $1}')
T2=$(SWITCHBOARD_SESSION_ID=S5 "$B" task request --to "$T/eps:builder" --subject "second" --key k9 | awk '{print $1}'); SWITCHBOARD_SESSION_ID=SE2b "$B" task working "$T2" >/dev/null
T0=$(SWITCHBOARD_SESSION_ID=S5 "$B" task request --to "$T/eps:builder" --subject "first" --key k0 | awk '{print $1}')
hook PostToolUse "$T/eps" SE2b Read '{}' | has "a task for you.*$T0" || die "setup: the holder was not notified, so there is no cursor"

CUR="$SWITCHBOARD_DIR/tasks/eps--builder/cursor-east.json"; cur(){ python3 -c "import json,sys; c=json.load(open(sys.argv[1])); print(c['machine'], c['seen'].get(sys.argv[2],0), c['polled'], ' '.join(sorted(c['seen'])))" "$CUR" "${1:-x}"; }
out=$("$B" tasks --for "$T/zeta:builder"); echo "$out" | has -x "worker last polled never" && echo "$out" | has "^$M3 .*  unseen$" && "$B" task "$M3" | has -x "  unseen" && ok "an address with no cursor says never polled, and its submitted task is marked unseen" || die "no cursor: $out"
N0=$(SWITCHBOARD_SESSION_ID=S5 "$B" task request --to "$T/eps:builder" --subject "to be seen" --key c0 | awk '{print $1}'); h=$(shasum "$CUR")
out=$(SWITCHBOARD_SESSION_ID=S5 "$B" task seen "$N0" 2>&1) && die "non-worker marked seen" || true
echo "$out" | has "needs a session in that repo" && [ "$(shasum "$CUR")" = "$h" ] && "$B" tasks --for "$T/eps:builder" | has "^$N0 .*  unseen$" && ok "a session that does not hold the worker address cannot mark seen" || die "seen worker check: $out"
SWITCHBOARD_SESSION_ID=SE2b "$B" task seen "$N0" | has -x "$N0 seen by east" && cur "$N0" | has "^east [1-9][0-9]* [1-9][0-9]* .*$N0" && ok "board task seen writes this machine's cursor with the task and a polled stamp" || die "seen: $(cat "$CUR")"
h=$(shasum "$CUR"); SWITCHBOARD_SESSION_ID=SE2b "$B" task seen "$N0" | has "already seen by east; nothing written" && [ "$(shasum "$CUR")" = "$h" ] && ok "a second seen within the hour is a no-op" || die "second seen wrote"
s0=$(cur "$N0" | awk '{print $2}'); SWITCHBOARD_NOW=$(( $(date +%s) + 3700 )) SWITCHBOARD_SESSION_ID=SE2b "$B" task seen "$N0" >/dev/null
[ "$(cur "$N0" | awk '{print $2}')" = "$s0" ] && [ "$(cur "$N0" | awk '{print $3}')" -gt $(( $(date +%s) + 3000 )) ] && ok "after an hour a repeated seen refreshes polled and keeps the first seen time" || die "hourly polled: $(cat "$CUR")"
out=$("$B" tasks --for "$T/eps:builder"); "$B" task "$N0" | has "^  seen east [0-9][0-9]:[0-9][0-9]$" && ! echo "$out" | has "^$N0 .*unseen" && ! echo "$out" | has "^$T2 .*unseen" && echo "$out" | has -x "worker last polled 0m ago on east" && ok "seen shows in board task and board tasks, and --for says when the worker last polled" || die "seen display: $out"
N2=$(SWITCHBOARD_SESSION_ID=S5 "$B" task request --to "$T/eps:builder" --subject "script seen" --key c2 | awk '{print $1}')
(cd "$T/eps" && "$B" task seen "$N2") | has -x "$N2 seen by east" && ok "a script with no session inside the worker repo marks seen" || die "script seen"
N1=$(SWITCHBOARD_SESSION_ID=S5 "$B" task request --to "$T/eps:builder" --subject "hooked" --key h1 | awk '{print $1}')
hook PostToolUse "$T/eps" SE3 Read '{}' | has "task $N1 requested" && ! cur | has "$N1" && hook PostToolUse "$T/eps" SE2b Read '{}' | has "task $N1 requested" && ! cur | has "$N1" && jq -e ".notified[\"$N1\"]" "$CUR" >/dev/null && "$B" task "$N1" | has "^  notified east [0-9:]*; unseen$" && ok "the request event reaching the address holder marks it notified, not seen, and another session in the repo marks nothing" || die "hook seen: $(cat "$CUR")"

finish
