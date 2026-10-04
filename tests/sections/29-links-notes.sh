#!/usr/bin/env bash
# a subagent's tool call takes no change or link note; task authority over an agent link is the seats that agreed
source "$(dirname "$0")/../lib.sh"
fx_link1   # owner-made link LID from alpha:roadmap (S1) to beta:implementer (S2); S2 has had no hook since the link was made
ptu(){ hook PostToolUse "$1" "$2" Read '{}' | ctx; }

# ---- item 6: a subagent shares its parent's session id, so a note shown to it is lost to the parent
out=$(AID=a1 pre PostToolUse "$T/beta" S2 u1 Read '{}' | ctx)
! echo "$out" | has "changes made elsewhere" && ! echo "$out" | has "bound to link $LID" \
  && ok "a subagent's PostToolUse gets no change note and no link note" || die "subagent took a note: $out"
out=$(ptu "$T/beta" S2); out2=$(ptu "$T/beta" S2)
echo "$out" | has "changes made elsewhere" && echo "$out" | has "bound to link $LID" \
  && ! echo "$out2" | has "changes made elsewhere" && ! echo "$out2" | has "bound to link $LID" \
  && ok "the parent's next PostToolUse gets the change note and the link note, once" || die "parent lost or repeated the notes: $out / $out2"

# ---- item 7: an agent link from delta:lead (SA) to eps:builder (SB)
export SWITCHBOARD_TEST_PROPOSE=1
# the subjects below ("item-a k1") are covered only through an id in them that is a covers entry: the scope_ids path
export SWITCHBOARD_SCOPE_IDS='item-[a-z]+'
fx_repos delta eps
PA=$(fake SA "$T/delta" lead1); seat SB "$T/eps" builder1; seat SA2 "$T/delta" lead2; seat SB2 "$T/eps" builder2
for s in "SA delta" "SB eps" "SA2 delta" "SB2 eps"; do set -- $s; hook SessionStart "$T/$2" $1 >/dev/null; done
SWITCHBOARD_SESSION_ID=SA "$B" role lead >/dev/null; SWITCHBOARD_SESSION_ID=SB "$B" role builder >/dev/null
# a proposal needs --covers too, and its list is in the record, the acceptor's note and the accepted link
n=$(ls "$SWITCHBOARD_DIR/links" | grep -c .); out=$(SWITCHBOARD_SESSION_ID=SA "$B" link --from "$T/delta:lead" --to "$T/eps:builder" --scope "build item-a" 2>&1) && rc=0 || rc=$?
[ "$rc" -eq 1 ] && echo "$out" | has -F "a link needs --covers" && [ "$(ls "$SWITCHBOARD_DIR/links" | grep -c .)" -eq "$n" ] \
  && ok "a proposal without --covers is refused and nothing is written" || die "proposal without covers: rc $rc: $out"
LA=$(SWITCHBOARD_SESSION_ID=SA "$B" link --from "$T/delta:lead" --to "$T/eps:builder" --scope "build item-a" --covers "item-a, Item-A" | awk 'NR==1{print $2}')
pn=$(ptu "$T/eps" SB); "$B" links > "$T/links.txt"
SWITCHBOARD_SESSION_ID=SB "$B" link accept "$LA" >/dev/null && [ "$(jq -r .state "$SWITCHBOARD_DIR/links/$LA.json")" = active ] || die "setup: agent link $LA not accepted"
echo "$pn" | has -F "proposes link $LA: delta:lead directs eps:builder within: build item-a. It covers tasks whose subject starts with: item-a. " \
  && grep -A1 "^$LA " "$T/links.txt" | has -x "    covers: item-a" && [ "$(jq -c .covers "$SWITCHBOARD_DIR/links/$LA.json")" = '["item-a"]' ] \
  && "$B" links | grep -A2 "^$LA " | has -x "    covers: item-a" && "$B" links --json | jq -e --arg l "$LA" '.links[] | select(.id == $l) | .covers == ["item-a"]' >/dev/null \
  && ok "the proposal's list is in the acceptor's note and board links, and acceptance keeps it" || die "proposal covers: $(jq -c .covers "$SWITCHBOARD_DIR/links/$LA.json") / $pn"
