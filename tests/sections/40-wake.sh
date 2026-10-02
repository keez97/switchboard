#!/usr/bin/env bash
# the listener: `switchboard wait`, run by the async Stop hook, wakes an idle session (exit 2, the notes on stderr)
# for a task at the role it holds, a proposal for the end it holds and a task or link event that concerns it, marks
# them shown as a prompt would, and wakes for nothing else. One waiter per Claude process; it exits 0 superseded, with
# its process gone, on SIGTERM, on an error and past the wake cap, and re-arms before its timeout. Each waiter runs as
# a child of a stand-in Claude process (tests/fakeclaude.py), so it finds its session by walking the real process tree.
source "$(dirname "$0")/../lib.sh"
unset SWITCHBOARD_NOWALK
FC="$TESTS/fakeclaude.py"
claude(){ # name -> pid of a new stand-in Claude process listening on $T/fc-<name>.sock
  python3 "$FC" serve "$T/fc-$1.sock" >/dev/null 2>&1 </dev/null & local pid=$!; echo $pid >> "$T/pids"
  local n=0; until [ -S "$T/fc-$1.sock" ] || [ $n -gt 50 ]; do python3 -c "import time; time.sleep(0.1)"; n=$((n+1)); done
  echo $pid; }
under(){ python3 "$FC" run "$T/fc-$1.sock" "$2" "$3"; }   # name cwd command: the command as that stand-in's child
h(){ # name event cwd session [json with more fields]: a hook event, run the way Claude Code runs one
  local more="${5:-}"; [ -n "$more" ] || more='{}'
  python3 -c 'import json,sys; d={"hook_event_name":sys.argv[1],"cwd":sys.argv[2],"session_id":sys.argv[3]}; d.update(json.loads(sys.argv[4])); print(json.dumps(d))' "$2" "$3" "$4" "$more" | under "$1" "$3" "\"$B\" hook"; }
prompt(){ h "$1" UserPromptSubmit "$2" "$3" '{"prompt": "go on"}' | ctx; }   # name cwd session: what a prompt shows
listen(){ # name cwd session tag [VAR=value]: switchboard wait as the stand-in's child in the background, as the async
  # Stop hook runs it; its stderr in $T/<tag>.err, its exit code in $T/<tag>.rc
  local stop; stop=$(printf '{"hook_event_name": "Stop", "cwd": "%s", "session_id": "%s"}' "$2" "$3")
  ( echo "$stop" | under "$1" "$2" "${5:-} \"$B\" wait 2>\"$T/$4.err\"; echo \$? >\"$T/$4.rc\"" >/dev/null 2>&1 ) &
  echo $! >> "$T/pids"; }
claim(){ # pid: the waiter pid the claim for that stand-in names, or nothing
  [ ! -f "$SWITCHBOARD_STATE/claude/wait-$1.json" ] || python3 -c "import json,sys; print(json.load(open(sys.argv[1])).get('waiter', ''))" "$SWITCHBOARD_STATE/claude/wait-$1.json"; }
arm(){ # name pid cwd session tag [VAR=value]: start a waiter and return once it has claimed the stand-in's process
  local old c n=0; old=$(claim "$2"); listen "$1" "$3" "$4" "$5" "${6:-}"
  until { c=$(claim "$2"); [ -n "$c" ] && [ "$c" != "$old" ]; } || [ $n -gt 50 ]; do python3 -c "import time; time.sleep(0.1)"; n=$((n+1)); done; }
rc_of(){ # tag seconds: the waiter's exit code once it is out within that time, else running
  local n=0; until [ -s "$T/$1.rc" ] || [ $n -ge $(($2 * 10)) ]; do python3 -c "import time; time.sleep(0.1)"; n=$((n+1)); done
  cat "$T/$1.rc" 2>/dev/null || echo running; }
why(){ echo "rc=$(cat "$T/$1.rc" 2>/dev/null || echo running) err=$(cat "$T/$1.err" 2>/dev/null)"; }
stopin(){ printf '{"hook_event_name": "Stop", "cwd": "%s", "session_id": "%s"%s}' "$2" "$3" "${4:-}" | under "$1" "$2" "\"$B\" wait"; }

