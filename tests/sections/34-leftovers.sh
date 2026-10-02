#!/usr/bin/env bash
# bad role, session and event files; transitions sharing one number; one task record added on two machines in one
# sync window
source "$(dirname "$0")/../lib.sh"
ln -s "$B" "$HOME/.claude/board"   # the task driver runs "$HOME/.claude/board", as on a real machine
LOG="$SWITCHBOARD_STATE/errors.log"
fx_link1   # S1 holds alpha:roadmap, S2 beta:implementer, S3 gamma:implementer; link LID alpha:roadmap -> beta:implementer
R="$SWITCHBOARD_DIR/roles"; S="$SWITCHBOARD_DIR/sessions"
GAMMA=$(basename "$(grep -l '"session_id": "S3"' "$R"/*.json | head -1)"); GAMMA=${GAMMA%%--*}   # gamma's slug in role file names
[ -n "$GAMMA" ] || die "setup: gamma's role file"
lines(){ grep -c "malformed $1" "$LOG" 2>/dev/null || true; }
others(){ grep -v " malformed \(roles\|sessions\|events\)/[^ ]*: .*; skipped$" "$LOG" 2>/dev/null || true; }   # any line but the bad-record ones
: > "$LOG"

# ---- role files that are JSON but not an object, among the good ones
echo '[1]' > "$R/zz-list.json"; echo '"x"' > "$R/zz-str.json"; echo '5' > "$R/zz-num.json"; echo 'null' > "$R/zz-null.json"
out=$(up "$T/beta" S2 "$(peer "$T/sock.$P1" road "next: build Y")" | ctx)
echo "$out" | has "bound to link $LID as implementer" && echo "$out" | has "This message arrives over link $LID" \
  && ok "with four role files that are not objects, a bound session still gets its link notes" || die "notes: $out / $(others)"
hook PostToolUse "$T/alpha" S1 Read '{}' >/dev/null; hook PostToolUse "$T/gamma" S3 Read '{}' >/dev/null
up "$T/beta" S2 "$(peer "$T/sock.$P1" road "again")" | ctx | has "This message arrives over link $LID" || die "second message lost its link note"
n=$(for f in list str num null; do lines "roles/zz-$f.json"; done | tr '\n' ' ')
[ "$n" = "1 1 1 1 " ] && grep -qE " role_of role_of:[0-9]+ malformed roles/zz-list.json: not a JSON object; skipped" "$LOG" \
  && ok "each bad role file is logged once, by the reader that found it, over several hooks" || die "log counts: $n / $(cat "$LOG")"
[ -z "$(others)" ] && ok "no hook step failed on them: errors.log holds the bad-record lines only" || die "other errors: $(others)"
echo '[2]' > "$R/zz-list.json"; touch -d '+1 min' "$R/zz-list.json"; hook PostToolUse "$T/beta" S2 Read '{}' >/dev/null
[ "$(lines roles/zz-list.json)" = 2 ] && [ "$(cat "$R/zz-str.json")" = '"x"' ] && [ -e "$R/zz-null.json" ] \
  && ok "a new version of a bad file is logged again; the files stay as they are" || die "relog: $(lines roles/zz-list.json)"
w=$("$B" who || true)
echo "$w" | has "role=implementer .*(impl)" && echo "$w" | has "role=roadmap .*(road)" && ok "board who lists the live sessions and their roles" || die "who: $w"
SWITCHBOARD_SESSION_ID=S3 "$B" role spare >/dev/null && "$B" who --role spare | has "(other)" \
  && ok "board role binds a role beside them" || die "role spare: $("$B" who)"
echo '[1]' > "$R/$GAMMA--extra.json"
SWITCHBOARD_SESSION_ID=S3 "$B" role extra >/dev/null && jq -e '.session_id == "S3"' "$R/$GAMMA--extra.json" >/dev/null \
  && ok "board role on a role whose own file is not an object: the end reads as open, and binding it writes a good record" || die "role extra: $(cat "$R/$GAMMA--extra.json")"
send_end "$T/gamma" S3 other >/dev/null
jq -e '.open and .was == "S3"' "$R/$GAMMA--extra.json" >/dev/null && [ -z "$(others)" ] \
  && ok "a session that ends releases its role with the bad files beside it" || die "release: $(cat "$R/$GAMMA--extra.json") / $(others)"