cp "$SWITCHBOARD_DIR/links/$LA.json" "$T/la.json"
again(){ cp "$T/la.json" "$SWITCHBOARD_DIR/links/$LA.json"; }   # the link as it stands before the close reaches this clone
for s in "SA delta" "SB eps" "SA2 delta" "SB2 eps"; do set -- $s; ptu "$T/$2" $1 >/dev/null; done
rq(){ SWITCHBOARD_SESSION_ID="$1" "$B" task request --to "$T/eps:builder" --subject "item-a $2" --key "$2" --link "$LA" --no-sign | awk '{print $1}'; }
verdict(){ "$B" task "$1" --json | jq -r .link.verdict; }
RQ(){ cat "$SWITCHBOARD_DIR/tasks/eps--builder/$1/000-request.json"; }
TA=$(rq SA k1)
[ "$(verdict "$TA")" = ok ] && [ "$(env -u SWITCHBOARD_SCOPE_IDS "$B" task "$TA" --json | jq -r .link.verdict)" = "covers list does not name the subject" ] && RQ "$TA" | jq -e ".seat == {\"machine\":\"east\",\"pid\":$PA,\"procStart\":\"$("$B" _procstart "$PA")\"}" >/dev/null \
  && ptu "$T/eps" SB | has "The link's scope makes this an instruction you act on" \
  && ok "the sessions that agreed: the request stores its seat, the verdict is ok through the id in the subject and the worker's note is an instruction" || die "agreed pair: $(verdict "$TA") $(RQ "$TA")"

# a machine with a key the owner lists (west) writes a request in its own name and signs it: the seat that agreed is
# in the link record for anyone to copy, so a seat naming another machine than the request's fails the link
mkdir -p "$SWITCHBOARD_DIR/keys"; ssh-keygen -q -t ed25519 -N "" -f "$T/west" -C west
echo "west namespaces=\"switchboard-task\" $(cat "$T/west.pub")" > "$SWITCHBOARD_DIR/keys/allowed_signers"
aswest(){ # tid seat-machine: the request rewritten in west's name with its seat's machine set, then signed with west's key
  python3 - "$SWITCHBOARD_DIR/tasks/eps--builder/$1/000-request.json" "$2" <<'PY'
import json,sys; f,m=sys.argv[1:3]; r=json.load(open(f)); r["machine"]="west"; r["seat"]["machine"]=m
open(f,"w").write(json.dumps(r, indent=1, sort_keys=True) + "\n")
PY
  ssh-keygen -Y sign -f "$T/west" -n switchboard-task < "$SWITCHBOARD_DIR/tasks/eps--builder/$1/000-request.json" \
    > "$SWITCHBOARD_DIR/tasks/eps--builder/$1/000-request.sig" 2>/dev/null; }
TW=$(rq SA kw1); aswest "$TW" east; TW2=$(rq SA kw2); aswest "$TW2" west
[ "$("$B" task "$TW" --json | jq -r .signature)" = "signed by west" ] && [ "$(verdict "$TW")" = "the request's seat names another machine" ] \
  && [ "$(verdict "$TW2")" = "requester is not the session that agreed to the link" ] && [ "$(verdict "$TA")" = ok ] \
  && ok "a request signed by west that copies the agreeing seat fails as a seat of another machine; with west's own seat it is not the agreeing one" \
  || die "copied seat: $(verdict "$TW") / $(verdict "$TW2") / $(verdict "$TA")"
# the same machine drops the seat key instead of copying it: a request over a link two sessions made always has one
noseat(){ python3 - "$SWITCHBOARD_DIR/tasks/eps--builder/$1/000-request.json" <<'PY'
import json,sys; f=sys.argv[1]; r=json.load(open(f)); r["machine"]="west"; r.pop("seat",None)
open(f,"w").write(json.dumps(r, indent=1, sort_keys=True) + "\n")
PY
  ssh-keygen -Y sign -f "$T/west" -n switchboard-task < "$SWITCHBOARD_DIR/tasks/eps--builder/$1/000-request.json" \
    > "$SWITCHBOARD_DIR/tasks/eps--builder/$1/000-request.sig" 2>/dev/null; }
TN=$(rq SA kn1); noseat "$TN"
[ "$("$B" task "$TN" --json | jq -r .signature)" = "signed by west" ] && [ "$(verdict "$TN")" = "the request names no seat for a link two sessions made" ] \
  && ptu "$T/eps" SB | has "^Link $LA does not cover this request (the request names no seat for a link two sessions made), so it is information" \
  && ok "a request signed by west with no seat key fails the agent link, and the worker's note says information only" \
  || die "seatless signed request: $("$B" task "$TN" --json | jq -c '{signature, v: .link.verdict}')"

# a new holder of B's role reads a task before the close of the link reaches it
SWITCHBOARD_SESSION_ID=SB2 "$B" role builder --take >/dev/null || die "setup: SB2 did not take eps:builder"; again
TB=$(rq SA k2); out=$(ptu "$T/eps" SB2)
echo "$out" | has "a task for you.*$TB" && echo "$out" | has "^Link $LA does not cover this request (this session is not the one that agreed to the link), so it is information" \
  && [ "$(verdict "$TB")" = ok ] \
  && ok "a new holder of the worker end gets the task note as information only; the request itself still judges ok" || die "new worker: $out"
