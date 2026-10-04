#!/usr/bin/env bash
# links a session makes: proposed, accepted by the other end, tight limits, widening refused, the guard on Bash
# shellcheck disable=SC2088  # the guard is given each command as a session writes it, ~/.claude/board unexpanded
source "$(dirname "$0")/../lib.sh"
export SWITCHBOARD_TEST_PROPOSE=1   # the fake sessions below get the rules a real session gets
fx_repos alpha beta gamma delta
P1=$(fake S1 "$T/alpha" road); P2=$(fake S2 "$T/beta" impl); P3=$(fake S3 "$T/gamma" other); P4=$(fake S4 "$T/beta" bystander)
P5=$(fake S5 "$T/delta" planner)
for s in "S1 alpha" "S2 beta" "S3 gamma" "S4 beta" "S5 delta"; do set -- $s; hook SessionStart "$T/$2" $1 >/dev/null; done
SWITCHBOARD_SESSION_ID=S1 "$B" role roadmap >/dev/null; SWITCHBOARD_SESSION_ID=S2 "$B" role implementer >/dev/null
try(){ "$@" 2>&1 || true; }   # a refusal exits non-zero; the check reads what it said
L(){ jq -r "$2" "$SWITCHBOARD_DIR/links/$1.json"; }
bashpre(){ python3 -c 'import json,sys; print(json.dumps({"hook_event_name":"PreToolUse","cwd":sys.argv[1],"session_id":sys.argv[2],"tool_name":"Bash","tool_input":{"command":sys.argv[3]}}))' "$@" | "$B" hook; }
ptu(){ hook PostToolUse "$1" "$2" Read '{}' | ctx; }
ev(){ python3 - "$SWITCHBOARD_DIR" "$1" <<'PY'
import json,glob,sys
for f in glob.glob(sys.argv[1]+"/events/*.json"):
    e=json.load(open(f))
    if sys.argv[2] in e["summary"]: print(len(e["affects"]), "all" in e["affects"], e["summary"])
PY
}
NOW=$(date +%s)

# ---- propose
out=$(SWITCHBOARD_SESSION_ID=S1 "$B" link --from "$T/alpha:roadmap" --to "$T/beta:implementer" --scope "order the next work items" --covers "order the next work items")
LP=$(echo "$out" | awk 'NR==1{print $2}')
[ "$(L "$LP" .state)" = proposed ] && [ "$(L "$LP" .cap)" = 0 ] && [ "$(L "$LP" .span)" = 86400 ] && { [ "$(L "$LP" .until)" -le "$NOW" ] || [ "$(L "$LP" .until)" -le $((NOW + 5)) ]; } \
  && e=$(L "$LP" .expires) && [ "$e" -gt $((NOW + 86400 - 60)) ] && [ "$e" -lt $((NOW + 86400 + 60)) ] && echo "$out" | has "proposed, not active" \
  && ok "board link from a session writes a proposal: no cap, 24 hours from acceptance, expiring unanswered in 24 hours" || die "proposal record: $out $(cat "$SWITCHBOARD_DIR/links/$LP.json")"
ev "link $LP proposed by" | has "^2 False .*alpha:roadmap (session \"road\" on east).*alpha:roadmap directs beta:implementer" && ok "the proposal is an event for its two repos, naming the proposer" || die "proposal event: $(ev "link $LP proposed")"
"$B" links | has "^proposed, not active" && "$B" links | has "^$LP .*waits for beta:implementer" && ! "$B" links | grep -v "^proposed" | grep "^$LP " | has "today" \
  && ok "board links lists the proposal apart from the active links" || die "links: $("$B" links)"

# ---- the other end is told, once, and nobody else
[ -z "$(AID=a1 pre PostToolUse "$T/beta" S2 u0 Read '{}' | ctx | grep "proposes link")" ] && ok "a subagent's tool call gets no proposal note" || die "subagent got the proposal"
n2=$(ptu "$T/beta" S2)
echo "$n2" | has "alpha:roadmap (session \"road\" on east) proposes link $LP: alpha:roadmap directs beta:implementer within: order the next work items" \
  && echo "$n2" | has "Accept only if the scope and the covers list fit the work this session is already doing" && echo "$n2" | has "board link accept $LP" \
  && echo "$n2" | has "board link decline $LP" && echo "$n2" | has "for 24 hours from acceptance, no cap" \
  && ok "the session holding the other end gets a note naming the proposer, direction, scope, limits and both commands" || die "proposal note: $n2"
[ -z "$(ptu "$T/beta" S2 | grep "proposes link")" ] && [ -z "$(up "$T/beta" S2 "next" | ctx | grep "proposes link")" ] && ok "the note is shown once per session" || die "note repeated"
[ -z "$(ptu "$T/alpha" S1 | grep "proposes link")" ] && [ -z "$(ptu "$T/gamma" S3 | grep "proposes link")" ] && [ -z "$(ptu "$T/beta" S4 | grep "proposes link")" ] \
  && ok "the proposer, a session in another repo and a session beside the holder get no note" || die "note to the wrong session"

