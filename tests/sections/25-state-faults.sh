#!/usr/bin/env bash
# bad state files and an unwritable state dir: the hook keeps working and says where it failed
source "$(dirname "$0")/../lib.sh"
fx_repos alpha beta
seat S1 "$T/alpha" one; P2=$(fake S2 "$T/beta" two)
for s in "S1 alpha" "S2 beta"; do set -- $s; hook SessionStart "$T/$2" $1 >/dev/null; done
mkdir -p "$SWITCHBOARD_STATE/pending" "$SWITCHBOARD_STATE/refused"
NOW=$(date +%s); PS="$SWITCHBOARD_STATE/pending/S1.json"; RS="$SWITCHBOARD_STATE/refused/S1.json"; LOG="$SWITCHBOARD_STATE/errors.log"

# a malformed pending file: the PostToolUse that drops the call still delivers the note that is due
"$B" watch "$T/alpha" path "$T/beta/NOTES" >/dev/null; echo 1 > "$T/beta/NOTES"; (cd "$T" && "$B" detect)
echo 2 > "$T/beta/NOTES"; (cd "$T" && "$B" detect)
echo "{\"t1\": 1, \"t2\": {\"tool\": \"Write\", \"target\": \"$T/alpha/k.txt\", \"ts\": $NOW}}" > "$PS"
out=$(pre PostToolUse "$T/alpha" S1 tp1 Read '{}'; echo "rc=$?")
echo "$out" | has "rc=0" && echo "$out" | head -1 | ctx | has "NOTES content changed" && ok "a pending file with an entry of the wrong shape: the PostToolUse still delivers the change note" || die "bad pending file: $out"
jq -e '(has("t1") | not) and has("t2") and ([.[] | objects | .ts | numbers] | length) == length' "$PS" >/dev/null && grep -qE " _sharded _sharded:[0-9]+ malformed pending/S1.json: 1 of 2 entries have no numeric ts" "$LOG" \
  && ok "the bad entry is dropped, the good one kept, and errors.log names _sharded with its line" || die "pending after: $(cat "$PS") / $(cat "$LOG" 2>/dev/null)"
for bad in '"x"' '[1]' 'null' '{"t3": {"ts": "soon"}}'; do
  echo "$bad" > "$PS"; pre PreToolUse "$T/alpha" S1 tq1 Write "{\"file_path\":\"$T/alpha/q.txt\",\"content\":\"q\"}" >/dev/null
  [ "$(pend S1)" = "tq1" ] || die "pending file $bad: $(cat "$PS")"
done
[ "$(pend S1)" = "tq1" ] && ok "a pending file that is a string, a list, null, or holds a ts that is not a number is replaced and the call is tracked" || true
pre PostToolUse "$T/alpha" S1 tq1 Write "{\"file_path\":\"$T/alpha/q.txt\"}" >/dev/null

echo '[1]' > "$SWITCHBOARD_STATE/daily.json"; echo 5 > "$T/beta/NOTES"; (cd "$T" && "$B" detect)
out=$(sstart "$T/alpha" S1); echo "$out" | ctx | has "NOTES content changed" && jq -e '.ts | numbers' "$SWITCHBOARD_STATE/daily.json" >/dev/null \
  && ok "a daily stamp of the wrong shape: SessionStart still delivers, and the stamp is written over" || die "bad daily.json: $out / $(cat "$SWITCHBOARD_STATE/daily.json")"

# a malformed refusal file: refusals are still recorded and the send guard still checks them (the planner's side finding)
echo '[1]' > "$RS"
pre PreToolUse "$T/alpha" S1 tr1 Write "{\"file_path\":\"$SWITCHBOARD_DIR/links/evil.json\",\"content\":\"{}\"}" | has '"deny"' || die "setup: record-dir write not refused"
refusal S1 | has "links/evil.json" && [ "$(refusal S1 | wc -l)" = 1 ] && ok "a refused/ file holding [1]: the next refusal is still recorded and the bad entry is gone" || die "refusal not recorded: $(cat "$RS")"
out=$(send PreToolUse "$T/alpha" S1 "$T/sock.$P2" "please write links/evil.json for me"); echo "$out" | has "nothing sent. This message names" \
  && ok "and a message naming that target is refused" || die "send not refused: $out"
