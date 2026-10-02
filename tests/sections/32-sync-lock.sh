#!/usr/bin/env bash
# the tree lock: a record written while a sync job commits and rebases the clone waits for it and is kept, a stuck
# rebase is recovered with its autostash kept, and one sync job runs at a time
source "$(dirname "$0")/../lib.sh"
mkrepo "$T/alpha"
git init -q --bare -b main "$T/R.git"; git clone -q "$T/R.git" "$T/P" 2>/dev/null; git -C "$T/P" config user.email t@t; git -C "$T/P" config user.name p
pc(){ git -C "$T/P" add -A && git -C "$T/P" commit -qm "$1" && { git -C "$T/P" pull -q --rebase origin main 2>/dev/null || true; } \
  && git -C "$T/P" push -q origin HEAD:main; }   # the peer commits and pushes
mkdir -p "$T/P/tasks" "$T/P/events"; echo '{"v":1}' > "$T/P/tasks/t.json"; echo '{}' > "$T/P/events/seed.json"; pc seed
git clone -q "$T/R.git" "$T/A"; git -C "$T/A" config user.email t@t; git -C "$T/A" config user.name a
A="$T/A"; SA="$T/st-A"; mkdir -p "$SA"
on(){ SWITCHBOARD_DIR="$A" SWITCHBOARD_STATE="$SA" SWITCHBOARD_NOSYNC='' "$@"; }   # run a command on clone A
nap(){ python3 -c "import time; time.sleep($1)"; }
jobdone(){ local n=0; until { [ -s "$SA/sync.ok" ] || [ -s "$SA/sync.fail" ]; } && ! held "$SA/sync-job.lock" || [ $n -gt 80 ]; do nap 0.25; n=$((n+1)); done; }
v(){ python3 -c "import json,sys; print(json.load(sys.stdin)['v'])" 2>/dev/null || true; }   # the v of a record on stdin
rv(){ git -C "$T/R.git" show main:tasks/t.json 2>/dev/null | v; }   # the v of tasks/t.json on the remote
procs(){ ps -A -o args= | awk -v s="$1" 'index($0, s) && !/awk/'; }
aged(){ python3 -c "import os,sys,time; t=time.time()-300; [os.utime(p,(t,t)) for p in sys.argv[1:]]" "$@"; }   # files: 5 minutes old

# P0-1: a record written through the board while the job rebases waits for the rebase, then lands, then goes out
echo '{}' > "$T/P/events/peer.json"; pc peer
echo '{"v":2}' > "$A/tasks/t.json"
cat > "$T/w.py" <<'PY'
import importlib.machinery, importlib.util, sys
ld = importlib.machinery.SourceFileLoader("board", sys.argv[1])
b = importlib.util.module_from_spec(importlib.util.spec_from_loader("board", ld)); ld.exec_module(b)
b.save(b.BOARD / "tasks" / "t.json", {"v": 3})
open(sys.argv[2], "w").write("1")
PY
# git runs post-checkout inside the rebase: the hook starts a board write, which runs alongside, and keeps the rebase
# going a second longer so the write is attempted while the rebase still runs
printf '#!/bin/sh\nmkdir "%s/once" 2>/dev/null || exit 0\npython3 "%s/w.py" "%s" "%s/wrote" </dev/null >/dev/null 2>&1 &\nsleep 1\n' "$T" "$T" "$B" "$T" > "$A/.git/hooks/post-checkout"
chmod +x "$A/.git/hooks/post-checkout"
on "$B" sync-job; waitfor "$T/wrote"
t1=$(v < "$A/tasks/t.json"); r1=$(rv)
rm -f "$SA/sync.ok"; on "$B" sync-job; r2=$(rv)
[ -d "$T/once" ] && [ "$t1" = 3 ] && [ "$r1" = 2 ] && [ "$r2" = 3 ] && [ -s "$SA/sync.ok" ] && [ ! -e "$SA/sync.fail" ] \
  && ! grep -qs "tree lock" "$SA/errors.log" \
  && ok "a record written through the board during the job's rebase waits for it: the tree keeps it and the next sync pushes it" \
  || die "write during rebase: hook ran $([ -d "$T/once" ] && echo yes || echo no), tree v$t1, remote v$r1 then v$r2, fail [$(cat "$SA/sync.fail" 2>/dev/null)] log [$(cat "$SA/errors.log" 2>/dev/null)]"