# ---- session records that are JSON but not an object
echo '[1]' > "$S/west-zz.json"; echo '5' > "$S/east-zz.json"
out=$(up "$T/beta" S2 "$(peer "$T/sock.$P1" road "with bad sessions")" | ctx)
hook SessionStart "$T/alpha" S1 >/dev/null; hook PostToolUse "$T/alpha" S1 Read '{}' >/dev/null
echo "$out" | has "This message arrives over link $LID" && [ "$(lines sessions/west-zz.json)" = 1 ] && [ "$(lines sessions/east-zz.json)" = 1 ] \
  && [ -z "$(others)" ] && ok "with session records that are not objects the link note stands, each is logged once and no step fails" \
  || die "sessions: $out / $(grep sessions/ "$LOG") / $(others)"
"$B" who | has "role=implementer .*(impl)" && SWITCHBOARD_SESSION_ID=S1 "$B" role second >/dev/null && "$B" who --role second | has "(road)" \
  && [ "$(cat "$S/west-zz.json")" = '[1]' ] && ok "board who and board role work beside them, and the files stay" || die "who/role: $("$B" who)"
"$B" status >/dev/null && [ -z "$(others)" ] || die "status with bad records: $(others)"
BETA=$(jq -r 'objects | select(.session_id == "S2") | .repo' "$R"/*.json 2>/dev/null | head -1 || true); IMPL=$(grep -l '"session_id": "S2"' "$R"/*.json | head -1)
[ -n "$BETA" ] && [ -n "$IMPL" ] || die "setup: beta's id and S2's role file"

# each block below starts with no bad file left from the ones before, so it shows its own case alone
rm -f "$R"/zz-*.json "$R/$GAMMA--extra.json" "$S"/*-zz.json; : > "$LOG"

# ---- role files that are objects with fields of another type
SWITCHBOARD_SESSION_ID=S1 "$B" role roadmap >/dev/null || die "setup: S1 back to alpha:roadmap"   # it took alpha:second above
jq '.since = "soon"' "$IMPL" > "$R/zz-since.json"                                    # S2's own seat, a since that is text
echo "{\"repo\": [1], \"role\": \"y\", \"machine\": \"east\"}" > "$R/zz-repo.json"   # reap's own-machine pass
echo "{\"repo\": \"$BETA\", \"role\": \"z\", \"session_id\": 5}" > "$R/zz-sid.json"   # no pid: seat_of goes by session id
echo "{\"repo\": \"$BETA\", \"role\": \"w\", \"open\": 5, \"was_machine\": \"east\", \"was_host\": \"\", \"why\": {}}" > "$R/zz-why.json"
echo "{\"role\": \"v\"}" > "$R/zz-norepo.json"
out=$(up "$T/beta" S2 "$(peer "$T/sock.$P1" road "with typed roles")" | ctx); hook SessionStart "$T/beta" S2 >/dev/null
hook PostToolUse "$T/beta" S2 Read '{}' >/dev/null; w=$("$B" who || true)
n=$(for f in since repo sid why norepo; do lines "roles/zz-$f.json"; done | tr '\n' ' ')
echo "$out" | has "This message arrives over link $LID" && echo "$w" | has "role=implementer .*(impl)" && [ "$n" = "1 1 1 1 1 " ] \
  && grep -q "malformed roles/zz-since.json: since missing or of another type; skipped" "$LOG" && [ -z "$(others)" ] \
  && ok "role files with a field of another type or no repo read as none: link notes and who stand, each logged once" \
  || die "typed roles: $out / $n / $w / $(others)"
SWITCHBOARD_SESSION_ID=S2 "$B" role spare2 >/dev/null && "$B" who --role spare2 | has "(impl)" && "$B" status >/dev/null && [ -z "$(others)" ] \
  && ok "board role and board status work beside them" || die "role beside typed roles: $(others)"
rm -f "$R"/zz-*.json; : > "$LOG"; SWITCHBOARD_SESSION_ID=S2 "$B" role implementer >/dev/null || die "setup: S2 back to implementer"

# ---- event files that are not events, beside a good one
NOW=$(date +%s); EV="$SWITCHBOARD_DIR/events"
ev(){ echo "{\"id\": $2, \"ts\": $3, \"machine\": \"east\", \"kind\": \"change\", \"target\": \"t\", \"summary\": \"$1\", \"affects\": $4, \"expires\": $5, \"observer\": {\"session\": \"\", \"repo\": \"\"}}"; }
ev "good event" '"20990101T000000-east-good000001"' "$NOW" "[\"$BETA\"]" $((NOW + 999)) > "$EV/20990101T000000-east-good000001.json"
echo 'nope' > "$EV/zz-1.json"; echo 'null' > "$EV/zz-2.json"; echo '[1]' > "$EV/zz-3.json"
ev "bad id" 5 "$NOW" "[\"$BETA\"]" $((NOW + 999)) > "$EV/zz-4.json"
ev "bad ts" '"20990101T000000-east-zz5"' '"x"' "[\"$BETA\"]" $((NOW + 999)) > "$EV/zz-5.json"
ev "bad expires" '"20990101T000000-east-zz6"' "$NOW" "[\"$BETA\"]" '"later"' > "$EV/zz-6.json"
ev "bad affects" '"20990101T000000-east-zz7"' "$NOW" '"all"' $((NOW + 999)) > "$EV/zz-7.json"
out=$(hook PostToolUse "$T/beta" S2 Read '{}' | ctx); rd=$("$B" read --repo beta 2>&1 || true); "$B" status >/dev/null || true
n=$(for i in 1 2 3 4 5 6 7; do lines "events/zz-$i.json"; done | tr '\n' ' ')
echo "$out" | has "good event" && ! echo "$out" | has "bad " && echo "$rd" | has "good event" && [ "$n" = "1 1 1 1 1 1 1 " ] \
  && grep -qE " live_events live_events:[0-9]+ malformed events/zz-5.json: ts missing or of another type; skipped" "$LOG" && [ -z "$(others)" ] \
  && ok "event files that are not events are skipped and logged once each over three reads; the good event is delivered" \
  || die "events: $out / $rd / $n / $(others)"
rm -f "$EV"/zz-*.json; : > "$LOG"

# ---- transitions that share one number, and a ts that is not a number
TO="$T/beta:implementer"
rq(){ SWITCHBOARD_SESSION_ID=S1 "$B" task request --to "$TO" --subject "$1" --key "$1" --no-sign | awk '{print $1}'; }
tr_(){ # task id, number (one digit), state, machine, ts as JSON (null: none): a transition written as task_transition writes one
  jq -n --arg id "$1" --argjson n "$2" --arg s "$3" --arg m "$4" --argjson ts "$5" \
    '{id: $id, seq: $n, state: $s, note: "", artifacts: [], session: "", machine: $m, ts: $ts} | if $ts == null then del(.ts) else . end' > "$TH/$1/00$2-$3.json"; }
st(){ "$B" task "$1" --json | jq -r "$2"; }
TA=$(rq order-a); TH=$(dirname "$(ls -d "$SWITCHBOARD_DIR"/tasks/*/"$TA")")
tr_ "$TA" 1 rejected west $((NOW + 20)); tr_ "$TA" 1 working east $((NOW + 10))
TB2=$(rq order-b); tr_ "$TB2" 1 working east $((NOW + 10)); tr_ "$TB2" 2 completed east $((NOW + 30)); tr_ "$TB2" 2 failed west null; tr_ "$TB2" 2 rejected west '"soon"'
[ "$(st "$TA" .state)" = rejected ] && [ "$(st "$TA" '.transitions[-1].machine')" = west ] \
  && "$B" tasks --for "$TO" | has "$TA  rejected" \
  && ok "two transitions at one number: the later ts is the state, in board task --json, its last transition and board tasks" \
  || die "order-a: $(st "$TA" .state) $(st "$TA" '.transitions[-1].machine')"