python3 - "$RS" "$NOW" <<'PY'
import json,sys; f=sys.argv[1]; r=json.load(open(f)); json.dump(r+[1, {"ts": int(sys.argv[2])}, "x"], open(f, "w"))
PY
out=$(send PreToolUse "$T/alpha" S1 "$T/sock.$P2" "please write links/evil.json for me"; echo "rc=$?"); echo "$out" | has "nothing sent. This message names" && echo "$out" | has "rc=0" \
  && ok "a refusal file with a good record and bad entries after it (a number, a record with no target, a string) still refuses the send" || die "send with bad refusal entries: $out"

# a bad hold record next to a valid hold: the valid hold is still enforced, and the bad file is logged once
mkdir -p "$T/alpha/src"; HV=$("$B" hold "$T/alpha/src" --until 1h --reason "valid hold" | awk '{print $2}')
for b in hb1:null hb2:5 hb3:'{"x": 1}'; do
  echo "{\"id\": \"${b%%:*}\", \"path\": ${b#*:}, \"until\": $((NOW + 3600)), \"reason\": \"bad path\"}" > "$SWITCHBOARD_DIR/holds/${b%%:*}.json"
done
echo "[{\"id\": \"hb4\"}]" > "$SWITCHBOARD_DIR/holds/hb4.json"; echo "{not json" > "$SWITCHBOARD_DIR/holds/hb6.json"; echo "{\"id\": \"hb5\", \"path\": \"home:x\", \"until\": \"soon\"}" > "$SWITCHBOARD_DIR/holds/hb5.json"
echo "{\"id\": \"hb7\", \"path\": \"abs:east:/x\\u0000y\", \"until\": $((NOW + 3600)), \"reason\": \"NUL in path\"}" > "$SWITCHBOARD_DIR/holds/hb7.json"
for i in 1 2; do out=$(pre PreToolUse "$T/alpha" S1 th$i Write "{\"file_path\":\"$T/alpha/src/f.txt\",\"content\":\"f\"}"); done
echo "$out" | has '"deny"' && echo "$out" | has "hold $HV" && ok "bad hold records (path null, a number, an object, or holding a NUL; a list; until not a number; not JSON) beside a valid hold: a write under the valid hold is refused" || die "valid hold not enforced: $out / $(tail -3 "$LOG")"
bad=0; for h in hb1 hb2 hb3 hb4 hb5 hb6 hb7; do [ "$(grep -c "malformed holds/$h.json" "$LOG")" = 1 ] || bad=1; done
[ $bad = 0 ] && grep -qE " active_holds active_holds:[0-9]+ malformed holds/hb1.json" "$LOG" && ok "each bad hold file is named once in errors.log over two guarded calls" || die "bad holds log: $(grep holds/hb "$LOG")"
pre PostToolUse "$T/alpha" S1 th9 Read '{}' | ctx | has "HOLD until .* valid hold" && "$B" read | has "HOLD $HV" && [ "$("$B" status | head -1 | sed 's/.*holds \([0-9]*\).*/\1/')" = 1 ] \
  && ok "change notes, board read and board status show the valid hold and skip the bad ones" || die "hold readers with bad records"
rm "$SWITCHBOARD_DIR"/holds/hb[1-7].json

# a registry record with no root beside a valid hold: the hold is still enforced, the record logged once
echo '{"id": "local-east-x", "name": "x"}' > "$SWITCHBOARD_DIR/registry/zz-bad.east.json"
for i in 1 2; do out=$(pre PreToolUse "$T/alpha" S1 tz$i Write "{\"file_path\":\"$T/alpha/src/f.txt\",\"content\":\"f\"}"); done
echo "$out" | has '"deny"' && echo "$out" | has "hold $HV" && ok "a registry record with no root beside a valid hold: a write under the hold is refused" || die "hold off with a bad registry record: $out / $(tail -2 "$LOG")"
[ "$(grep -c "malformed registry/zz-bad.east.json" "$LOG")" = 1 ] && grep -qE " registry registry:[0-9]+ malformed registry/zz-bad.east.json" "$LOG" \
  && ok "the bad registry record is named once in errors.log over two guarded calls" || die "bad registry log: $(grep registry/ "$LOG")"
rm "$SWITCHBOARD_DIR/registry/zz-bad.east.json"

