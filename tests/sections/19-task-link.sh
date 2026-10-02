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
LF=$(lk SD2 "$T/delta:scout" "app"); TF=$(rq "app@def5678" lk2 "$LF")
"$B" task "$TF" | has -x "  link $LF: from is not the requester" && ok "a link whose from is another address shows from is not the requester" || die "from: $("$B" task "$TF" | grep link)"
LS=$(lk S5 "$T/delta:lead" "docs only"); TS=$(rq "app@0a1b2c3" lk3 "$LS")
"$B" task "$TS" | has -x "  link $LS: scope does not name the subject" && ok "a scope that does not name the subject says so" || die "scope: $("$B" task "$TS" | grep link)"
n=$(find "$SWITCHBOARD_DIR/tasks" -name 000-request.json | wc -l); out=$(SWITCHBOARD_SESSION_ID=S5 "$B" task request --to "$T/eps:builder" --subject "x" --key lk4 --link lffffff 2>&1) && die "bogus link accepted" || true
echo "$out" | has -x "switchboard: no link lffffff. Nothing was written." && [ "$(find "$SWITCHBOARD_DIR/tasks" -name 000-request.json | wc -l)" -eq "$n" ] && "$B" task "$TID" --json | has '"link": null' && ok "a link id with no link file is refused at write time; a request naming none has link null" || die "bogus link: $out"

finish
