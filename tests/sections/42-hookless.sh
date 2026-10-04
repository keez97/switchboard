#!/usr/bin/env bash
# a session that runs without switchboard's hooks (over SSH the desktop app loads its own --plugin-dir copy of the
# plugin, which has no hooks folder): role, status and who say so in one stderr line, naming that copy when the
# Claude process's command line has one, and print the same stdout as with hooks. CLI calls and hooks run as children
# of a stand-in Claude process (tests/fakeclaude.py) with a session file, so the CLI finds the session by walking the
# real process tree.
source "$(dirname "$0")/../lib.sh"
unset SWITCHBOARD_NOWALK
FC="$TESTS/fakeclaude.py"
claude(){ # name sid [Claude's own flags...] -> pid of a new stand-in on $T/fc-<name>.sock, with a session file in alpha
  local name=$1 sid=$2; shift 2
  python3 "$FC" serve "$T/fc-$name.sock" "$@" >/dev/null 2>&1 </dev/null & local pid=$!; echo $pid >> "$T/pids"
  local n=0; until [ -S "$T/fc-$name.sock" ] || [ $n -gt 50 ]; do python3 -c "import time; time.sleep(0.1)"; n=$((n+1)); done
  python3 - "$pid" "$sid" "$T/alpha" "$("$B" _procstart $pid)" "$T/fc-$name.sock" <<'PY'
import json,os,sys
pid,sid,cwd,ps,sock=sys.argv[1:6]
json.dump({"pid":int(pid),"sessionId":sid,"cwd":cwd,"name":"session "+sid,"procStart":ps,"messagingSocketPath":sock,
           "bridgeSessionId":"session_"+sid,"peerProtocol":1,"version":"9.9.9"},open(os.path.expanduser("~/.claude/sessions/%s.json"%pid),"w"))
PY
  echo $pid; }
under(){ python3 "$FC" run "$T/fc-$1.sock" "$T/alpha" "$2" </dev/null; }   # name command: the command as that stand-in's child
runs(){ # name tag: role, who and status as that stand-in's children; stdout in $T/<tag>.out, stderr in $T/<tag>.err
  : > "$T/$2.out"; : > "$T/$2.err"
  for c in "role worker" "who" "status"; do under "$1" "\"$B\" $c" >> "$T/$2.out" 2>> "$T/$2.err"; done; }
WARN='^switchboard: this session runs without switchboard.s hooks (no notes, holds, link headers or wake)\. Desktop over SSH: set "switchboard@inline": false in the host.s ~/.claude/settings.json, then /reload-plugins\. See README "Desktop sessions over SSH"\.'
fx_repos alpha
mkdir -p "$T/inline/.claude-plugin" "$T/full/.claude-plugin" "$T/full/hooks" "$T/other/.claude-plugin"
echo '{"name": "switchboard"}' | tee "$T/inline/.claude-plugin/plugin.json" > "$T/full/.claude-plugin/plugin.json"
echo '{}' > "$T/full/hooks/hooks.json"; echo '{"name": "notes"}' > "$T/other/.claude-plugin/plugin.json"

A=$(claude A sA)
REC="$SWITCHBOARD_STATE/claude/sA.json"
[ ! -e "$REC" ] || die "setup: a process record for sA before any hook"
runs A none
[ "$(grep -c "$WARN" "$T/none.err")" = 3 ] && [ "$(wc -l < "$T/none.err")" = 3 ] && ok "no hook has run: role, who and status each print the warning, one stderr line" || die "warning: $(cat "$T/none.err")"
! grep -q "Cause:" "$T/none.err" && ok "no --plugin-dir in the Claude process's command line: no cause named" || die "cause: $(cat "$T/none.err")"
grep -qx "this session now holds role worker in alpha" "$T/none.out" && ! grep -q "without switchboard" "$T/none.out" && ok "the warning stays off stdout" || die "stdout: $(cat "$T/none.out")"