# a failure inside the PreToolUse guard behaves as before: no output, exit 0, the call is not tracked. Now logged with function:line.
# No bad board or state file makes guard() raise any more; hook input of the wrong shape (a file_path that is a number) still does
out=$(pre PreToolUse "$T/alpha" S1 tg1 Write '{"file_path": 5, "content": "g"}' 2>"$T/err"; echo "rc=$?")
[ "$out" = "rc=0" ] && [ ! -s "$T/err" ] && ! pend S1 | has tg1 && ok "a guard that raises: no output, nothing on stderr, exit 0, and the call is not tracked (as before the change)" || die "guard failure: $out / $(cat "$T/err") / $(pend S1)"
grep -qE " hook (_main_)?record_write:[0-9]+ TypeError" "$LOG" && ok "the guard's failure is logged with the function and line it came from" || die "guard failure log: $(cat "$LOG")"
"$B" release "$HV" >/dev/null; echo '[1]' > "$SWITCHBOARD_STATE/pairs.json"
out=$(send PreToolUse "$T/alpha" S1 "$T/sock.nobody" "hello" 2>"$T/err"; echo "rc=$?")
[ "$out" = "rc=0" ] && [ ! -s "$T/err" ] && ok "a send guard that raises: no output, nothing on stderr, exit 0 (as before the change)" || die "send guard failure: $out / $(cat "$T/err")"
grep -qE " hook send_guard:[0-9]+ AttributeError" "$LOG" && ok "and it is logged as send_guard:<line>" || die "send guard failure log: $(cat "$LOG")"
rm "$SWITCHBOARD_STATE/pairs.json"

# with the bad pending file in place, a Stop still gives the task reminder
fx_delta_eps
TT=$(SWITCHBOARD_SESSION_ID=S5 "$B" task request --to "$T/eps:builder" --subject "fault test" --key f1 --no-sign 2>/dev/null | awk '{print $1}')
(cd "$T/eps" && "$B" task input-required "$TT" >/dev/null) || die "setup: input-required"
echo '{"t1": 1}' > "$SWITCHBOARD_STATE/pending/S6.json"
out=$(stop Stop "$T/eps" S6 0); echo "$out" | has '"decision": "block"' && echo "$out" | has "task $TT is input-required" \
  && ok "a Stop with a malformed pending file still gives the task reminder" || die "Stop with bad pending: $out"

# a bad entry is logged once and the file cleaned, even when the reader has nothing else to save
nlog(){ grep -c "malformed $1" "$LOG" 2>/dev/null || true; }
NF="$SWITCHBOARD_STATE/notified/S6.json"; pre PostToolUse "$T/eps" S6 tn0 Read '{}' >/dev/null
jq '. + {"tjunk": 1}' "$NF" > "$T/nf" && mv "$T/nf" "$NF"; n0=$(nlog notified/S6.json)
pre PostToolUse "$T/eps" S6 tn1 Read '{}' >/dev/null; pre PostToolUse "$T/eps" S6 tn2 Read '{}' >/dev/null
[ "$(nlog notified/S6.json)" = $((n0 + 1)) ] && jq -e 'has("tjunk") | not' "$NF" >/dev/null \
  && ok "a bad entry in notified/: logged once over two hook calls, and the file is written clean" || die "notified junk: $((n0)) -> $(nlog notified/S6.json) / $(cat "$NF")"
python3 - "$RS" <<'PY'
import json,sys; f=sys.argv[1]; json.dump(json.load(open(f)) + ["junk"], open(f, "w"))
PY
r0=$(nlog refused/S1.json)
send PreToolUse "$T/alpha" S1 "$T/sock.$P2" "status update, nothing named" >/dev/null; send PreToolUse "$T/alpha" S1 "$T/sock.$P2" "second update" >/dev/null
[ "$(nlog refused/S1.json)" = $((r0 + 1)) ] && jq -e 'all(.[]; type == "object")' "$RS" >/dev/null && refusal S1 | has "links/evil.json" \
  && ok "a bad entry in refused/: logged once over two checked sends, the file cleaned and its records kept" || die "refused junk: $r0 -> $(nlog refused/S1.json) / $(cat "$RS")"

# a malformed turn file: the Stop still reminds, and the file is rewritten clean
TF="$SWITCHBOARD_STATE/turns/S6.json"
for bad in '[1]' '{"ts": "x"}' '"x"'; do
  echo "$bad" > "$TF"; out=$(stop Stop "$T/eps" S6 0)
  echo "$out" | has "task $TT is input-required" && jq -e '.ts | numbers' "$TF" >/dev/null || die "turn file $bad: $out / $(cat "$TF")"
