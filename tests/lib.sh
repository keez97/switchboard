# shellcheck shell=bash
# Shared setup for the self-test sections. A section sources this file, builds the fixture it needs with the fx_*
# functions and runs its checks. Every section gets its own throwaway HOME, board clone and state dir.
set -euo pipefail
# checks pipe into has, never into grep -q: grep -q exits on the first match, and a producer still writing then dies
# of SIGPIPE, which pipefail reports as a failed check. has reads all its input before it matches.
has(){ local s; s=$(cat); grep -q "$@" <<<"$s"; }
TESTS="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
B="$(cd "$TESTS/.." && pwd)/bin/switchboard"
T="$(cd "$(mktemp -d)" && pwd -P)"
# a caller's own board variables (a session that runs the suite with the board switched off, say) must not leak in,
# under either name the CLI reads (AGENT_BOARD_ is the older one), nor a config file of the caller's own
for v in MACHINE DIR STATE OWNER ALLOW_TMP NOW SESSION_ID TEST_PROPOSE SESSIONS_DIR NOSYNC NOSCAN OFF PULL_EVERY NOWALK \
  GUARD_BUDGET WAIT_TIMEOUT; do unset "SWITCHBOARD_$v" "AGENT_BOARD_$v"; done
unset SWITCHBOARD_SCAN SWITCHBOARD_SHARED SWITCHBOARD_SCOPE_IDS SWITCHBOARD_SKIP XDG_CONFIG_HOME
# the per-user fallback dir (errors when the state dir is unwritable, the config file's notice mark) under TMPDIR
export TMPDIR="$T/tmp"; mkdir -p "$TMPDIR"
export HOME="$T/home" SWITCHBOARD_DIR="$T/board" SWITCHBOARD_STATE="$T/state" SWITCHBOARD_NOSYNC=1 SWITCHBOARD_NOSCAN=1 SWITCHBOARD_ALLOW_TMP=1 SWITCHBOARD_MACHINE=east
# the owner the notes and refusals name: a name of the suite's own, so no check depends on the default
export SWITCHBOARD_OWNER=Robin
# the sections that fake Claude Code's session files run hooks straight from this shell, whose process tree has no
# Claude process in it: the hook must not adopt whatever process sits above the test run (sessionless.sh walks)
export SWITCHBOARD_NOWALK=1
# an uncaught exception in any board run (a hook, a CLI call inside a negated check) is written here by
# tests/py/sitecustomize.py, and finish fails the section on it: a crash never passes as "no output"
export SWITCHBOARD_CRASHLOG="$T/crashes" PYTHONPATH="$TESTS/py${PYTHONPATH:+:$PYTHONPATH}"
mkdir -p "$HOME/.claude/sessions" "$SWITCHBOARD_DIR"; echo '{"enabledPlugins":{"a":true}}' > "$HOME/.claude/settings.json"
# no config file: the fields no variable sets take the defaults; 35-config.sh checks the config file
# a board folder's own files (.gitattributes, .gitignore, defaults.json), as `switchboard init` writes them; init itself
# sets up a whole machine (config file, git repo, key: 38-init.sh)
binit(){ python3 - "$B" "$1" <<'PY'
import importlib.machinery, importlib.util, pathlib, sys
l = importlib.machinery.SourceFileLoader("sb", sys.argv[1]); m = importlib.util.module_from_spec(importlib.util.spec_from_loader("sb", l))
l.exec_module(m); pathlib.Path(sys.argv[2]).mkdir(parents=True, exist_ok=True); m.board_files(pathlib.Path(sys.argv[2]))
PY
}
trap 'kill $(cat "$T/pids" 2>/dev/null) 2>/dev/null || true; [ -n "${KEEP:-}" ] && echo "kept $T" || rm -rf "$T"' EXIT
cap_procs(){ # a section that runs pre-push hooks: this shell and its children may start at most 1000 more processes than
  # this user has now (threads count on Linux), so a hook that runs itself fails to fork there, far below the user's limit
  local n l; n=$(ps -L -u "$(id -u)" -o lwp= 2>/dev/null | wc -l); [ "$n" -gt 0 ] || n=$(ps -u "$(id -u)" -o pid= | wc -l)
  l=$((n + 1000)); { [ "$(ulimit -u)" = unlimited ] || [ "$(ulimit -u)" -gt "$l" ]; } && ulimit -S -u "$l"
  return 0; }
FAILED=0
ok(){ echo "  ok   $1"; }
die(){ # a failed check is printed and counted and the section goes on; a failed setup step ends the section
  echo "  FAIL $1"; FAILED=1; case "$1" in setup:*) exit 1;; esac; }
finish(){
  if [ -s "$T/crashes" ]; then echo "  FAIL the board crashed during this section:"; sed 's/^/    /' "$T/crashes"; FAILED=1; fi
  exit "$FAILED"; }
