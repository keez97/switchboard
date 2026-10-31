#!/usr/bin/env bash
# each machine stamps the version it runs; a record of a later format carries no authority; older CLIs still running
# on a machine read the records this one writes
source "$(dirname "$0")/../lib.sh"
# One file per older switchboard still running on a machine, tests/fixtures/switchboard-<version>, copied from that
# release's bin/switchboard (git show <sha>:bin/switchboard). To cover another, drop its file in.
FIXTURES=("$TESTS"/fixtures/switchboard-*)
[ -x "${FIXTURES[0]}" ] || die "setup: no fixture CLI in $TESTS/fixtures"
VER=$(jq -r .version "$TESTS/../.claude-plugin/plugin.json")
NOW=$(date +%s)
STAMP="$SWITCHBOARD_DIR/machines/east.json"
# a board with a remote, so a sync job runs and stamps
git init -q --bare -b main "$T/one.git"; git clone -q "$T/one.git" "$T/seed" 2>/dev/null; binit "$T/seed"
( cd "$T/seed" && git add -A && git -c user.email=t@t -c user.name=t commit -qm seed && git push -q origin HEAD:main )
rmdir "$SWITCHBOARD_DIR"; git clone -q "$T/one.git" "$SWITCHBOARD_DIR"
git -C "$SWITCHBOARD_DIR" config user.email t@t; git -C "$SWITCHBOARD_DIR" config user.name east
syncd(){ rm -f "$SWITCHBOARD_STATE/sync.ok"; SWITCHBOARD_NOSYNC='' "$@" sync; waitfor "$SWITCHBOARD_STATE/sync.ok"; }   # cli [env]: one sync job, to its end
fx_repos alpha beta; P1=$(fake S1 "$T/alpha" road)

# t1: SessionStart syncs, and the sync stamps the version
( export SWITCHBOARD_NOSYNC=''; rm -f "$SWITCHBOARD_STATE/sync.ok"; sstart "$T/alpha" S1 >/dev/null; waitfor "$SWITCHBOARD_STATE/sync.ok" )
[ "$(jq -r .version "$STAMP" 2>/dev/null)" = "$VER" ] && [ -n "$VER" ] && [ "$(jq -r .machine "$STAMP")" = east ] \
  && ok "after SessionStart the machine's stamp names the version it runs ($VER)" || die "t1 stamp: $(cat "$STAMP" 2>&1)"

# t2: a link of a later record format carries no authority, logged once
SWITCHBOARD_SESSION_ID=S1 "$B" role roadmap >/dev/null
LID=$("$B" link --from "$T/alpha:roadmap" --to "$T/beta:implementer" --scope "format test" --covers "format test" --to-session open | awk 'NR==1{print $2}')
[ "$(jq -r .v "$SWITCHBOARD_DIR/links/$LID.json")" = 1 ] && "$B" links --json | jq -e --arg l "$LID" '[.links[].id] | index($l) != null' >/dev/null \
  && ok "a new link record carries \"v\": 1 and is active" || die "t2 setup: $(cat "$SWITCHBOARD_DIR/links/$LID.json")"
jq '.v = 99' "$SWITCHBOARD_DIR/links/$LID.json" > "$T/lx" && mv "$T/lx" "$SWITCHBOARD_DIR/links/$LID.json"
"$B" links --json | jq -e --arg l "$LID" '[.links[].id] | index($l) == null' >/dev/null && ! "$B" links | has "^$LID " \
  && ok "a link file with \"v\": 99 is not listed as active" || die "t2 listed: $("$B" links)"
# the same file through a request, which judges the link record itself
out=$(cd "$T/alpha" && SWITCHBOARD_SESSION_ID=S1 "$B" task request --to "$T/beta:implementer" --subject "format test: x" --key v99 --link "$LID" --no-sign 2>&1) \
  && die "t2 request over a v99 link was written: $out" || { echo "$out" | has "record format 99, newer than this switchboard reads" \
  && ok "a request over a v99 link is refused as of a later format" || die "t2 request: $out"; }
"$B" links >/dev/null; "$B" links --json >/dev/null
[ "$(grep -c "malformed links/$LID.json: record format 99" "$SWITCHBOARD_STATE/errors.log")" = 1 ] \
  && ok "the v99 record is logged once over several reads" || die "t2 log: $(cat "$SWITCHBOARD_STATE/errors.log" 2>&1)"