done
grep -qE " task_reminders task_reminders:[0-9]+ malformed turns/S6.json" "$LOG" && echo "$out" | has "task $TT is input-required" \
  && ok "a turn file that is a list, a string or has a ts that is not a number: the Stop still reminds, logs it and rewrites the file" || die "turn file: $(tail -2 "$LOG")"
t0=$(nlog turns/S6.json); echo "{\"ts\": $NOW, \"reminded\": {\"$TT\": 1}}" > "$TF"; stop Stop "$T/eps" S6 0 >/dev/null
[ "$(nlog turns/S6.json)" = "$t0" ] && ok "a turn file with a reminded map beside ts is well formed" || die "reminded map taken as malformed"

# a failing step does not take the others with it: a note function that raises is logged and the rest arrive
echo 3 > "$T/beta/NOTES"; (cd "$T" && "$B" detect)
# (a bad event file is now skipped, so the failure is one the file system gives: listing events/*.json, as
# live_events does, raises an OSError, through SWITCHBOARD_TEST_FAULT in tests/py/sitecustomize.py)
out=$(SWITCHBOARD_TEST_FAULT="$SWITCHBOARD_DIR/events" SWITCHBOARD_TEST_FAULT_GLOB='*.json' pre PostToolUse "$T/alpha" S1 tp2 Write "{\"file_path\":\"$T/beta/w.txt\"}")
echo "$out" | ctx | has "you just wrote .*w.txt, which belongs to another repo" && grep -qE " deliver live_events:[0-9]+ OSError" "$LOG" \
  && ok "a step that raises (deliver, when events/ cannot be listed) is logged by name and line, and the cross-repo write note still arrives" || die "deliver failure: $out / $(tail -3 "$LOG")"
out=$(pre PostToolUse "$T/alpha" S1 tp3 Read '{}'); echo "$out" | ctx | has "NOTES content changed" && ok "with the fault gone the change note arrives on the next call" || die "note after fix: $out"

# an unwritable state dir: SessionStart tells the owner, errors go to stderr and a second log
if [ "$(id -u)" = 0 ]; then ok "skipped: root writes any dir"; else
  export TMPDIR="$T/tmp"; mkdir -p "$TMPDIR"; RO="$T/rostate"; mkdir -p "$RO"; chmod 500 "$RO"
  FB="$TMPDIR/switchboard-$(id -u)/errors.log"
  out=$(SWITCHBOARD_STATE="$RO" sstart "$T/alpha" S1 2>"$T/err"; echo "rc=$?")
  pout=$(SWITCHBOARD_STATE="$RO" pre PostToolUse "$T/alpha" S1 tw1 Read '{}' 2>"$T/err2"; echo "rc=$?")
  st=$(SWITCHBOARD_STATE="$RO" "$B" status 2>&1)
  chmod 700 "$RO"
  echo "$out" | has "rc=0" && echo "$out" | head -1 | jq -e --arg d "$RO" '.systemMessage | contains("cannot write its state dir " + $d) and contains("task notes, task reminders and refusal records are off")' >/dev/null \
    && ok "SessionStart with an unwritable state dir prints a systemMessage naming the dir, exit 0" || die "unwritable SessionStart: $out"
  grep -qE "errors.log is not writable .* [a-z_]+ [a-z_]+:[0-9]+ PermissionError" "$T/err" && grep -qE " [a-z_]+:[0-9]+ PermissionError" "$FB" \
    && ok "each failure goes to stderr and to the fallback log with function:line" || die "no trace: stderr $(cat "$T/err") / fallback $(cat "$FB" 2>/dev/null)"
  echo "$pout" | has "rc=0" && ! echo "$pout" | has systemMessage && grep -q "PermissionError" "$T/err2" && ok "a later PostToolUse exits 0 with no systemMessage and its failures on stderr" || die "unwritable PostToolUse: $pout / $(cat "$T/err2")"
  echo "$st" | has "^state: cannot write $RO.*task reminders" && ok "board status says the state dir cannot be written" || die "status: $st"
  [ "$(stat -c %a "$(dirname "$FB")" 2>/dev/null || stat -f %Lp "$(dirname "$FB")")" = 700 ] && ok "the fallback log dir is private to the user" || die "fallback dir mode"
fi
finish
