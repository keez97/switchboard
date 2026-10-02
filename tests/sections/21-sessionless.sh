#!/usr/bin/env bash
# without Claude Code's session file: events, holds, roles and tasks work with the session directory missing, empty
# or garbled, and with a valid file as before. Hooks and CLI calls run as children of a stand-in Claude process
# (tests/fakeclaude.py), so the board finds each session by walking the real process tree.
source "$(dirname "$0")/../lib.sh"
unset SWITCHBOARD_NOWALK
FC="$TESTS/fakeclaude.py"
claude(){ # name -> pid of a new stand-in Claude process listening on $T/fc-<name>.sock
  python3 "$FC" serve "$T/fc-$1.sock" >/dev/null 2>&1 </dev/null & local pid=$!; echo $pid >> "$T/pids"
  local n=0; until [ -S "$T/fc-$1.sock" ] || [ $n -gt 50 ]; do python3 -c "import time; time.sleep(0.1)"; n=$((n+1)); done
  echo $pid; }
under(){ # name cwd command: run the command as a child of that stand-in; stdin passes through
  python3 "$FC" run "$T/fc-$1.sock" "$2" "$3"; }
h(){ # name event cwd session [json with more fields]: a hook event, run the way Claude Code runs one
  local more="${5:-}"; [ -n "$more" ] || more='{}'
  python3 -c 'import json,sys; d={"hook_event_name":sys.argv[1],"cwd":sys.argv[2],"session_id":sys.argv[3]}; d.update(json.loads(sys.argv[4])); print(json.dumps(d))' "$2" "$3" "$4" "$more" | under "$1" "$3" "\"$B\" hook"; }
sessfile(){ # pid sid cwd: the session file Claude Code would write for that process
  python3 - "$1" "$2" "$3" "$("$B" _procstart "$1")" "$SWITCHBOARD_SESSIONS_DIR" "$T" <<'PY'
import json,sys
pid,sid,cwd,ps,d,t=sys.argv[1:7]
json.dump({"pid":int(pid),"sessionId":sid,"cwd":cwd,"name":"session "+sid,"procStart":ps,"messagingSocketPath":"%s/fc-W-file.sock"%t if sid.startswith("sW") else "%s/fc-R-file.sock"%t,
           "bridgeSessionId":"session_"+sid,"peerProtocol":1,"version":"9.9.9"},open("%s/%s.json"%(d,pid),"w"))
PY
}

