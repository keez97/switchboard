#!/usr/bin/env bash
# mid-turn sync: a prompt or tool call starts the sync job at most once per interval, so a note pushed from the
# other machine reaches a session with no Stop in between (one event later: the job pulls, the next event reads it)
source "$(dirname "$0")/../lib.sh"
mkrepo "$T/alpha"
git init -q --bare -b main "$T/two.git"; git clone -q "$T/two.git" "$T/seed" 2>/dev/null
( cd "$T/seed" && echo '*.jsonl merge=union' > .gitattributes && git add -A && git -c user.email=t@t -c user.name=t commit -qm seed && git push -q origin HEAD:main )
for m in east west; do git clone -q "$T/two.git" "$T/clone-$m"; git -C "$T/clone-$m" config user.email t@t; git -C "$T/clone-$m" config user.name "$m"; done
on(){ local m=$1; shift; SWITCHBOARD_DIR="${BD:-$T/clone-$m}" SWITCHBOARD_STATE="${ST:-$T/state-$m}" SWITCHBOARD_MACHINE="$m" SWITCHBOARD_NOSYNC='' "$@"; }   # run a command as that machine
tool(){ on "$1" pre PostToolUse "$T/alpha" S1 "$2" Read '{}'; }   # machine tool_use_id: S1 ran a Read in alpha
nap(){ python3 -c "import time; time.sleep($1)"; }
jobdone(){ # state dir: a job wrote sync.ok and released its lock (sync.ok is written first)
  local n=0; until { [ -s "$1/sync.ok" ] && ! held "$1/sync-job.lock"; } || [ $n -gt 40 ]; do nap 0.25; n=$((n+1)); done; }
idle(){ local n=0; while held "$1/sync-job.lock" && [ $n -lt 40 ]; do nap 0.25; n=$((n+1)); done; }
mtime(){ python3 -c "import os,sys; p=sys.argv[1]; print(os.stat(p).st_mtime_ns if os.path.exists(p) else 'none')" "$1"; }   # no raise: the crash log counts it
age(){ python3 -c "import os,sys,time; t=time.time()-int(sys.argv[2]); os.utime(sys.argv[1],(t,t))" "$1" "$2"; }   # file seconds: set its mtime that far back
ev(){ # tag: west writes an event for every repo and pushes it with its own sync
  python3 - "$T/clone-west" "$1" <<'PY'
import json,os,sys,time; d,tag=sys.argv[1:3]; t=int(time.time()); os.makedirs(d+"/events",exist_ok=True)
json.dump({"id":"%s-west-%s"%(time.strftime("%Y%m%dT%H%M%S"),tag),"ts":t,"machine":"west","kind":"test","target":"x",
           "summary":"pushed from west "+tag,"affects":["all"],"expires":t+3600,"ns":time.time_ns(),"observer":{}},
          open("%s/events/e-west-%s.json"%(d,tag),"w"))
PY
  rm -f "$T/state-west/sync.ok"; on west "$B" sync; jobdone "$T/state-west"
  git -C "$T/two.git" log --oneline -1 -- "events/e-west-$1.json" | has . || die "setup: event $1 not pushed from west"; }
SM="$T/state-east"; seat S1 "$T/alpha" road
on east "$B" register "$T/alpha" >/dev/null; on east sstart "$T/alpha" S1 >/dev/null; jobdone "$SM"
[ -s "$SM/sync.ok" ] || die "setup: SessionStart on east did not sync"

ev r1; rm -f "$SM/sync.ok"
o1=$(SWITCHBOARD_PULL_EVERY=0 tool east t1 | ctx); jobdone "$SM"; o2=$(tool east t2 | ctx)
! echo "$o1" | has "pushed from west r1" && echo "$o2" | has "pushed from west r1" && [ -s "$SM/sync.ok" ] \
  && ok "a PostToolUse past the interval starts the sync job and the next PostToolUse carries the event west pushed, no Stop between" \
  || die "mid-turn pull: first [$o1] next [$o2] sync.ok $(cat "$SM/sync.ok" 2>/dev/null)"
ev r2; rm -f "$SM/sync.ok"
SWITCHBOARD_PULL_EVERY=0 on east up "$T/alpha" S1 "go on" >/dev/null; jobdone "$SM"
[ -s "$SM/sync.ok" ] && tool east t3 | ctx | has "pushed from west r2" && ok "a UserPromptSubmit past the interval starts it too" || die "prompt pull: $(cat "$SM/sync.ok" 2>/dev/null)"
ev r3; rm -f "$SM/sync.ok"
AID=a1 SWITCHBOARD_PULL_EVERY=0 on east pre PostToolUse "$T/alpha" S1 t4 Read '{}' >/dev/null; jobdone "$SM"
[ -s "$SM/sync.ok" ] && tool east t5 | ctx | has "pushed from west r3" && ok "a subagent's PostToolUse starts it too: the stamp is per machine" || die "subagent pull: $(cat "$SM/sync.ok" 2>/dev/null)"

