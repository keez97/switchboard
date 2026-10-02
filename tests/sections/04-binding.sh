#!/usr/bin/env bash
# binding a link's ends to the sessions that hold them
source "$(dirname "$0")/../lib.sh"
fx_repos beta gamma   # bystanders: gamma must not hear of a bind, beta only of what expires

mkrepo "$T/delta"; mkrepo "$T/eps"; for r in delta eps; do "$B" register "$T/$r" >/dev/null; done
P5=$(fake S5 "$T/delta" planner); P6=$(fake S6 "$T/eps" worker)
for s in "S5 delta" "S6 eps"; do set -- $s; hook SessionStart "$T/$2" $1 >/dev/null; done
out=$(SWITCHBOARD_SESSION_ID=S5 "$B" link --from "$T/delta:lead" --to "$T/eps:builder" --scope "bind test" --cap 9); L2=$(echo "$out" | awk 'NR==1{print $2}')
"$B" who --role lead | has "sock.$P5" && "$B" who --role builder | has "sock.$P6" && ok "at creation the creator's end binds to the creator and a sole candidate binds to the other end" || die "creation binding wrong: $out"
up "$T/eps" S6 "$(peer "$T/sock.$P5" planner "build Z")" | has "bound to link $L2 as builder.*Robin authorised delta:lead" && ok "the first message tells the woken session it is bound and authorised" || die "no bound note on first message"
[ -z "$(hook PostToolUse "$T/eps" S6 Read '{}' | grep "bound to link")" ] && ok "the bound note is not repeated" || die "bound note repeated"
hook PostToolUse "$T/delta" S5 Read '{}' | has "bound to link $L2 as lead" && ok "a bound session that gets no message learns it at its next hook" || die "creator not told"

mkrepo "$T/zeta"; "$B" register "$T/zeta" >/dev/null
P7=$(fake S7 "$T/zeta" one); P8=$(fake S8 "$T/zeta" two); P9=$(fake S9 "$T/zeta" "zeta work @Builder")
for s in S7 S8 S9; do hook SessionStart "$T/zeta" $s >/dev/null; done
out=$(SWITCHBOARD_SESSION_ID=S5 "$B" link --from "$T/delta:lead" --to "$T/zeta:builder" --scope "tag test")
"$B" who "$T/zeta" --role builder | has "sock.$P9" && ok "an @tagged session wins over several others" || die "tag did not win: $out"
n=$(ls "$SWITCHBOARD_DIR/links" | wc -l)
out=$(SWITCHBOARD_SESSION_ID=S5 "$B" link --from "$T/delta:lead" --to "$T/zeta:tester" --scope "ambiguous" 2>&1) && die "ambiguous link did not fail" || true
echo "$out" | has "to=uds:$T/sock.$P7" && echo "$out" | has "to=uds:$T/sock.$P8" && [ "$(ls "$SWITCHBOARD_DIR/links" | wc -l)" -eq "$n" ] && ok "several untagged candidates: nothing is created and the candidates are listed" || die "ambiguity not reported: $out"
SWITCHBOARD_SESSION_ID=S5 "$B" link --from "$T/delta:lead" --to "$T/zeta:tester" --scope "ambiguous" --to-session "uds:$T/sock.$P8" >/dev/null
"$B" who "$T/zeta" --role tester | has "sock.$P8" && ok "the rerun with --to-session binds the chosen session" || die "--to-session did not bind"