[ "$(st "$TB2" .state)" = completed ] && [ "$(st "$TB2" '[.transitions[].state] | join(",")')" = "working,failed,completed" ] \
  && [ "$(st "$TB2" '.bad_records | join(",")')" = 002-rejected.json ] \
  && { "$B" task "$TB2" || true; } | has "002-rejected.json  BAD RECORD: ts missing or of another type" && [ -z "$(others)" ] \
  && ok "a transition with no ts sorts first within its number; one whose ts is text is a bad record; nothing raises" \
  || die "order-b: $(st "$TB2" '[.transitions[].state]') $(st "$TB2" .bad_records) / $(others)"
TC=$(rq order-c); tr_ "$TC" 1 input-required east $((NOW + 20)); tr_ "$TC" 1 working west $((NOW + 10))
r=$(stop Stop "$T/beta" S2 0 | jq -r .reason 2>/dev/null)
echo "$r" | has "task $TC is input-required" && ! echo "$r" | has "task $TC is working" \
  && ok "the Stop reminder names the state of the later of two transitions at one number" || die "reminder: $r"

# ---- task records with fields of another type: each a bad record, never a crash, in every reader
: > "$LOG"
TE=$(rq typed-e); TF=$(rq typed-f)
jq -n --arg id "$TE" --argjson ts "$NOW" '{id: $id, seq: 1, state: "working", note: ["x"], artifacts: [], session: "", machine: "east", ts: $ts}' > "$TH/$TE/001-working.json"
jq -n --arg id "$TE" --argjson ts "$NOW" '{id: $id, seq: 2, state: "input-required", note: "", waiting_on: {}, artifacts: [], session: "", machine: "east", ts: ($ts + 1)}' > "$TH/$TE/002-input-required.json"
jq -n --arg id "$TE" --argjson ts "$NOW" '{id: $id, seq: 3, state: "completed", note: "", artifacts: ["x"], session: "", machine: "east", ts: ($ts + 2)}' > "$TH/$TE/003-completed.json"
jq -n --arg id "$TE" --argjson ts "$NOW" '{id: $id, seq: 4, state: 5, note: "", artifacts: [], session: "", machine: "east", ts: ($ts + 3)}' > "$TH/$TE/004-failed.json"
jq -n --arg id "$TE" '{id: $id, note: "", requester: "x", session: "", machine: "east", ts: "y"}' > "$TH/$TE/cancel-requested.json"
jq '.requester = "x"' "$TH/$TF/000-request.json" > "$T/req.json" && mv "$T/req.json" "$TH/$TF/000-request.json"   # a request whose requester is text
tv=$("$B" task "$TE" 2>&1 || true); tj=$("$B" task "$TE" --json 2>&1 || true); tl=$("$B" tasks --for "$TO" 2>&1 || true)
nt=$(up "$T/beta" S2 "next" | ctx); r=$(stop Stop "$T/beta" S2 0 || true); tf=$("$B" task "$TF" 2>&1 || true)
echo "$tj" | jq -e '.state == "?" and (.bad_records | length) == 5 and .transitions == []' >/dev/null \
  && [ "$(echo "$tv" | grep -c "BAD RECORD: .* missing or of another type")" = 5 ] && echo "$tl" | has "$TE .*BAD RECORD" \
  && echo "$tf" | has "000-request.json  BAD RECORD: requester missing or of another type" && echo "$tl" | has "$TF .*BAD RECORD" \
  && ! echo "$nt" | has "a task for you.*$TF" && [ -z "$(others)" ] \
  && ok "transitions with a note, waiting_on, artifact or state of another type, a cancel and a request with fields of another type: each a bad record in task, task --json and tasks; no note, reminder or step raises" \
  || die "typed tasks: $tj / $tv / $tl / $tf / $nt / $(others)"
