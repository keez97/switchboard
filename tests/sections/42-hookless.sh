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
PIDA="$SWITCHBOARD_STATE/claude/pid-$A.json"
[ -f "$REC" ] && [ -f "$PIDA" ] && ok "a PostToolUse hook records the session's process and marks the process it runs in" || die "no record after PostToolUse"
runs A hooked
[ ! -s "$T/hooked.err" ] && ok "with the record: no warning from role, who or status" || die "warned with hooks: $(cat "$T/hooked.err")"
mv "$PIDA" "$T/pidA.json"
runs A bare
mv "$T/pidA.json" "$PIDA"
[ "$(grep -c "$WARN" "$T/bare.err")" = 3 ] && ok "the process's mark moved away: the warning is back" || die "no warning: $(cat "$T/bare.err")"
cmp -s "$T/hooked.out" "$T/bare.out" && ok "stdout of role, who and status is byte-identical with and without the warning" || die "stdout differs: $(diff "$T/hooked.out" "$T/bare.out")"
mv "$PIDA" "$T/pidA.json"
! SWITCHBOARD_NOWALK=1 python3 "$FC" run "$T/fc-A.sock" "$T/alpha" "\"$B\" who" 2>&1 >/dev/null </dev/null | has "without switchboard" \
  && ok "NOWALK: no warning" || die "warned with NOWALK"
! SWITCHBOARD_OFF=1 python3 "$FC" run "$T/fc-A.sock" "$T/alpha" "\"$B\" status" 2>&1 >/dev/null </dev/null | has "without switchboard" \
  && ok "switchboard switched off: no warning" || die "warned with OFF"
# the pid now runs another process (the hooks ran in an earlier process with that pid): its mark says nothing of this one
python3 -c "import json,sys; r=json.load(open(sys.argv[1])); r['procStart']='1'; json.dump(r,open(sys.argv[2],'w'))" "$T/pidA.json" "$PIDA"
under A "\"$B\" who" 2>&1 >/dev/null | has "$WARN" && ok "a mark for this pid with another procStart: the warning shows" || die "stale mark hid the warning"
mv "$T/pidA.json" "$PIDA"

# the same session id reopened in a new process (the desktop app reopens a session, claude --resume): the record names
# the earlier process until a hook in the new one rewrites it, on any event, not only on session start
ev(){ printf '{"hook_event_name": "%s", "cwd": "%s", "session_id": "sE", "source": "resume", "prompt": "hi", "tool_name": "Read", "tool_input": {}, "tool_use_id": "u1"}' \
  "$2" "$T/alpha" | python3 "$FC" run "$T/fc-$1.sock" "$T/alpha" "\"$B\" hook" >/dev/null; }
pid_of(){ python3 -c "import json,sys; print(json.load(open(sys.argv[1]))['pid'])" "$SWITCHBOARD_STATE/claude/sE.json"; }
E=$(claude E sE); ev E SessionStart; ev E PostToolUse
[ "$(pid_of)" = "$E" ] && cp "$SWITCHBOARD_STATE/claude/sE.json" "$T/recE.json" || die "setup: no record of E"
E2=$(claude E2 sE)   # E still runs: two processes, two session files, one session id
# hooks in both, alternating: the record keeps naming E, where each hook used to rewrite it to its own process
seq=""; want=""
for e in SessionStart PostToolUse UserPromptSubmit PostToolUse Stop; do
  ev E2 "$e"; seq="$seq $(pid_of)"; ev E "$e"; seq="$seq $(pid_of)"; want="$want $E $E"; done
[ "$seq" = "$want" ] && ok "two live processes on one session id, hooks alternating between them: the record keeps naming the first" || die "record pids:$seq, want$want"
# both run hooks, the record names E: neither warns, whichever wrote the session's record
ev E2 PostToolUse
bad=""; for n in E E2; do out=$(under $n "\"$B\" who" 2>&1 >/dev/null); [ -z "$out" ] || bad="$bad $n"; done
[ -z "$bad" ] && ok "two live processes on one session id, both with hooks: who under either prints no warning" \
  || die "two live processes with hooks, who warned under:$bad"
# a third process of the same session id whose hooks never ran: it alone warns
E3=$(claude E3 sE)
bad=""; under E3 "\"$B\" who" 2>&1 >/dev/null | has "$WARN" || bad=" E3 silent"
for n in E E2; do out=$(under $n "\"$B\" who" 2>&1 >/dev/null); [ -z "$out" ] || bad="$bad $n warned"; done
[ -z "$bad" ] && ok "a process of the same session id whose hooks never ran warns; the two whose hooks ran do not" \
  || die "a hookless process next to two with hooks:$bad"
python3 "$FC" quit "$T/fc-E3.sock"; rm -f "$HOME/.claude/sessions/$E3.json"
# walk only (no session files): a CLI call under E finds E's own process, not the other one's
mkdir -p "$T/sess"; mv "$HOME/.claude/sessions/$E.json" "$HOME/.claude/sessions/$E2.json" "$T/sess/"
rm "$SWITCHBOARD_STATE/claude/sE.json"; rm -f "$SWITCHBOARD_STATE/claude/pid-$E2.json"; ev E PostToolUse
for e in PostToolUse UserPromptSubmit PostToolUse; do ev E2 "$e"; ev E "$e"; done; ev E2 PostToolUse
own=$(under E "python3 -c \"
import importlib.machinery, importlib.util
l = importlib.machinery.SourceFileLoader('sb', '$B'); m = importlib.util.module_from_spec(importlib.util.spec_from_loader('sb', l)); l.exec_module(m)
print(m.own_session()['pid'])\"")
[ "$(pid_of)" = "$E" ] && [ "$own" = "$E" ] && ok "walk only, hooks alternating: the record stays on the first process and own_session under it returns its pid" \
  || die "walk only: record pid $(pid_of), own_session under E $own, want $E"