mkrepo "$T/eta"; "$B" register "$T/eta" >/dev/null
out=$(SWITCHBOARD_SESSION_ID=S5 "$B" link --from "$T/delta:lead" --to "$T/eta:fixer" --scope "open end test"); L4=$(echo "$out" | awk 'NR==1{print $2}')
echo "$out" | has "eta:fixer open" && ok "no live session: the link is created with that end open" || die "open end not reported: $out"
send PreToolUse "$T/delta" S5 "$T/sock.gone" "anyone there" | has "end open, nothing sent" && ok "a send towards an open end is refused" || die "open-end send not refused"
PA=$(fake SA "$T/eta" plain)   # already running, never published: no SessionStart
up "$T/eta" SA "hello" | has "link $L4 has an open end fixer" && ok "the offer reaches a session that was already running" || die "no offer to a running session"
"$B" who "$T/eta" --role fixer | has "no live session" && ok "an untagged session is offered the end, never bound silently" || die "untagged session bound"
[ -z "$(hook PostToolUse "$T/eta" SA Read '{}' | grep "open end")" ] && [ -z "$(up "$T/eta" SA "again" | grep "open end")" ] && ok "the offer is shown once" || die "offer repeated"
PB=$(fake SB "$T/eta" "eta @fixer"); hook SessionStart "$T/eta" SB >/dev/null
"$B" who "$T/eta" --role fixer | has "sock.$PB" && ok "an open end binds later to a tagged session" || die "tagged session not bound later"
hook SessionStart "$T/delta" sD9 >/dev/null; hook SessionStart "$T/gamma" sG9 >/dev/null   # drain: a hook delivers the newest 5 only
"$B" bind "$L4" fixer --session "uds:$T/sock.$PA" >/dev/null
"$B" who "$T/eta" --role fixer | has "sock.$PA" && ! "$B" who "$T/eta" --role fixer | has "sock.$PB" && ok "bind moves an end and releases the old binding" || die "bind did not move the end"
python3 - "$(grep -l "moved with board bind" "$SWITCHBOARD_DIR"/events/*.json)" <<'PY' && ok "a bind posts its event to the two repos of the link only" || die "bind event went elsewhere"
import json,sys; a=json.load(open(sys.argv[1]))["affects"]; sys.exit(0 if len(a)==2 and any("-delta-" in x for x in a) and any("-eta-" in x for x in a) else 1)
PY
hook PostToolUse "$T/delta" sD9 Read '{}' | has "moved with board bind" && [ -z "$(hook PostToolUse "$T/gamma" sG9 Read '{}' | grep "moved with board bind")" ] && ok "the counterpart repo hears of it and an unrelated repo does not" || die "bind event delivery wrong"
resid "$PA" SAb
python3 -c "import json; print(json.dumps({'hook_event_name':'SessionStart','source':'clear','cwd':'$T/eta','session_id':'SAb'}))" | "$B" hook >/dev/null
"$B" who "$T/eta" --role fixer | has "sock.$PA" && [ "$("$B" who "$T/eta" | grep -c "sock.$PA")" -eq 1 ] && ok "a clear leaves the binding untouched and the seat is listed once" || die "clear broke the binding"
kill $PA; wait $PA 2>/dev/null || true; hook Stop "$T/delta" S5
python3 -c "import json,sys; sys.exit(0 if json.load(open('$SWITCHBOARD_DIR/sessions/east-SAb.json')).get('ended') else 1)" && ok "its presence record is ended, so other machines stop listing it" || die "dead session record not ended"
grep -lq "end eta:fixer is open (its session is gone)" "$SWITCHBOARD_DIR"/events/*.json && ok "a bound process that dies leaves its end open and both repos are told" || die "dead holder not reaped"

python3 - <<PY
import json,glob,time
for f in glob.glob("$SWITCHBOARD_DIR/events/*.json"):
    e=json.load(open(f)); e["ts"]-=40*86400; e["expires"]-=40*86400; json.dump(e,open(f,"w"))
PY
[ -z "$(hook SessionStart "$T/beta" sB9)" ] && ok "expired events are not delivered" || die "expired event delivered"
"$B" archive; [ -z "$(ls "$SWITCHBOARD_DIR/events")" ] && [ -n "$(find "$SWITCHBOARD_DIR/archive" -name '*.json')" ] && ok "old events move to archive, nothing deleted" || die "archive failed"
echo '{"hook_event_name":"SessionStart","cwd":"/nonexistent"' | "$B" hook && ok "malformed hook input never breaks a session" || die "hook crashed"

finish