jq '.v = 1' "$SWITCHBOARD_DIR/links/$LID.json" > "$T/lx" && mv "$T/lx" "$SWITCHBOARD_DIR/links/$LID.json"
"$B" links | has "^$LID " && ok "back at \"v\": 1 the same link is active again" || die "t2 v1: $("$B" links)"
# a request written while the link was format 1 is judged again when read: at v99 the worker gets information
P2=$(fake S2 "$T/beta" impl); sstart "$T/beta" S2 >/dev/null; SWITCHBOARD_SESSION_ID=S2 "$B" role implementer >/dev/null
TQ=$(cd "$T/alpha" && SWITCHBOARD_SESSION_ID=S1 "$B" task request --to "$T/beta:implementer" --subject "format test: y" --key v1 --link "$LID" --no-sign | awk '{print $1}')
[ "$("$B" task "$TQ" --json | jq -r .link.verdict)" = ok ] || die "t2 setup: request over the v1 link: $("$B" task "$TQ" --json | jq -c .link)"
setv(){ jq --argjson v "$2" '.v = $v' "$SWITCHBOARD_DIR/links/$1.json" > "$T/lx" && mv "$T/lx" "$SWITCHBOARD_DIR/links/$1.json"; }   # lid json-value
setv "$LID" 99
[ "$("$B" task "$TQ" --json | jq -r .link.verdict)" = "link of record format 99, newer than this switchboard reads" ] \
  && "$B" task "$TQ" | has "link $LID: link of record format 99, newer than this switchboard reads" \
  && note=$(hook UserPromptSubmit "$T/beta" S2 | ctx) && echo "$note" | has "$TQ.*\[link of record format 99, newer than this switchboard reads\]" \
  && echo "$note" | has "information" \
  && ok "a request over a link that is now v99 reads with the verdict link of record format 99, not as an instruction" \
  || die "t2 link_check: $("$B" task "$TQ" --json | jq -c .link) | note: ${note:-}"
# any "v" that is not an int from 1 to RECORD_V is a format this copy does not read
bad=""
for v in '"99"' 2.0 99.5 '[2]' '{"major": 2}' null 0 -1 true; do
  setv "$LID" "$v"
  "$B" links --json | jq -e --arg l "$LID" '[.links[].id] | index($l) == null' >/dev/null || bad="$bad listed:$v"
  "$B" task "$TQ" --json | jq -r .link.verdict | has "^link of record format .*, newer than this switchboard reads$" || bad="$bad verdict:$v"
  ( cd "$T/alpha" && SWITCHBOARD_SESSION_ID=S1 "$B" task request --to "$T/beta:implementer" --subject "format test: z" --key "bad$v" --link "$LID" --no-sign >/dev/null 2>&1 ) && bad="$bad written:$v"
done
[ -z "$bad" ] && ok "a \"v\" of \"99\", 2.0, 99.5, [2], an object, null, 0, -1 or true gives no authority: not listed, not ok, no request" || die "t2 v values:$bad"
# the commands that change a link refuse one of a later format and write nothing
setv "$LID" 99; cp "$SWITCHBOARD_DIR/links/$LID.json" "$T/v99"
for c in "link-cap $LID 5" "bind $LID implementer --session S2" "unlink $LID"; do
  out=$("$B" $c 2>&1) && die "t2 $c on a v99 link ran: $out" || true
  echo "$out" | has "Link $LID is of record format 99, newer than this switchboard reads" && cmp -s "$T/v99" "$SWITCHBOARD_DIR/links/$LID.json" \
    && ok "$(echo "$c" | awk '{print $1}') on a v99 link is refused and the record is unchanged" || die "t2 $c: $out $(cat "$SWITCHBOARD_DIR/links/$LID.json")"