rm -f "$A/.git/hooks/post-checkout"

# P0-2: a rebase dir git left holding only its autostash: the next job keeps the autostash, removes the dir, syncs
echo note > "$A/notes.txt"; git -C "$A" add notes.txt; git -C "$A" commit -qm notes
echo "a local change" >> "$A/notes.txt"; S=$(git -C "$A" stash create); git -C "$A" checkout -q -- notes.txt
mkdir "$A/.git/rebase-merge"; echo "$S" > "$A/.git/rebase-merge/autostash"
echo '{}' > "$T/P/events/peer2.json"; pc peer2; echo '{"v":4}' > "$A/tasks/t.json"; rm -f "$SA/sync.ok" "$SA/sync.fail"
on "$B" sync-job   # a fresh dir: it may be a rebase that has written only its autostash yet
[ "$(ls "$A/.git/rebase-merge")" = autostash ] && [ -z "$(git -C "$A" stash list)" ] && [ ! -e "$SA/stuck-rebase" ] && [ ! -e "$SA/sync.ok" ] \
  && grep -q "under 120 s old.*left for a later sync" "$SA/sync.fail" \
  && ok "a rebase dir holding only its autostash but under 2 minutes old is left for a later sync: no stash, no move, nothing synced" \
  || die "young stuck dir: $(ls "$A/.git/rebase-merge" 2>&1), stash [$(git -C "$A" stash list)], fail [$(cat "$SA/sync.fail" 2>/dev/null)]"
aged "$A/.git/rebase-merge/autostash" "$A/.git/rebase-merge"; rm -f "$SA/sync.fail"
on "$B" sync-job
MV=$(ls -d "$SA"/stuck-rebase/rebase-merge-* 2>/dev/null | head -1)
[ ! -e "$A/.git/rebase-merge" ] && git -C "$A" stash list | has "switchboard: recovered autostash" && git -C "$A" stash show -p 'stash@{0}' | has "a local change" \
  && [ -n "$MV" ] && [ "$(ls "$MV")" = autostash ] && [ "$(cat "$MV/autostash")" = "$S" ] && grep -qF "moved to $MV" "$SA/sync.fail" \
  && [ "$(rv)" = 4 ] && [ -f "$A/events/peer2.json" ] && [ -s "$SA/sync.ok" ] \
  && grep -q "autostash.*git stash list" "$SA/sync.fail" && on "$B" status | has "last failure .*autostash" \
  && ok "a rebase-merge dir holding only its autostash: the autostash goes to git stash list, the dir moves to the state dir, the sync goes through, status names both" \
  || die "stuck rebase: dir $(ls "$A/.git/rebase-merge" 2>&1), stash [$(git -C "$A" stash list)] [$(git -C "$A" stash show -p 'stash@{0}' 2>&1 | tail -3)], remote v$(rv), peer2 $(ls "$A/events"), ok [$(cat "$SA/sync.ok" 2>/dev/null)] fail [$(cat "$SA/sync.fail" 2>/dev/null)] status [$(on "$B" status 2>&1 | tail -2)]"
git -C "$A" stash clear
mkdir "$A/.git/rebase-merge"; echo 0123456789abcdef0123456789abcdef01234567 > "$A/.git/rebase-merge/autostash"; rm -f "$SA/sync.ok" "$SA/sync.fail"
aged "$A/.git/rebase-merge/autostash" "$A/.git/rebase-merge"
on "$B" sync-job
[ -f "$A/.git/rebase-merge/autostash" ] && grep -q "could not be kept" "$SA/sync.fail" && [ ! -e "$SA/sync.ok" ] \
  && ok "an autostash git cannot store is never dropped: the dir stays as it is, nothing syncs, and sync.fail says why" \
  || die "unstorable autostash: dir $(ls "$A/.git/rebase-merge" 2>&1), ok [$(cat "$SA/sync.ok" 2>/dev/null)] fail [$(cat "$SA/sync.fail" 2>/dev/null)]"
