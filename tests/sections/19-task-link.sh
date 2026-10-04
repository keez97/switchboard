#!/usr/bin/env bash
# a request may name a link
source "$(dirname "$0")/../lib.sh"
fx_delta_eps; seat SD2 "$T/delta" "second in delta"; hook SessionStart "$T/delta" SD2 >/dev/null   # SD2 takes delta:scout below
TID=$(SWITCHBOARD_SESSION_ID=S5 "$B" task request --to "$T/eps:builder" --subject "no link" --key k1 | awk '{print $1}')

lk(){ SWITCHBOARD_SESSION_ID="$1" "$B" link --from "$2" --to "$T/eps:builder" --scope "$3" --covers "${4:-app}" --until 30d | awk 'NR==1{print $2}'; }   # covers app unless named
rq(){ SWITCHBOARD_SESSION_ID=S5 "$B" task request --to "$T/eps:builder" --subject "$1" --key "$2" --link "$3" 2>/dev/null | awk '{print $1}'; }
LK=$(lk S5 "$T/delta:lead" "evaluate app builds for eps"); TK=$(rq "app@abc1234" lk1 "$LK")
"$B" task "$TK" | has -x "  link $LK: ok" && "$B" task "$TK" --json | python3 -c "import json,sys; l=json.load(sys.stdin)['link']; sys.exit(0 if l=={'id':'$LK','verdict':'ok','scope':'evaluate app builds for eps','covers':['app'],'covers_mode':'list','active':True,'from_is_requester':True,'to_is_worker':True,'scope_covers_subject':True} else 1)" && grep -q "\"link\": \"$LK\"" "$SWITCHBOARD_DIR"/tasks/eps--builder/"$TK"/000-request.json && ok "a request naming a live link from the requester's own address shows link ok in text and json" || die "link ok: $("$B" task "$TK" --json | python3 -c "import json,sys; print(json.load(sys.stdin)['link'])")"
"$B" unlink "$LK" --reason "done" >/dev/null; "$B" task "$TK" | has -x "  link $LK: link revoked" && "$B" task "$TK" --json | has '"active": false' && ok "after unlink the same request shows link revoked, judged at read time" || die "revoked: $("$B" task "$TK" | grep link)"
n=$(find "$SWITCHBOARD_DIR/tasks" -name 000-request.json | wc -l); out=$(SWITCHBOARD_SESSION_ID=S5 "$B" task request --to "$T/eps:builder" --subject "app@abc1234" --key lk1 --link "$LK" 2>&1) && rc=0 || rc=$?
[ "$rc" = 0 ] && [ "$out" = "$TK already requested (same worker and key); nothing written" ] && [ "$(find "$SWITCHBOARD_DIR/tasks" -name 000-request.json | wc -l)" = "$n" ] \
  && ok "after unlink, rerunning the request with the same key is still the no-op it was, rc 0" || die "rerun after unlink: rc=$rc $out"