idle "$SM"; s0=$(mtime "$SM/pull.stamp"); rm -f "$SM/sync.ok"
tool east t6 >/dev/null; nap 2
[ "$s0" != none ] && [ "$(mtime "$SM/pull.stamp")" = "$s0" ] && [ ! -e "$SM/sync.ok" ] && ! held "$SM/sync-job.lock" \
  && ok "within the interval a PostToolUse starts no job: stamp unchanged, no sync.ok" || die "within interval: stamp $s0 -> $(mtime "$SM/pull.stamp"), sync.ok $(cat "$SM/sync.ok" 2>/dev/null)"

rm -f "$SM/pull.stamp"
SWITCHBOARD_DIR="$T/clone-east" SWITCHBOARD_STATE="$SM" SWITCHBOARD_MACHINE=east SWITCHBOARD_NOSYNC=1 SWITCHBOARD_PULL_EVERY=0 pre PostToolUse "$T/alpha" S1 t7 Read '{}' >/dev/null; nap 2
mkdir -p "$T/plain/events"; BD="$T/plain" ST="$T/state-plain" SWITCHBOARD_PULL_EVERY=0 tool east t8 >/dev/null; nap 2
[ ! -e "$SM/pull.stamp" ] && [ ! -e "$SM/sync.ok" ] && [ ! -e "$T/state-plain/pull.stamp" ] && [ ! -e "$T/state-plain/sync.ok" ] \
  && ! grep -qs pull_due "$SM/errors.log" "$T/state-plain/errors.log" \
  && ok "SWITCHBOARD_NOSYNC, or a board with no .git, starts nothing and writes no stamp" || die "nosync/no git: $(ls "$SM" "$T/state-plain" 2>&1 | tr '\n' ' ')"

hold "$SM/sync-job.lock" 6   # a live job's lock
SWITCHBOARD_PULL_EVERY=0 tool east t9 >/dev/null; nap 2
[ -f "$SM/pull.stamp" ] && [ ! -e "$SM/sync.ok" ] && kill -0 "$HOLDER" 2>/dev/null \
  && ok "a lock held by a live job means no second job, and the stamp still moves on" || die "live lock: stamp $(mtime "$SM/pull.stamp") sync.ok $(cat "$SM/sync.ok" 2>/dev/null)"
kill "$HOLDER"; wait "$HOLDER" 2>/dev/null || true   # the holder dies: the kernel drops its lock, the file stays
SWITCHBOARD_PULL_EVERY=0 tool east t10 >/dev/null; jobdone "$SM"
[ -s "$SM/sync.ok" ] && [ -f "$SM/sync-job.lock" ] && ! held "$SM/sync-job.lock" && ok "a lock file left by a dead job is no lock: the next job runs" || die "dead lock: sync.ok $(cat "$SM/sync.ok" 2>/dev/null)"

if [ "$(id -u)" = 0 ]; then ok "skipped: root writes any dir"; else
  RO="$T/state-ro"; mkdir -p "$RO" "$T/tmp"; chmod 500 "$RO"; FB="$T/tmp/switchboard-$(id -u)/errors.log"
  a=$(TMPDIR="$T/tmp" ST="$RO" SWITCHBOARD_PULL_EVERY=0 tool east t11 2>"$T/err-ro"; echo "rc=$?")
  b=$(TMPDIR="$T/tmp2" ST="$RO" SWITCHBOARD_PULL_EVERY=0 SWITCHBOARD_DIR="$T/clone-east" SWITCHBOARD_STATE="$RO" SWITCHBOARD_MACHINE=east SWITCHBOARD_NOSYNC=1 pre PostToolUse "$T/alpha" S1 t12 Read '{}' 2>/dev/null; echo "rc=$?")
  nap 1; chmod 700 "$RO"
  [ "$a" = "$b" ] && echo "$a" | has "rc=0" && grep -q "pull_due.*PermissionError" "$T/err-ro" && grep -q "pull_due.*PermissionError" "$FB" \
    && [ ! -e "$RO/pull.stamp" ] && [ ! -e "$RO/sync.ok" ] \
    && ok "an unwritable state dir: the failure is logged with pull_due, the hook exits 0 and its output is unchanged" || die "unwritable: [$a] vs [$b] / $(cat "$T/err-ro") / $(cat "$FB" 2>/dev/null)"
fi