fx_repos alpha beta src
W=$(claude W); R=$(claude R)
h W SessionStart "$T/alpha" sW '{"source": "startup"}' >/dev/null; h R SessionStart "$T/beta" sR '{"source": "startup"}' >/dev/null
under W "$T/alpha" "\"$B\" role builder" </dev/null >/dev/null; under R "$T/beta" "\"$B\" role planner" </dev/null >/dev/null
prompt W "$T/alpha" sW >/dev/null; prompt R "$T/beta" sR >/dev/null

# ---- the hook as installed: async, asyncRewake, and its timeout is the one the waiter re-arms before
python3 - "$B" "$TESTS/../hooks/hooks.json" <<'PY' && ok "hooks.json runs wait on Stop with async and asyncRewake, its timeout WAIT_TIMEOUT" || die "hooks.json waiter entry"
import importlib.machinery, importlib.util, json, sys
l = importlib.machinery.SourceFileLoader("sb", sys.argv[1]); m = importlib.util.module_from_spec(importlib.util.spec_from_loader("sb", l)); l.exec_module(m)
w = [x for e in json.load(open(sys.argv[2]))["hooks"]["Stop"] for x in e["hooks"] if x["command"].endswith(" wait")]
sys.exit(not (len(w) == 1 and w[0].get("async") is True and w[0].get("asyncRewake") is True and w[0]["timeout"] == m.WAIT_TIMEOUT))
PY

# ---- a task for the role it holds wakes it; the next prompt does not repeat the note
arm W "$W" "$T/alpha" sW w1
TK=$(under R "$T/beta" "\"$B\" task request --to $T/alpha:builder --subject 'wake check' --key k1 --no-sign" </dev/null 2>"$T/req.err" | awk '{print $1}')
has "listener wakes the session holding alpha:builder within seconds when it is idle on this machine" < "$T/req.err" \
  && ok "task request tells the requester the listener wakes the worker, and to message it if it does not answer" || die "request text: $(cat "$T/req.err")"
[ "$(rc_of w1 8)" = 2 ] && head -1 "$T/w1.err" | has "^switchboard woke this session: work for it arrived while it was idle" \
  && has "a task for you (you hold alpha:builder): $TK \"wake check\"" < "$T/w1.err" && has "task $TK requested of alpha:builder" < "$T/w1.err" \
  && ok "a task for the role it holds wakes the waiter: exit 2, the task note and its event on stderr" || die "task wake: $(why w1)"
p=$(prompt W "$T/alpha" sW); ! echo "$p" | has "$TK" && "$B" task "$TK" | has "notified east" \
  && ok "the note is marked shown as a prompt marks it: the next prompt does not repeat it, and the cursor says notified" || die "task repeated: $p"

# ---- a proposal for the end it holds wakes it; so does its acceptance, at the proposer
arm W "$W" "$T/alpha" sW w2
under R "$T/beta" "\"$B\" link --from $T/beta:planner --to $T/alpha:builder --scope 'wake checks'" </dev/null >"$T/prop" 2>/dev/null
LID=$(awk 'NR==1{print $2}' "$T/prop")
has "alpha:builder held by .*: switchboard's listener wakes it within seconds when it is idle on this machine .*message it at that to= address" < "$T/prop" \
  && ok "link tells the proposer the listener wakes the other end, and to message it if it does not answer" || die "proposal text: $(cat "$T/prop")"
[ "$(rc_of w2 8)" = 2 ] && has "proposes link $LID" < "$T/w2.err" && ok "a proposal for the end it holds wakes the waiter" || die "proposal wake: $(why w2)"
! prompt W "$T/alpha" sW | has "proposes link $LID" && ok "the next prompt does not repeat the proposal" || die "proposal repeated"
arm R "$R" "$T/beta" sR w3
under W "$T/alpha" "\"$B\" link accept $LID" </dev/null >/dev/null 2>&1
[ "$(rc_of w3 8)" = 2 ] && has "link $LID accepted by" < "$T/w3.err" && ok "the acceptance wakes the proposer's waiter" || die "accept wake: $(why w3)"
! prompt R "$T/beta" sR | has "link $LID accepted by" && ok "the proposer's next prompt does not repeat it" || die "accept repeated"
prompt W "$T/alpha" sW >/dev/null