edl(){ python3 - "$SWITCHBOARD_DIR/links/$1.json" "$2" "$3" <<'PY'   # rewrite one key of a link record, as an older board or another machine could leave it
import json,sys
f,k,v=sys.argv[1:4]; d=json.load(open(f)); d[k]=json.loads(v); json.dump(d,open(f,"w"))
PY
}
nreq(){ find "$SWITCHBOARD_DIR/tasks" -name 000-request.json | wc -l; }
LF=$(lk S5 "$T/delta:lead" "app"); TF=$(rq "app@def5678" lk2 "$LF"); edl "$LF" from "{\"repo\":\"$T/delta\",\"role\":\"scout\"}"
"$B" task "$TF" | has -x "  link $LF: from is not the requester" && ok "a request written before the link's from changed shows from is not the requester, judged at read time" || die "from: $("$B" task "$TF" | grep link)"
LS=$(lk S5 "$T/delta:lead" "app builds and docs" "docs only, doc fixes"); n=$(nreq); out=$(SWITCHBOARD_SESSION_ID=S5 "$B" task request --to "$T/eps:builder" --subject "app@0a1b2c3" --key lk3 --link "$LS" 2>&1 >/dev/null) && rc=0 || rc=$?
[ "$rc" -eq 1 ] && echo "$out" | has -xF "switchboard: link $LS does not cover this request: its covers list does not name the subject. link $LS covers: docs only, doc fixes; the subject must start with one of them, followed by ':' or '@' (\"<prefix>: ...\"), or be one. Nothing was written." && [ "$(nreq)" -eq "$n" ] && ok "a subject no covers entry starts is refused at request time, naming the list, though the scope names it, and nothing is written" || die "uncovered: rc $rc: $out"
LC=$(lk S5 "$T/delta:lead" "app builds" "app builds"); n=$(nreq); out=$(SWITCHBOARD_SESSION_ID=S5 "$B" task request --to "$T/eps:builder" --subject "APP Builds: nightly" --key lk5 --link "$LC" 2>/dev/null)
echo "$out" | grep -q -x "t[0-9a-f]\{8\} requested from eps:builder: APP Builds: nightly" && [ "$(nreq)" -eq $((n+1)) ] && ok "a covered request over the link (an entry and ':', any case) is accepted and still prints its one line" || die "covered: $out"
TS=$(echo "$out" | awk '{print $1}'); edl "$LC" covers '["docs only"]'
"$B" task "$TS" | has -x "  link $LC: covers list does not name the subject" && "$B" task "$TS" --json | jq -e '.link.covers == ["docs only"] and .link.scope_covers_subject == false' >/dev/null \
  && ok "a covers list that stopped naming the subject after the request says so, judged at read time" || die "covers: $("$B" task "$TS" | grep link)"
LX=$(lk S5 "$T/delta:lead" "app"); edl "$LX" until "$(( $(date +%s) - 60 ))"; n=$(nreq); out=$(SWITCHBOARD_SESSION_ID=S5 "$B" task request --to "$T/eps:builder" --subject "app@1111111" --key lk6 --link "$LX" 2>&1 >/dev/null) && rc=0 || rc=$?
[ "$rc" -eq 1 ] && echo "$out" | has "does not cover this request: it is expired, revoked or a proposal not yet accepted. Nothing was written\.$" && [ "$(nreq)" -eq "$n" ] && ok "an expired link is refused at request time and nothing is written" || die "expired: rc $rc: $out"
LW=$(lk SD2 "$T/delta:scout" "app"); n=$(nreq); out=$(SWITCHBOARD_SESSION_ID=S5 "$B" task request --to "$T/eps:builder" --subject "app@2222222" --key lk7 --link "$LW" 2>&1 >/dev/null) && rc=0 || rc=$?
[ "$rc" -eq 1 ] && echo "$out" | has "does not cover this request: it runs from delta:scout to eps:builder, and this request is from delta:lead to eps:builder\. Nothing was written\.$" && [ "$(nreq)" -eq "$n" ] && ok "a request from an address that is not the link's from is refused at request time" || die "wrong requester: rc $rc: $out"
LV=$(lk S5 "$T/delta:lead" "app"); n=$(nreq); out=$(SWITCHBOARD_SESSION_ID=S5 "$B" task request --to "$T/delta:scout" --subject "app@3333333" --key lk8 --link "$LV" 2>&1 >/dev/null) && rc=0 || rc=$?
[ "$rc" -eq 1 ] && echo "$out" | has "it runs from delta:lead to eps:builder, and this request is from delta:lead to delta:scout\. Nothing was written\.$" && [ "$(nreq)" -eq "$n" ] && ok "a request to an address that is not the link's to is refused at request time" || die "wrong worker: rc $rc: $out"
n=$(find "$SWITCHBOARD_DIR/tasks" -name 000-request.json | wc -l); out=$(SWITCHBOARD_SESSION_ID=S5 "$B" task request --to "$T/eps:builder" --subject "x" --key lk4 --link lffffff 2>&1) && die "bogus link accepted" || true
echo "$out" | has -x "switchboard: no link lffffff. Nothing was written." && [ "$(find "$SWITCHBOARD_DIR/tasks" -name 000-request.json | wc -l)" -eq "$n" ] && "$B" task "$TID" --json | has '"link": null' && ok "a link id with no link file is refused at write time; a request naming none has link null" || die "bogus link: $out"