v2=$(SWITCHBOARD_SESSION_ID=SB2 "$B" task "$TB" | grep "^  link "); j2=$(SWITCHBOARD_SESSION_ID=SB2 "$B" task "$TB" --json | jq -r .link.verdict)
l2=$(SWITCHBOARD_SESSION_ID=SB2 "$B" tasks --for "$T/eps:builder" --open --json | jq -r ".[] | select(.id == \"$TB\") | .link.verdict")
# reading a task writes nothing about the reader: with SB2's own presence record gone, both reads leave sessions/ and
# roles/ as they were and still judge by the seat the role file gives; then the same with sessions/ read-only
SR="$SWITCHBOARD_DIR/sessions/east-SB2.json"; rm -f "$SR"
s0=$(cd "$SWITCHBOARD_DIR" && find sessions roles -type f -exec md5sum {} + | sort)
r1=$(SWITCHBOARD_SESSION_ID=SB2 "$B" task "$TB" --json | jq -r .link.verdict)
r2=$(SWITCHBOARD_SESSION_ID=SB2 "$B" tasks --for "$T/eps:builder" --open --json | jq -r ".[] | select(.id == \"$TB\") | .link.verdict")
SWITCHBOARD_SESSION_ID=SB2 "$B" task "$TB" >/dev/null
s1=$(cd "$SWITCHBOARD_DIR" && find sessions roles -type f -exec md5sum {} + | sort)
[ "$s0" = "$s1" ] && [ ! -e "$SR" ] && [ "$r1" = "this session is not the one that agreed to the link" ] && [ "$r2" = "$r1" ] \
  && ok "board task and board tasks --open --json write no presence record and still judge the reader by seat" || die "reads wrote or judged wrong: $r1 / $r2 / $(ls "$SWITCHBOARD_DIR/sessions")"
rm -f "$SR"; chmod a-w "$SWITCHBOARD_DIR/sessions"   # the reviewer's repro: no own record, and none can be written
r1=$(SWITCHBOARD_SESSION_ID=SB2 "$B" task "$TB" --json | jq -r .link.verdict)
r2=$(SWITCHBOARD_SESSION_ID=SB2 "$B" tasks --for "$T/eps:builder" --open --json | jq -r ".[] | select(.id == \"$TB\") | .link.verdict")
chmod u+w "$SWITCHBOARD_DIR/sessions"
[ "$r1" = "this session is not the one that agreed to the link" ] && [ "$r2" = "$r1" ] \
  && ok "with its presence record gone and sessions/ read-only, the new holder of the worker end still gets the failing verdict" || die "read-only sessions: $r1 / $r2"
# when the reader cannot be determined, an agent link fails closed; a caller with no session is judged as before
# (a bad role file reads as no record, so the failure is one the file system gives: listing roles/ raises an OSError,
# through SWITCHBOARD_TEST_FAULT in tests/py/sitecustomize.py)
export SWITCHBOARD_TEST_FAULT="$SWITCHBOARD_DIR/roles"
r1=$(SWITCHBOARD_SESSION_ID=SB2 "$B" task "$TB" --json | jq -r .link.verdict)
r2=$(SWITCHBOARD_SESSION_ID=SB2 "$B" tasks --for "$T/eps:builder" --open --json | jq -r ".[] | select(.id == \"$TB\") | .link.verdict")
r3=$(verdict "$TB")
unset SWITCHBOARD_TEST_FAULT
[ "$r1" = "cannot tell whether this session agreed to the link" ] && [ "$r2" = "$r1" ] && [ "$r3" = ok ] && grep -q " task_reader " "$SWITCHBOARD_STATE/errors.log" \
  && ok "a reader that cannot be determined fails the agent link closed, logged; a caller with no session still reads ok" || die "fail closed: $r1 / $r2 / $r3"
SWITCHBOARD_SESSION_ID=SB "$B" role builder --take >/dev/null || die "setup: SB did not take eps:builder back"; again
v1=$(SWITCHBOARD_SESSION_ID=SB "$B" task "$TB" | grep "^  link "); j1=$(SWITCHBOARD_SESSION_ID=SB "$B" task "$TB" --json | jq -r .link.verdict)
l1=$(SWITCHBOARD_SESSION_ID=SB "$B" tasks --for "$T/eps:builder" --open --json | jq -r ".[] | select(.id == \"$TB\") | .link.verdict")
[ "$v2" = "  link $LA: this session is not the one that agreed to the link" ] && [ "$j2" = "this session is not the one that agreed to the link" ] \
  && [ "$v1" = "  link $LA: ok" ] && [ "$j1" = ok ] \
  && ok "board task run by the new holder of the worker end shows the failing verdict, text and json; the agreed holder sees ok" || die "board task: $v2 / $j2 / $v1 / $j1"
