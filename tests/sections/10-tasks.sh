#!/usr/bin/env bash
# task records: requests, transitions, receipts and the task commands
source "$(dirname "$0")/../lib.sh"
fx_delta_eps; fx_repos gamma kappa zeta
seat S3 "$T/gamma" other; hook SessionStart "$T/gamma" S3 >/dev/null   # a session outside the worker repo

tk(){ SWITCHBOARD_SESSION_ID=S5 "$B" task request --to "$T/eps:builder" "$@"; }
TID=$(tk --subject "app@abc123" --key k1 --kind eval --body "run the reviewer" --watch "$T/gamma:watcher" | awk '{print $1}')
TD="$SWITCHBOARD_DIR/tasks/eps--builder/$TID"; ev(){ grep -l "task $TID requested" "$SWITCHBOARD_DIR"/events/*.json 2>/dev/null | wc -l | tr -d ' '; }
python3 - "$TD/000-request.json" "$TID" <<'PY' && [ "$(ls "$TD")" = "000-request.json" ] && [ "$(ev)" = 1 ] && ok "a request writes one record at the worker's address and one event" || die "request record: $(ls -R "$SWITCHBOARD_DIR/tasks") $(cat "$TD/000-request.json")"
import json,sys; r=json.load(open(sys.argv[1]))
sys.exit(0 if (r["id"],r["subject"],r["key"],r["kind"],r["body"],r["worker"]["role"],r["requester"]["role"],r["session"],r["machine"],r["watchers"][0]["role"],r["parent"])==
         (sys.argv[2],"app@abc123","k1","eval","run the reviewer","builder","lead","S5","east","watcher","") and r["ts"]>0 and sys.argv[2].startswith("t") else 1)
PY
python3 -c "import json,sys; e=json.load(open(sys.argv[1])); sys.exit(0 if len(e['affects'])==1 and '-eps-' in e['affects'][0] else 1)" "$(grep -l "task $TID requested" "$SWITCHBOARD_DIR"/events/*.json)" && hook SessionStart "$T/eps" sE1 | has "task $TID requested of eps:builder by delta:lead: app@abc123" && ok "the event is addressed to the worker's repo and reaches a session there" || die "task event not delivered"
[ "$(tk --subject "another subject" --key k1 | awk '{print $1}')" = "$TID" ] && [ "$(ls "$SWITCHBOARD_DIR/tasks/eps--builder")" = "$TID" ] && [ "$(ls "$TD")" = "000-request.json" ] && [ "$(ev)" = 1 ] && grep -q app@abc123 "$TD/000-request.json" && ok "the same worker and key twice is a no-op that prints the existing id" || die "duplicate key wrote: $(ls -R "$SWITCHBOARD_DIR/tasks")"
nf=$(find "$SWITCHBOARD_DIR/tasks" -type f | wc -l); ne=$(ls "$SWITCHBOARD_DIR/events" | wc -l); python3 -c "print('x'*9000)" > "$T/big.txt"
out=$(tk --subject s --key k2 --body-file "$T/big.txt" 2>&1) && die "oversized body accepted" || true
echo "$out" | has "over the 8192 byte cap" || die "oversized body: $out"
out=$(tk --subject s --key k3 --body "$(printf -- '-----BEGIN OPENSSH PRIV%s KEY-----\nb3BlbnNzaA' ATE)" 2>&1) && die "private key accepted" || true
echo "$out" | has "secret pattern (private_key)" && [ "$(find "$SWITCHBOARD_DIR/tasks" -type f | wc -l)" -eq "$nf" ] && [ "$(ls "$SWITCHBOARD_DIR/events" | wc -l)" -eq "$ne" ] && ok "a body over the cap and a body with a private key are refused with nothing written" || die "secret body: $out"
out=$("$B" task "$TID"); echo "$out" | has "^$TID  submitted  app@abc123" && echo "$out" | has "worker eps:builder, requested by delta:lead" && echo "$out" | has "watchers gamma:watcher" && ok "board task shows the request and its state" || die "task show: $out"
echo '{"state": "working"' > "$TD/001-working.json"; out=$("$B" task "$TID") && die "bad record passed" || true
echo "$out" | has "001-working.json  BAD RECORD: not valid JSON" && "$B" tasks --subject app@abc123 | has "BAD RECORD" && ok "a record that is not valid JSON is reported, not skipped" || die "bad record: $out"
rm "$TD/001-working.json"
"$B" tasks --subject app@abc123 | has "^$TID  submitted .* app@abc123  (eps:builder)  unseen$" && "$B" tasks --for "$T/eps:builder" | has "^$TID" && "$B" tasks --subject nothing | has "^no tasks" && ok "board tasks finds it by subject and by worker address" || die "tasks list: $("$B" tasks --subject app@abc123)"
hook PreToolUse "$T/delta" S5 Write "{\"file_path\":\"$TD/001-completed.json\"}" | has '"deny"' && hook PreToolUse "$SWITCHBOARD_DIR" S5 Bash "{\"command\":\"echo {} > tasks/eps--builder/$TID/001-completed.json\"}" | has '"deny"' && ok "a Write or shell write into tasks/ from a session is refused by the guard" || die "tasks write allowed"
wk(){ SWITCHBOARD_SESSION_ID=S6 "$B" task "$@"; }; files(){ ls "$TD" | tr '\n' ' '; }
f0=$(files); out=$(SWITCHBOARD_SESSION_ID=S3 "$B" task working "$TID" 2>&1) && die "non-worker wrote state" || true
echo "$out" | has "refused. Acting as eps:builder needs a session in that repo" && [ "$(files)" = "$f0" ] && ok "a session that does not hold the worker address is refused with nothing written" || die "non-worker: $out"
out=$(cd "$T/gamma" && "$B" task working "$TID" 2>&1) && die "script outside the worker repo wrote state" || true
echo "$out" | has "runs outside eps" && [ "$(files)" = "$f0" ] && ok "a script with no session outside the worker repo is refused" || die "outside script: $out"
wk working "$TID" --note "started the run" | has "^$TID 001 working" && [ -f "$TD/001-working.json" ] && ok "the worker holder writes working as 001" || die "working not written: $(files)"
mkdir -p "$T/eps/out" && echo '{"score": 7}' > "$T/eps/out/score.json" && git -C "$T/eps" add out && git -C "$T/eps" -c user.email=t@t -c user.name=t commit -qm score
EC=$(git -C "$T/eps" rev-parse HEAD); EH=$(shasum -a 256 "$T/eps/out/score.json" | awk '{print $1}'); GOOD="eps:$EC:out/score.json#$EH"
f1=$(files); out=$(wk completed "$TID" --artifact "eps:$EC:out/score.json#$(printf '0%.0s' $(seq 64))" 2>&1) && die "wrong hash accepted" || true
echo "$out" | has "the sha256 of out/score.json at $EC is $EH, not the one given" && [ "$(files)" = "$f1" ] && ok "a ref with a wrong hash is refused with nothing written" || die "wrong hash: $out"
out=$(wk completed "$TID" --artifact "eps:$EC:out/missing.json#$EH" 2>&1) && die "missing path accepted" || true
echo "$out" | has "does not exist" && out=$(wk working "$TID" --artifact "$GOOD" 2>&1) && die "artifact on working accepted" || true
echo "$out" | has "goes with completed only" && [ "$(files)" = "$f1" ] && ok "a missing path, and an artifact on a state other than completed, are refused" || die "artifact rules: $out"
python3 -c "print('n'*2100)" > "$T/bignote.txt"; out=$(wk input-required "$TID" --note "$(cat "$T/bignote.txt")" 2>&1) && die "big note accepted" || true
echo "$out" | has "over the 2048 byte cap" && out=$(wk input-required "$TID" --note "token gh""p_$(printf 'a%.0s' $(seq 36))" 2>&1) && die "token note accepted" || true
echo "$out" | has "secret pattern (github_token)" && [ "$(files)" = "$f1" ] && ok "a note over the cap and a note with a token are refused" || die "note checks: $out"
seat S11 "$T/delta" "delta reader"; seat S12 "$T/kappa" "kappa reader"; hook SessionStart "$T/delta" S11 >/dev/null; hook SessionStart "$T/kappa" S12 >/dev/null
SWITCHBOARD_SESSION_ID=S5 "$B" task cancel "$TID" --note "no longer needed" | has "cancel requested" && [ -f "$TD/cancel-requested.json" ] && "$B" tasks --subject app@abc123 | has "working (cancel requested)" && ok "the requester writes one cancel request and the list shows it on an open task" || die "cancel: $(files) $("$B" tasks --subject app@abc123)"
hook PostToolUse "$T/eps" sE1 Read '{}' | has "task $TID cancel-requested: app@abc123 (no longer needed)" && ok "the cancel request reaches the worker's repo" || die "cancel event not delivered"
wk completed "$TID" --note "done anyway" --artifact "$GOOD" --artifact "farrepo:abc1234:out/x.json#$EH" | has "^$TID 002 completed" || die "completed not written: $(files)"
python3 - "$TD/002-completed.json" "$GOOD" <<'PY' && ok "completed writes its artifacts: a local ref verified, a non-local ref marked unverified" || die "artifacts: $(cat "$TD/002-completed.json")"
import json,sys; r=json.load(open(sys.argv[1])); a=r["artifacts"]
sys.exit(0 if r["seq"]==2 and r["session"]=="S6" and a[0]=={"ref":sys.argv[2],"unverified":False} and a[1]["unverified"] is True and "waiting_on" not in r else 1)
PY
out=$("$B" task "$TID"); echo "$out" | has "^$TID  completed  app@abc123" && [ "$(echo "$out" | grep -oE '^0[0-9]{2}' | tr '\n' ' ')" = "001 002 " ] && echo "$out" | has "002-completed.json  completed .* done anyway  2 artifacts" && echo "$out" | has "farrepo:.*(unverified)" && [ -f "$TD/cancel-requested.json" ] && ok "a cancel then a completed ends completed with the cancel file kept, and the numbers are contiguous" || die "task show: $out"
f2=$(files); out=$(wk failed "$TID" 2>&1) && die "transition after completed accepted" || true
echo "$out" | has "is completed, which is final" && out=$(SWITCHBOARD_SESSION_ID=S5 "$B" task cancel "$TID" 2>&1) && die "cancel after completed accepted" || true
echo "$out" | has "is completed, which is final" && [ "$(files)" = "$f2" ] && ok "after completed a transition or a cancel is refused" || die "after terminal: $out"
hook PostToolUse "$T/delta" S11 Read '{}' | has "task $TID completed: app@abc123 (done anyway)" && ! hook PostToolUse "$T/kappa" S12 Read '{}' | has "task $TID" && ok "the transition event reaches a session in the requester's repo and not one in an unrelated repo" || die "transition event delivery"
T2=$(tk --subject "second" --key k9 | awk '{print $1}'); (cd "$T/eps" && "$B" task input-required "$T2") | has "001 input-required" && grep -q '"waiting_on": "robin"' "$SWITCHBOARD_DIR"/tasks/eps--builder/"$T2"/001-input-required.json && ok "a script with no session inside the worker repo writes state, and input-required waits on the owner, lowercased, by default" || die "script in worker repo"
TG=$(cd "$T/gamma" && "$B" task request --to "$T/eps:builder" --subject "from gamma" --key g1 --no-sign 2>/dev/null | awk '{print $1}')
grep -h -o "task $TG requested [^\"]*" "$SWITCHBOARD_DIR"/events/*.json | has -x "task $TG requested of eps:builder by gamma (no role, information only): from gamma" && ok "a request from no role says so once: (no role, information only)" || die "no-role request event: $(grep -h -o "task $TG requested [^\"]*" "$SWITCHBOARD_DIR"/events/*.json)"
M1=$(SWITCHBOARD_SESSION_ID=S6 "$B" task request --to "$T/delta:lead" --subject "review" --key m1 | awk '{print $1}')
M3=$(SWITCHBOARD_SESSION_ID=S5 "$B" task request --to "$T/zeta:builder" --subject "unrelated" --key m3 | awk '{print $1}')
out=$(SWITCHBOARD_SESSION_ID=S6 "$B" tasks --mine); echo "$out" | has "^$M1 " && echo "$out" | has "^$T2 " && ! echo "$out" | has "^$M3 " && ok "--mine lists a task the caller requested and one it works, not a third" || die "--mine: $out"
OLD=$(SWITCHBOARD_NOW=$(( $(date +%s) - 8*3600 )) SWITCHBOARD_SESSION_ID=S5 "$B" task request --to "$T/eps:builder" --subject "old one" --key s1 | awk '{print $1}')
out=$("$B" tasks --stale); echo "$out" | has "^$OLD  submitted .* 8h  old one" && ! echo "$out" | has "^$T2 \|^$M1 " && [ -z "$("$B" tasks --stale 10 | grep "^$OLD")" ] && SWITCHBOARD_SESSION_ID=S5 "$B" tasks --mine --stale | has "^$OLD " && ok "--stale lists a request older than the window and not a fresh one, and combines with --mine" || die "--stale: $out"
CK=$(env -u SWITCHBOARD_ALLOW_TMP SWITCHBOARD_NOW=$(( $(date +%s) - 8*3600 )) SWITCHBOARD_SESSION_ID=S5 "$B" task request --to "$T/eps:builder" --subject "clock" --key n1 | awk '{print $1}')
python3 -c "import json,sys,time; sys.exit(0 if abs(json.load(open(sys.argv[1]))['ts']-time.time())<60 else 1)" "$SWITCHBOARD_DIR/tasks/eps--builder/$CK/000-request.json" && ! "$B" tasks --stale | has "^$CK " && ok "SWITCHBOARD_NOW alone, without the test-board variable, changes nothing" || die "clock override honoured outside a test board"
rp(){ SWITCHBOARD_SESSION_ID=S5 "$B" task request --to "$T/eps:builder" --kind report --subject "$1" --key "$2" | awk '{print $1}'; }
RD="$SWITCHBOARD_DIR/tasks/eps--builder"; rnote(){ python3 -c "import json,sys; print(json.load(open(sys.argv[1]))['note'])" "$1"; }
R1=$(rp "status one" r1); R2=$(rp "status two" r2)
SWITCHBOARD_SESSION_ID=S5 "$B" task "$R1" >/dev/null; SWITCHBOARD_SESSION_ID=S5 "$B" task seen "$R1" >/dev/null 2>&1 || true
[ "$(ls "$RD/$R1")" = "000-request.json" ] && "$B" task "$R1" | has "^$R1  submitted " && ok "a report stays open when its requester reads it" || die "requester read closed a report: $(ls "$RD/$R1")"
wk "$R1" >/dev/null; "$B" task "$R1" | has "^$R1  completed " && [ "$(rnote "$RD/$R1/001-completed.json")" = "report read" ] && python3 -c "import json,sys; r=json.load(open(sys.argv[1])); sys.exit(0 if r['session']=='S6' and r['seq']==1 else 1)" "$RD/$R1/001-completed.json" && ok "a report completes with the note 'report read' when its worker reads it" || die "report read: $(ls "$RD/$R1")"
out=$(wk seen "$R2"); echo "$out" | has -x "$R2 seen by east" && echo "$out" | has -x "$R2 001 completed" && [ "$(rnote "$RD/$R2/001-completed.json")" = "report read" ] && ok "task seen by the worker completes a report and prints the transition line" || die "report seen: $out"
hook PostToolUse "$T/delta" S11 Read '{}' | has "task $R1 completed: status one (report read)" && ok "the completion reaches the requester's repo as a transition event" || die "report completion event not delivered"
f3=$(ls "$RD/$R2" | tr '\n' ' '); wk "$R2" >/dev/null; wk seen "$R2" | has -x "$R2 already seen by east; nothing written" && [ "$(ls "$RD/$R2" | tr '\n' ' ')" = "$f3" ] && ok "a report that is already terminal is left alone" || die "terminal report rewritten"
RH=$(rp "status hooked" r6); out=$(hook PostToolUse "$T/eps" S6 Read '{}'); echo "$out" | has "a task for you.*$RH" && [ "$(ls "$RD/$RH")" = "000-request.json" ] && ok "the hook's task note is a notice and does not close a report" || die "hook note closed or missed a report: $out"
wk rejected "$RH" >/dev/null
# the worker rejects a report while its own read of it would complete it; the tree lock held 2 s widens the window.
# One record wins, and a read never completes a report after the rejection
won=""
for i in 1 2 3; do
  R=$(rp "race $i" race$i); hold "$SWITCHBOARD_STATE/tree.lock" 2
  wk rejected "$R" --note "not mine" > "$T/rej.out" 2>&1 & a=$!
  wk "$R" > /dev/null 2>&1 & b=$!
  wait $a && rj=0 || rj=$?; wait $b || true
  recs=$(cd "$RD/$R" && ls | grep -v '^000-' | tr '\n' ' ')
  if [ "$rj" = 0 ]; then
    [ "$recs" = "001-rejected.json " ] && has -x "$R 001 rejected" < "$T/rej.out" && "$B" task "$R" | has "^$R  rejected " && won="$won r" || won="$won BAD($recs: $(cat "$T/rej.out"))"
  else
    [ "$recs" = "001-completed.json " ] && has -x "switchboard: task $R is completed, which is final. Nothing was written." < "$T/rej.out" && won="$won c" || won="$won BAD($recs: $(cat "$T/rej.out"))"
  fi
done
! echo "$won" | grep -q BAD && ok "a rejection racing the worker's read of its report: one record wins, a stated rejection stands ($won )" || die "rejection and read raced:$won"
[ ! -s "$SWITCHBOARD_STATE/errors.log" ] || die "race: errors logged: $(cat "$SWITCHBOARD_STATE/errors.log")"
RO=$(SWITCHBOARD_NOW=$(( $(date +%s) - 8*3600 )) SWITCHBOARD_SESSION_ID=S5 "$B" task request --to "$T/eps:builder" --kind report --subject "old report" --key r4 | awk '{print $1}')
RN=$(SWITCHBOARD_NOW=$(( $(date +%s) - 8*3600 )) SWITCHBOARD_SESSION_ID=S5 "$B" task request --to "$T/eps:builder" --kind eval --subject "old eval" --key r5 | awk '{print $1}')
"$B" tasks --stale | has "^$RO " && wk "$RO" >/dev/null && wk seen "$RN" | has -x "$RN seen by east" && out=$("$B" tasks --stale) && ! echo "$out" | has "^$RO " && echo "$out" | has "^$RN  submitted" && ok "tasks --stale lists a report until its worker reads it, and a seen task of another kind stays open and stale" || die "stale with reports: $("$B" tasks --stale)"
wk rejected "$RN" >/dev/null
RB1=$(rp "bulk one" b1); RB2=$(rp "bulk two" b2); RB3=$(SWITCHBOARD_SESSION_ID=S5 "$B" task request --to "$T/zeta:builder" --subject "bulk elsewhere" --key b3 | awk '{print $1}')
BD="$SWITCHBOARD_DIR/tasks"; set +e; out=$(wk completed "$RB1" "$RB3" "$RB2" --note "swept" 2>"$T/bulk.err"); rc=$?; set -e
echo "$out" | has -x "$RB1 001 completed" && echo "$out" | has -x "$RB2 001 completed" && [ "$(echo "$out" | wc -l | tr -d ' ')" = 2 ] && has "$RB3" < "$T/bulk.err" && has "Acting as zeta:builder" < "$T/bulk.err" && [ "$rc" = 1 ] && [ "$(ls "$BD/zeta--builder/$RB3")" = "000-request.json" ] && [ "$(rnote "$BD/eps--builder/$RB2/001-completed.json")" = swept ] && ok "a bulk close takes the tasks it may and refuses the rest on stderr with exit 1" || die "bulk: rc=$rc out=[$out] err=[$(cat "$T/bulk.err")]"
RB4=$(rp "bulk four" b4); RB5=$(rp "bulk five" b5); set +e; wk completed "$RB4" "$RB5" > /dev/null 2>&1; rc=$?; set -e
[ "$rc" = 0 ] && "$B" task "$RB4" | has "^$RB4  completed " && "$B" task "$RB5" | has "^$RB5  completed " && ok "a bulk close with nothing refused exits 0" || die "bulk all ok: rc=$rc"
RB6=$(rp "bulk six" b6); RB7=$(rp "bulk seven" b7); n6=$(find "$RD" -type f | wc -l)
out=$(wk completed "$RB6" "$RB7" --artifact "$GOOD" 2>&1) && die "bulk with an artifact accepted" || true
echo "$out" | has "goes with one task" && [ "$(find "$RD" -type f | wc -l)" = "$n6" ] && ok "--artifact with more than one task is refused with nothing written" || die "bulk artifact: $out"
out=$(wk seen "$RB6" "$RB7" 2>&1) && die "seen took two tasks" || true
echo "$out" | has "takes one task id" && out=$(wk cancel "$RB6" "$RB7" 2>&1) && die "cancel took two tasks" || true
echo "$out" | has "takes one task id" && [ "$(find "$RD" -type f | wc -l)" = "$n6" ] && ok "seen, cancel and show keep one task id: a second is refused" || die "two ids: $out"
out=$("$B" task "$RB6" "$RB7" t00000001 2>&1) && die "a read took three task ids" || true
[ "$out" = "switchboard: task <tid> takes one task id, and 3 were given. Nothing was written." ] && out=$("$B" task "$RB6" "$RB7" 2>&1) && die "a read took two task ids" || true
[ "$out" = "switchboard: task <tid> takes one task id, and 2 were given. Nothing was written." ] && "$B" task "$RB6" "$RB6" | has "^$RB6  submitted " \
  && ok "a read of more than one task id is refused, naming task <tid> and counting every id; one id given twice reads it" || die "read with ids: $out"
RS=$(SWITCHBOARD_SESSION_ID=S5 "$B" task request --to "$T/eps:builder" --subject "single" --key b8 | awk '{print $1}')
out=$(wk working "$RS" --note one) && [ "$out" = "$RS 001 working" ] && out=$(wk working "$RB1" 2>&1) && die "single refusal exited 0" || true
[ "$out" = "switchboard: task $RB1 is completed, which is final. Nothing was written." ] && ok "one task id prints and refuses exactly as before" || die "single tid output: $out"
wk rejected "$RB6" "$RB7" "$RS" >/dev/null
[ -z "$(stop SubagentStop "$T/eps" S6 0)" ] && ok "SubagentStop never gives the task reminder" || die "SubagentStop reminded"
out=$(stop Stop "$T/eps" S6 0); echo "$out" | has '"decision": "block"' && echo "$out" | has -F "task $T2 is input-required since 0m. If its state changed, record it: \`switchboard task working|input-required|completed|failed|rejected $T2\`. If nothing changed, record nothing; never record a state that did not happen." && ! echo "$out" | has "$OLD\|$TID" && ok "a Stop reminds of a task left in input-required, and not of a submitted or completed one" || die "Stop reminder: $out"
[ -z "$(stop Stop "$T/eps" S6 1)" ] && ok "the continuation the reminder forces is not reminded again" || die "reminder repeated in the continuation"
SWITCHBOARD_SESSION_ID=S6 "$B" task working "$T2" >/dev/null
[ -z "$(SWITCHBOARD_NOW=$(( $(date +%s) + 60 )) stop Stop "$T/eps" S6 0)" ] && ok "a Stop after a transition this turn does not remind" || die "reminded after a transition"
stop Stop "$T/eps" S6 0 | has "task $T2 is working since 0m" && ok "the next turn with the task still in working and no transition is reminded" || die "working not reminded next turn"
[ -z "$(stop Stop "$T/eps" S6 0)" ] && ok "a task already reminded at its latest record is not reminded again while nothing changes" || die "reminded twice for one record"
(cd "$T/eps" && "$B" task working "$T2" --note "still running" >/dev/null) || die "setup: script transition of $T2"
r1=$(stop Stop "$T/eps" S6 0); r2=$(stop Stop "$T/eps" S6 0)
echo "$r1" | has "task $T2 is working since 0m" && [ -z "$r2" ] && ok "a new record by someone else makes the task due once more, then it rests" || die "after another's transition: [$r1] [$r2]"
# the same again with every step in one second: the session's own older record must not pass for this turn's
N=$(( $(date +%s) + 600 )); at(){ local n=$1; shift; SWITCHBOARD_NOW=$n "$@"; }
at $N env SWITCHBOARD_SESSION_ID=S6 "$B" task working "$T2" >/dev/null; at $((N + 60)) stop Stop "$T/eps" S6 0 >/dev/null
at $N stop Stop "$T/eps" S6 0 | has "task $T2 is working" && [ -z "$(at $N stop Stop "$T/eps" S6 0)" ] || die "setup: same-second reminder of $T2"
(cd "$T/eps" && SWITCHBOARD_NOW=$N "$B" task working "$T2" >/dev/null)
at $N stop Stop "$T/eps" S6 0 | has "task $T2 is working" && ok "within one second, another's new record is still reminded once" || die "same-second record by another: not reminded"
at $N env SWITCHBOARD_SESSION_ID=S6 "$B" task working "$T2" --note "mine, same second" >/dev/null
[ -z "$(at $N stop Stop "$T/eps" S6 0)" ] && at $N stop Stop "$T/eps" S6 0 | has "task $T2 is working" \
  && ok "the worker's own record, in the same second as its Stop, is this turn's; the next Stop reminds once" || die "own same-second record: reminded late or early"
PE2=$(fake SE2 "$T/eps" "eps second"); hook SessionStart "$T/eps" SE2 >/dev/null
out=$(SWITCHBOARD_SESSION_ID=SE2 "$B" role builder --take)
echo "$out" | has "Open tasks at eps:builder" && echo "$out" | grep "^  - " | head -1 | has "^  - $OLD submitted 8h old one" && echo "$out" | has "^  - $T2 working" && ! echo "$out" | has "$TID" && ok "a role take prints the open tasks at that address, oldest first, and not a completed one" || die "role take: $out"
resid "$PE2" SE2b; out=$(python3 -c "import json; print(json.dumps({'hook_event_name':'SessionStart','source':'clear','cwd':'$T/eps','session_id':'SE2b'}))" | "$B" hook)
echo "$out" | has "holds role builder in link $L2" && echo "$out" | has "  - $T2 working" && ok "a cleared holder gets the open tasks back with its role" || die "role note after clear: $out"
rsum(){ { cat "$SWITCHBOARD_STATE"/refused/S5.json "$SWITCHBOARD_STATE"/refused/SE3.json 2>/dev/null || true; } | shasum; }; r0=$(rsum)
(cd "$T/eps" && "$B" me) | has -x "terminal repo=eps" && (cd "$T/eps" && "$B" me --holds "$T/eps:reviewer" >/dev/null) && ok "board me names a terminal and --holds passes for a terminal inside the repo" || die "terminal me"
out=$(SWITCHBOARD_SESSION_ID=S5 "$B" me --holds "$T/eps:reviewer" 2>&1) && die "session in another repo passed --holds" || true
echo "$out" | has -x "session S5 repo=delta role=lead" && echo "$out" | has "refused. Acting as eps:reviewer needs a session in that repo; this session is in delta" && ok "--holds fails for a session in another repo with acting_as's reason" || die "other repo: $out"
seat SE3 "$T/eps" "eps third"; hook SessionStart "$T/eps" SE3 >/dev/null
out=$(SWITCHBOARD_SESSION_ID=SE3 "$B" me --holds "$T/eps:reviewer" 2>&1) && die "session without the role passed --holds" || true
echo "$out" | has "refused. This session does not hold eps:reviewer" && [ "$(rsum)" = "$r0" ] && ok "--holds fails for a session in the repo without the role, and a failing --holds records no refusal" || die "no role: $out"
SWITCHBOARD_SESSION_ID=SE3 "$B" role reviewer >/dev/null; out=$(SWITCHBOARD_SESSION_ID=SE3 "$B" me --holds "$T/eps:reviewer") && echo "$out" | has -x "session SE3 repo=eps role=reviewer" && ok "after board role, --holds passes and board me shows the role" || die "after role: $out"

finish