scenario(){ # mode: missing | empty | garbled | file
  local m=$1 M="$T/$1"
  export SWITCHBOARD_DIR="$M/board" SWITCHBOARD_STATE="$M/state" SWITCHBOARD_SESSIONS_DIR="$M/sessions"
  mkdir -p "$SWITCHBOARD_DIR"; [ "$m" = missing ] || mkdir -p "$SWITCHBOARD_SESSIONS_DIR"
  for r in w r src; do mkrepo "$M/$r"; "$B" register "$M/$r" >/dev/null; done
  "$B" watch "$M/w" path "$M/src/VERSION" >/dev/null; echo 1 > "$M/src/VERSION"; (cd "$M/src" && "$B" detect)
  local W R; W=$(claude "W-$m"); R=$(claude "R-$m")
  if [ "$m" = file ]; then sessfile "$W" sW "$M/w"; sessfile "$R" sR "$M/r"; fi
  if [ "$m" = garbled ]; then   # not JSON, not an object, binary, a directory, and files naming both processes in a shape this code does not know
    local D="$SWITCHBOARD_SESSIONS_DIR"; echo '{"pid": 1, "sessionId": ' > "$D/junk.json"; echo '[1, 2, 3]' > "$D/list.json"
    head -c 64 /dev/urandom > "$D/bin.json"; mkdir -p "$D/dir.json"
    echo "{\"pid\": $W, \"sessionId\": \"sW\", \"procStart\": 5.5, \"messagingSocketPath\": 42, \"peerProtocol\": 1, \"name\": [\"x\"]}" > "$D/$W.json"
    echo "{\"pid\": \"$R\", \"sessionId\": \"sR\", \"peerProtocol\": 3, \"version\": \"99.0.0\"}" > "$D/$R.json"
  fi
  echo 2 > "$M/src/VERSION"; (cd "$M/src" && "$B" detect)
  h "W-$m" SessionStart "$M/w" sW '{"source": "startup"}' | ctx | has "src-[0-9a-f]*:VERSION content changed" && ok "[$m] a change event arrives on SessionStart" || die "[$m] SessionStart: $(h "W-$m" UserPromptSubmit "$M/w" sW '{"prompt": "x"}')"
  echo 3 > "$M/src/VERSION"; (cd "$M/src" && "$B" detect)
  h "W-$m" UserPromptSubmit "$M/w" sW '{"prompt": "go on"}' | ctx | has "src-[0-9a-f]*:VERSION content changed" && ok "[$m] a change event arrives on UserPromptSubmit" || die "[$m] UserPromptSubmit"
  echo 4 > "$M/src/VERSION"; (cd "$M/src" && "$B" detect)
  h "W-$m" PostToolUse "$M/w" sW '{"tool_name": "Read", "tool_input": {}, "tool_use_id": "u1"}' | ctx | has "src-[0-9a-f]*:VERSION content changed" && ok "[$m] a change event arrives on PostToolUse" || die "[$m] PostToolUse"
  local hid; hid=$("$B" hold "$M/src" --until 1h --reason "frozen for the test" | awk '{print $2}')
  h "W-$m" PreToolUse "$M/w" sW "{\"tool_name\": \"Edit\", \"tool_input\": {\"file_path\": \"$M/src/x\"}, \"tool_use_id\": \"u2\"}" | has "hold $hid: .* frozen until" && ok "[$m] a hold refuses an edit" || die "[$m] hold not enforced"
  "$B" release "$hid" >/dev/null
  h "R-$m" SessionStart "$M/r" sR '{"source": "startup"}' >/dev/null
  under "W-$m" "$M/w" "\"$B\" role worker" </dev/null | has -x "this session now holds role worker in w" && [ "$(jq -r .pid "$SWITCHBOARD_DIR"/roles/*--worker.json)" = "$W" ] \
    && [ "$(jq -r .procStart "$SWITCHBOARD_DIR"/roles/*--worker.json)" = "$("$B" _procstart "$W")" ] && ok "[$m] board role from a session binds the role to that session's process" || die "[$m] role: $(cat "$SWITCHBOARD_DIR"/roles/*--worker.json 2>&1)"
  local addr="to=-"; [ "$m" = file ] && addr="to=uds:$T/fc-W-file.sock"
  "$B" who --role worker | has "^east .* w .*role=worker .*$addr " && ok "[$m] board who lists the holder, with a to= address only from a session file" || die "[$m] who: $("$B" who)"
  under "R-$m" "$M/r" "\"$B\" me" </dev/null | has -x "session sR repo=r role=-" && (cd "$M/w" && "$B" me) | has -x "terminal repo=w" && ok "[$m] a CLI call finds its own session through the process tree; a terminal finds none" || die "[$m] me: $(under "R-$m" "$M/r" "\"$B\" me" </dev/null)"
  local tid; tid=$(under "R-$m" "$M/r" "\"$B\" task request --to $M/w:worker --subject 'sessionless check' --key k-$m --no-sign" </dev/null | awk '{print $1}')
  h "W-$m" PostToolUse "$M/w" sW '{"tool_name": "Read", "tool_input": {}, "tool_use_id": "u3"}' | ctx | has "a task for you (you hold w:worker): $tid \"sessionless check\" from r (no role)" && ok "[$m] the role holder gets the task note" || die "[$m] no task note for $tid"
  under "W-$m" "$M/w" "\"$B\" task $tid" </dev/null >/dev/null; "$B" task "$tid" | has "^  notified east [0-9:]*; seen east [0-9:]*$" && ok "[$m] board task <tid> from the holder marks it seen" || die "[$m] seen: $("$B" task "$tid")"
  [ "$m" != file ] || python3 - "$SWITCHBOARD_SESSIONS_DIR/$W.json" <<'PY'   # a clear: Claude Code's file names the new session
import json,sys; f=sys.argv[1]; d=json.load(open(f)); d["sessionId"]="sW2"; json.dump(d,open(f,"w"))
PY
  h "W-$m" SessionEnd "$M/w" sW '{"reason": "clear"}' >/dev/null; h "W-$m" SessionStart "$M/w" sW2 '{"source": "clear"}' >/dev/null
  under "W-$m" "$M/w" "\"$B\" me" </dev/null | has -x "session sW2 repo=w role=worker" && [ "$("$B" who "$M/w" | grep -c "role=worker")" = 1 ] && ok "[$m] after a clear in the same process the CLI speaks for the new session id and the role stays" || die "[$m] clear: $(under "W-$m" "$M/w" "\"$B\" me" </dev/null); $("$B" who)"
  if [ "$m" = file ]; then   # a hook for another session id in the same process: the file still names the session
    h "W-$m" PostToolUse "$M/w" sX '{"tool_name": "Read", "tool_input": {}, "tool_use_id": "u4"}' >/dev/null
    under "W-$m" "$M/w" "\"$B\" me" </dev/null | has -x "session sW2 repo=w role=worker" && ok "[$m] the session file names the session in its process over the newest id the hooks recorded there" || die "[$m] newest id won over the file: $(under "W-$m" "$M/w" "\"$B\" me" </dev/null)"
  fi
  if [ "$m" = garbled ]; then
    ! grep -lq "session file" "$SWITCHBOARD_DIR"/events/*.json 2>/dev/null && ok "[$m] a session file in an unknown shape is passed over and raises no event" || die "[$m] format event"
  fi
  [ ! -s "$SWITCHBOARD_STATE/errors.log" ] && ok "[$m] no hook or CLI call logged an error" || die "[$m] errors: $(cat "$SWITCHBOARD_STATE/errors.log")"
  python3 "$FC" quit "$T/fc-W-$m.sock"; python3 "$FC" quit "$T/fc-R-$m.sock"
}
for m in missing empty garbled file; do scenario $m; done

finish