done
# unlink on a record of another shape refuses with a reason, never a traceback
printf '[1]\n' > "$SWITCHBOARD_DIR/links/lbad001.json"
echo '{"v": 1, "id": "lbad002", "ends": ["a", "b"]}' > "$SWITCHBOARD_DIR/links/lbad002.json"
echo '{"v": 99, "id": "lbad003", "ends": ["a", "b"]}' > "$SWITCHBOARD_DIR/links/lbad003.json"
echo '{"id": "lbad004", "from": "x", "to": {"repo": 1, "role": "r"}}' > "$SWITCHBOARD_DIR/links/lbad004.json"
bad=""
for l in lbad001 lbad002 lbad003 lbad004; do
  cp "$SWITCHBOARD_DIR/links/$l.json" "$T/was"
  out=$("$B" unlink "$l" 2>&1) && bad="$bad ran:$l"
  echo "$out" | has Traceback && bad="$bad traceback:$l"
  echo "$out" | has "Nothing was written" && cmp -s "$T/was" "$SWITCHBOARD_DIR/links/$l.json" || bad="$bad $l:$out"
done
rm -f "$SWITCHBOARD_DIR"/links/lbad00[1-4].json   # links() itself has no rule for them
[ -z "$bad" ] && [ ! -s "$T/crashes" ] && ok "unlink of a list, a record without from and to, or ends of the wrong type refuses with a reason" \
  || die "t2 unlink shapes:$bad $(cat "$T/crashes" 2>/dev/null | head -c 600)"
setv "$LID" 1
# a proposal of a later format cannot be accepted: accepting is what gives it authority
LP=$(SWITCHBOARD_TEST_PROPOSE=1 SWITCHBOARD_SESSION_ID=S1 "$B" link --from "$T/alpha:roadmap" --to "$T/beta:implementer" --scope "format proposal" --covers "format proposal" | awk 'NR==1{print $2}')
[ "$(jq -r '.v, .state' "$SWITCHBOARD_DIR/links/$LP.json" | tr '\n' ' ')" = "1 proposed " ] || die "t2 proposal: $(cat "$SWITCHBOARD_DIR/links/$LP.json")"
jq '.v = 99' "$SWITCHBOARD_DIR/links/$LP.json" > "$T/lx" && mv "$T/lx" "$SWITCHBOARD_DIR/links/$LP.json"
out=$(SWITCHBOARD_TEST_PROPOSE=1 SWITCHBOARD_SESSION_ID=S2 "$B" link accept "$LP" 2>&1) && die "t2 a v99 proposal was accepted: $out" || true
echo "$out" | has "proposal $LP is of record format 99" && [ "$(jq -r .state "$SWITCHBOARD_DIR/links/$LP.json")" = proposed ] \
  && ! "$B" links --json | jq -e --arg l "$LP" '[.proposals[].id] | index($l) != null' >/dev/null \
  && ok "a v99 proposal is not listed and its other end cannot accept it" || die "t2 accept: $out $(jq -c '{state,v}' "$SWITCHBOARD_DIR/links/$LP.json")"

# machines_behind: no version, or one below the first that reads the format
python3 - "$SWITCHBOARD_DIR" <<'PY'
import json, sys
d = sys.argv[1]
for m, v in (("west", None), ("north", "0.7.0"), ("south", "0.9.1"), ("odd", "x"), ("huge", "9" * 5000)):
    json.dump(dict({"machine": m, "synced": 1}, **({"version": v} if v else {})), open("%s/machines/%s.json" % (d, m), "w"))
PY
behind=$(python3 - "$B" <<'PY'
import importlib.machinery, importlib.util, sys
l = importlib.machinery.SourceFileLoader("sb", sys.argv[1]); m = importlib.util.module_from_spec(importlib.util.spec_from_loader("sb", l))
l.exec_module(m); print(" ".join(m.machines_behind(1)))
PY
) || behind="raised: $behind"
[ "$behind" = "huge north odd west" ] && ok "machines_behind(1) names the machines with no version, one before 0.8.0 or one it cannot read (a 5000-digit part)" || die "machines_behind: $behind"
rm -f "$SWITCHBOARD_DIR"/machines/{west,north,south,odd,huge}.json

