#!/usr/bin/env bash
# a desktop clear: new process, same app session
source "$(dirname "$0")/../lib.sh"
fx_delta

mkrepo "$T/iota"; "$B" register "$T/iota" >/dev/null
PH=$(fake SH1 "$T/iota" "iota work" 1 local_hostA); sstart "$T/iota" SH1 >/dev/null
L5=$(SWITCHBOARD_SESSION_ID=S5 "$B" link --from "$T/delta:lead" --to "$T/iota:maker" --scope "clear test" | awk 'NR==1{print $2}')
"$B" who "$T/iota" --role maker | has "sock.$PH" || die "setup: maker not bound"
for i in 1 2; do post "$T/delta" S5 "$T/sock.$PH" "make part $i" >/dev/null; done
send_end "$T/iota" SH1 other; kill $PH; wait $PH 2>/dev/null || true
python3 -c "import json,sys; r=json.load(open(sys.argv[1])); sys.exit(0 if r.get('open') and r['was_host']=='local_hostA' and r['end_reason']=='other' and r['why'] else 1)" "$SWITCHBOARD_DIR"/roles/*iota*--maker.json && ok "an opened end keeps the app session id, why it opened and the SessionEnd reason" || die "open record lacks host or reason"
send PreToolUse "$T/delta" S5 "$T/sock.$PH" "anyone" | has "end open, nothing sent" && ok "between the clear and the next prompt the end is open and a send is refused" || die "send to a cleared end not refused"
seat SX1 "$T/iota" "iota work" 1 local_hostB; out=$(sstart "$T/iota" SX1)
echo "$out" | has "open end maker" && "$B" who "$T/iota" --role maker | has "no live session" && ok "a different app session in the same repo, same title, is offered the end and not rebound" || die "different host rebound: $out"
PH2=$(fake SH2 "$T/iota" "renamed" 1 local_hostA); out=$(sstart "$T/iota" SH2)
"$B" who "$T/iota" --role maker | has "sock.$PH2" && echo "$out" | has "holds role maker in link $L5" && echo "$out" | has "make part 2" && ok "a new pid and session id with the same app session id rebinds and gets the bound note with the last exchanges" || die "same host not rebound: $out"
grep -lq "same app session after a clear.*SessionEnd reason other" "$SWITCHBOARD_DIR"/events/*.json && ok "the rebind event says why the end had opened" || die "rebind event lacks the reason"
mkrepo "$T/kappa"; "$B" register "$T/kappa" >/dev/null
PN=$(fake SN1 "$T/kappa" plain); sstart "$T/kappa" SN1 >/dev/null
SWITCHBOARD_SESSION_ID=S5 "$B" link --from "$T/delta:lead" --to "$T/kappa:maker" --scope "no host test" >/dev/null
send_end "$T/kappa" SN1 other; kill $PN; wait $PN 2>/dev/null || true
seat SN2 "$T/kappa" plain; sstart "$T/kappa" SN2 | has "open end maker" && "$B" who "$T/kappa" --role maker | has "no live session" && ok "a missing app session id never matches a missing one" || die "empty host matched"

finish