mkrepo(){ mkdir -p "$1" && git -C "$1" init -q -b main && git -C "$1" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init; }
hook(){ # event cwd session [tool] [tool_input json]
  python3 - "$@" <<'PY' | "$B" hook
import json,sys
e,cwd,sid=sys.argv[1:4]; d={"hook_event_name":e,"cwd":cwd,"session_id":sid}
if len(sys.argv)>4: d["tool_name"]=sys.argv[4]; d["tool_input"]=json.loads(sys.argv[5])
print(json.dumps(d))
PY
}
seat(){ ( fake "$@" ) >/dev/null; }   # fake, for a session whose pid no check names
fake(){ # sid cwd name [protocol] [host]   -> starts a live process and writes a Claude-style session file for it
  python3 -c "import time; time.sleep(600)" >/dev/null 2>&1 </dev/null & local pid=$!; echo $pid >> "$T/pids"; : > "$T/sock.$pid"   # fake runs in $(...): a variable would be lost
  python3 - "$1" "$2" "$3" "$pid" "$("$B" _procstart $pid)" "$T/sock.$pid" "${4:-1}" "${5:-}" <<'PY'
import json,sys,os
sid,cwd,name,pid,ps,sock,proto,host=sys.argv[1:9]
json.dump({"pid":int(pid),"sessionId":sid,"cwd":cwd,"name":name,"procStart":ps,"messagingSocketPath":sock,
           "bridgeSessionId":"session_"+sid,"peerProtocol":int(proto),"version":"9.9.9",**({"hostSessionId":host} if host else {})},
          open(os.path.expanduser("~/.claude/sessions/%s.json"%pid),"w"))
PY
  echo $pid; }