[ "$l2" = "this session is not the one that agreed to the link" ] && [ "$l1" = ok ] \
  && ok "board tasks --open --json agrees: the failing verdict for the new holder of the worker end, ok for the agreed holder" || die "board tasks: $l2 / $l1"

# a new holder of A's role requests before the close
SWITCHBOARD_SESSION_ID=SA2 "$B" role lead --take >/dev/null || die "setup: SA2 did not take delta:lead"; again
TC=$(rq SA2 k3); out=$(ptu "$T/eps" SB)
[ "$(verdict "$TC")" = "requester is not the session that agreed to the link" ] && "$B" task "$TC" | has -x "  link $LA: requester is not the session that agreed to the link" \
  && echo "$out" | has "a task for you.*$TC" && echo "$out" | has "^Link $LA does not cover this request (requester is not the session that agreed to the link), so it is information" \
  && ok "a new holder of the requesting end gets a failing verdict, and the worker's note says information only" || die "new requester: $(verdict "$TC") / $out"

# a request with no seat over a link two sessions made fails: seats and agent links came in the same release
F="$SWITCHBOARD_DIR/tasks/eps--builder/$TC/000-request.json"; jq 'del(.seat)' "$F" > "$T/req" && mv "$T/req" "$F"
[ "$(verdict "$TC")" = "the request names no seat for a link two sessions made" ] \
  && ok "the same request with no seat fails the agent link: it names no seat" || die "seatless: $(verdict "$TC")"
# a seat key that is present but not a record fails the agent link; only a missing key is an old request
bad=""
for v in '"x"' '[]' 'null' '7' 'false'; do
  jq --argjson v "$v" '.seat = $v' "$F" > "$T/req" && mv "$T/req" "$F"
  [ "$(verdict "$TC")" = "requester is not the session that agreed to the link" ] || bad="$bad $v"
done
[ -z "${bad:-}" ] && ok "a request whose seat is a string, a list, null, a number or false fails the agent link" || die "malformed seat judged ok:$bad"
# a link whose from or to is not a record: a verdict, never a crash
bad=""
for e in from to; do
  jq --arg e "$e" '.[$e] = "x" | .id = "l0bad"' "$T/la.json" > "$SWITCHBOARD_DIR/links/l0bad.json"
  jq '.link = "l0bad"' "$F" > "$T/req" && mv "$T/req" "$F"
  v=$("$B" task "$TC" --json | jq -r .link.verdict) && [ -n "$v" ] && [ "$v" != ok ] || bad="$bad $e:$v"
done
[ -z "${bad:-}" ] && ok "a link whose from or to is not a record gives a failing verdict in board task --json, not a crash" || die "broken end:$bad"

# an owner-made link keeps the role check: a new holder of either end is covered
seat S7 "$T/alpha" road2; hook SessionStart "$T/alpha" S7 >/dev/null; SWITCHBOARD_SESSION_ID=S7 "$B" role roadmap --take >/dev/null || die "setup: S7 did not take alpha:roadmap"
seat S8 "$T/beta" impl2; hook SessionStart "$T/beta" S8 >/dev/null; SWITCHBOARD_SESSION_ID=S8 "$B" role implementer --take >/dev/null || die "setup: S8 did not take beta:implementer"
ptu "$T/beta" S8 >/dev/null
TD=$(SWITCHBOARD_SESSION_ID=S7 "$B" task request --to "$T/beta:implementer" --subject "order the next work items" --key k4 --link "$LID" --no-sign | awk '{print $1}')
[ "$("$B" task "$TD" --json | jq -r .link.verdict)" = ok ] && ptu "$T/beta" S8 | has "The link's scope makes this an instruction you act on" \
  && ok "an owner-made link: new holders of both ends request and read under it as before" || die "owner link: $("$B" task "$TD" --json | jq -c .link)"
FD="$SWITCHBOARD_DIR/tasks/beta--implementer/$TD/000-request.json"; jq 'del(.seat)' "$FD" > "$T/req" && mv "$T/req" "$FD"
[ "$("$B" task "$TD" --json | jq -r .link.verdict)" = ok ] \
  && ok "over an owner-made link a request with no seat still judges ok by role" || die "owner link, no seat: $("$B" task "$TD" --json | jq -c .link)"

finish
