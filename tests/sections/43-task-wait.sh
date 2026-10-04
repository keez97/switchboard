#!/usr/bin/env bash
# task <tid> --wait: block until a task ends or reaches the --until state, writing nothing while it polls
source "$(dirname "$0")/../lib.sh"
fx_delta_eps

mk(){ SWITCHBOARD_SESSION_ID=S5 "$B" task request --to "$T/eps:builder" --subject "wait $1" --key "w$1" | awk '{print $1}'; }
wk(){ SWITCHBOARD_SESSION_ID=S6 "$B" task "$@"; }
snap(){ { find "$SWITCHBOARD_DIR" -type f -not -path '*/.git/*' | sort; find "$SWITCHBOARD_STATE" -name 'wait-*' | sort; } | cksum; }

T1=$(mk 1); wk working "$T1" >/dev/null; wk completed "$T1" --note "done early" >/dev/null
s=$(date +%s); out=$("$B" task "$T1" --wait --timeout 30) && rc=0 || rc=$?; e=$(( $(date +%s) - s ))
[ "$rc" = 0 ] && [ "$e" -lt 2 ] && [ "$out" = "$("$B" task "$T1")" ] && echo "$out" | has "^$T1  completed  wait 1" \
  && ok "a task already final returns at once with the output of task <tid>" || die "already final: rc $rc after ${e}s: $out"

T2=$(mk 2); wk working "$T2" >/dev/null
( sleep 3; wk completed "$T2" --note "finished while waited on" >/dev/null ) & echo $! >> "$T/pids"
out=$("$B" task "$T2" --wait) && rc=0 || rc=$?
[ "$rc" = 0 ] && [ "$(echo "$out" | head -1 | awk '{print $2}')" = completed ] && echo "$out" | has "002-completed.json .*finished while waited on" \
  && ok "it returns 0 with the status line when the worker completes the task during the wait" || die "completed during wait: rc $rc: $out"
wait

T3=$(mk 3)
( sleep 3; wk working "$T3" --note "started" >/dev/null ) & echo $! >> "$T/pids"
out=$("$B" task "$T3" --wait --until working --timeout 30) && rc=0 || rc=$?
[ "$rc" = 0 ] && [ "$(echo "$out" | head -1 | awk '{print $2}')" = working ] \
  && ok "--until working returns when the worker sets working, a state that is not final" || die "--until working: rc $rc: $out"
wait
wk completed "$T3" >/dev/null; "$B" task "$T3" --wait --until completed --timeout 5 | head -1 | has "^$T3  completed" \
  && ok "--until names a final state too" || die "--until completed"

T6=$(mk 6)
( sleep 2; wk rejected "$T6" --note "not mine" >/dev/null ) & echo $! >> "$T/pids"
s=$(date +%s); out=$("$B" task "$T6" --wait --until working --timeout 30 2>"$T/err") && rc=0 || rc=$?; e=$(( $(date +%s) - s ))
[ "$rc" = 1 ] && [ "$e" -lt 10 ] && [ "$(head -1 "$T/err")" = "switchboard: task $T6 ended rejected, not working" ] && echo "$out" | has "^$T6  rejected  wait 6" \
  && ok "--until working on a task the worker rejects stops at once: the task on stdout, one line on stderr, exit 1" || die "ended other state: rc $rc after ${e}s out [$out] err [$(cat "$T/err")]"
wait

T4=$(mk 4); before=$(snap)
s=$(date +%s); out=$("$B" task "$T4" --wait --timeout 3 2>"$T/err") && rc=0 || rc=$?; e=$(( $(date +%s) - s ))
[ "$rc" = 1 ] && [ -z "$out" ] && [ "$(cat "$T/err")" = "switchboard: task $T4 is still submitted after 3s" ] && [ "$e" -ge 3 ] && [ "$e" -lt 6 ] \
  && ok "a wait that times out prints one line on stderr, nothing on stdout, and exits 1 at the timeout" || die "timeout: rc $rc after ${e}s out [$out] err [$(cat "$T/err")]"
[ "$(snap)" = "$before" ] && ok "polling writes no file on the board and no claim file in the state dir" || die "polling changed files"

