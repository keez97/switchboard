#!/usr/bin/env bash
# a request may name a link
source "$(dirname "$0")/../lib.sh"
fx_delta_eps; seat SD2 "$T/delta" "second in delta"; hook SessionStart "$T/delta" SD2 >/dev/null   # SD2 takes delta:scout below
TID=$(SWITCHBOARD_SESSION_ID=S5 "$B" task request --to "$T/eps:builder" --subject "no link" --key k1 | awk '{print $1}')

lk(){ SWITCHBOARD_SESSION_ID="$1" "$B" link --from "$2" --to "$T/eps:builder" --scope "$3" --until 30d | awk 'NR==1{print $2}'; }
rq(){ SWITCHBOARD_SESSION_ID=S5 "$B" task request --to "$T/eps:builder" --subject "$1" --key "$2" --link "$3" 2>/dev/null | awk '{print $1}'; }
LK=$(lk S5 "$T/delta:lead" "evaluate app builds for eps"); TK=$(rq "app@abc1234" lk1 "$LK")
"$B" task "$TK" | has -x "  link $LK: ok" && "$B" task "$TK" --json | python3 -c "import json,sys; l=json.load(sys.stdin)['link']; sys.exit(0 if l=={'id':'$LK','verdict':'ok','scope':'evaluate app builds for eps','active':True,'from_is_requester':True,'to_is_worker':True,'scope_covers_subject':True} else 1)" && grep -q "\"link\": \"$LK\"" "$SWITCHBOARD_DIR"/tasks/eps--builder/"$TK"/000-request.json && ok "a request naming a live link from the requester's own address shows link ok in text and json" || die "link ok: $("$B" task "$TK" --json | python3 -c "import json,sys; print(json.load(sys.stdin)['link'])")"
"$B" unlink "$LK" --reason "done" >/dev/null; "$B" task "$TK" | has -x "  link $LK: link revoked" && "$B" task "$TK" --json | has '"active": false' && ok "after unlink the same request shows link revoked, judged at read time" || die "revoked: $("$B" task "$TK" | grep link)"
edl(){ python3 - "$SWITCHBOARD_DIR/links/$1.json" "$2" "$3" <<'PY'   # rewrite one key of a link record, as an older board or another machine could leave it
import json,sys
f,k,v=sys.argv[1:4]; d=json.load(open(f)); d[k]=json.loads(v); json.dump(d,open(f,"w"))
PY
}
nreq(){ find "$SWITCHBOARD_DIR/tasks" -name 000-request.json | wc -l; }
LF=$(lk S5 "$T/delta:lead" "app"); TF=$(rq "app@def5678" lk2 "$LF"); edl "$LF" from "{\"repo\":\"$T/delta\",\"role\":\"scout\"}"
"$B" task "$TF" | has -x "  link $LF: from is not the requester" && ok "a request written before the link's from changed shows from is not the requester, judged at read time" || die "from: $("$B" task "$TF" | grep link)"
LS=$(lk S5 "$T/delta:lead" "docs only"); n=$(nreq); out=$(SWITCHBOARD_SESSION_ID=S5 "$B" task request --to "$T/eps:builder" --subject "app@0a1b2c3" --key lk3 --link "$LS" 2>&1 >/dev/null) && rc=0 || rc=$?
[ "$rc" -eq 1 ] && echo "$out" | has -x "switchboard: link $LS does not cover this request: its scope 'docs only' does not name the subject (the subject, its part before ':' or '@', or an id in it must appear in the scope). Nothing was written." && [ "$(nreq)" -eq "$n" ] && ok "a link whose scope does not name the subject is refused at request time, quoting the scope, and nothing is written" || die "uncovered: rc $rc: $out"
LC=$(lk S5 "$T/delta:lead" "app builds"); n=$(nreq); out=$(SWITCHBOARD_SESSION_ID=S5 "$B" task request --to "$T/eps:builder" --subject "app builds: nightly" --key lk5 --link "$LC" 2>/dev/null)
echo "$out" | grep -q -x "t[0-9a-f]\{8\} requested from eps:builder: app builds: nightly" && [ "$(nreq)" -eq $((n+1)) ] && ok "a covered request over the link is accepted and still prints its one line" || die "covered: $out"
TS=$(echo "$out" | awk '{print $1}'); edl "$LC" scope '"docs only"'
"$B" task "$TS" | has -x "  link $LC: scope does not name the subject" && ok "a scope that stopped naming the subject after the request says so, judged at read time" || die "scope: $("$B" task "$TS" | grep link)"
LX=$(lk S5 "$T/delta:lead" "app"); edl "$LX" until "$(( $(date +%s) - 60 ))"; n=$(nreq); out=$(SWITCHBOARD_SESSION_ID=S5 "$B" task request --to "$T/eps:builder" --subject "app@1111111" --key lk6 --link "$LX" 2>&1 >/dev/null) && rc=0 || rc=$?
[ "$rc" -eq 1 ] && echo "$out" | has "does not cover this request: it is expired, revoked or a proposal not yet accepted. Nothing was written\.$" && [ "$(nreq)" -eq "$n" ] && ok "an expired link is refused at request time and nothing is written" || die "expired: rc $rc: $out"
LW=$(lk SD2 "$T/delta:scout" "app"); n=$(nreq); out=$(SWITCHBOARD_SESSION_ID=S5 "$B" task request --to "$T/eps:builder" --subject "app@2222222" --key lk7 --link "$LW" 2>&1 >/dev/null) && rc=0 || rc=$?
[ "$rc" -eq 1 ] && echo "$out" | has "does not cover this request: it runs from delta:scout to eps:builder, and this request is from delta:lead to eps:builder\. Nothing was written\.$" && [ "$(nreq)" -eq "$n" ] && ok "a request from an address that is not the link's from is refused at request time" || die "wrong requester: rc $rc: $out"
LV=$(lk S5 "$T/delta:lead" "app"); n=$(nreq); out=$(SWITCHBOARD_SESSION_ID=S5 "$B" task request --to "$T/delta:scout" --subject "app@3333333" --key lk8 --link "$LV" 2>&1 >/dev/null) && rc=0 || rc=$?
[ "$rc" -eq 1 ] && echo "$out" | has "it runs from delta:lead to eps:builder, and this request is from delta:lead to delta:scout\. Nothing was written\.$" && [ "$(nreq)" -eq "$n" ] && ok "a request to an address that is not the link's to is refused at request time" || die "wrong worker: rc $rc: $out"
n=$(find "$SWITCHBOARD_DIR/tasks" -name 000-request.json | wc -l); out=$(SWITCHBOARD_SESSION_ID=S5 "$B" task request --to "$T/eps:builder" --subject "x" --key lk4 --link lffffff 2>&1) && die "bogus link accepted" || true
echo "$out" | has -x "switchboard: no link lffffff. Nothing was written." && [ "$(find "$SWITCHBOARD_DIR/tasks" -name 000-request.json | wc -l)" -eq "$n" ] && "$B" task "$TID" --json | has '"link": null' && ok "a link id with no link file is refused at write time; a request naming none has link null" || die "bogus link: $out"

finish