# ---- a watched file's change does not wake it; the next prompt shows it
"$B" watch "$T/alpha" path "$T/src/VERSION" >/dev/null; echo 1 > "$T/src/VERSION"; (cd "$T/src" && "$B" detect)
arm W "$W" "$T/alpha" sW w4
echo 2 > "$T/src/VERSION"; (cd "$T/src" && "$B" detect)
[ "$(rc_of w4 5)" = running ] && ok "a watch change event does not wake the waiter" || die "watch woke it: $(why w4)"
prompt W "$T/alpha" sW | has "src-[0-9a-f]*:VERSION content changed" && ok "the watch change waits for the next prompt" || die "watch change lost"

# ---- one waiter per Claude process: a second one takes over, and the first exits 0
arm W "$W" "$T/alpha" sW w5
[ "$(rc_of w4 5)" = 0 ] && [ ! -s "$T/w4.err" ] && [ "$(rc_of w5 0)" = running ] \
  && ok "a second waiter for the same process makes the first exit 0, with no output" || die "supersede: $(why w4); $(why w5)"

# ---- SIGTERM: exit 0, no output
kill -TERM "$(claim "$W")"
[ "$(rc_of w5 5)" = 0 ] && [ ! -s "$T/w5.err" ] && ok "SIGTERM makes the waiter exit 0 with no output" || die "sigterm: $(why w5)"

# ---- off, a subagent: nothing
c0=$(claim "$W")
o=$(stopin W "$T/alpha" sW ', "agent_id": "a1"' 2>&1; echo "rc=$?"); o2=$(SWITCHBOARD_OFF=1 stopin W "$T/alpha" sW 2>&1; echo "rc=$?")
[ "$o" = "rc=0" ] && [ "$o2" = "rc=0" ] && [ "$(claim "$W")" = "$c0" ] \
  && ok "in a subagent and with SWITCHBOARD_OFF the waiter exits 0 at once and claims nothing" || die "subagent/off: $o / $o2"

# ---- its Claude process ends: exit 0
Z=$(claude Z); h Z SessionStart "$T/alpha" sZ '{"source": "startup"}' >/dev/null
arm Z "$Z" "$T/alpha" sZ w6
python3 "$FC" quit "$T/fc-Z.sock"
[ "$(rc_of w6 6)" = 0 ] && [ ! -s "$T/w6.err" ] && ok "the waiter exits 0 when its Claude process ends" || die "process gone: $(why w6)"

# ---- after a clear no Stop comes: the waiter goes on for the new session id
arm W "$W" "$T/alpha" sW w7
h W SessionEnd "$T/alpha" sW '{"reason": "clear"}' >/dev/null; h W SessionStart "$T/alpha" sW2 '{"source": "clear"}' >/dev/null
TK2=$(under R "$T/beta" "\"$B\" task request --to $T/alpha:builder --subject 'after the clear' --key k2 --no-sign" </dev/null 2>/dev/null | awk '{print $1}')
[ "$(rc_of w7 8)" = 2 ] && has "a task for you (you hold alpha:builder): $TK2" < "$T/w7.err" && ! prompt W "$T/alpha" sW2 | has "$TK2" \
  && ok "a waiter started before a clear wakes the new session id, and its next prompt does not repeat the note" || die "clear: $(why w7)"
[ ! -s "$SWITCHBOARD_STATE/errors.log" ] && ok "no waiter or hook logged an error so far" || die "errors: $(cat "$SWITCHBOARD_STATE/errors.log")"

# ---- work that arrived during the turn wakes it at once
TK3=$(under R "$T/beta" "\"$B\" task request --to $T/alpha:builder --subject 'during the turn' --key k3 --no-sign" </dev/null 2>/dev/null | awk '{print $1}')
listen W "$T/alpha" sW2 w8
[ "$(rc_of w8 2)" = 2 ] && has "$TK3" < "$T/w8.err" && ok "work pending when the waiter starts wakes it at once" || die "pending: $(why w8)"

