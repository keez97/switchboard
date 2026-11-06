#!/usr/bin/env bash
# the test switches (decision D16): SWITCHBOARD_ALLOW_TMP and every switch it gates (NOW, SESSION_ID, SESSIONS_DIR,
# STATE, ...) hold only on a board under a temp folder that is not the board the passwd home's config file names. A
# session that sets them, from a file the guard never sees or with XDG_CONFIG_HOME and HOME moved so another config file
# is read, gets the real clock and its own session's rules on the configured board. The guard looks for the names in
# quoted words too. SWITCHBOARD_TEST_PWHOME (tests/py/sitecustomize.py) stands a config file in for the passwd home's,
# naming this section's board, so no live config is read.
source "$(dirname "$0")/../lib.sh"
unset SWITCHBOARD_NOWALK
FC="$TESTS/fakeclaude.py"
claude(){ # name -> pid of a stand-in Claude process listening on $T/fc-<name>.sock
  python3 "$FC" serve "$T/fc-$1.sock" >/dev/null 2>&1 </dev/null & local pid=$!; echo $pid >> "$T/pids"
  local n=0; until [ -S "$T/fc-$1.sock" ] || [ $n -gt 50 ]; do python3 -c "import time; time.sleep(0.1)"; n=$((n+1)); done
  echo $pid; }
under(){ python3 "$FC" run "$T/fc-$1.sock" "$2" "$3" </dev/null; }   # name cwd command: run it as that stand-in's child
FAR=4102444800   # 2100-01-01
CB="$SWITCHBOARD_DIR"   # the configured board of this section
PW="$T/pw"; mkdir -p "$PW/.config/switchboard" "$T/empty"
printf '{"machine": "east", "owner": "Robin", "board_dir": "%s"}\n' "$CB" > "$PW/.config/switchboard/config.json"
fx_repos alpha beta
W=$(claude W)
python3 - "$W" "$("$B" _procstart "$W")" "$T/alpha" <<'PY'
import json,os,sys
pid,ps,cwd=sys.argv[1:4]
json.dump({"pid":int(pid),"sessionId":"sW","cwd":cwd,"name":"session sW","procStart":ps,"messagingSocketPath":cwd+"/../fc-W.sock","peerProtocol":1,"version":"9.9.9"},
          open(os.path.expanduser("~/.claude/sessions/%s.json"%pid),"w"))