# ---- covers: a link names the subject prefixes it covers (F-017: free text matched "Build" in "builder's" and
# "Karim" in a clause listing what the link may not do). The scope below is a real one from the board
RS="the architect assigns and sequences stations-eval and stations-dev work (ROADMAP steps, PLAN-04/05/07, converge, line-fixes), re-orders or pauses tasks. Everything in the builder's own scope stays the builder's call. Karim alone: kernel acks, ROADMAP decisions, anything public."
refused(){ # link subject key: rc 1, the refusal on stderr, nothing written
  local n; n=$(nreq); out=$(SWITCHBOARD_SESSION_ID=S5 "$B" task request --to "$T/eps:builder" --subject "$2" --key "$3" --link "$1" 2>&1 >/dev/null) && rc=0 || rc=$?
  [ "$rc" -eq 1 ] && [ "$(nreq)" -eq "$n" ]; }
LR=$(lk S5 "$T/delta:lead" "$RS" "ROADMAP steps, eval-all")
refused "$LR" "Karim: the .githooks/pre-push hold check (t9b8549a2) is yours" cv1 && echo "$out" | has -F "link $LR covers: ROADMAP steps, eval-all; the subject must start with one of them" \
  && refused "$LR" "Build: host_name() helper in the evaluator" cv2 && refused "$LR" "ROADMAP steps and more" cv3 && refused "$LR" "eval-all-nightly: x" cv4 \
  && ok "with a covers list, \"Karim: ...\", \"Build: ...\", and an entry followed by anything but ':' or '@' are refused at send, though the scope has those words" || die "covers refusals: rc $rc: $out"
TR=$(rq "ROADMAP steps: bundle 0.4.40" cv5 "$LR"); TE=$(rq "eval-all@c3917ed" cv6 "$LR"); TQ=$(rq "eval-all" cv7 "$LR")
[ -n "$TR" ] && [ -n "$TE" ] && [ -n "$TQ" ] && "$B" task "$TR" | has -x "  link $LR: ok" && "$B" task "$TQ" --json | jq -e '.link.verdict == "ok" and .link.covers == ["ROADMAP steps", "eval-all"]' >/dev/null \
  && ok "an entry followed by ':' or '@', or equal to the whole subject, is covered" || die "covered by list: $TR $TE $TQ $("$B" task "$TQ" --json | jq -c .link)"
TB=$(rq "ROADMAP steps: later judged" cv9 "$LR"); edl "$LR" covers '["eval-all"]'
[ "$("$B" task "$TB" --json | jq -r .link.verdict)" = "covers list does not name the subject" ] && ok "a subject the list no longer covers is judged uncovered at read time" || die "read time: $("$B" task "$TB" --json | jq -c .link)"
# a covers key that is not a list of text covers nothing, and never falls back to the scope
edl "$LR" covers '"ROADMAP steps"'; v1=$("$B" task "$TR" --json | jq -r .link.verdict); edl "$LR" covers '[]'; v2=$("$B" task "$TR" --json | jq -r .link.verdict)
edl "$LR" covers '["eval-all"]'
[ "$v1" = "covers list does not name the subject" ] && [ "$v2" = "$v1" ] && ok "a covers key that is not a list of text, or an empty list, covers nothing" || die "bad covers: $v1 / $v2"