# t3: each older CLI reads the new records without a traceback: an owner link with no end, a granted link, and an
# agent link extended to no end (its until stays a number: older code reads it unguarded)
python3 - "$SWITCHBOARD_DIR" "$LID" "$NOW" <<'PY'
import json, sys
d, lid, now = sys.argv[1], sys.argv[2], int(sys.argv[3])
l = json.load(open("%s/links/%s.json" % (d, lid)))
a, b = l["from"], l["to"]   # alpha:roadmap and beta:implementer, as the board names their repos
base = {"v": 1, "from": a, "to": b, "covers": ["new format"], "cap": 0, "created": now, "machine": "west", "by_session": ""}
seat = lambda e, pid: dict(e, machine="west", pid=pid, procStart="1", session_id="W%d" % pid, name="w")
recs = {
    "la00001": dict(base, scope="owner, no end", ends="never", idle_days=None),
    "la00002": dict(base, scope="granted", ends="never", idle_days=None, granted_at=now,
                    granted_by={"session": "S1", "tool_use_id": "toolu_1", "ts": now}),
    "la00003": dict(base, scope="agent, extended", state="active", span=86400, until=253402300799, ends="never",
                    idle_days=None, expires=now + 86400, accepted=now, proposed_by=seat(a, 1), accepted_by=dict(seat(b, 2), covers=["new format"]),
                    granted_at=now, granted_by={"session": "S1", "tool_use_id": "toolu_2", "ts": now}),
}
for lid, r in recs.items():
    json.dump(dict(r, id=lid), open("%s/links/%s.json" % (d, lid), "w"))