idle "$SM"; rm -f "$SM/sync.ok"; touch "$SM/pull.stamp"; age "$SM/pull.stamp" 30; s0=$(mtime "$SM/pull.stamp")
( unset SWITCHBOARD_ALLOW_TMP; SWITCHBOARD_PULL_EVERY=0 tool east t13 >/dev/null ); nap 2; s1=$(mtime "$SM/pull.stamp"); k1=$([ -e "$SM/sync.ok" ] && echo job || echo none)
SWITCHBOARD_PULL_EVERY=0 tool east t14 >/dev/null; jobdone "$SM"
[ "$s1" = "$s0" ] && [ "$k1" = none ] && [ "$(mtime "$SM/pull.stamp")" != "$s0" ] && [ -s "$SM/sync.ok" ] \
  && ok "SWITCHBOARD_PULL_EVERY is ignored without SWITCHBOARD_ALLOW_TMP (a 30 s old stamp is not due) and honoured with it" \
  || die "override: without ALLOW_TMP stamp $s0 -> $s1, $k1; with it $(mtime "$SM/pull.stamp") sync.ok $(cat "$SM/sync.ok" 2>/dev/null)"

# SessionStart's own pull: a bounded fetch in its own process group, then a fast-forward only
procs(){ ps -A -o args= | awk -v s="$1" 'index($0, s) && !/awk/'; }   # running commands that name s
ffs(){ git -C "$T/clone-east" reflog | grep -cE "merge refs/remotes/origin/main: Fast-forward" || true; }   # SessionStart's merge, by its ref
SLOW="$T/slow-pack"; printf '#!/bin/sh\n# the first fetch through here hangs 10 s, the later ones go straight through\nmkdir "%s/slow.once" 2>/dev/null && sleep 10\nexec git upload-pack "$@"\n' "$T" > "$SLOW"; chmod +x "$SLOW"
idle "$SM"; ev r4; git -C "$T/clone-east" config remote.origin.uploadpack "$SLOW"; rm -f "$SM/sync.ok"
t0=$(date +%s); on east sstart "$T/alpha" S1 >/dev/null; t1=$(date +%s); jobdone "$SM"; left=$(procs "$SLOW")
git -C "$T/clone-east" config --unset remote.origin.uploadpack
[ -d "$T/slow.once" ] && [ $((t1 - t0)) -lt 8 ] && [ -z "$left" ] && [ -s "$SM/sync.ok" ] \
  && ok "a remote that hangs: SessionStart returns in $((t1 - t0)) s and its timed-out fetch leaves no git process behind" \
  || die "slow remote: SessionStart took $((t1 - t0)) s, left running: [$left], sync.ok $(cat "$SM/sync.ok" 2>/dev/null)"
idle "$SM"; ev r5; f0=$(ffs); rm -f "$SM/sync.ok"
o5=$(on east sstart "$T/alpha" S1 | ctx); jobdone "$SM"
echo "$o5" | has "pushed from west r5" && [ "$(ffs)" -gt "$f0" ] \
  && ok "a fast remote and no local commits: SessionStart fast-forwards to the remote's records and shows them in the same call" \
  || die "fast-forward at SessionStart: [$o5] fast-forwards $f0 -> $(ffs)"
idle "$SM"; ev r6; M="$T/clone-east/events"
echo '{"id":"e-east-local"}' > "$M/e-east-local.json"; git -C "$T/clone-east" add events/e-east-local.json; git -C "$T/clone-east" commit -qm "local record"
echo '{"id":"e-east-dirty"}' > "$M/e-east-dirty.json"; f0=$(ffs); rm -f "$SM/sync.ok"
on east sstart "$T/alpha" S1 >/dev/null; f1=$(ffs); jobdone "$SM"
tree=$(git -C "$T/two.git" ls-tree -r main --name-only)
[ "$f1" = "$f0" ] && echo "$tree" | has "events/e-east-local.json" && echo "$tree" | has "events/e-east-dirty.json" && echo "$tree" | has "events/e-west-r6.json" \
  && [ -f "$M/e-west-r6.json" ] && [ ! -e "$T/clone-east/.git/rebase-merge" ] && [ ! -e "$T/clone-east/.git/rebase-apply" ] \
  && ok "an unpushed local commit and an uncommitted record: SessionStart leaves them to the job, which merges and pushes both" \
  || die "local commits: fast-forwards $f0 -> $f1, remote has: $(echo "$tree" | grep events/ | tr '\n' ' ')"

for s in "$SM" "$T/state-west" "$T/state-plain"; do idle "$s"; done   # no job may outlive the section's dir
! held "$SM/sync-job.lock" && ! held "$T/state-west/sync-job.lock" && [ -z "$(procs "$T/")" ] && ok "no sync job and no git process is left running" \
  || die "left running: [$(procs "$T/")]"

finish