# ---- no covers list: a link made before 0.7.0 falls back to whole words of its scope, and says so
for i in 1 2; do hook PostToolUse "$T/eps" S6 Read '{}' >/dev/null; done   # the earlier tasks' notes out of the way
LO=$(lk S5 "$T/delta:lead" "$RS" "Karim, Build"); python3 - "$SWITCHBOARD_DIR/links/$LO.json" <<'PY'
import json,sys; f=sys.argv[1]; d=json.load(open(f)); del d["covers"]; json.dump(d,open(f,"w"))
PY
refused "$LO" "Build: host_name() helper in the evaluator" fb1 && echo "$out" | has -F "it has no covers list, so its scope words are used, and its scope" \
  && ok "no list: \"Build: ...\" is refused, \"Build\" is not a whole word of \"builder's\"" || die "fallback Build: rc $rc: $out"
TK=$(rq "Karim: the .githooks/pre-push hold check (t9b8549a2) is yours" fb2 "$LO"); note=$(hook PostToolUse "$T/eps" S6 Read '{}' | ctx)
[ -n "$TK" ] && "$B" task "$TK" | has -x "  link $LO: ok, by scope words (no covers list)" \
  && "$B" task "$TK" --json | jq -e '.link.verdict == "ok" and .link.covers == "scope words (no covers list)" and .link.scope_covers_subject' >/dev/null \
  && echo "$note" | grep -A2 -F "$TK" | has -F "Link $LO has no covers list, so its scope words make this an instruction you act on" \
  && ok "no list: \"Karim: ...\" is still covered by the whole word \"Karim\", and the verdict and the worker's note say it is the scope words" || die "fallback Karim: $TK $("$B" task "$TK" --json | jq -c .link) / $note"
TP=$(rq "ROADMAP steps: x" fb3 "$LO"); TW=$(rq "PLAN-04/05/07" fb4 "$LO")
[ -n "$TP" ] && [ -n "$TW" ] && [ -z "$(rq "line: x" fb5 "$LO")" ] && [ -z "$(rq "eval: x" fb6 "$LO")" ] \
  && ok "no list: whole words of the scope cover; a word joined to another by '-' (line-fixes, stations-eval) does not" || die "fallback words: $TP $TW"
# the scope stops naming a subject after the request: not ok at read time, and the worker's note says so (20); refused at send
TV=$(rq "Karim: judged later" fb7 "$LO"); edl "$LO" scope '"docs only"'
[ -n "$TV" ] && "$B" task "$TV" | has -x "  link $LO: scope does not name the subject" \
  && "$B" task "$TV" --json | jq -e '.link.verdict == "scope does not name the subject" and .link.covers_mode == "scope words" and (.link.scope_covers_subject | not)' >/dev/null \
  && ok "no list: a scope that stopped naming the subject after the request reads scope does not name the subject" || die "fallback read time: $("$B" task "$TV" --json | jq -c .link)"
refused "$LO" "app: x" fb8 && echo "$out" | has -xF "switchboard: link $LO does not cover this request: it has no covers list, so its scope words are used, and its scope 'docs only' does not name the subject (the subject, its part before ':' or '@', or an id in it must appear in the scope as whole words). Nothing was written." \
  && ok "no list: a subject the scope does not name is refused at send with the scope quoted, and nothing is written" || die "fallback send: rc $rc: $out"