PY
for F in "${FIXTURES[@]}"; do
  v=${F##*/switchboard-}; : > "$T/err"; rc=0
  { "$F" links > "$T/out" 2>> "$T/err" && "$F" links --json > "$T/json" 2>> "$T/err" && "$F" status >/dev/null 2>> "$T/err" \
    && python3 -c "import json,sys; print(json.dumps({'hook_event_name':'SessionStart','source':'startup','cwd':sys.argv[1],'session_id':'S1'}))" "$T/alpha" \
      | "$F" hook > "$T/ctx" 2>> "$T/err"; } || rc=$?
  ids=$(jq -r '[.links[].id | select(startswith("la0000"))] | sort | join(" ")' "$T/json" 2>/dev/null)
  [ "$rc" = 0 ] && ! grep -q Traceback "$T/err" && [ ! -s "$T/crashes" ] && grep -q "^la00001 " "$T/out" && grep -q "^la00002 " "$T/out" \
    && grep -q "^la00003 " "$T/out" && [ "$ids" = "la00001 la00002 la00003" ] \
    && ok "the $v CLI lists an owner link with no end, a granted link and an extended agent link without a traceback" \
    || die "t3 $v: rc $rc ids '$ids' $(head -c 600 "$T/err") $(cat "$T/crashes" 2>/dev/null | head -c 600)"
done
"$B" links | grep -c "^la0000[123] " | has -x 3 && ok "this CLI lists the same three" || die "t3 this CLI: $("$B" links)"

# t3b: each older CLI's merge driver keeps a no-end owner link's ends and idle_days when the other side changed its cap
# or closed it (the drivers merge whatever syncs, whichever machine made the record)
mkdir -p "$T/mu"
for F in "${FIXTURES[@]}" "$B"; do
  v=${F##*/switchboard-}; [ "$F" = "$B" ] && v=this
  python3 - "$T/mu" "$F" <<'PY' && ok "the $v merge driver keeps ends never, idle_days null and no until on a no-end owner link, with a cap change or a close on either side" || die "t3b $v merge"
import json, os, subprocess, sys
d, cli = sys.argv[1], sys.argv[2]
o = {"v": 1, "id": "la00009", "from": {"repo": "a", "role": "x"}, "to": {"repo": "b", "role": "y"}, "scope": "s", "covers": ["s"],
     "cap": 100, "ends": "never", "idle_days": None, "created": 1793000000, "machine": "east", "by_session": ""}
capped = dict(o, cap=50)
closed = dict(o, revoked=1793100000, closed_reason="ended by Robin's terminal", closed_by="terminal")
ok = True
for ours, theirs, want in ((capped, o, {"cap": 50}), (o, capped, {"cap": 50}), (o, closed, {"revoked": 1793100000}),
                           (closed, capped, {"revoked": 1793100000, "cap": 50})):
    for n, x in (("o", o), (".merge_file_a", ours), ("t", theirs)):
        json.dump(x, open(os.path.join(d, n), "w"))
    rc = subprocess.run([cli, "merge-link", "o", ".merge_file_a", "t"], cwd=d, capture_output=True).returncode
    m = json.load(open(os.path.join(d, ".merge_file_a")))
    ok = ok and rc == 0 and m.get("ends") == "never" and "idle_days" in m and m["idle_days"] is None and "until" not in m \
        and m.get("v") == 1 and all(m.get(k) == w for k, w in want.items())
sys.exit(0 if ok else 1)
PY
done

# t3c: how each CLI judges a request over a link whose covers list and scope words differ. 0.7.0 and this one read the
# covers list; 0.6.0, which has none, reads the scope words (README, "Update every machine on the board the same day")
LC=$("$B" link --from "$T/alpha:roadmap" --to "$T/beta:implementer" --scope "alpha beta" --covers "gamma work" | awk 'NR==1{print $2}')
TC=$(cd "$T/alpha" && SWITCHBOARD_SESSION_ID=S1 "$B" task request --to "$T/beta:implementer" --subject "gamma work: x" --key c1 --link "$LC" --no-sign | awk '{print $1}')
out=$(cd "$T/alpha" && SWITCHBOARD_SESSION_ID=S1 "$B" task request --to "$T/beta:implementer" --subject "alpha: y" --key c2 --link "$LC" --no-sign 2>&1) \
  && die "t3c this CLI wrote a request its link's covers list does not cover: $out"
F6=$TESTS/fixtures/switchboard-0.6.0
TS=$(cd "$T/alpha" && SWITCHBOARD_SESSION_ID=S1 "$F6" task request --to "$T/beta:implementer" --subject "alpha: y" --key c3 --link "$LC" --no-sign 2>&1 | awk '{print $1}')
[ -n "$TC" ] && [ -n "$TS" ] || die "t3c setup: $TC / $TS"
verdict(){ "$1" task "$2" --json 2>/dev/null | jq -r '.link.verdict // "none"'; }
got=""; for F in "${FIXTURES[@]}" "$B"; do v=${F##*/switchboard-}; [ "$F" = "$B" ] && v=this; got="$got $v:$(verdict "$F" "$TC")/$(verdict "$F" "$TS")"; done
[ "$got" = " 0.6.0:scope does not name the subject/ok 0.7.0:ok/covers list does not name the subject this:ok/covers list does not name the subject" ] \
  && ok "0.6.0 judges a v1 link by its scope words (a request the covers list names is not covered there, one only the scope words name is); 0.7.0 and this CLI by its covers list" \
  || die "t3c verdicts:$got"

# t4: an older CLI's hourly sync drops the version; the next run of this one puts it back, and never lowers one
for F in "${FIXTURES[@]}"; do
  v=${F##*/switchboard-}
  syncd "$B"; jq -r .version "$STAMP" | has -x "$VER" || die "t4 $v setup: $(cat "$STAMP")"
  syncd env SWITCHBOARD_NOW=$((NOW + 7200)) "$F"   # an hour on: that CLI rewrites the stamp in its own format
  [ "$(jq -r .synced "$STAMP")" = $((NOW + 7200)) ] || die "t4 $v: the older sync did not rewrite the stamp: $(cat "$STAMP")"
  syncd "$B"   # within the hour of that stamp: only a version that differs makes it rewrite
  [ "$(jq -r .version "$STAMP")" = "$VER" ] && ok "a $VER stamp rewritten by the $v CLI's sync names $VER again after the next $VER sync" \
    || die "t4 $v: $(cat "$STAMP")"
done
jq '.version = "9.0.0"' "$STAMP" > "$T/sx" && mv "$T/sx" "$STAMP"
syncd env SWITCHBOARD_NOW=$((NOW + 4*3600)) "$B"
[ "$(jq -r .version "$STAMP")" = 9.0.0 ] && [ "$(jq -r .synced "$STAMP")" = $((NOW + 4*3600)) ] \
  && ok "an hourly rewrite keeps a higher version a newer copy on this machine stamped" || die "t4 lowered: $(cat "$STAMP")"
# a stored version this copy cannot read (a part of 5000 digits) neither stops the sync nor stays
python3 -c "import json,sys; d=json.load(open(sys.argv[1])); d['version']='9'*5000; json.dump(d,open(sys.argv[1],'w'))" "$STAMP"
syncd "$B"
[ -f "$SWITCHBOARD_STATE/sync.ok" ] && [ "$(jq -r .version "$STAMP")" = "$VER" ] \
  && ok "a sync over a stamp whose version has a 5000-digit part completes and stamps $VER" || die "t4 huge: $(head -c 300 "$SWITCHBOARD_STATE/sync.fail" 2>&1) $(jq -c '{synced, v: (.version|tostring|.[0:20])}' "$STAMP")"

finish