rm -rf "$A/.git/rebase-merge"
# a rebase dir with more than its autostash (here an empty todo, and no head-name, so rebase --abort fails) may be a
# rebase under way: left as it is, no stash stored, nothing synced
mkdir "$A/.git/rebase-merge"; echo "$S" > "$A/.git/rebase-merge/autostash"; : > "$A/.git/rebase-merge/todo"; rm -f "$SA/sync.ok" "$SA/sync.fail"
n0=$(ls "$SA/stuck-rebase" | wc -l); on "$B" sync-job
[ "$(ls "$A/.git/rebase-merge" | tr '\n' ' ')" = "autostash todo " ] && [ -z "$(git -C "$A" stash list)" ] && [ "$(ls "$SA/stuck-rebase" | wc -l)" = "$n0" ] \
  && grep -q "resolve it by hand" "$SA/sync.fail" && [ ! -e "$SA/sync.ok" ] \
  && ok "a rebase dir holding more than its autostash is never touched: no stash, no move, nothing synced, sync.fail says resolve it by hand" \
  || die "rebase dir with more: $(ls "$A/.git/rebase-merge" 2>&1 | tr '\n' ' '), stash [$(git -C "$A" stash list)], ok [$(cat "$SA/sync.ok" 2>/dev/null)] fail [$(cat "$SA/sync.fail" 2>/dev/null)]"
rm -rf "$A/.git/rebase-merge"

# a session's own fetch of another branch in the clone, between the job's fetch and its rebase, rewrites FETCH_HEAD:
# the job rebases onto the branch it fetched itself, so the other branch never reaches the remote's main
for form in "feature" "refs/heads/feature:refs/remotes/origin/feature"; do
  n=$((${n:-0} + 1)); echo "{\"n\":$n}" > "$T/P/events/main-$n.json"; pc "main $n"
  git -C "$T/P" checkout -q -b "feature" 2>/dev/null || git -C "$T/P" checkout -q feature
  echo "{\"n\":$n}" > "$T/P/events/unreviewed-$n.json"; git -C "$T/P" add -A; git -C "$T/P" commit -qm "UNREVIEWED $n"
  git -C "$T/P" push -q origin feature; git -C "$T/P" checkout -q main
  echo '{}' > "$A/events/mine-$n.json"; rm -f "$SA/sync.ok" "$SA/sync.fail"
  hold "$SA/tree.lock" 3 sh   # a board write in progress: the job's window waits for it
  SWITCHBOARD_DIR="$A" SWITCHBOARD_STATE="$SA" SWITCHBOARD_NOSYNC='' "$B" sync-job & J=$!
  nap 1.2; git -C "$A" fetch -q origin "$form"
  wait "$J" || true; wait "$HOLDER" || true
  tree=$(git -C "$T/R.git" ls-tree -r --name-only main)
  [ -z "$(git -C "$T/R.git" log --format=%s main | grep UNREVIEWED)" ] && echo "$tree" | has "events/mine-$n.json" \
    && echo "$tree" | has "events/main-$n.json" && [ -s "$SA/sync.ok" ] \
    && ok "git fetch origin $form in the clone while the job waits for its window: main gets the job's records, never the fetched branch" \
    || die "fetch of $form during the job: main has [$(git -C "$T/R.git" log --format=%s main | head -4 | tr '\n' '|')], fail [$(cat "$SA/sync.fail" 2>/dev/null)]"
done

# the remote's main force-pushed to drop a commit the clone already has: the job's rebase drops it too (fork point from
# the tracking ref's reflog), never pushing it back; the clone got it by a clone after it, or by a pull
for way in clone pull; do
  F="$T/fp-$way"; git init -q --bare -b main "$F/R.git"; git clone -q "$F/R.git" "$F/P" 2>/dev/null
  git -C "$F/P" config user.email t@t; git -C "$F/P" config user.name p; mkdir -p "$F/P/events"; echo '{}' > "$F/P/events/seed.json"
  git -C "$F/P" add -A; git -C "$F/P" commit -qm seed; git -C "$F/P" push -q origin HEAD:main
  if [ "$way" = pull ]; then git clone -q "$F/R.git" "$F/A"; fi
  echo x > "$F/P/secret.txt"; git -C "$F/P" add -A; git -C "$F/P" commit -qm "X secret"; git -C "$F/P" push -q origin HEAD:main
  if [ "$way" = pull ]; then git -C "$F/A" pull -q; else git clone -q "$F/R.git" "$F/A"; fi
  git -C "$F/A" config user.email t@t; git -C "$F/A" config user.name a; [ -f "$F/A/secret.txt" ] || die "setup: $way did not bring X"
  git -C "$F/P" reset -q --hard HEAD~1; echo y > "$F/P/y.txt"; git -C "$F/P" add -A; git -C "$F/P" commit -qm "Y rewrite"; git -C "$F/P" push -q -f origin HEAD:main
  echo '{}' > "$F/A/events/mine.json"
  SWITCHBOARD_DIR="$F/A" SWITCHBOARD_STATE="$F/st" SWITCHBOARD_NOSYNC='' "$B" sync-job
  tree=$(git -C "$F/R.git" ls-tree -r --name-only main)
  ! echo "$tree" | has secret.txt && [ -z "$(git -C "$F/R.git" log --format=%s main | grep 'X secret')" ] && echo "$tree" | has events/mine.json \
    && echo "$tree" | has y.txt && [ -s "$F/st/sync.ok" ] \
    && ok "main force-pushed to drop a commit the clone got by $way: the job's push keeps it dropped and carries the clone's record" \
    || die "force push, $way: main has [$(git -C "$F/R.git" log --format=%s main | tr '\n' '|')], fail [$(cat "$F/st/sync.fail" 2>/dev/null)]"