# ---- the wake cap: 12 an hour per Claude process, then exit 0 and one line in errors.log; the work waits for a prompt
python3 - "$SWITCHBOARD_STATE/claude/wait-$W.json" "$W" "$("$B" _procstart "$W")" <<'PY'
import json, sys, time
json.dump({"pid": int(sys.argv[2]), "procStart": sys.argv[3], "waiter": 1, "wakes": [time.time() - 60] * 12}, open(sys.argv[1], "w"))
PY
TK4=$(under R "$T/beta" "\"$B\" task request --to $T/alpha:builder --subject 'over the cap' --key k4 --no-sign" </dev/null 2>/dev/null | awk '{print $1}')
listen W "$T/alpha" sW2 w9
[ "$(rc_of w9 4)" = 0 ] && [ ! -s "$T/w9.err" ] && [ "$(grep -c " wait .*12 wakes in the last hour" "$SWITCHBOARD_STATE/errors.log")" = 1 ] \
  && ok "past 12 wakes in an hour the waiter exits 0 and logs one line" || die "cap: $(why w9) $(cat "$SWITCHBOARD_STATE/errors.log" 2>&1)"
prompt W "$T/alpha" sW2 | has "a task for you (you hold alpha:builder): $TK4" && ok "the work held back by the cap arrives at the next prompt" || die "cap lost $TK4"

# ---- before its timeout it wakes the session once to re-arm
rm -f "$SWITCHBOARD_STATE/claude/wait-$W.json"
listen W "$T/alpha" sW2 w10 SWITCHBOARD_WAIT_TIMEOUT=4
[ "$(rc_of w10 6)" = 2 ] && [ "$(wc -l < "$T/w10.err")" = 1 ] && has "^switchboard is re-arming its listener for this session. Nothing new arrived; end your turn now without doing anything.$" < "$T/w10.err" \
  && ok "before its timeout the waiter exits 2 with one line asking the session to end its turn" || die "re-arm: $(why w10)"

# ---- an error: logged, exit 0, never 2
rm -f "$SWITCHBOARD_STATE/claude/wait-$W.json"; mkdir "$SWITCHBOARD_STATE/claude/wait-$W.json"   # the claim cannot be written
under R "$T/beta" "\"$B\" task request --to $T/alpha:builder --subject 'with a fault' --key k5 --no-sign" </dev/null >/dev/null 2>&1
listen W "$T/alpha" sW2 w11
[ "$(rc_of w11 4)" = 0 ] && [ ! -s "$T/w11.err" ] && grep -q " wait save:[0-9]* IsADirectoryError" "$SWITCHBOARD_STATE/errors.log" \
  && ok "an exception in the waiter is logged and it exits 0, not 2" || die "error path: $(why w11) $(cat "$SWITCHBOARD_STATE/errors.log")"
rmdir "$SWITCHBOARD_STATE/claude/wait-$W.json"

# ---- the event that woke it shows even when newer events push it past the five a note carries
under W "$T/alpha" "\"$B\" unlink $LID" </dev/null >/dev/null 2>&1
"$B" watch "$T/beta" path "$T/src/NOTES" >/dev/null; echo 0 > "$T/src/NOTES"; (cd "$T/src" && "$B" detect)
for i in 1 2 3 4 5; do echo "$i" > "$T/src/NOTES"; (cd "$T/src" && "$B" detect); done
listen R "$T/beta" sR w12
[ "$(rc_of w12 4)" = 2 ] && has "link $LID closed: ended by" < "$T/w12.err" && [ "$(grep -c "NOTES content changed" "$T/w12.err")" = 5 ] \
  && ok "the event that woke the session shows even behind five newer ones" || die "cutoff: $(why w12)"

python3 "$FC" quit "$T/fc-W.sock"; python3 "$FC" quit "$T/fc-R.sock"
finish