rm -rf "${TH:?}/$TE" "${TH:?}/$TF"

# ---- a request that does not read when a hook looks (empty, as in a checkout) is looked at again, not dropped for good
: > "$LOG"; TN=$(rq notes-n); cp "$TH/$TN/000-request.json" "$T/req-n.json"; : > "$TH/$TN/000-request.json"
n1=$(up "$T/beta" S2 "first" | ctx); cp "$T/req-n.json" "$TH/$TN/000-request.json"; n2=$(up "$T/beta" S2 "second" | ctx)
! echo "$n1" | has "a task for you.*$TN" && echo "$n2" | has "a task for you.*$TN" && [ -z "$(others)" ] \
  && ok "a request that reads empty gets no task note that call, and gets it once it reads" || die "task note: $n1 / $n2 / $(others)"

# ---- session records that are objects with fields of another type
: > "$LOG"; PS2=$("$B" _procstart "$P2")
echo "{\"session_id\": \"Z1\", \"machine\": \"west\", \"repo\": \"$BETA\", \"bridge\": \"b1\", \"started\": 1, \"seen\": \"x\"}" > "$S/west-zt1.json"
echo "{\"session_id\": \"Z2\", \"machine\": \"east\", \"repo\": \"$BETA\", \"pid\": $P2, \"procStart\": \"$PS2\", \"uds\": 5, \"started\": \"x\"}" > "$S/east-zt2.json"
echo "{\"session_id\": 7, \"machine\": \"east\", \"repo\": \"$BETA\"}" > "$S/east-zt3.json"
echo "{\"session_id\": \"Z4\", \"machine\": \"west\", \"repo\": [\"x\"], \"bridge\": \"b4\", \"started\": 1, \"seen\": $NOW}" > "$S/west-zt4.json"
echo "{\"session_id\": \"Z5\", \"machine\": \"west\", \"bridge\": \"b5\", \"started\": 1, \"seen\": $NOW, \"name\": [1]}" > "$S/west-zt5.json"
out=$(up "$T/beta" S2 "$(peer "$T/sock.$P1" road "with typed sessions")" | ctx); hook SessionStart "$T/alpha" S1 >/dev/null
hook PostToolUse "$T/beta" S2 Read '{}' >/dev/null; w=$("$B" who 2>&1 || true); "$B" status >/dev/null 2>&1 || true
n=$(for i in 1 2 3 4 5; do lines "sessions/[a-z]*-zt$i.json"; done | tr '\n' ' ')
echo "$out" | has "This message arrives over link $LID" && echo "$w" | has "role=implementer .*(impl)" && ! echo "$w" | has "Z[1-5]" \
  && [ "$n" = "1 1 1 1 1 " ] && [ -z "$(others)" ] \
  && ok "session records with a seen, started, uds, session_id, repo or name of another type, or no repo, read as absent: notes and who stand, each logged once" \
  || die "typed sessions: $out / $w / $n / $(others)"