PY
under W "$T/alpha" "\"$B\" role roadmap" | has "holds role roadmap" || die "setup: sW takes alpha:roadmap"
# what a session sets to look like a test: the switches, with the config file it reads moved away from the passwd one
ATT="SWITCHBOARD_TEST_PWHOME=$PW SWITCHBOARD_ALLOW_TMP=1 XDG_CONFIG_HOME=$T/empty SWITCHBOARD_DIR=$CB"
LIVE="env -u SWITCHBOARD_STATE SWITCHBOARD_TEST_PWHOME=$PW"
active(){ python3 - "$CB/links" <<'PY'   # links in force: every record that is not a proposal
import json,pathlib,sys
print(sum(1 for f in pathlib.Path(sys.argv[1]).glob("*.json") if json.loads(f.read_text()).get("state") != "proposed"))
PY
}
hold_until(){ # env words...: the until of a hold made with them, minus now, in days
  local f; env "$@" "$B" hold "$T/beta/x$RANDOM" --until 1d --reason clock >/dev/null || { echo fail; return; }
  f=$(ls -t "$CB"/holds/*.json | head -1); python3 -c "import json,sys,time; print(round((json.load(open(sys.argv[1]))['until']-time.time())/86400))" "$f"; }

# the control: a test board in a temp folder keeps its switches
[ "$(hold_until SWITCHBOARD_NOW=$FAR)" -gt 20000 ] && ok "a test board under a temp folder keeps SWITCHBOARD_NOW" || die "NOW on a test board: $(hold_until SWITCHBOARD_NOW=$FAR)"
(cd "$T/alpha" && SWITCHBOARD_SESSION_ID=sW "$B" me) | has -x "session sW .*" && ok "a test board keeps SWITCHBOARD_SESSION_ID" || die "SESSION_ID on a test board: $(cd "$T/alpha" && SWITCHBOARD_SESSION_ID=sW "$B" me)"

# R3-2: the clock on the configured board, with the config file found or hidden
[ "$(hold_until -u SWITCHBOARD_STATE SWITCHBOARD_TEST_PWHOME=$PW SWITCHBOARD_NOW=$FAR)" = 1 ] && ok "R3-2: SWITCHBOARD_NOW on the configured board is ignored" || die "R3-2 NOW: $(hold_until -u SWITCHBOARD_STATE SWITCHBOARD_TEST_PWHOME=$PW SWITCHBOARD_NOW=$FAR)"
[ "$(hold_until -u SWITCHBOARD_STATE $ATT SWITCHBOARD_NOW=$FAR)" = 1 ] && ok "R3-2: and with XDG_CONFIG_HOME at an empty folder" || die "R3-2 NOW, config hidden: $(hold_until -u SWITCHBOARD_STATE $ATT SWITCHBOARD_NOW=$FAR)"
[ "$(hold_until -u SWITCHBOARD_STATE $ATT HOME=$T/empty SWITCHBOARD_NOW=$FAR)" = 1 ] && ok "R3-2: and with HOME moved too" || die "R3-2 NOW, HOME moved"

# a board outside the temp folders is no test board, configured or not (/dev/shm is in none of TEMP_PREFIXES)
if [ -d /dev/shm ] && [ -w /dev/shm ]; then
  SHM=$(mktemp -d /dev/shm/sb-49-XXXXXX); mkdir -p "$SHM/board"
  env -u SWITCHBOARD_STATE SWITCHBOARD_DIR="$SHM/board" SWITCHBOARD_NOW=$FAR "$B" hold "$SHM/x" --until 1d --reason clock >/dev/null
  u=$(python3 -c "import json,glob,sys,time; print(round((json.load(open(glob.glob(sys.argv[1]+'/board/holds/*.json')[0]))['until']-time.time())/86400))" "$SHM")
  rm -rf "$SHM"
  [ "$u" = 1 ] && ok "SWITCHBOARD_NOW on a board outside the temp folders is ignored" || die "NOW outside temp: $u"
else ok "no /dev/shm here: the board outside the temp folders is not checked"; fi

# R3-1: from a session, with the switches set, the link is the session's: a proposal, and no owner link
n0=$(active)
out=$(under W "$T/alpha" "$LIVE $ATT SWITCHBOARD_SESSION_ID=sW \"$B\" link --from $T/alpha:roadmap --to $T/beta:implementer --scope r31 --covers r31 2>&1" || true)
echo "$out" | has "proposed" && [ "$(active)" = "$n0" ] && ok "R3-1: SESSION_ID with ALLOW_TMP and the config hidden makes a proposal, no owner link" || die "R3-1 SESSION_ID: $out"
out=$(under W "$T/alpha" "$LIVE $ATT SWITCHBOARD_SESSION_ID=sW \"$B\" link --from $T/alpha:roadmap --to $T/beta:implementer --scope r31b --covers r31b --until never 2>&1" || true)
! echo "$out" | has "created" && [ "$(active)" = "$n0" ] && ok "R3-1: the same with --until never is refused" || die "R3-1 never: $out"
printf 'SWITCHBOARD_TEST_PWHOME=%s\nSWITCHBOARD_ALLOW_TMP=1\nXDG_CONFIG_HOME=%s\nSWITCHBOARD_DIR=%s\nSWITCHBOARD_SESSION_ID=sW\nSWITCHBOARD_NOW=%s\n' "$PW" "$T/empty" "$CB" "$FAR" > "$T/vars.env"
out=$(under W "$T/alpha" "unset SWITCHBOARD_STATE; set -a; . $T/vars.env; set +a; \"$B\" link --from $T/alpha:roadmap --to $T/beta:implementer --scope r31c --covers r31c 2>&1" || true)
echo "$out" | has "proposed" && [ "$(active)" = "$n0" ] && ok "R3-1: the switches from a sourced file are refused by the CLI" || die "R3-1 sourced: $out"
(cd "$T/alpha" && $LIVE $ATT SWITCHBOARD_SESSION_ID=sW "$B" me) | has -x "terminal .*" && ok "SESSION_ID on the configured board is ignored: a shell with no Claude above it is no session" || die "SESSION_ID live: $(cd "$T/alpha" && $LIVE $ATT SWITCHBOARD_SESSION_ID=sW "$B" me)"

# STATE and SESSIONS_DIR are test switches too
if out=$(env SWITCHBOARD_TEST_PWHOME="$PW" "$B" links 2>&1); then die "STATE on the configured board ran: $out"
else echo "$out" | has "SWITCHBOARD_STATE is a test switch" && ok "SWITCHBOARD_STATE on the configured board stops the command" || die "STATE: $out"; fi
under W "$T/alpha" "$LIVE SWITCHBOARD_SESSIONS_DIR=$T/empty \"$B\" me" | has -x "session sW .*" && ok "SWITCHBOARD_SESSIONS_DIR on the configured board is ignored" || die "SESSIONS_DIR live: $(under W "$T/alpha" "$LIVE SWITCHBOARD_SESSIONS_DIR=$T/empty \"$B\" me")"

# V3-1: the guard finds the names in quoted words
pre_cmd(){ python3 -c 'import json,sys; print(json.dumps({"hook_event_name":"PreToolUse","cwd":sys.argv[1],"session_id":"sW","tool_use_id":"t1","tool_name":"Bash","tool_input":{"command":sys.argv[2]}}))' "$T/alpha" "$1" | "$B" hook; }
for c in "env 'SWITCHBOARD_ALLOW_TMP=1' 'SWITCHBOARD_SESSION_ID=V1' 'XDG_CONFIG_HOME=/nonexistent' 'SWITCHBOARD_DIR=$CB' switchboard link --from alpha:x --to beta:y --scope ab --covers abc" \
         "env -S 'SWITCHBOARD_ALLOW_TMP=1 SWITCHBOARD_SESSION_ID=V1' switchboard link --from alpha:x --to beta:y --scope ab --covers ab" \
         "env \"SWITCHBOARD_ALLOW_TMP=1\" switchboard link accept l1a2b3c" \
         "env 'SWITCHBOARD_NOW=$FAR' switchboard link accept l1a2b3c" \
         "SWITCHBOARD_NOW=$FAR switchboard link accept l1a2b3c"; do
  pre_cmd "$c" | has '"permissionDecision": "deny"' && ok "V3-1: denied: ${c:0:70}" || die "V3-1 allowed: $c"
done
pre_cmd "switchboard link --from alpha:x --to beta:y --scope 'what NOW means' --covers ab" | has deny && die "a scope with a plain word is refused" || ok "a link with ordinary quoted words is still allowed"

# D19: no session found is the owner's terminal only with no Claude Code process above the call. The stand-in engine is
# a copy of sh where the desktop app keeps its engine in the passwd home; -c '...; true' keeps sh from exec'ing the CLI
ENG="$PW/.claude/remote/ccd-cli/9.9.9"; mkdir -p "$(dirname "$ENG")"; cp /bin/sh "$ENG"
LK(){ echo "link --from $T/alpha:roadmap --to $T/beta:implementer --scope $1 --covers $1"; }
snap(){ find "$CB/links" "$CB/events" -type f 2>/dev/null | sort | xargs cat 2>/dev/null | sha256sum; }
s0=$(snap); out=$($LIVE "$ENG" -c "\"$B\" $(LK d19a) 2>&1; true")
echo "$out" | has "runs under a Claude Code process" && [ "$(snap)" = "$s0" ] && ok "D19: an owner link from no session under the desktop engine is refused, nothing written" || die "D19 engine: $out"
out=$($LIVE /bin/sh -c "\"$B\" $(LK d19b) 2>&1; true"); L=$(echo "$out" | sed -n 's/^link \(l[0-9a-f]*\) created$/\1/p')
[ -n "$L" ] && ok "D19: the same from a plain sh is the owner's terminal: link $L active" || die "D19 plain sh: $out"
s0=$(snap); out=$($LIVE CLAUDECODE=1 "$B" $(LK d19c) 2>&1 || true)
echo "$out" | has "runs under a Claude Code process" && [ "$(snap)" = "$s0" ] && ok "D19: CLAUDECODE=1 with no Claude above refuses it too" || die "D19 CLAUDECODE: $out"
s0=$(snap); out=$($LIVE CLAUDE_CODE_ENTRYPOINT=cli "$B" $(LK d19d) 2>&1 || true)
echo "$out" | has "runs under a Claude Code process" && [ "$(snap)" = "$s0" ] && ok "D19: and CLAUDE_CODE_ENTRYPOINT" || die "D19 ENTRYPOINT: $out"
# the other owner acts, under the engine: bind, ending a link no session here holds, raising or removing a cap, decline
P=$(python3 -c "import json,glob,sys; print([json.load(open(f))['id'] for f in glob.glob(sys.argv[1]+'/links/*.json') if json.load(open(f)).get('state')=='proposed'][0])" "$CB")
for c in "bind $L implementer --session open" "unlink $L" "link-cap $L 0" "link-cap $L 999" "link decline $P"; do
  s0=$(snap); out=$($LIVE "$ENG" -c "\"$B\" $c 2>&1; true")
  echo "$out" | has "runs under a Claude Code process" && [ "$(snap)" = "$s0" ] && ok "D19: $c under the engine is refused" || die "D19 $c: $out"
done
s0=$(snap); out=$($LIVE "$ENG" -c "\"$B\" link-cap $L 3 2>&1; true")
echo "$out" | has -x ok && ok "D19: lowering a cap stays open, as for a session" || die "D19 lower cap: $out"
# the engine is judged in the passwd home, never HOME: the same copy in HOME is no Claude install
mkdir -p "$HOME/.claude/remote/ccd-cli"; cp /bin/sh "$HOME/.claude/remote/ccd-cli/9.9.9"
out=$($LIVE "$HOME/.claude/remote/ccd-cli/9.9.9" -c "\"$B\" unlink $L 2>&1; true")
echo "$out" | has -x ok && ok "D19: a copy under HOME, not the passwd home, is no engine: the owner ends link $L" || die "D19 HOME copy: $out"
# the round 4 route: a session that moves HOME (and STATE with it) from a sourced file is found by its file in the
# passwd home, and gets a session's rules: a proposal, never an owner link
mkdir -p "$PW/.claude/sessions"; cp "$HOME/.claude/sessions/$W.json" "$PW/.claude/sessions/"
printf 'SWITCHBOARD_TEST_PWHOME=%s\nHOME=%s\nSWITCHBOARD_DIR=%s\n' "$PW" "$T/empty" "$CB" > "$T/home.env"
n0=$(active); out=$(under W "$T/alpha" "unset SWITCHBOARD_STATE; set -a; . $T/home.env; set +a; \"$B\" $(LK d19e) 2>&1" || true)
echo "$out" | has "proposed" && [ "$(active)" = "$n0" ] && ok "D19: HOME moved from a sourced file: the session is found in the passwd home and proposes" || die "D19 HOME moved: $out"
finish