own=$(under E2 "python3 -c \"
import importlib.machinery, importlib.util
l = importlib.machinery.SourceFileLoader('sb', '$B'); m = importlib.util.module_from_spec(importlib.util.spec_from_loader('sb', l)); l.exec_module(m)
d = m.own_session() or {}; print(d.get('pid'), d.get('sessionId'), d.get('procStart') == m.proc_start($E2))\"")
[ "$own" = "$E2 sE True" ] && ok "walk only, the record on the first process: own_session under the second returns its own pid and procStart and the session id" \
  || die "walk only: own_session under E2 gave '$own', want '$E2 sE True'"
out=$(under E2 "\"$B\" who" 2>&1 >/dev/null)
[ -z "$out" ] && ok "walk only: who under the second process prints no warning" || die "walk only, who under E2 warned: $out"
# a record a walk made, the session files back: a prompt in the other live process leaves it as it is
mv "$T/sess/$E.json" "$T/sess/$E2.json" "$HOME/.claude/sessions/"
ev E2 UserPromptSubmit
[ "$(pid_of)" = "$E" ] && ok "a walk's record and both session files: a prompt in the other live process leaves the record on the first" || die "recheck: record pid $(pid_of), want $E"
python3 "$FC" quit "$T/fc-E.sock"; rm -f "$HOME/.claude/sessions/$E.json"
cp "$T/recE.json" "$SWITCHBOARD_STATE/claude/sE.json"
ev E2 SessionStart
out=$(under E2 "\"$B\" who" 2>&1 >/dev/null)
[ -z "$out" ] && [ "$(pid_of)" = "$E2" ] && ok "reopened in a new process, SessionStart: the record names the new process and no warning" || die "resume, SessionStart: pid $(pid_of), want $E2: $out"
cp "$T/recE.json" "$SWITCHBOARD_STATE/claude/sE.json"
ev E2 PostToolUse
out=$(under E2 "\"$B\" who" 2>&1 >/dev/null)
[ -z "$out" ] && [ "$(pid_of)" = "$E2" ] && ok "reopened, plugins reloaded mid-session, PostToolUse alone: the record names the new process and no warning" || die "resume, PostToolUse: pid $(pid_of), want $E2: $out"
python3 "$FC" quit "$T/fc-E2.sock"

# the state dir does not exist and cannot be created (its parent is read-only): the hooks run and cannot record the
# process. status names the state dir; the warning stays off, as it does for an existing state dir that is read-only
mkdir -p "$T/ro"; chmod 555 "$T/ro"
F=$(claude F sF)
for e in SessionStart PostToolUse; do
  printf '{"hook_event_name": "%s", "cwd": "%s", "session_id": "sF", "tool_name": "Read", "tool_input": {}, "tool_use_id": "u1"}' "$e" "$T/alpha" \
    | TMPDIR="$T/fb" SWITCHBOARD_STATE="$T/ro/state" python3 "$FC" run "$T/fc-F.sock" "$T/alpha" "\"$B\" hook" >/dev/null 2>&1 || true
done
[ ! -e "$T/ro/state" ] || die "setup: the state dir was created under a read-only parent"
n=$(cat "$T"/fb/switchboard-*/errors.log 2>/dev/null | grep -c " remember_process ") || true
[ "$n" = 2 ] && ! grep -qs " mark_process " "$T"/fb/switchboard-*/errors.log \
  && ok "a state dir that cannot be created: each hook logs the process record it could not write once" || die "fallback log: $(cat "$T"/fb/switchboard-*/errors.log 2>&1)"
out=$(SWITCHBOARD_STATE="$T/ro/state" python3 "$FC" run "$T/fc-F.sock" "$T/alpha" "\"$B\" who" 2>&1 >/dev/null </dev/null)
! echo "$out" | grep -q "without switchboard" && ok "a state dir that cannot be created: no hookless warning" || die "warned with no state dir: $out"
SWITCHBOARD_STATE="$T/ro/state" python3 "$FC" run "$T/fc-F.sock" "$T/alpha" "\"$B\" status" 2>/dev/null </dev/null | has "$T/ro/state" \
  && ok "status names the state dir it cannot write" || die "status: $(SWITCHBOARD_STATE="$T/ro/state" under F "\"$B\" status" 2>&1)"
chmod 755 "$T/ro"
mkdir -p "$T/rw"
out=$(SWITCHBOARD_STATE="$T/rw/state" python3 "$FC" run "$T/fc-F.sock" "$T/alpha" "\"$B\" who" 2>&1 >/dev/null </dev/null)
echo "$out" | has "$WARN" && ok "a state dir not there yet whose parent is writable: no hook ran, the warning shows" || die "no warning, creatable state dir: $out"
python3 "$FC" quit "$T/fc-F.sock"

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