# ---- a proposal carries no authority
up "$T/beta" S2 "$(peer "$T/sock.$P1" road "next: build X")" | ctx | has "no link covers this sender" && ! up "$T/beta" S2 "$(peer "$T/sock.$P1" road "again")" | has "authorised" \
  && ok "a message over a proposed link gets no authority header" || die "proposal gave authority"
# a proposal stores until = its creation, so code older than proposals reads it as expired; the state alone must hold too
jq ".until = $((NOW + 3600))" "$SWITCHBOARD_DIR/links/$LP.json" > "$T/lp" && mv "$T/lp" "$SWITCHBOARD_DIR/links/$LP.json"
up "$T/beta" S2 "$(peer "$T/sock.$P1" road "next: build Z")" | ctx | has "no link covers this sender" && ok "a proposal with an end date ahead still carries no authority" || die "state alone did not hold"
# a request over a proposal is refused now; one written before that (or by an older board) is made here by activating the link for the write
setstate(){ jq --arg s "$1" '.state = $s' "$SWITCHBOARD_DIR/links/$LP.json" > "$T/lp" && mv "$T/lp" "$SWITCHBOARD_DIR/links/$LP.json"; }
out=$(SWITCHBOARD_SESSION_ID=S1 "$B" task request --to "$T/beta:implementer" --subject "order the next work items" --key k0 --link "$LP" --no-sign 2>&1) || true; echo "$out" | has -x "switchboard: link $LP does not cover this request: it is expired, revoked or a proposal not yet accepted. Nothing was written." \
  && ok "a request over a proposed link is refused at request time" || die "request over a proposal was not refused: $out"
setstate active; SWITCHBOARD_SESSION_ID=S1 "$B" task request --to "$T/beta:implementer" --subject "order the next work items" --key k1 --link "$LP" --no-sign >/dev/null; setstate proposed
ptu "$T/beta" S2 | has "Link $LP does not cover this request (link proposed, not accepted)" && ok "a task over a proposed link is information the worker may decline" || die "task over proposal: $(ptu "$T/beta" S2)"

# ---- only the other end accepts
r3=$(SWITCHBOARD_SESSION_ID=S3 "$B" link accept "$LP" 2>&1) && die "S3 accepted" || true
r4=$(SWITCHBOARD_SESSION_ID=S4 "$B" link accept "$LP" 2>&1) && die "S4 accepted" || true
r1=$(SWITCHBOARD_SESSION_ID=S1 "$B" link accept "$LP" 2>&1) && die "the proposer accepted" || true
rt=$(env -u SWITCHBOARD_SESSION_ID "$B" link accept "$LP" 2>&1) && die "a terminal accepted" || true
echo "$r3" | has "needs a session in that repo" && echo "$r4" | has 'held by another session ("impl")' && echo "$r1" | has "This session proposed link" \
  && echo "$rt" | has "a terminal does not" && [ "$(L "$LP" .state)" = proposed ] && ok "a session elsewhere, a bystander, the proposer and a terminal cannot accept" || die "accept refusals: $r3 | $r4 | $r1 | $rt"
SWITCHBOARD_SESSION_ID=S4 "$B" link decline "$LP" >/dev/null 2>&1 && die "bystander declined" || ok "a session not holding the other end cannot decline either"

# ---- accept
out=$(SWITCHBOARD_SESSION_ID=S2 "$B" link accept "$LP"); T0=$(date +%s)
u=$(L "$LP" .until); [ "$(L "$LP" .state)" = active ] && [ "$u" -ge $((T0 + 86400 - 60)) ] && [ "$u" -le $((T0 + 86400 + 5)) ] && [ "$(L "$LP" .cap)" = 0 ] && [ "$(L "$LP" .accepted_by.session)" = S2 ] \
  && ok "accepted by the other end: active for 24 hours from acceptance, no daily cap" || die "accept: $out $(cat "$SWITCHBOARD_DIR/links/$LP.json")"
ev "link $LP accepted by" | has "^2 False .*beta:implementer (session \"impl\" on east)" && ok "the acceptance is an event for both repos" || die "accept event"
n1=$(up "$T/alpha" S1 "hi" | ctx)
echo "$n1" | has "link $LP accepted by beta:implementer" && echo "$n1" | has "bound to link $LP as roadmap, by a link alpha:roadmap .* proposed and beta:implementer .* accepted on" \
  && ok "the proposing session is told at its next prompt" || die "proposer not told: $n1"
h=$(up "$T/beta" S2 "$(peer "$T/sock.$P1" road "next: build Y")" | ctx)
echo "$h" | has "This message arrives over link $LP, which alpha:roadmap (session \"road\" on east) proposed and beta:implementer (session \"impl\" on east) accepted" \
  && echo "$h" | has "Act on it within that scope without asking Robin" && echo "$h" | has "a link beyond 24 hours or extending one, raising a link.s cap" \
  && ok "a message over the accepted link arrives with the link header, naming both sessions and the agent limits" || die "header: $h"