SWITCHBOARD_SESSION_ID=S2 "$B" role spare3 >/dev/null && "$B" who --role spare3 | has "(impl)" && [ -z "$(others)" ] \
  && [ "$(jq -c . "$S/east-zt3.json")" = "{\"session_id\":7,\"machine\":\"east\",\"repo\":\"$BETA\"}" ] \
  && ok "board role works beside them and the files stay as they are" || die "role beside typed sessions: $(others)"
rm -f "$S"/*-zt*.json; : > "$LOG"
SWITCHBOARD_SESSION_ID=S2 "$B" role implementer >/dev/null || die "setup: S2 back to implementer"

# ---- SessionEnd with this machine's own session file not an object: the role still opens and the sync still runs
: > "$LOG"; seat S7 "$T/gamma" lone; hook SessionStart "$T/gamma" S7 >/dev/null
SWITCHBOARD_SESSION_ID=S7 "$B" role lone >/dev/null || die "setup: S7 takes gamma:lone"
echo '[1]' > "$S/east-S7.json"
# the board becomes a clone of a bare remote, as in section 15: the release must reach the remote by the hook's own sync
git init -q --bare -b main "$T/se-remote.git"; git -C "$SWITCHBOARD_DIR" init -q -b main
git -C "$SWITCHBOARD_DIR" config user.email t@t; git -C "$SWITCHBOARD_DIR" config user.name t
git -C "$SWITCHBOARD_DIR" remote add origin "$T/se-remote.git"; git -C "$SWITCHBOARD_DIR" commit -q --allow-empty -m init
git -C "$SWITCHBOARD_DIR" push -q -u origin main; rm -f "$SWITCHBOARD_STATE/sync.ok" "$SWITCHBOARD_STATE/sync.fail"
export SWITCHBOARD_NOSYNC=; send_end "$T/gamma" S7 other >/dev/null; export SWITCHBOARD_NOSYNC=1
waitfor "$SWITCHBOARD_STATE/sync.ok"
pushed=$(git -C "$T/se-remote.git" show "main:roles/$GAMMA--lone.json" 2>/dev/null || true)
jq -e '.open and .was == "S7"' "$R/$GAMMA--lone.json" >/dev/null && [ "$(cat "$S/east-S7.json")" = '[1]' ] \
  && [ "$(lines sessions/east-S7.json)" = 1 ] && [ -z "$(others)" ] && echo "$pushed" | jq -e '.open and .was == "S7"' >/dev/null \
  && ok "SessionEnd with its own session file not an object: logged, the file stays, the role opens and its sync pushes the release" \
  || die "session end: $(cat "$R/$GAMMA--lone.json") / pushed: $pushed / $("$B" status | grep sync:) / $(others)"

# ---- merge-task given the temp file names git gives a driver, and one task record added on two machines
binit "$T/files"
# shellcheck disable=SC2034  # FAILED is read by lib.sh's finish
python3 - "$B" "$T" "$T/files/.gitattributes" <<'PY' || FAILED=1
import glob, json, os, re, shlex, shutil, subprocess, sys, time
B, T, ATTR = sys.argv[1:4]
DRV = ("sh -c 'c=$1; shift; if [ -L \"$c\" ] && [ -x \"$c\" ]; then exec \"$c\" %s \"$@\"; fi; "
       "if [ -x \"$HOME/.claude/board\" ]; then exec \"$HOME/.claude/board\" %s \"$@\"; fi; "
       "exec git merge-file \"$2\" \"$1\" \"$3\"' switchboard %s %s")
tdriver = lambda st: DRV % ("merge-task", "merge-task", shlex.quote(st + "/cli"), "%O %A %B %P")  # st: that machine's state dir
NOW, failed, P = int(time.time()), [], [""]


def ok(cond, what, why=""):
    print("  ok   " + what if cond else "  FAIL %s%s" % (what, ": " + why if why else ""))
    failed.extend([] if cond else [what])


def setup(cond, what):
    if not cond:
        print("  FAIL setup: " + what)
        sys.exit(1)


def run(args, cwd=None, inp=None, **env):
    r = subprocess.run(args, cwd=cwd, input=inp, env=dict(os.environ, **env), capture_output=True, text=True)
    return r.returncode, r.stdout


def git(d, *a):
    return run(["git", "-C", d, "-c", "user.email=t@t", "-c", "user.name=t"] + list(a))


def write(f, text):
    with open(f, "w") as fh:
        fh.write(text)


def read(f):
    try:
        return open(f).read()
    except OSError:
        return ""


rec = lambda **k: json.dumps(k, indent=1, sort_keys=True) + "\n"  # write_once's format
U, US = T + "/unit", T + "/unit-state"
os.makedirs(U)


def mt(o, a, t, path="tasks/w--r/t00000001/001-working.json"):
    for n, v in (("o", o), (".merge_file_a", a), ("t", t)):
        write(U + "/" + n, v)
    return run([B, "merge-task", "o", ".merge_file_a", "t", path], cwd=U, SWITCHBOARD_STATE=US)[0], read(U + "/.merge_file_a")


dropped = lambda: sorted(os.listdir(US + "/dropped")) if os.path.isdir(US + "/dropped") else []
early, late = rec(id="t1", seq=1, state="working", machine="east", ts=100), rec(id="t1", seq=1, state="working", machine="west", ts=200)
r1, r2 = mt("", early, late), mt("", late, early)
ok(r1 == r2 == (0, early) and dropped() == ["tasks__w--r__t00000001__001-working.json.200.json"] and
   read(US + "/dropped/" + dropped()[0]) == late,
   "merge-task: an add on both sides keeps the earlier ts whole, from either side, and the other is kept in STATE/dropped",
   "%s %s %s" % (r1, r2, dropped()))
log = read(US + "/errors.log")
ok(len(log.splitlines()) == 1 and "001-working.json" in log and "kept the record of east (ts 100)" in log,
   "merge-task: one log line names the path and the winner, though the merge ran twice", log)
a, b = rec(id="t1", ts=100, note="a"), rec(id="t1", ts=100, note="b")
r1, r2 = mt("", a, b, "tasks/w--r/t1/cancel-requested.json"), mt("", b, a, "tasks/w--r/t1/cancel-requested.json")
ok(r1 == r2 == (0, b), "merge-task: a tie in ts goes to the larger JSON text, the same bytes from either side", "%s %s" % (r1, r2))
ok(mt("", early, early)[0] == 0 and len(dropped()) == 2, "merge-task: the same record on both sides merges, and drops nothing", str(dropped()))
cases = [("", "nope", late), ("", early, "[1]"), ("", rec(id="t1", state="working"), late), (rec(id="t1", ts=50), early, late),
         ("", early, late, ""), ("", early, late, "tasks/w--r/t00000001/000-request.json")]
rcs = [mt(*c) for c in cases]
ok([r[0] for r in rcs] == [1] * 6 and all("<<<<<<< ours" in r[1] for r in rcs) and len(dropped()) == 2,
   "merge-task: bad JSON, a side that is no object, no ts, a base that is not empty, no path, or a request: exit 1 with git's markers",
   str(rcs))
write(U + "/001-working.json", early); write(U + "/other.json", late)
rc = run([B, "merge-task", "o", "001-working.json", "other.json", "tasks/w--r/t1/001-working.json"], cwd=U, SWITCHBOARD_STATE=US)[0]
ok(rc == 1 and read(U + "/001-working.json") == early and len(dropped()) == 2,
   "merge-task run by hand on a record, not git's temp file: exit 1, the record and STATE untouched", "rc %d" % rc)


# ---- two clones of one bare remote
def clone(m):
    return "%s/%s-%s" % (T, P[0], m)


def state(m):
    return "%s/%s-state-%s" % (T, P[0], m)


def on(m, args, cwd=None, **env):
    return run([B] + args, cwd=cwd, SWITCHBOARD_DIR=clone(m), SWITCHBOARD_STATE=state(m), SWITCHBOARD_MACHINE=m, **env)


def syncw(m, front=False):  # one sync, finished when this returns; front: board sync, which sets the drivers first
    for f in ("sync.ok", "sync.fail"):
        if os.path.exists(state(m) + "/" + f):
            os.remove(state(m) + "/" + f)
    on(m, ["sync" if front else "sync-job"], SWITCHBOARD_NOSYNC="")
    for _ in range(120 if front else 0):
        if not os.path.isdir(state(m) + "/sync.lock") and any(os.path.exists(state(m) + "/" + f) for f in ("sync.ok", "sync.fail")):
            break
        time.sleep(0.25)


def round_():  # the first pushes, the second merges onto it and pushes, the first catches up
    for m in ("east", "west", "east"):
        syncw(m)


def status(m):
    return on(m, ["status"])[1]


def clean(m):
    s = [x for x in status(m).splitlines() if x.startswith("sync:")]
    return os.path.exists(state(m) + "/sync.ok") and not os.path.exists(state(m) + "/sync.fail") and \
        not git(clone(m), "diff", "--name-only", "--diff-filter=U")[1].strip() and s and "last failure" not in s[0]


def same(rel):
    return read("%s/%s" % (clone("east"), rel)) == read("%s/%s" % (clone("west"), rel)) != "" and \
        git(clone("east"), "rev-parse", "HEAD")[1] == git(clone("west"), "rev-parse", "HEAD")[1]


for r in ("wa", "wb"):  # a remote gives each repo the same id on both machines
    os.makedirs(T + "/" + r); git(T + "/" + r, "init", "-q", "-b", "main"); git(T + "/" + r, "commit", "-q", "--allow-empty", "-m", "init")
    git(T + "/" + r, "remote", "add", "origin", "https://example.com/t/%s.git" % r)


def pair(name, signers=""):
    """A bare remote seeded with the .gitattributes init writes (and keys/allowed_signers when given), a clone per
    machine with wa and wb registered, each synced by board sync, which sets the merge drivers."""
    P[0] = name
    bare, seed = "%s/%s.git" % (T, name), "%s/%s-seed" % (T, name)
    run(["git", "init", "-q", "--bare", "-b", "main", bare]); run(["git", "clone", "-q", bare, seed])
    shutil.copy(ATTR, seed); os.makedirs(seed + "/links"); write(seed + "/links/seed.log.jsonl", '{"line":"seed"}\n')
    if signers:
        os.makedirs(seed + "/keys"); write(seed + "/keys/allowed_signers", signers)
    git(seed, "add", "-A"); git(seed, "commit", "-qm", "seed"); git(seed, "push", "-q", "origin", "HEAD:main")
    for m in ("east", "west"):
        run(["git", "clone", "-q", bare, clone(m)])
        run(["git", "-C", clone(m), "config", "user.email", "t@t"]); run(["git", "-C", clone(m), "config", "user.name", m])
        on(m, ["register", T + "/wa"]); on(m, ["register", T + "/wb"])
    for m in ("east", "west", "east"):
        syncw(m, front=True)


pair("task")
drv = [git(clone(m), "config", "merge.board-task.driver")[1].strip() for m in ("east", "west")]
ok(drv == [tdriver(state(m)) for m in ("east", "west")], "board sync sets the board-task merge driver in the .git/config of each clone", str(drv))
t = "tasks/w--r/t00000001/"
attrs = git(clone("east"), "check-attr", "merge", "--", t + "000-request.json", t + "000-request.sig", "tasks/w--r/cursor-east.json",
            t + "001-working.json", t + "012-completed.json", t + "cancel-requested.json")[1].strip().split("\n")
ok([a.rsplit(": ", 1)[-1] for a in attrs] == ["unspecified"] * 3 + ["board-task"] * 3,
   "the request, its signature and a cursor get git's own merge; transitions and the cancel record get board-task", str(attrs))
out = on("east", ["task", "request", "--to", T + "/wb:builder", "--subject", "two workers", "--key", "k1", "--no-sign"], cwd=T)[1]
TID = (out.split() or [""])[0]
setup(re.fullmatch(r"t[0-9a-f]{8}", TID), "request on east: %s" % out)
round_()
home = [d for d in os.listdir(clone("west") + "/tasks") if d.endswith("--builder")]
setup(len(home) == 1, "the task reached west: %s" % home)
rel = "tasks/%s/%s/" % (home[0], TID)
# both machines' workers take it in one window: no session, inside the worker repo, as a poller runs
rcs = [on("east", ["task", "working", TID, "--note", "east took it"], cwd=T + "/wb", SWITCHBOARD_NOW=str(NOW + 10))[0],
       on("west", ["task", "working", TID, "--note", "west took it"], cwd=T + "/wb", SWITCHBOARD_NOW=str(NOW + 20))[0]]
setup(rcs == [0, 0] and os.path.exists(clone("west") + "/" + rel + "001-working.json"), "two workings: %s" % rcs)
round_()
x = json.loads(read(clone("west") + "/" + rel + "001-working.json") or "{}")
drop = "%s001-working.json.%d.json" % (rel.replace("/", "__"), NOW + 20)
ok(clean("east") and clean("west") and same(rel + "001-working.json") and x.get("machine") == "east" and x.get("ts") == NOW + 10,
   "two machines add the same transition: both syncs succeed and both clones keep the earlier record, byte for byte",
   "%s / %s / %s" % (status("east"), status("west"), x))
ok(json.loads(read(state("west") + "/dropped/" + drop) or "{}").get("note") == "west took it" and
   not os.path.isdir(state("east") + "/dropped"),
   "the dropped transition is kept in STATE/dropped on the machine that ran the merge", str(os.listdir(state("west"))))
# the requester cancels from both machines in one window; the earlier is west's, and west merges again
rcs = [on("east", ["task", "cancel", TID, "--note", "east cancel"], cwd=T, SWITCHBOARD_NOW=str(NOW + 40))[0],
       on("west", ["task", "cancel", TID, "--note", "west cancel"], cwd=T, SWITCHBOARD_NOW=str(NOW + 30))[0]]
setup(rcs == [0, 0], "two cancels: %s" % rcs)
round_()
x = json.loads(read(clone("east") + "/" + rel + "cancel-requested.json") or "{}")
drop2 = "%scancel-requested.json.%d.json" % (rel.replace("/", "__"), NOW + 40)
ok(clean("east") and clean("west") and same(rel + "cancel-requested.json") and x.get("note") == "west cancel" and
   json.loads(read(state("west") + "/dropped/" + drop2) or "{}").get("note") == "east cancel",
   "two machines add cancel-requested.json: both syncs succeed, both keep the earlier, and the other machine's is kept on the merging one",
   "%s / %s / %s" % (status("east"), status("west"), x))
# a stale drop, as one a rebase aborted after the merge leaves: its bytes are what the clone holds at that path
drop3 = "%s001-working.json.%d.json" % (rel.replace("/", "__"), NOW + 10)
os.makedirs(state("west") + "/dropped", exist_ok=True)
write(state("west") + "/dropped/" + drop3, read(clone("west") + "/" + rel + "001-working.json"))
st = [l for l in status("west").splitlines() if l.startswith("dropped:")]
ok(st and drop in st[0] and drop2 in st[0] and drop3 not in st[0] and "2 task record" in st[0]
   and os.path.exists(state("west") + "/dropped/" + drop3) and not [l for l in status("east").splitlines() if l.startswith("dropped:")],
   "board status on the merging machine names both drops but not one whose bytes the clone holds (kept), and on the other names none", str(st))
for f in (drop, drop2, drop3):
    if os.path.exists(state("west") + "/dropped/" + f):
        os.remove(state("west") + "/dropped/" + f)
ok(st and not [l for l in status("west").splitlines() if l.startswith("dropped:")], "removing the files clears the status line")

# one key requested on both machines in one window, unsigned on east and signed on west: the request must stop the
# sync with a conflict status names, never merge into east's request beside west's signature (BAD SIGNATURE)
signers = ""
for m in ("east", "west"):
    k = "%s/.ssh/switchboard_%s" % (os.environ["HOME"], m)
    os.makedirs(os.path.dirname(k), exist_ok=True)
    if not os.path.exists(k):
        run(["ssh-keygen", "-q", "-t", "ed25519", "-N", "", "-f", k, "-C", m])
    signers += '%s namespaces="switchboard-task" %s' % (m, read(k + ".pub"))
pair("sig", signers)
rcs = [on("east", ["task", "request", "--to", T + "/wb:builder", "--subject", "kE", "--key", "kE", "--no-sign"], cwd=T,
          SWITCHBOARD_NOW=str(NOW + 300)),
       on("west", ["task", "request", "--to", T + "/wb:builder", "--subject", "kE", "--key", "kE"], cwd=T, SWITCHBOARD_NOW=str(NOW + 310))]
TK = (rcs[0][1].split() or [""])[0]
setup([r[0] for r in rcs] == [0, 0] and TK and glob.glob(clone("west") + "/tasks/*/%s/000-request.sig" % TK), "two requests of kE: %s" % rcs)
round_()
sigs = [(json.loads(on(m, ["task", TK, "--json"])[1] or "{}") or {}).get("signature") for m in ("east", "west")]
sl = [l for l in status("west").splitlines() if l.startswith("sync:")]
ok(sl and re.search(r"NOT RECOVERED.*conflict in tasks/[^ ]*/%s/000-request\.json" % TK, sl[0]) and clean("east")
   and "BAD SIGNATURE" not in sigs, "one key requested on both machines, one signed: the second sync stops on the request and status "
   "names it; no clone holds one machine's request beside the other's signature", "%s / %s" % (sl, sigs))
sys.exit(1 if failed else 0)
PY
finish
