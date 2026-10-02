#!/usr/bin/env bash
# a zombie process, and discovery that the scan folders alone decide
source "$(dirname "$0")/../lib.sh"
fx_repos alpha

# item 14: a killed process its parent never reaps keeps its pid and start time; it is not a live session
python3 - "$T/zchild" >/dev/null 2>&1 </dev/null <<'PY' &
import os, sys, time
pid = os.fork()
if pid == 0:
    time.sleep(600); os._exit(0)
open(sys.argv[1], "w").write(str(pid)); time.sleep(600)   # never waits: a killed child stays a zombie
PY
echo $! >> "$T/pids"; waitfor "$T/zchild"; ZC=$(cat "$T/zchild"); [ -n "$ZC" ] || die "setup: no child"; echo "$ZC" >> "$T/pids"; : > "$T/sock.$ZC"
python3 - SZ "$T/alpha" "zombie test" "$ZC" "$("$B" _procstart "$ZC")" "$T/sock.$ZC" <<'PY'
import json, os, sys
sid, cwd, name, pid, ps, sock = sys.argv[1:7]
json.dump({"pid": int(pid), "sessionId": sid, "cwd": cwd, "name": name, "procStart": ps, "messagingSocketPath": sock,
           "bridgeSessionId": "session_" + sid, "peerProtocol": 1, "version": "9.9.9"},
          open(os.path.expanduser("~/.claude/sessions/%s.json" % pid), "w"))
PY
hook SessionStart "$T/alpha" SZ >/dev/null; SWITCHBOARD_SESSION_ID=SZ "$B" role z >/dev/null
"$B" who --role z | has "sock.$ZC" || die "setup: SZ does not hold alpha:z"
zst(){ ps -o stat= -p "$ZC" 2>/dev/null | cut -c1; }   # ps, not /proc: macOS runs this section too
kill -9 "$ZC"; n=0; until [ "$(zst)" = Z ] || [ $n -gt 40 ]; do python3 -c "import time; time.sleep(0.1)"; n=$((n+1)); done
[ "$(zst)" = Z ] || die "setup: $ZC is not a zombie"
[ -z "$("$B" _procstart "$ZC")" ] && ok "a zombie has no process start: _procstart prints nothing" || die "zombie start: $("$B" _procstart "$ZC")"
! "$B" who --role z | has "sock.$ZC" && ok "board who does not list a session whose process is a zombie" || die "zombie listed: $("$B" who --role z)"
P1=$(fake S1 "$T/alpha" other); hook SessionStart "$T/alpha" S1 >/dev/null
python3 - "$SWITCHBOARD_DIR/roles" <<'PY' && ok "the next hook opens the zombie's role: its session is gone" || die "role not opened: $(cat "$SWITCHBOARD_DIR"/roles/*.json)"
import glob, json, sys
r = [json.load(open(f)) for f in glob.glob(sys.argv[1] + "/*.json")]
sys.exit(0 if any(x.get("role") == "z" and x.get("open") and x.get("why") == "its session is gone" for x in r) else 1)
PY
[ -n "$("$B" _procstart "$P1")" ] && "$B" who | has "sock.$P1" && ok "a running process still counts as live" || die "live process lost"

# item 16: the scan folders alone decide discovery: with none, no repo is registered and no scan starts, even on a
# board that is a git clone; with one, its repos are registered and scanned
mkrepo "$HOME/projects/realrepo"; rm -f "$SWITCHBOARD_STATE/daily.json"; git -C "$SWITCHBOARD_DIR" init -q -b main
( unset SWITCHBOARD_NOSCAN; hook SessionStart "$T/alpha" S1 >/dev/null )
[ -s "$SWITCHBOARD_STATE/daily.json" ] || die "setup: the daily pass did not run"
! grep -qs realrepo "$SWITCHBOARD_DIR"/registry/*.json && [ ! -e "$SWITCHBOARD_STATE/scan.json" ] \
  && ok "no scan folders: a board that is a git clone registers no repo and starts no scan, with SWITCHBOARD_NOSCAN unset" || die "discovered without scan folders: $(grep -l realrepo "$SWITCHBOARD_DIR"/registry/*.json) scan.json: $(cat "$SWITCHBOARD_STATE/scan.json" 2>/dev/null)"
rm -f "$SWITCHBOARD_STATE/daily.json"
# shellcheck disable=SC2088  # SWITCHBOARD_SCAN takes ~ unexpanded; the CLI expands it
( unset SWITCHBOARD_NOSCAN; SWITCHBOARD_SCAN="~/projects" hook SessionStart "$T/alpha" S1 >/dev/null )
n=0; until ls "$SWITCHBOARD_DIR"/subs/*.auto.east.json >/dev/null 2>&1 || [ $n -gt 40 ]; do python3 -c "import time; time.sleep(0.25)"; n=$((n+1)); done   # the scan runs detached
grep -qs realrepo "$SWITCHBOARD_DIR"/registry/*.json && [ -s "$SWITCHBOARD_STATE/scan.json" ] && ls "$SWITCHBOARD_DIR"/subs/*.auto.east.json >/dev/null 2>&1 \
  && ok "a scan folder (~/projects) registers realrepo and scans it" || die "scan folder: registry $(ls "$SWITCHBOARD_DIR/registry") scan $(cat "$SWITCHBOARD_STATE/scan.json" 2>/dev/null)"
rm -f "$SWITCHBOARD_STATE/daily.json" "$SWITCHBOARD_STATE/scan.json"; rm -f "$SWITCHBOARD_DIR"/registry/*realrepo*
# shellcheck disable=SC2088  # SWITCHBOARD_SCAN takes ~ unexpanded; the CLI expands it
SWITCHBOARD_SCAN="~/projects" hook SessionStart "$T/alpha" S1 >/dev/null
! grep -qs realrepo "$SWITCHBOARD_DIR"/registry/*.json && [ ! -e "$SWITCHBOARD_STATE/scan.json" ] && ok "SWITCHBOARD_NOSCAN stops discovery as well as scans" || die "NOSCAN did not stop discovery"
# shellcheck disable=SC2088  # SWITCHBOARD_SCAN takes ~ unexpanded; the CLI expands it
SWITCHBOARD_SCAN="~/projects" "$B" discover && grep -qs realrepo "$SWITCHBOARD_DIR"/registry/*.json && ok "switchboard discover by hand still registers" || die "discover by hand"
finish