# plugins reloaded mid-life: SessionStart does not fire again, the next tool call's PostToolUse records the process
printf '{"hook_event_name": "PostToolUse", "cwd": "%s", "session_id": "sA", "tool_name": "Read", "tool_input": {}, "tool_use_id": "u1"}' "$T/alpha" \
  | python3 "$FC" run "$T/fc-A.sock" "$T/alpha" "\"$B\" hook" >/dev/null
[ -f "$REC" ] && ok "a PostToolUse hook records the session's process" || die "no record after PostToolUse"
runs A hooked
[ ! -s "$T/hooked.err" ] && ok "with the record: no warning from role, who or status" || die "warned with hooks: $(cat "$T/hooked.err")"
mv "$REC" "$T/rec.json"
runs A bare
mv "$T/rec.json" "$REC"
[ "$(grep -c "$WARN" "$T/bare.err")" = 3 ] && ok "the record moved away: the warning is back" || die "no warning: $(cat "$T/bare.err")"
cmp -s "$T/hooked.out" "$T/bare.out" && ok "stdout of role, who and status is byte-identical with and without the warning" || die "stdout differs: $(diff "$T/hooked.out" "$T/bare.out")"
mv "$REC" "$T/rec.json"
! SWITCHBOARD_NOWALK=1 python3 "$FC" run "$T/fc-A.sock" "$T/alpha" "\"$B\" who" 2>&1 >/dev/null </dev/null | has "without switchboard" \
  && ok "NOWALK: no warning" || die "warned with NOWALK"
! SWITCHBOARD_OFF=1 python3 "$FC" run "$T/fc-A.sock" "$T/alpha" "\"$B\" status" 2>&1 >/dev/null </dev/null | has "without switchboard" \
  && ok "switchboard switched off: no warning" || die "warned with OFF"
# the app reopens a session in a new process with the same session id: a record naming the earlier process is stale
python3 -c "import json,sys; r=json.load(open(sys.argv[1])); r['pid']=int(sys.argv[2]); json.dump(r,open(sys.argv[3],'w'))" "$T/rec.json" $$ "$REC"
under A "\"$B\" who" 2>&1 >/dev/null | has "$WARN" && ok "a record for the same session id naming another process: the warning shows" || die "stale record hid the warning"
mv "$T/rec.json" "$REC"

# the desktop app's copy: --plugin-dir names a switchboard plugin with no hooks/hooks.json
claude B sB --model x --plugin-dir "$T/other" --plugin-dir "$T/inline" >/dev/null
under B "\"$B\" who" 2>&1 >/dev/null | has "$WARN Cause: $T/inline has no hooks/hooks\.json\.$" && ok "--plugin-dir <dir> with no hooks folder: the warning names it" || die "cause: $(under B "\"$B\" who" 2>&1 >/dev/null)"
claude C sC "--plugin-dir=$T/inline" >/dev/null
under C "\"$B\" status" 2>&1 >/dev/null | has "$WARN Cause: $T/inline has no hooks/hooks\.json\.$" && ok "--plugin-dir=<dir>: the warning names it" || die "cause =: $(under C "\"$B\" status" 2>&1 >/dev/null)"
claude D sD --plugin-dir "$T/full" --plugin-dir "$T/other" >/dev/null
out=$(under D "\"$B\" who" 2>&1 >/dev/null)
echo "$out" | has "$WARN" && ! echo "$out" | grep -q "Cause:" && ok "a switchboard --plugin-dir with hooks, or another plugin's: no cause named" || die "cause for a full copy: $out"

# a terminal or a script has no Claude process above it: no warning. HOME and the state dir are this section's own, so
# the walk from the test shell cannot match the Claude session that runs the suite
for c in who status; do ! "$B" $c 2>&1 >/dev/null | has "without switchboard" || die "warned from a terminal: $c"; done
ok "no Claude process above the call: who and status give no warning"
[ ! -s "$SWITCHBOARD_STATE/errors.log" ] && ok "no CLI call or hook logged an error" || die "errors: $(cat "$SWITCHBOARD_STATE/errors.log")"
for n in A B C D; do python3 "$FC" quit "$T/fc-$n.sock"; done

finish
