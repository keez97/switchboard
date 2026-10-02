#!/usr/bin/env bash
# a query a poller can loop on
source "$(dirname "$0")/../lib.sh"
fx_delta_eps; fx_repos gamma zeta; fx_holder SE2b   # SE2b holds eps:builder
CUR="$SWITCHBOARD_DIR/tasks/eps--builder/cursor-east.json"; cur(){ python3 -c "import json,sys; c=json.load(open(sys.argv[1])); print(c['machine'], c['seen'].get(sys.argv[2],0), c['polled'], ' '.join(sorted(c['seen'])))" "$CUR" "${1:-x}"; }
rq(){ SWITCHBOARD_SESSION_ID=S5 "$B" task request --to "$T/eps:builder" --subject "$1" --key "$2" | awk '{print $1}'; }
# at eps:builder: one completed, one working, one submitted 8 hours ago, and submitted ones seen and not seen
TID=$(rq "app@abc123" k1); SWITCHBOARD_SESSION_ID=SE2b "$B" task working "$TID" >/dev/null; SWITCHBOARD_SESSION_ID=SE2b "$B" task completed "$TID" >/dev/null
T2=$(rq second k9); SWITCHBOARD_SESSION_ID=SE2b "$B" task working "$T2" >/dev/null
OLD=$(SWITCHBOARD_NOW=$(( $(date +%s) - 8*3600 )) rq "old one" s1); CK=$(rq clock n1)
N0=$(rq "to be seen" c0); N2=$(rq "script seen" c2); N1=$(rq hooked h1)
for x in $N0 $N2; do SWITCHBOARD_SESSION_ID=SE2b "$B" task seen "$x" >/dev/null; done
[ "$(find "$SWITCHBOARD_DIR/tasks/eps--builder" -mindepth 1 -maxdepth 1 -name 't*' | grep -c .)" = 7 ] || die "setup: seven tasks at eps:builder"

EXP=$(python3 - "$SWITCHBOARD_DIR/tasks/eps--builder" <<'PY2'
import json,sys,glob,os
rows=[]
for d in glob.glob(sys.argv[1]+"/t*"):
    if not any(os.path.basename(f)[:3].isdigit() and not f.endswith("000-request.json") for f in glob.glob(d+"/*.json")):
        rows.append((json.load(open(d+"/000-request.json"))["ts"], os.path.basename(d)))
print("\n".join(t for _,t in sorted(rows)))
PY2
)
out=$("$B" tasks --for "$T/eps:builder" --open); [ "$out" = "$EXP" ] && [ "$(echo "$out" | head -1)" = "$OLD" ] && echo "$out" | has -x "$N0" && ! echo "$out" | has -x "$T2\|$TID" && ! echo "$out" | has -v '^t[0-9a-f]\{8\}$' && ok "--open prints only submitted ids, oldest first, a seen one included" || die "--open: $out vs $EXP"
[ -z "$("$B" tasks --for "$T/zeta:tester" --open)" ] && "$B" tasks --for "$T/zeta:tester" --open >/dev/null && ok "--open on an address with nothing prints nothing and exits 0" || die "--open empty"
for x in $OLD $CK $N1; do SWITCHBOARD_SESSION_ID=SE2b "$B" task seen "$x" >/dev/null; done   # only notified so far: the holder reads them
U1=$(SWITCHBOARD_SESSION_ID=S5 "$B" task request --to "$T/eps:builder" --subject "fresh" --key u1 | awk '{print $1}')
[ "$("$B" tasks --for "$T/eps:builder" --open --unseen)" = "$U1" ] && [ "$("$B" tasks --for "$T/eps:builder" --open | tail -1)" = "$U1" ] && ok "--unseen narrows to ids in no cursor" || die "--unseen: $("$B" tasks --for "$T/eps:builder" --open --unseen)"
echo '{"seen": ' > "$SWITCHBOARD_DIR/tasks/eps--builder/cursor-west.json"
out=$("$B" tasks --for "$T/eps:builder" --open 2>"$T/err"); [ "$out" = "$(printf '%s\n%s' "$EXP" "$U1")" ] && grep -q "cursor-west.json at eps:builder is unreadable" "$T/err" && "$B" task "$OLD" | has "(cursor-west.json unreadable)" && ok "a bad cursor file leaves --open listing, and says so on stderr only" || die "bad cursor: $out / $(cat "$T/err")"
rm "$SWITCHBOARD_DIR/tasks/eps--builder/cursor-west.json"
sm(){ python3 -c "import json,sys; print(json.dumps(json.load(open(sys.argv[1]))['seen'],sort_keys=True))" "$CUR"; }; s0=$(sm)
LATER=$(( $(date +%s) + 7500 ))
SWITCHBOARD_NOW=$LATER SWITCHBOARD_SESSION_ID=SE2b "$B" task seen | has -x "eps:builder polled by east" && [ "$(cur | awk '{print $3}')" = "$LATER" ] && [ "$(sm)" = "$s0" ] && ok "a bare seen stamps polled and never touches the seen map" || die "bare seen: $(cat "$CUR")"
h=$(shasum "$CUR"); SWITCHBOARD_NOW=$(( LATER + 60 )) SWITCHBOARD_SESSION_ID=SE2b "$B" task seen | has "polled by east within the hour; nothing written" && [ "$(shasum "$CUR")" = "$h" ] && (cd "$T/eps" && SWITCHBOARD_NOW=$(( LATER + 3700 )) "$B" task seen --for "$T/eps:builder") | has -x "eps:builder polled by east" && [ "$(sm)" = "$s0" ] && ok "a second bare seen within the hour writes nothing; a script names the address with --for" || die "bare seen hourly: $(cat "$CUR")"
out=$(cd "$T/gamma" && "$B" task seen 2>&1) && die "bare seen without an address passed" || true
echo "$out" | has "needs --for" && out=$(cd "$T/gamma" && "$B" task seen --for "$T/eps:builder" 2>&1) && die "bare seen outside the worker repo passed" || true
echo "$out" | has "Only the worker eps:builder writes its cursor" && ok "a bare seen needs an address and the worker check" || die "bare seen checks: $out"

finish