wk working "$T4" >/dev/null
"$B" task "$T4" --wait --until working --timeout 0 --json | python3 -c "import json,sys; j=json.load(sys.stdin); sys.exit(0 if j['state']=='working' and j['id']==sys.argv[1] else 1)" "$T4" \
  && ok "--wait --json prints the --json output at the end, and --timeout 0 returns when the state is already there" || die "wait --json"

T5=$(mk 5); "$B" task "$T5" --wait --timeout 0 >"$T/out" 2>&1 & W=$!; echo $W >> "$T/pids"; python3 -c "import time; time.sleep(1)"
kill -TERM $W; wait $W && rc=0 || rc=$?
[ "$rc" = 1 ] && [ ! -s "$T/out" ] && ok "SIGTERM ends a wait quietly with exit 1" || die "sigterm: rc $rc: $(cat "$T/out")"

out=$("$B" task t00000000 --wait 2>&1) && die "unknown task waited" || true
[ "$out" = "$("$B" task t00000000 2>&1 || true)" ] && echo "$out" | has "no task t00000000" && ok "an unknown task id fails as task <tid> does" || die "unknown tid: $out"
bad(){ local want=$1; shift; local o; o=$("$B" "$@" 2>&1) && { die "accepted: $*"; return; } || true; echo "$o" | has -F -- "$want" && return 0; die "$* gave: $o"; }
bad "--until and --timeout go with --wait" task "$T1" --until completed
bad "--until and --timeout go with --wait" task "$T1" --timeout 5
bad "--wait goes with" task working "$T4" --wait
bad "--wait goes with" task request --to "$T/eps:builder" --subject s --key e1 --wait
bad "--wait goes with" task cancel "$T4" --wait
bad "invalid choice" task "$T4" --wait --until submitted
bad "number of seconds" task "$T4" --wait --timeout -1
ok "--until and --timeout without --wait, --wait with a write verb, a bad state and a negative timeout are errors"

# a change another machine pushed: east waits, west records the transition, east's pull job brings it
git init -q --bare -b main "$T/two.git"; git clone -q "$T/two.git" "$T/seed" 2>/dev/null
( cd "$T/seed" && echo '*.jsonl merge=union' > .gitattributes && git add -A && git -c user.email=t@t -c user.name=t commit -qm seed && git push -q origin HEAD:main )
for m in east west; do git clone -q "$T/two.git" "$T/clone-$m"; git -C "$T/clone-$m" config user.email t@t; git -C "$T/clone-$m" config user.name "$m"; done
on(){ local m=$1; shift; SWITCHBOARD_DIR="$T/clone-$m" SWITCHBOARD_STATE="$T/state-$m" SWITCHBOARD_MACHINE="$m" SWITCHBOARD_NOSYNC='' "$@"; }
syncm(){ rm -f "$T/state-$1/sync.ok"; on "$1" "$B" sync; waitfor "$T/state-$1/sync.ok"; }
mkrepo "$T/wrk"; git -C "$T/wrk" remote add origin https://example.com/acme/wrk.git   # a remote gives both machines one repo id
for m in east west; do on $m "$B" register "$T/wrk" >/dev/null; done
TW=$(on east "$B" task request --to "$T/wrk:builder" --subject "from east" --key x1 --no-sign | awk '{print $1}'); syncm east; syncm west
[ -f "$T/clone-west"/tasks/*/"$TW"/000-request.json ] || die "setup: west has no task $TW"
( python3 -c "import time; time.sleep(1)"; cd "$T/wrk" && on west "$B" task completed "$TW" --note "done on west" >/dev/null ) & echo $! >> "$T/pids"
s=$(date +%s); out=$(SWITCHBOARD_PULL_EVERY=0 on east "$B" task "$TW" --wait --timeout 40 2>&1) && rc=0 || rc=$?; e=$(( $(date +%s) - s ))
[ "$rc" = 0 ] && echo "$out" | has "^$TW  completed  from east" && echo "$out" | has "done on west" \
  && ok "a transition recorded on another machine is picked up through pull_due while waiting (${e}s)" || die "two machines: rc $rc after ${e}s: $out"
wait

finish