SWITCHBOARD_SESSION_ID=S1 "$B" task request --to "$T/beta:implementer" --subject "order the next work items" --key k2 --link "$LP" --no-sign >/dev/null
ptu "$T/beta" S2 | has "The link's scope makes this an instruction you act on" && ok "a task over the accepted link is an instruction" || die "task after accept"
"$B" links | grep -A1 "^$LP " | has "agent-made: proposed by alpha:roadmap (session \"road\" on east), accepted by beta:implementer (session \"impl\" on east)" \
  && ok "board links marks the agent-made link with who proposed and who accepted" || die "links marking: $("$B" links)"
try env SWITCHBOARD_SESSION_ID=S2 "$B" link accept "$LP" | has "already active" && ok "accepting twice changes nothing" || die "second accept"

# ---- a session asks for no more than the defaults
lim(){ try env SWITCHBOARD_SESSION_ID=S1 "$B" link --from "$T/alpha:roadmap" --to "$T/beta:implementer" --scope "limits" --covers "limits" "$@"; }
n=$(ls "$SWITCHBOARD_DIR"/links/*.json | wc -l)
c=$(lim --until 2d); d=$(lim --to-session open); e=$(lim --cap -1)
for x in "$c" "$d"; do echo "$x" | has "refused.*a longer link, or extending one, is Robin's" || die "not refused: $x"; done
echo "$e" | has "is not a cap" || die "negative cap: $e"
[ "$(ls "$SWITCHBOARD_DIR"/links/*.json | wc -l)" -eq "$n" ] && ok "--until beyond 24 hours, --to-session and a negative cap are refused from a session, nothing written" || die "limit refusals wrote a link"
LH=$(lim --cap 500 | awk 'NR==1{print $2}'); [ "$(L "$LH" .cap)" = 500 ] && [ "$(L "$LH" .state)" = proposed ] && ok "any cap on a proposal is fewer than no cap, so a session may set one" || die "cap on proposal: $LH"
LS=$(lim --cap 5 --until 12h | awk 'NR==1{print $2}'); [ "$(L "$LS" .cap)" = 5 ] && [ "$(L "$LS" .span)" = 43200 ] && ok "a session may ask for less: cap 5, 12 hours" || die "less refused: $LS"

# ---- widening stays the owner's; ending does not
SWITCHBOARD_SESSION_ID=S2 "$B" link-cap "$LP" 20 >/dev/null && [ "$(L "$LP" .cap)" = 20 ] && SWITCHBOARD_SESSION_ID=S2 "$B" link-cap "$LP" 10 >/dev/null && [ "$(L "$LP" .cap)" = 10 ] \
  && ok "a session may set a cap on an uncapped link and lower it" || die "lowering refused: $(L "$LP" .cap)"
o2=$(ptu "$T/beta" S2); o1=$(ptu "$T/alpha" S1); ! echo "$o2" | has "cap set to" && echo "$o1" | has "link $LP cap set to 20 messages a day" && echo "$o1" | has "link $LP cap set to 10 messages a day" \
  && ok "the session that set a cap is not told of its own act; the other end hears each change, two in one second too" || die "cap notes: setter $o2 | other end $o1"
try env SWITCHBOARD_SESSION_ID=S2 "$B" link-cap "$LP" 0 | has "Removing link $LP's cap (10 a day now) is Robin's" && try env SWITCHBOARD_SESSION_ID=S2 "$B" link-cap "$LP" -1 | has "refused. This command sets link $LP's cap to -1, which is not a cap. Nothing was written." \
  && ok "the CLI refusal says removing a cap, and a negative cap, for what they are" || die "cap removal text: $(try env SWITCHBOARD_SESSION_ID=S2 "$B" link-cap "$LP" 0)"
try env SWITCHBOARD_SESSION_ID=S1 "$B" link-cap "$LP" 50 | has "Raising link $LP's cap (10 a day now) is Robin's" && SWITCHBOARD_SESSION_ID=S2 "$B" link-cap "$LP" 0 >/dev/null 2>&1 && die "cap removed" || true
[ "$(L "$LP" .cap)" = 10 ] && ok "link-cap raising or removing the cap is refused from a session" || die "cap changed: $(L "$LP" .cap)"
try env SWITCHBOARD_SESSION_ID=S1 "$B" bind "$LP" implementer --session "uds:$T/sock.$P4" | has "is Robin's, from a terminal" && "$B" who --role implementer | has "sock.$P2" \
  && ok "board bind from a session is refused" || die "bind from a session"
env -u SWITCHBOARD_SESSION_ID "$B" link-cap "$LP" 40 >/dev/null && [ "$(L "$LP" .cap)" = 40 ] && ok "the owner's terminal still raises a cap" || die "terminal raise"

# ---- decline, expiry, unlink
LD=$(SWITCHBOARD_SESSION_ID=S1 "$B" link --from "$T/alpha:roadmap" --to "$T/beta:implementer" --scope "second thing" --covers "second thing" | awk 'NR==1{print $2}')
SWITCHBOARD_SESSION_ID=S2 "$B" link decline "$LD" --reason "not this session's work" >/dev/null
L "$LD" .closed_reason | has 'declined by beta:implementer (session "impl" on east): not this session.s work' && [ "$(L "$LD" '.revoked > 0')" = true ] \
  && ev "link $LD closed: declined" | has "^2 False" && up "$T/alpha" S1 "x" | ctx | has "link $LD closed: declined by" \
  && ok "a decline closes the proposal, is an event for both repos and reaches the proposer" || die "decline: $(cat "$SWITCHBOARD_DIR/links/$LD.json")"
[ -z "$(ptu "$T/beta" S2 | grep "closed: declined")" ] && ok "the declining session is not told of its own decline" || die "decliner told of its own decline"
try env SWITCHBOARD_SESSION_ID=S2 "$B" link accept "$LD" | has "not an open proposal" && ok "a declined proposal cannot be accepted" || die "accepted after decline"
LE=$(SWITCHBOARD_SESSION_ID=S1 "$B" link --from "$T/alpha:roadmap" --to "$T/beta:implementer" --scope "third thing" --covers "third thing" | awk 'NR==1{print $2}')
jq ".expires = $((NOW - 1))" "$SWITCHBOARD_DIR/links/$LE.json" > "$T/le" && mv "$T/le" "$SWITCHBOARD_DIR/links/$LE.json"
try env SWITCHBOARD_SESSION_ID=S2 "$B" link accept "$LE" | has "expired unanswered" && ok "an expired proposal cannot be accepted" || die "accepted after expiry"
hook UserPromptSubmit "$T/gamma" S3 >/dev/null
L "$LE" .closed_reason | has "^proposal expired unanswered after 24 hours" && ev "link $LE closed: proposal expired" | has "^2 False" \
  && up "$T/alpha" S1 "y" | ctx | has "link $LE closed: proposal expired" && ok "an unanswered proposal closes after 24 hours; both repos and the proposer hear it" || die "expiry: $(cat "$SWITCHBOARD_DIR/links/$LE.json")"
SWITCHBOARD_SESSION_ID=S2 "$B" unlink "$LP" --reason "done" >/dev/null && [ "$(L "$LP" '.revoked > 0')" = true ] \
  && L "$LP" .closed_reason | has -x 'ended by beta:implementer (session "impl" on east): done' && ok "a session holding an end may end the link" || die "unlink from an end"

# ---- an open other end: a session there holding no role accepts and is bound
LO=$(SWITCHBOARD_SESSION_ID=S1 "$B" link --from "$T/alpha:roadmap" --to "$T/gamma:reviewer" --scope "review the plan" --covers "review the plan" | awk 'NR==1{print $2}')
ptu "$T/gamma" S3 | has "Its end gamma:reviewer is open and this session holds no role here; accepting binds this session to it" && ok "an open other end is offered to a session there with no role" || die "open-end offer"
SWITCHBOARD_SESSION_ID=S3 "$B" link accept "$LO" | has "this session now holds gamma:reviewer" && "$B" who --role reviewer | has "sock.$P3" && [ "$(L "$LO" .state)" = active ] \
  && ok "accepting binds that session to the end" || die "open-end accept"

# ---- the proposer holds one end
out=$(SWITCHBOARD_SESSION_ID=S5 "$B" link --from "$T/delta:lead" --to "$T/alpha:roadmap" --scope "taking" --covers "taking" 2>&1)
echo "$out" | has "delta:lead held by this session (taken now)" && "$B" who --role lead | has "sock.$P5" && ok "a session with no role takes a free end in its repo as it proposes" || die "taking: $out"
try env SWITCHBOARD_SESSION_ID=S2 "$B" link --from "$T/beta:other" --to "$T/alpha:roadmap" --scope "x" --covers "test work" | has "This session holds beta:implementer" \
  && try env SWITCHBOARD_SESSION_ID=S2 "$B" link --from "$T/gamma:x" --to "$T/alpha:roadmap" --scope "x" --covers "test work" | has "needs a session in that repo" \
  && ok "a session proposes only from an end it holds or can take" || die "proposer end check"
LT=$(SWITCHBOARD_SESSION_ID=S5 "$B" link --from "$T/delta:lead" --to "$T/beta:implementer" --scope "either end" --covers "either end" | awk 'NR==1{print $2}')
SWITCHBOARD_SESSION_ID=S1 "$B" link --from "$T/beta:implementer" --to "$T/alpha:roadmap" --scope "reverse" --covers "reverse" | has "alpha:roadmap held by this session" && ok "the proposer may hold the --to end" || die "proposer at --to"

# ---- the owner's terminal is unchanged
LW=$(env -u SWITCHBOARD_SESSION_ID "$B" link --from "$T/alpha:roadmap" --to "$T/beta:implementer" --scope "owner work" --covers "owner work" | awk 'NR==1{print $2}'); T1=$(date +%s)
u=$(L "$LW" .until); [ "$(L "$LW" '.state // "none"')" = none ] && [ "$(L "$LW" .cap)" = 100 ] && [ "$u" -ge $((T1 + 7*86400 - 60)) ] && [ "$u" -le $((T1 + 7*86400 + 5)) ] \
  && up "$T/beta" S2 "$(peer "$T/sock.$P1" road "owner direction")" | ctx | has "Robin authorised alpha:roadmap on" && ok "a link from the owner's terminal is active at once, 7 days, cap 100, with the owner's header" || die "owner link: $(cat "$SWITCHBOARD_DIR/links/$LW.json")"
ev "link $LW created" | has "^1 True .*within: owner work (100 messages a day)$" && ok "the owner's link is still announced to every repo" || die "owner event: $(ev "link $LW created")"
tcap(){ env -u SWITCHBOARD_SESSION_ID SWITCHBOARD_NOW=$NOW "$B" link-cap "$LW" "$1" >/dev/null; }
ptu "$T/alpha" S1 >/dev/null; tcap 50; tcap 20; tcap 50
[ "$(ptu "$T/alpha" S1 | grep -o "link $LW cap set to [0-9]*" | awk '{print $NF}' | tr '\n' ' ')" = "50 20 50 " ] && ok "three cap changes in one second are three events, in the order they were made" || die "same-second caps: $(ls "$SWITCHBOARD_DIR/events" | tail -4)"
tcap 100; out=$(try env -u SWITCHBOARD_SESSION_ID "$B" link-cap "$LW" -1)
echo "$out" | has "refused. This command sets link $LW's cap to -1, which is not a cap. Nothing was written." && [ "$(L "$LW" .cap)" = 100 ] && ok "a negative cap is refused from the owner's terminal too, nothing written" || die "terminal -1: $out cap $(L "$LW" .cap)"
n=$(ls "$SWITCHBOARD_DIR"/links/*.json | wc -l); out=$(try env -u SWITCHBOARD_SESSION_ID "$B" link --from "$T/alpha:roadmap" --to "$T/beta:implementer" --scope "negative" --covers "negative" --cap -1)
echo "$out" | has "is not a cap" && [ "$(ls "$SWITCHBOARD_DIR"/links/*.json | wc -l)" -eq "$n" ] && ok "a terminal link with a negative cap is refused, nothing written" || die "terminal link -1: $out"
fx_repos cz0 cz1; LZ=$(env -u SWITCHBOARD_SESSION_ID "$B" link --from "$T/cz0:a" --to "$T/cz1:b" --scope "cap zero" --covers "cap zero" --cap 0 | awk 'NR==1{print $2}')
ev "link $LZ created" | has "within: cap zero (no cap)$" && ! ev "link $LZ created" | has "cap no cap" && ok "a terminal link with --cap 0 is announced with no cap" || die "cap 0 event: $(ev "link $LZ created")"

# ---- the PreToolUse guard: owner-only forms and detached link commands from any session
deny(){ bashpre "$T/alpha" S1 "$1" | has '"permissionDecision": "deny"'; }
deny "setsid ~/.claude/board link-cap $LW 500" && deny "nohup ~/.claude/board link --from alpha:roadmap --to beta:implementer --scope 'x y' --until 7d > /dev/null 2>&1 &" \
  && deny "env SWITCHBOARD_SESSION_ID=S2 ~/.claude/board link accept $LT" && deny "bash -c \"setsid $B link --from a:b --to c:d --scope 'r d' --cap 100\"" \
  && ok "the guard refuses owner-only forms wrapped in setsid, nohup, env or bash -c" || die "guard let a wrapped form through"
deny "setsid ~/.claude/board link --from alpha:roadmap --to beta:implementer --scope x" && deny "(~/.claude/board link accept $LT &)" \
  && deny "cd /tmp && SWITCHBOARD_ALLOW_TMP=1 $B link --from a:b --to c:d --scope x" \
  && deny "SWITCHBOARD_STATE=/tmp/s SWITCHBOARD_SESSIONS_DIR=/tmp/e ~/.claude/board link --from a:b --to c:d --scope x" \
  && deny "HOME=/tmp/h SWITCHBOARD_DIR=~/work/board ~/.claude/board link accept $LT" && ok "a link command run detached or with the board's identity variables is refused" || die "detached plain form allowed"
deny "~/.claude/board link --from a:b --to c:d --scope x --until=3d" && deny "board link --from a:b --to c:d --scope x --until 2026-12-31" && deny "~/.claude/board bind $LW implementer --session uds:x" \
  && deny "x=\$(~/.claude/board link-cap $LW 0)" && deny "~/.claude/board link --from a:b --to c:d --scope x --to-session open" && ok "--until beyond 24 hours, bind, removing a cap and --to-session are refused unwrapped too" || die "plain owner form allowed"
r=$(bashpre "$T/alpha" S1 "setsid ~/.claude/board link-cap $LW 500"); echo "$r" | has "Widening a link, and any link beyond 24 hours from acceptance, is Robin's" \
  && ok "the refusal says what the owner keeps and what a session may do" || die "refusal text: $r"
r0=$(bashpre "$T/alpha" S1 "~/.claude/board link-cap $LW 0"); rn=$(bashpre "$T/alpha" S1 "~/.claude/board link-cap $LW -1"); rr=$(bashpre "$T/alpha" S1 "~/.claude/board link-cap $LW 500")
echo "$r0" | has "This command removes link $LW's cap of 100 a day\." && echo "$rn" | has "This command sets link $LW's cap to -1, which is not a cap\. A negative cap is refused for everyone" && ! echo "$rn" | has "Widening" && echo "$rr" | has "raises link $LW's cap from 100 to 500 a day" \
  && ok "the guard says removing a cap and a negative cap for what they are, and a raise as a raise" || die "guard cap texts: $r0 | $rn | $rr"
allow(){ [ -z "$(bashpre "$T/alpha" S1 "$1")" ]; }
allow "~/.claude/board link --from a:b --to c:d --scope \"R&D, at board level\" --cap 5 --until 12h" && allow "~/.claude/board link --from a:b --to c:d --scope x --cap=500" && allow "~/.claude/board link-cap $LW 5" && allow "~/.claude/board unlink $LW && ~/.claude/board links 2>&1 | head" \
  && allow "git commit -qm \"setsid board link-cap $LW 100\"" && allow "SWITCHBOARD_OFF=1 ~/.claude/board link --from a:b --to c:d --scope x" && allow "~/.claude/board link accept $LT" && ok "proposing within limits, lowering, unlink, accept and prose that names a form pass" || die "guard false positive"

# ---- an agent link binds the two sessions that agreed, not whoever holds an end later
fx_repos pa pb pc pd
Q1P=$(fake Q1 "$T/pa" lead1); Q2P=$(fake Q2 "$T/pb" doer2); Q3P=$(fake Q3 "$T/pc" boss3); seat Q4 "$T/pd" hand4
for s in "Q1 pa" "Q2 pb" "Q3 pc" "Q4 pd"; do set -- $s; hook SessionStart "$T/$2" $1 >/dev/null; done
SWITCHBOARD_SESSION_ID=Q1 "$B" role lead >/dev/null; SWITCHBOARD_SESSION_ID=Q2 "$B" role doer >/dev/null
SWITCHBOARD_SESSION_ID=Q3 "$B" role boss >/dev/null; SWITCHBOARD_SESSION_ID=Q4 "$B" role hand >/dev/null
prop(){ try env SWITCHBOARD_SESSION_ID="$1" "$B" link --from "$T/pa:lead" --to "$T/pb:doer" --scope "$2" --covers "$2" | awk 'NR==1{print $2}'; }
hdr(){ up "$T/$1" "$2" "$(peer "$T/sock.$3" x "$4")" | ctx; }
LA=$(prop Q1 "agent pair A"); SWITCHBOARD_SESSION_ID=Q2 "$B" link accept "$LA" >/dev/null
# a /clear in the same process: new session id, same seat
resid "$Q2P" Q2b; send_end "$T/pb" Q2 clear >/dev/null
python3 -c "import json; print(json.dumps({'hook_event_name':'SessionStart','source':'clear','cwd':'$T/pb','session_id':'Q2b'}))" | "$B" hook >/dev/null
[ "$(L "$LA" '.revoked // 0')" = 0 ] && hdr pb Q2b "$Q1P" "after clear" | has "This message arrives over link $LA, which" && ok "a clear in the same process keeps the agent link and its header" || die "clear: $(cat "$SWITCHBOARD_DIR/links/$LA.json")"
# the accepting session ends
send_end "$T/pb" Q2b exit >/dev/null
L "$LA" .closed_reason | has "^the session that accepted it (pb:doer (session \"doer2\" on east)) no longer holds pb:doer: its session closed; a new proposal is needed" \
  && ev "link $LA closed: the session that accepted" | has "^2 False" && ok "the accepting session ending closes the agent link, with an event for both repos saying why" || die "accept end: $(cat "$SWITCHBOARD_DIR/links/$LA.json")"
seat Q7 "$T/pb" doer7; o7=$(hook SessionStart "$T/pb" Q7 | ctx)
jq 'del(.revoked)' "$SWITCHBOARD_DIR/links/$LA.json" > "$T/la" && mv "$T/la" "$SWITCHBOARD_DIR/links/$LA.json"   # as if the close had not reached this clone
o7="$o7$(ptu "$T/pb" Q7)"; ! echo "$o7" | grep "open end doer" | has "$LA" && ok "an agent link's open end is never offered to another session" || die "offered: $o7"
SWITCHBOARD_SESSION_ID=Q7 "$B" role doer >/dev/null
[ "$(L "$LA" '.revoked // 0')" != 0 ] || die "taking the role did not close the reopened record"
jq 'del(.revoked)' "$SWITCHBOARD_DIR/links/$LA.json" > "$T/la" && mv "$T/la" "$SWITCHBOARD_DIR/links/$LA.json"   # again: the check below is the second wall
h7=$(hdr pb Q7 "$Q1P" "direction to the new holder"); echo "$h7" | has "no link covers this sender" && ! ptu "$T/pb" Q7 | has "bound to link $LA" \
  && ok "a new holder of the accepting end gets no link header and no bound note, even from a link record still open" || die "new holder got authority: $h7"
python3 -c "import json,sys; d=json.load(open(sys.argv[1])); d['revoked']=1; json.dump(d,open(sys.argv[1],'w'))" "$SWITCHBOARD_DIR/links/$LA.json"
# the proposing session ends
LB=$(prop Q1 "agent pair B"); SWITCHBOARD_SESSION_ID=Q7 "$B" link accept "$LB" >/dev/null
[ "$(L "$LB" .state)" = active ] || die "setup: LB not accepted"
send_end "$T/pa" Q1 exit >/dev/null
L "$LB" .closed_reason | has "^the session that proposed it (pa:lead (session \"lead1\" on east)) no longer holds pa:lead: its session closed; a new proposal is needed" \
  && ok "the proposing session ending closes the agent link" || die "proposer end: $(cat "$SWITCHBOARD_DIR/links/$LB.json")"
Q8P=$(fake Q8 "$T/pa" lead8); hook SessionStart "$T/pa" Q8 >/dev/null; SWITCHBOARD_SESSION_ID=Q8 "$B" role lead >/dev/null
hdr pb Q7 "$Q8P" "direction from the new proposer end" | has "no link covers this sender" && ok "a new holder of the proposing end cannot direct over it" || die "new proposer end directed"
# the end taken over, a proposal whose proposer left, a process gone without SessionEnd
LC=$(prop Q8 "agent pair C"); SWITCHBOARD_SESSION_ID=Q7 "$B" link accept "$LC" >/dev/null
Q9P=$(fake Q9 "$T/pb" doer9); hook SessionStart "$T/pb" Q9 >/dev/null; SWITCHBOARD_SESSION_ID=Q9 "$B" role doer --take >/dev/null
L "$LC" .closed_reason | has "no longer holds pb:doer: the end moved to session \"doer9\"" && ok "another session taking the end closes the agent link" || die "takeover: $(cat "$SWITCHBOARD_DIR/links/$LC.json")"
LD=$(prop Q8 "agent pair D"); SWITCHBOARD_SESSION_ID=Q8 "$B" role other >/dev/null
L "$LD" .closed_reason | has "^the session that proposed it .* no longer holds pa:lead: its session took role other" && try env SWITCHBOARD_SESSION_ID=Q9 "$B" link accept "$LD" | has "not an open proposal" \
  && ok "a proposal closes when its proposer leaves its end, and cannot be accepted" || die "void proposal: $(cat "$SWITCHBOARD_DIR/links/$LD.json")"
SWITCHBOARD_SESSION_ID=Q8 "$B" role lead >/dev/null
LE2=$(prop Q8 "agent pair E"); SWITCHBOARD_SESSION_ID=Q9 "$B" link accept "$LE2" >/dev/null
kill "$Q9P"; hook UserPromptSubmit "$T/pc" Q3 >/dev/null
L "$LE2" .closed_reason | has "no longer holds pb:doer: its session is gone" && ok "a session gone without SessionEnd closes the agent link when it is reaped" || die "reap: $(cat "$SWITCHBOARD_DIR/links/$LE2.json")"
# an owner link is unchanged: its end opens, is offered, and the next holder gets the owner's header
LOW=$(env -u SWITCHBOARD_SESSION_ID "$B" link --from "$T/pc:boss" --to "$T/pd:hand" --scope "owner pair" --covers "owner pair" | awk 'NR==1{print $2}')
send_end "$T/pd" Q4 exit >/dev/null
seat QA "$T/pd" hand10; hook SessionStart "$T/pd" QA | ctx | has "link $LOW has an open end hand" && SWITCHBOARD_SESSION_ID=QA "$B" role hand >/dev/null \
  && [ "$(L "$LOW" '.revoked // 0')" = 0 ] && hdr pd QA "$Q3P" "owner direction" | has "Robin authorised pc:boss" && ok "an owner link survives its end changing holder, as before" || die "owner link: $(cat "$SWITCHBOARD_DIR/links/$LOW.json")"
# unlink: a session at either end, or the terminal; not a bystander
LF=$(prop Q8 "agent pair F"); seat QB "$T/pb" doer11; hook SessionStart "$T/pb" QB >/dev/null; SWITCHBOARD_SESSION_ID=QB "$B" link accept "$LF" >/dev/null
try env SWITCHBOARD_SESSION_ID=Q3 "$B" unlink "$LF" | has "holds neither end of link $LF" && [ "$(L "$LF" '.revoked // 0')" = 0 ] \
  && ok "a session holding neither end cannot unlink" || die "bystander unlinked: $(cat "$SWITCHBOARD_DIR/links/$LF.json")"
SWITCHBOARD_SESSION_ID=Q3 "$B" unlink "$LOW" >/dev/null && env -u SWITCHBOARD_SESSION_ID "$B" unlink "$LF" >/dev/null && [ "$(L "$LOW" '.revoked > 0')" = true ] && [ "$(L "$LF" '.revoked > 0')" = true ] \
  && ok "a session at an end, and the owner's terminal, may unlink" || die "unlink by end or terminal"
L "$LOW" .closed_reason | has -x 'ended by pc:boss (session "boss3" on east)' && L "$LF" .closed_reason | has -x "ended by Robin's terminal" \
  && ev "link $LOW closed: ended by pc:boss" | has "(pc:boss directed pd:hand)" && ok "the close names who ended the link: the session at its end, or the owner's terminal" || die "unlink reason: $(L "$LOW" .closed_reason) | $(L "$LF" .closed_reason)"
bashpre "$T/pc" Q3 "setsid ~/.claude/board unlink $LF" | has '"permissionDecision": "deny"' && [ -z "$(bashpre "$T/pc" Q3 "~/.claude/board unlink $LF")" ] \
  && ok "unlink run detached is refused by the guard; plain unlink passes" || die "guard unlink"

# a covers list the acceptor was not shown: a 0.6.0 proposal has none, and a 0.6.0 acceptance does not stamp the list
fx_repos px py
X1P=$(fake X1 "$T/px" lead20); seat X2 "$T/py" doer20
for s in "X1 px" "X2 py"; do set -- $s; hook SessionStart "$T/$2" $1 >/dev/null; done
SWITCHBOARD_SESSION_ID=X1 "$B" role lead >/dev/null; SWITCHBOARD_SESSION_ID=X2 "$B" role doer >/dev/null
LX=$(try env SWITCHBOARD_SESSION_ID=X1 "$B" link --from "$T/px:lead" --to "$T/py:doer" --scope "fix the client" --covers "client, deploy" | awk 'NR==1{print $2}')
FX="$SWITCHBOARD_DIR/links/$LX.json"; cp "$FX" "$T/lx.json"
jq 'del(.covers)' "$T/lx.json" > "$FX"; m0=$(md5sum < "$FX")   # the proposal as 0.6.0 writes it
out=$(SWITCHBOARD_SESSION_ID=X2 "$B" link accept "$LX" 2>&1) && rc=0 || rc=$?
[ "$rc" -ne 0 ] && echo "$out" | has -x "switchboard: proposal $LX has no covers list (made by an older switchboard): propose again with --covers. Nothing was written." \
  && [ "$(md5sum < "$FX")" = "$m0" ] && [ "$(L "$LX" .state)" = proposed ] \
  && ok "accepting a proposal with no covers list is refused and nothing is written" || die "no-covers accept: rc $rc: $out / $(cat "$FX")"
cp "$T/lx.json" "$FX"; SWITCHBOARD_SESSION_ID=X2 "$B" link accept "$LX" >/dev/null || die "setup: $LX not accepted"
xrq(){ SWITCHBOARD_SESSION_ID=X1 "$B" task request --to "$T/py:doer" --subject "$1" --key "$2" --link "$LX" --no-sign 2>&1; }
xv(){ "$B" task "$1" --json | jq -r .link.verdict; }
TX1=$(xrq "deploy: prod" kx1 | awk 'NR==1{print $1}')
[ "$(jq -c .accepted_by.covers "$FX")" = '["client","deploy"]' ] && [ "$(xv "$TX1")" = ok ] \
  && ok "acceptance stamps the covers list it showed; a subject the list covers and the scope does not is ok" || die "stamped: $(cat "$FX") / $(xv "$TX1")"
jq 'del(.accepted_by.covers)' "$FX" > "$T/lx2.json" && mv "$T/lx2.json" "$FX"   # the acceptance as 0.6.0 leaves it
nx=$(ptu "$T/py" X2); TX3=$(xrq "client: regenerate" kx3 | awk 'NR==1{print $1}'); out=$(xrq "deploy: staging" kx2) && rc=0 || rc=$?
[ "$(xv "$TX1")" = "scope does not name the subject, and the covers list was not shown at acceptance" ] && [ "$(xv "$TX3")" = ok ] \
  && [ "$rc" -ne 0 ] && echo "$out" | has -F "its covers list was not shown when it was accepted (by an older switchboard), so its scope 'fix the client' must name the subject too" \
  && [ "$(ls "$SWITCHBOARD_DIR/tasks/py--doer" | grep -c '^t')" -eq 2 ] \
  && ok "an acceptance without the stamp: the subject needs the covers list and the scope words, at read time and at send time" \
  || die "unstamped: $(xv "$TX1") / $(xv "$TX3") / rc $rc $out"
echo "$nx" | has "a task for you.*$TX1" && echo "$nx" | has "^Link $LX does not cover this request (scope does not name the subject, and the covers list was not shown at acceptance), so it is information" \
  && ok "the worker's note for such a request says information only, naming the list not shown" || die "unstamped note: $nx"

[ ! -s "$SWITCHBOARD_STATE/errors.log" ] && ok "no hook error was swallowed" || die "errors: $(cat "$SWITCHBOARD_STATE/errors.log")"

# a broken proposal record and an unreadable command cost the note, never the hook
echo "{\"id\": \"lbad\", \"state\": \"proposed\", \"from\": {}, \"to\": {\"repo\": \"$(L "$LP" .to.repo)\", \"role\": \"implementer\"}, \"span\": \"x\", \"expires\": $((NOW + 3600))}" > "$SWITCHBOARD_DIR/links/lbad.json"
SWITCHBOARD_SESSION_ID=S1 "$B" task request --to "$T/beta:implementer" --subject "after the break" --key k9 --no-sign >/dev/null
ptu "$T/beta" S2 | has "a task for you" && grep -q "proposal_notes" "$SWITCHBOARD_STATE/errors.log" && ok "a broken proposal record is logged and the other notes still arrive" || die "broken record: $(cat "$SWITCHBOARD_STATE/errors.log" 2>/dev/null)"
[ -z "$(bashpre "$T/alpha" S1 "~/.claude/board link-cap $LW \"500")" ] && ok "a command the guard cannot parse is left to the CLI" || die "unparseable command refused"
rm "$SWITCHBOARD_DIR/links/lbad.json"
finish