resid(){ # pid new-session-id: the session file of that process now names another session (a clear)
  python3 - "$1" "$2" <<'PY'
import json,os,sys; f=os.path.expanduser("~/.claude/sessions/%s.json"%sys.argv[1]); d=json.load(open(f)); d["sessionId"]=sys.argv[2]; json.dump(d,open(f,"w"))
PY
}
peer(){ printf '<cross-session-message from="uds:%s" from-name="%s" from-mode="prompting">\n%s\n</cross-session-message>' "$1" "$2" "$3"; }
up(){ python3 - "$1" "$2" "$3" <<'PY' | "$B" hook
import json,sys; print(json.dumps({"hook_event_name":"UserPromptSubmit","cwd":sys.argv[1],"session_id":sys.argv[2],"prompt":sys.argv[3]}))
PY
}
send(){ hook "$1" "$2" "$3" SendMessage "{\"to\":\"uds:$4\",\"message\":\"$5\"}"; }
post(){ python3 - "$1" "$2" "$3" "$4" <<'PY' | "$B" hook
import json,sys; print(json.dumps({"hook_event_name":"PostToolUse","cwd":sys.argv[1],"session_id":sys.argv[2],"tool_name":"SendMessage","tool_input":{"to":"uds:"+sys.argv[3],"message":sys.argv[4]},"tool_response":{"success":True}}))
PY
}
pre(){ # event cwd session tool_use_id tool tool_input [reason]
  python3 - "$@" <<'PY2' | "$B" hook
import json,os,sys
e,cwd,sid,tid,tool,ti=sys.argv[1:7]; d={"hook_event_name":e,"cwd":cwd,"session_id":sid,"tool_use_id":tid,"tool_name":tool,"tool_input":json.loads(ti)}
if len(sys.argv)>7: d["reason"]=sys.argv[7]
if os.environ.get("AID"): d["agent_id"]=os.environ["AID"]
print(json.dumps(d))
PY2
}
refusal(){ python3 -c "import json,sys; [print(json.dumps(r)) for r in json.load(open(sys.argv[1]))]" "$SWITCHBOARD_STATE/refused/$1.json" 2>/dev/null; }
pend(){ python3 -c "import json,sys; print(' '.join(json.load(open(sys.argv[1]))))" "$SWITCHBOARD_STATE/pending/$1.json" 2>/dev/null; }
sstart(){ python3 -c "import json,sys; print(json.dumps({'hook_event_name':'SessionStart','source':'startup','cwd':sys.argv[1],'session_id':sys.argv[2]}))" "$1" "$2" | "$B" hook; }
send_end(){ python3 -c "import json,sys; print(json.dumps({'hook_event_name':'SessionEnd','reason':sys.argv[3],'cwd':sys.argv[1],'session_id':sys.argv[2]}))" "$1" "$2" "$3" | "$B" hook; }
stop(){ python3 -c "import json,sys; print(json.dumps({'hook_event_name':sys.argv[1],'cwd':sys.argv[2],'session_id':sys.argv[3],'stop_hook_active':sys.argv[4]=='1'}))" "$@" | "$B" hook; }
ctx(){ python3 -c "import json,sys; t=sys.stdin.read().strip(); print(json.loads(t)['hookSpecificOutput']['additionalContext'] if t else '')"; }
waitfor(){ local n=0; until [ -s "$1" ] || [ $n -gt 40 ]; do python3 -c "import time; time.sleep(0.5)"; n=$((n+1)); done; }
held(){ # lock file: true while a process holds it (sync-job.lock, tree.lock in a state dir), probed shared, never waiting
  python3 -c "
import fcntl, sys
f = open(sys.argv[1], 'a')
try:
    fcntl.flock(f, fcntl.LOCK_SH | fcntl.LOCK_NB)
except BlockingIOError:
    sys.exit(0)
sys.exit(1)" "$1"; }
hold(){ # lock file seconds [sh]: a background process holds it exclusive (shared with sh) that long, its pid in HOLDER;
  # returns once it does
  rm -f "$T/holding"; python3 -c "
import fcntl, sys, time
f = open(sys.argv[1], 'a'); fcntl.flock(f, fcntl.LOCK_SH if sys.argv[4] == 'sh' else fcntl.LOCK_EX)
open(sys.argv[2], 'w').write('1'); time.sleep(float(sys.argv[3]))" "$1" "$T/holding" "$2" "${3:-ex}" &
  HOLDER=$!; echo $HOLDER >> "$T/pids"; waitfor "$T/holding"; }
remote(){ # sid name seen-age-seconds: a presence record another machine (west) published for a session in theta
  python3 - "$SWITCHBOARD_DIR" "$THETA" "$@" <<'PY'
import json,sys,time; d,repo,sid,name,age=sys.argv[1:6]
json.dump({"session_id":sid,"machine":"west","repo":repo,"cwd":"/x","name":name,"pid":4242+sum(map(ord,sid)),"procStart":"1","uds":"/x",
           "bridge":"session_"+sid,"started":int(time.time())-int(age),"seen":int(time.time())-int(age),"role":""},
          open("%s/sessions/west-%s.json"%(d,sid),"w"))
PY
}

# ---------- fixtures ----------
fx_repos(){ for r in "$@"; do mkrepo "$T/$r"; "$B" register "$T/$r" >/dev/null; done; }
fx_link1(){ # alpha, beta, gamma; S1 holds alpha:roadmap, S2 beta:implementer, S3 gamma:implementer; link LID alpha:roadmap -> beta:implementer, cap 2
  fx_repos alpha beta gamma
  # shellcheck disable=SC2034  # P1 to P3 are for the sections that call this fixture
  { P1=$(fake S1 "$T/alpha" road); P2=$(fake S2 "$T/beta" impl); P3=$(fake S3 "$T/gamma" other); }
  for s in "S1 alpha" "S2 beta" "S3 gamma"; do set -- $s; hook SessionStart "$T/$2" $1 >/dev/null; done
  SWITCHBOARD_SESSION_ID=S1 "$B" role roadmap >/dev/null; SWITCHBOARD_SESSION_ID=S2 "$B" role implementer >/dev/null
  SWITCHBOARD_SESSION_ID=S3 "$B" role implementer >/dev/null
  LID=$(SWITCHBOARD_SESSION_ID=S1 "$B" link --from "$T/alpha:roadmap" --to "$T/beta:implementer" --scope "order the next work items" --cap 2 | awk 'NR==1{print $2}')
  [ -n "$LID" ] || die "setup: link alpha:roadmap -> beta:implementer"; }
fx_delta(){ # delta; S5 ("planner") in delta, not yet holding a role
  fx_repos delta
  # shellcheck disable=SC2034  # P5 is for the sections that call this fixture
  P5=$(fake S5 "$T/delta" planner); hook SessionStart "$T/delta" S5 >/dev/null; }
fx_delta_eps(){ # delta and eps; S5 holds delta:lead and S6 ("worker") eps:builder through link L2 ("bind test", cap 9)
  fx_delta; fx_repos eps; P6=$(fake S6 "$T/eps" worker); hook SessionStart "$T/eps" S6 >/dev/null
  # shellcheck disable=SC2034  # L2 is for the sections that call this fixture
  L2=$(SWITCHBOARD_SESSION_ID=S5 "$B" link --from "$T/delta:lead" --to "$T/eps:builder" --scope "bind test" --cap 9 | awk 'NR==1{print $2}')
  "$B" who --role builder | has "sock.$P6" || die "setup: eps:builder not bound to S6"; }
fx_holder(){ # sid: a second session in eps that takes eps:builder from S6
  seat "$1" "$T/eps" "eps holder $1"; hook SessionStart "$T/eps" "$1" >/dev/null
  SWITCHBOARD_SESSION_ID="$1" "$B" role builder --take >/dev/null || die "setup: $1 did not take eps:builder"; }
fx_key(){ # this machine's signing key and the owner's allowed_signers line for it
  mkdir -p "$HOME/.ssh" "$SWITCHBOARD_DIR/keys"; ssh-keygen -q -t ed25519 -N "" -f "$HOME/.ssh/switchboard_east" -C selftest
  echo "east namespaces=\"switchboard-task\" $(cat "$HOME/.ssh/switchboard_east.pub")" > "$SWITCHBOARD_DIR/keys/allowed_signers"; }