done
# an upstream that is a local branch, not remote/branch: a readable failure, not a crash
F="$T/fp-clone"; git -C "$F/A" branch -q base; git -C "$F/A" branch -q -u base main; echo '{}' > "$F/A/events/mine2.json"
SWITCHBOARD_DIR="$F/A" SWITCHBOARD_STATE="$F/st" SWITCHBOARD_NOSYNC='' "$B" sync-job
grep -q "upstream 'base' is not a remote and a branch" "$F/st/sync.fail" && ok "an upstream that is a local branch: sync.fail says the upstream is not a remote and a branch" \
  || die "local upstream: fail [$(cat "$F/st/sync.fail" 2>/dev/null)]"

# P0-3: eight jobs at once; the first fetch through the remote hangs 6 s, so the winner holds its lock that long
SLOW="$T/slow-pack"; printf '#!/bin/sh\nmkdir "%s/slow.once" 2>/dev/null && sleep 6\nexec git upload-pack "$@"\n' "$T" > "$SLOW"; chmod +x "$SLOW"
git -C "$A" config remote.origin.uploadpack "$SLOW"; echo '{"v":5}' > "$A/tasks/t.json"; rm -f "$SA/sync.ok" "$SA/sync.fail"
c0=$(git -C "$T/R.git" rev-list --count main); pids=""
for _ in 1 2 3 4 5 6 7 8; do SWITCHBOARD_DIR="$A" SWITCHBOARD_STATE="$SA" SWITCHBOARD_NOSYNC='' "$B" sync-job & pids="$pids $!"; done
nap 3; alive=0; for p in $pids; do kill -0 "$p" 2>/dev/null && alive=$((alive + 1)); done; h=$(held "$SA/sync-job.lock" && echo held || echo free)
for p in $pids; do wait "$p" || true; done
git -C "$A" config --unset remote.origin.uploadpack
[ -d "$T/slow.once" ] && [ "$alive" = 1 ] && [ "$h" = held ] && [ "$(git -C "$T/R.git" rev-list --count main)" = $((c0 + 1)) ] \
  && [ "$(rv)" = 5 ] && [ -s "$SA/sync.ok" ] && [ ! -e "$SA/sync.fail" ] \
  && [ ! -e "$A/.git/rebase-merge" ] && [ ! -e "$A/.git/rebase-apply" ] && [ -z "$(git -C "$A" status --porcelain)" ] \
  && ok "eight sync jobs at once: one holds the job lock, the other seven exit, one commit goes out and nothing is left half done" \
  || die "eight jobs: $alive alive after 3 s, lock $h, commits $c0 -> $(git -C "$T/R.git" rev-list --count main), fail [$(cat "$SA/sync.fail" 2>/dev/null)], status [$(git -C "$A" status --porcelain)]"