# ---- a new link needs --covers: at least one entry, 3 to 80 characters, no ':' or '@'
nl(){ ls "$SWITCHBOARD_DIR"/links/*.json | grep -c .; }
mk(){ local n; n=$(nl); out=$(SWITCHBOARD_SESSION_ID=S5 "$B" link --from "$T/delta:lead" --to "$T/eps:builder" --scope "s" "$@" 2>&1) && rc=0 || rc=$?
  [ "$rc" -eq 1 ] && [ "$(nl)" -eq "$n" ]; }
mk && echo "$out" | has -xF "switchboard: a link needs --covers, the subject prefixes it covers, comma-separated. For example --covers \"ROADMAP steps, eval-all\" covers a task whose subject starts \"ROADMAP steps: ...\" or \"eval-all: ...\". Nothing was written." \
  && ok "a link without --covers is refused with the flag and an example, and nothing is written" || die "no covers: rc $rc: $out"
mk --covers "ok entry, ab" && echo "$out" | has -F "entry 'ab' must be 3 to 80 characters" && mk --covers "eval: all" && mk --covers "app@x" && mk --covers " , " \
  && mk --covers "$(printf 'x%.0s' $(seq 81))" && ok "an entry under 3 or over 80 characters, one with ':' or '@', and an empty list are refused" || die "bad entries: rc $rc: $out"
bad=""   # DEL, U+0085 (next line), U+2028 (line separator), U+2029, U+200B (zero width space): Cc, Cc, Zl, Zp, Cf
for c in '\177' '\302\205' '\342\200\250' '\342\200\251' '\342\200\213'; do
  mk --covers "$(printf "abc${c}def")" && echo "$out" | has -F "no control or invisible characters" || bad="$bad $c"; done
[ -z "$bad" ] && ok "an entry with DEL, U+0085, U+2028, U+2029 or U+200B is refused, and nothing is written" || die "control entries:$bad: $out"
LD=$(lk S5 "$T/delta:lead" "dedup" " eval-all ,ROADMAP steps,, EVAL-ALL ")
[ "$(jq -c .covers "$SWITCHBOARD_DIR/links/$LD.json")" = '["eval-all","ROADMAP steps"]' ] && ok "entries are trimmed, empty ones dropped and repeats in any case kept once" || die "dedup: $(jq -c .covers "$SWITCHBOARD_DIR/links/$LD.json")"

# ---- links shows the list on its own line, row 1 as before; links --json has covers, null for a link with none
"$B" links > "$T/links.txt"; "$B" links --json > "$T/links.json"
grep -A3 "^$LR " "$T/links.txt" | has -x "    covers: eval-all" && grep -A3 "^$LO " "$T/links.txt" | has -x "    covers: scope words (no covers list)" \
  && grep "^$LR " "$T/links.txt" | has "^$LR  delta:lead -> eps:builder.*  scope: the architect.*  today 0/100  last activity" \
  && jq -e --arg r "$LR" --arg o "$LO" '[.links[] | select(.id == $r) | .covers] == [["eval-all"]] and [.links[] | select(.id == $o) | .covers] == [null]' "$T/links.json" >/dev/null \
  && ok "board links shows covers on an indented line under an unchanged row 1; --json has the list, null when there is none" || die "links: $(grep -A3 "^$LR " "$T/links.txt") / $(jq -c '[.links[] | {id, covers}]' "$T/links.json")"
# covers_mode: links --json and task --json agree, for a list, no list, and a covers key that does not read
edl "$LD" covers '"eval-all"'; TM=$(SWITCHBOARD_SESSION_ID=S5 "$B" task request --to "$T/eps:builder" --subject "eval-all" --key cm1 --link "$LD" --no-sign 2>/dev/null | awk 'NR==1{print $1}') || true
[ -z "$TM" ] || die "setup: a malformed covers list covered $TM"
edl "$LD" covers '["eval-all"]'; TM=$(rq "eval-all" cm2 "$LD"); edl "$LD" covers '"eval-all"'
"$B" links --json > "$T/links.json"; mode(){ jq -r --arg l "$1" '.links[] | select(.id == $l) | .covers_mode' "$T/links.json"; }
tmode(){ "$B" task "$1" --json | jq -r .link.covers_mode; }
[ "$(mode "$LR")" = list ] && [ "$(tmode "$TB")" = list ] && [ "$(mode "$LO")" = "scope words" ] && [ "$(tmode "$TV")" = "scope words" ] \
  && [ "$(mode "$LD")" = none ] && [ "$(tmode "$TM")" = none ] \
  && ok "links --json and task --json give the same covers_mode: list, scope words, and none for a covers key that does not read" \
  || die "covers_mode: $(mode "$LR")/$(tmode "$TB") $(mode "$LO")/$(tmode "$TV") $(mode "$LD")/$(tmode "$TM")"

finish