# SessionStart's fast-forward steps aside while the tree lock is held; the job it starts merges once it is free
seat S1 "$T/alpha" road; jobdone
echo '{}' > "$T/P/events/peer3.json"; pc peer3; h0=$(git -C "$A" rev-parse HEAD); rm -f "$SA/sync.ok" "$SA/errors.log"
hold "$SA/tree.lock" 5
t0=$(date +%s); on sstart "$T/alpha" S1 >/dev/null; t1=$(date +%s); h1=$(git -C "$A" rev-parse HEAD); p1=$([ -f "$A/events/peer3.json" ] && echo yes || echo no)
wait "$HOLDER" || true; jobdone
[ "$h1" = "$h0" ] && [ "$p1" = no ] && [ $((t1 - t0)) -lt 5 ] && grep -q "tree lock held" "$SA/errors.log" && [ -f "$A/events/peer3.json" ] && [ -s "$SA/sync.ok" ] \
  && ok "while the tree lock is held SessionStart does not fast-forward and its writes wait at most their bound ($((t1 - t0)) s); the job merges once it is free" \
  || die "ff under lock: HEAD moved $([ "$h1" = "$h0" ] && echo no || echo yes), peer3 then $p1 now $([ -f "$A/events/peer3.json" ] && echo yes || echo no), $((t1 - t0)) s, log [$(cat "$SA/errors.log" 2>/dev/null)]"

# a merge driver runs inside the job's window: it takes no lock, so it never waits on the job
mkdir -p "$T/mf"; echo '{"a":1}' > "$T/mf/base"; echo '{"a":1,"b":2}' > "$T/mf/.merge_file_x"; echo '{"a":1,"c":3}' > "$T/mf/theirs"
hold "$SA/tree.lock" 4
t0=$(python3 -c 'import time; print(int(time.time() * 1000))'); rc=0; on "$B" merge-record "$T/mf/base" "$T/mf/.merge_file_x" "$T/mf/theirs" events/x.json || rc=$?
t1=$(python3 -c 'import time; print(int(time.time() * 1000))'); kill "$HOLDER" 2>/dev/null || true; wait "$HOLDER" 2>/dev/null || true
[ "$rc" = 0 ] && [ $((t1 - t0)) -lt 2000 ] && python3 -c "import json,sys; d=json.load(open(sys.argv[1])); sys.exit(0 if d.get('b') == 2 and d.get('c') == 3 else 1)" "$T/mf/.merge_file_x" \
  && ok "merge-record merges while the tree lock is held exclusive, in $((t1 - t0)) ms" || die "merge driver under lock: rc $rc, $((t1 - t0)) ms, $(cat "$T/mf/.merge_file_x")"

# P2: a timed-out command whose grandchild keeps the output pipe open returns at the timeout, not when the grandchild exits
if ! command -v setsid >/dev/null; then ok "skipped: no setsid here"; else
  el=$(python3 - "$B" "$T/gc.pid" <<'PY'
import importlib.machinery, importlib.util, subprocess, sys, time
ld = importlib.machinery.SourceFileLoader("board", sys.argv[1])
b = importlib.util.module_from_spec(importlib.util.spec_from_loader("board", ld)); ld.exec_module(b)
t = time.monotonic()
try:
    b.run_bounded(["sh", "-c", "setsid sleep 8 & echo $! > %s; sleep 30" % sys.argv[2]], 1)
except subprocess.TimeoutExpired:
    pass
print("%.1f" % (time.monotonic() - t))
PY
)
  kill "$(cat "$T/gc.pid" 2>/dev/null)" 2>/dev/null || true
  python3 -c "import sys; sys.exit(0 if float(sys.argv[1] or 99) < 3 else 1)" "$el" && ok "run_bounded with a 1 s timeout and a grandchild holding its pipe returns in $el s" || die "run_bounded took $el s"
fi

# P2: a pull stamp dated ahead of the clock counts as due
jobdone; touch "$SA/pull.stamp"; python3 -c "import os,sys,time; t=time.time()+3600; os.utime(sys.argv[1],(t,t))" "$SA/pull.stamp"; rm -f "$SA/sync.ok"
( unset SWITCHBOARD_PULL_EVERY; on pre PostToolUse "$T/alpha" S1 t1 Read '{}' >/dev/null ); jobdone
[ -s "$SA/sync.ok" ] && python3 -c "import os,sys,time; sys.exit(0 if os.stat(sys.argv[1]).st_mtime <= time.time() + 1 else 1)" "$SA/pull.stamp" \
  && ok "a pull stamp an hour in the future is due: the tool call starts the job and the stamp is set to now" || die "future stamp: sync.ok $(cat "$SA/sync.ok" 2>/dev/null)"

jobdone; [ -z "$(procs "$T/")" ] && ! held "$SA/sync-job.lock" && ok "no sync job, git or sleep process is left running" || die "left running: [$(procs "$T/")]"
finish
