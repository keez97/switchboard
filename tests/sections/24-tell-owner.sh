#!/usr/bin/env bash
# tell the owner: link acts, task requests and messages to another repo or machine are recorded; a Stop whose final
# text does not mention one blocks once with the reason; the CLI prints the line to say; link acts ask for a push
source "$(dirname "$0")/../lib.sh"
export SWITCHBOARD_TEST_PROPOSE=1   # the fake sessions below get the rules a real session gets
fx_repos alpha beta
seat S1 "$T/alpha" road; P2=$(fake S2 "$T/beta" impl); P3=$(fake S3 "$T/alpha" helper)
for s in "S1 alpha" "S2 beta" "S3 alpha"; do set -- $s; hook SessionStart "$T/$2" $1 >/dev/null; done
SWITCHBOARD_SESSION_ID=S1 "$B" role roadmap >/dev/null; SWITCHBOARD_SESSION_ID=S2 "$B" role implementer >/dev/null
SWITCHBOARD_SESSION_ID=S3 "$B" role helper >/dev/null
stopm(){ # event cwd sid final-text [active] [transcript]: a Stop whose input carries the turn's final text ('-' leaves it out)
  python3 - "$@" <<'PY' | "$B" hook
import json,os,sys
e,cwd,sid,text=sys.argv[1:5]; d={"hook_event_name":e,"cwd":cwd,"session_id":sid,"stop_hook_active":len(sys.argv)>5 and sys.argv[5]=="1"}
if text!="-": d["last_assistant_message"]=text
if len(sys.argv)>6: d["transcript_path"]=sys.argv[6]
if os.environ.get("AID"): d["agent_id"]=os.environ["AID"]
print(json.dumps(d))
PY
}
sendto(){ # cwd sid to message: a SendMessage that succeeded (AID set: from a subagent)
  python3 - "$@" <<'PY' | "$B" hook
import json,os,sys
d={"hook_event_name":"PostToolUse","cwd":sys.argv[1],"session_id":sys.argv[2],"tool_name":"SendMessage","tool_use_id":"u1",
   "tool_input":{"to":sys.argv[3],"message":sys.argv[4]},"tool_response":{"success":True}}
if os.environ.get("AID"): d["agent_id"]=os.environ["AID"]
print(json.dumps(d))
PY
}
acts(){ [ -f "$SWITCHBOARD_STATE/tell/$1.json" ] && python3 -c "import json,sys; print(' '.join(sorted(json.load(open(sys.argv[1])))))" "$SWITCHBOARD_STATE/tell/$1.json" || true; }
reason(){ python3 -c "import json,sys; t=sys.stdin.read().strip(); d=json.loads(t) if t else {}; print(d.get('reason','') if d.get('decision')=='block' else '')"; }
PUSH="send Robin a push notification with that line if your tools include one (PushNotification); if they do not, the reply is enough"

# ---- a proposal: the CLI line, the act, a final text that names it clears it
SWITCHBOARD_SESSION_ID=S1 "$B" link --from "$T/alpha:roadmap" --to "$T/beta:implementer" --scope "order the next work items" --covers "order the next work items" >"$T/out" 2>"$T/err"
LP=$(awk 'NR==1{print $2}' "$T/out")
head -1 "$T/out" | has "^link $LP proposed, not active" && [ "$(wc -l < "$T/err")" = 1 ] \
  && has -F "Tell Robin in your reply, in one line: you proposed link $LP to beta:implementer (scope: \"order the next work items\"), and why. Also $PUSH" < "$T/err" \
  && ok "board link prints its own output on stdout and one closing line on stderr: what to tell Robin, and to push it" || die "propose line: $(cat "$T/out" "$T/err")"
[ "$(acts S1)" = "proposed$LP" ] && ok "the proposal is recorded for the proposing session's Stop" || die "proposal act: $(acts S1)"
[ -z "$(stopm Stop "$T/alpha" S1 "I proposed link $LP so beta can take the next items.")" ] && [ -z "$(acts S1)" ] \
  && ok "a final text naming the link id clears it with no block" || die "mentioned proposal blocked"

# ---- the proposal arrives: the note asks to tell and push, and an unmentioned one blocks once
n2=$(hook PostToolUse "$T/beta" S2 Read '{}' | ctx)
echo "$n2" | has -F "Tell Robin in your reply, in one line: alpha:roadmap proposed link $LP to this session (scope: \"order the next work items\"), and what you decide. Also $PUSH" \
  && [ "$(acts S2)" = "received$LP" ] && ok "the proposal note asks the receiving session to tell Robin and push, and records it" || die "received note: $n2 / $(acts S2)"
r=$(stopm Stop "$T/beta" S2 "Done with the file listing." | reason)
echo "$r" | has -F "switchboard: your reply does not tell Robin what this session did with other sessions this turn:" \
  && echo "$r" | has -F -- "- alpha:roadmap proposed link $LP to this session (scope: \"order the next work items\")" \
  && echo "$r" | has -F "Tell Robin now, in one line each, what you did, to whom and why. For a link, also $PUSH. This reminder comes once." \
  && ok "a final text that does not mention it gets one block naming the act, asking for a line and a push" || die "received block: $r"
[ -z "$(stopm Stop "$T/beta" S2 "Still nothing about it." 1)" ] && [ -z "$(stopm Stop "$T/beta" S2 "Nothing." 0)" ] \
  && ok "no second block for that act, in the continuation or the next turn" || die "blocked twice"

# ---- accept, decline, unlink
SWITCHBOARD_SESSION_ID=S2 "$B" link accept "$LP" >"$T/out" 2>"$T/err"
head -1 "$T/out" | has "^link $LP accepted" && has -F "Tell Robin in your reply, in one line: you accepted link $LP from alpha:roadmap (scope: \"order the next work items\"), and why. Also $PUSH" < "$T/err" \
  && ok "link accept prints the line to tell, with the push" || die "accept line: $(cat "$T/out" "$T/err")"
[ -z "$(stopm Stop "$T/beta" S2 "I accepted the roadmap link from alpha; it lets alpha order my next work items.")" ] \
  && ok "a final text naming the other repo and its role clears it" || die "accept mention blocked"
SWITCHBOARD_SESSION_ID=S1 "$B" unlink "$LP" >"$T/out" 2>"$T/err"
has -x ok < "$T/out" && has -F "you ended link $LP with beta:implementer" < "$T/err" && has -F "Also $PUSH" < "$T/err" && ok "unlink prints the line to tell, with the push" || die "unlink line: $(cat "$T/out" "$T/err")"
r=$(stopm Stop "$T/alpha" S1 "All set." | reason)
echo "$r" | has -F -- "- you ended link $LP with beta:implementer" && echo "$r" | has -F "For a link, also send Robin a push" && ok "an unmentioned unlink blocks once" || die "unlink block: $r"
LD=$(SWITCHBOARD_SESSION_ID=S1 "$B" link --from "$T/alpha:roadmap" --to "$T/beta:implementer" --scope "second try" --covers "second try" 2>/dev/null | awk 'NR==1{print $2}')
stopm Stop "$T/alpha" S1 "proposed $LD" >/dev/null
SWITCHBOARD_SESSION_ID=S2 "$B" link decline "$LD" --reason "not now" >"$T/out" 2>"$T/err"
has -F "you declined link $LD from alpha:roadmap" < "$T/err" && ok "link decline prints the line to tell" || die "decline line: $(cat "$T/err")"
r=$(stopm Stop "$T/beta" S2 "ok" | reason); echo "$r" | has -F -- "- you declined link $LD from alpha:roadmap" && ok "an unmentioned decline blocks once" || die "decline block: $r"

# ---- a task request: no push; a mention by address clears it
SWITCHBOARD_SESSION_ID=S1 "$B" task request --to "$T/beta:implementer" --subject "list the files" --key k1 --no-sign >"$T/out" 2>"$T/err"
TK=$(awk '{print $1}' "$T/out")
[ "$(wc -l < "$T/out")" = 1 ] && has -xF "Tell Robin in your reply, in one line: you requested task $TK \"list the files\" from beta:implementer, and why." < "$T/err" \
  && ok "task request keeps one stdout line and prints the line to tell on stderr, with no push" || die "task line: $(cat "$T/out" "$T/err")"
r=$(stopm Stop "$T/alpha" S1 "Finished." | reason)
echo "$r" | has -F -- "- you requested task $TK \"list the files\" from beta:implementer" && ! echo "$r" | has "push" \
  && ok "an unmentioned task request blocks once, and the reason asks for no push" || die "task block: $r"
[ -z "$(stopm Stop "$T/alpha" S1 "Finished." 1)" ] && ok "no second block for the task" || die "task blocked twice"
SWITCHBOARD_SESSION_ID=S1 "$B" task request --to "$T/beta:implementer" --subject "count the files" --key k2 --no-sign >/dev/null 2>&1
[ -z "$(stopm Stop "$T/alpha" S1 "Asked beta:implementer to count the files.")" ] && ok "a final text naming the address repo:role clears a task request" || die "task mention blocked"

# ---- a message to a session in another repo
sendto "$T/alpha" S1 "uds:$T/sock.$P2" "please list the files" >/dev/null
[ "$(acts S1)" = "msg>uds:$T/sock.$P2" ] && ok "a SendMessage to a session in another repo is recorded" || die "message act: $(acts S1)"
sendto "$T/alpha" S1 "uds:$T/sock.$P2" "and count them" >/dev/null
r=$(stopm Stop "$T/alpha" S1 "Waiting on the reply." | reason)
[ "$(echo "$r" | grep -c "^- ")" = 1 ] && echo "$r" | has -F -- "- you sent a message to beta:implementer (session \"impl\" on east)" && ! echo "$r" | has "push" \
  && ok "two messages to one session are one act; unmentioned, one block with no push" || die "message block: $r"
sendto "$T/alpha" S1 "uds:$T/sock.$P2" "one more" >/dev/null
[ -z "$(stopm Stop "$T/alpha" S1 "Sent the beta implementer one more note.")" ] && ok "a final text naming beta and implementer clears a message" || die "message mention blocked"
[ -z "$(stopm Stop "$T/alpha" S1 "Our beta build is fine.")" ] && ok "with nothing recorded a Stop never blocks" || die "blocked with nothing recorded"
sendto "$T/alpha" S1 "uds:$T/sock.$P2" "again" >/dev/null
[ -n "$(stopm Stop "$T/alpha" S1 "Our beta build is fine." | reason)" ] && ok "the repo's name without its role does not count as a mention" || die "repo name alone cleared it"

# ---- a subagent's act counts for the main session; SubagentStop never blocks
AID=a1 sendto "$T/alpha" S1 "uds:$T/sock.$P2" "from the subagent" >/dev/null
[ -z "$(AID=a1 stopm SubagentStop "$T/alpha" S1 "subagent done")" ] && [ -n "$(acts S1)" ] && ok "SubagentStop never blocks and leaves the act for the main session" || die "SubagentStop blocked or settled"
stopm Stop "$T/alpha" S1 "Main done." | reason | has "you sent a message to beta:implementer" && ok "the subagent's act blocks the main session's Stop once" || die "subagent act not counted"
SWITCHBOARD_SESSION_ID=S1 "$B" task request --to "$T/beta:implementer" --subject "subagent task" --key k3 --no-sign >/dev/null 2>&1   # a subagent's Bash runs under the same session
[ -z "$(AID=a2 stopm SubagentStop "$T/alpha" S1 "x")" ] && stopm Stop "$T/alpha" S1 "Main done." | reason | has "subagent task" && ok "a board command a subagent runs counts the same way" || die "subagent CLI act"

# ---- nothing inside the session's own repo, nothing for reads
sendto "$T/alpha" S1 "uds:$T/sock.$P3" "same repo" >/dev/null
SWITCHBOARD_SESSION_ID=S1 "$B" task request --to "$T/alpha:helper" --subject "own repo" --key k4 --no-sign >/dev/null 2>"$T/err"
SWITCHBOARD_SESSION_ID=S1 "$B" link --from "$T/alpha:roadmap" --to "$T/alpha:helper" --scope "inside alpha" --covers "inside alpha" >/dev/null 2>&1
has "you requested task" < "$T/err" && [ -z "$(acts S1)" ] && [ -z "$(stopm Stop "$T/alpha" S1 "done")" ] \
  && ok "a message, task and link inside the session's own repo print the line but record nothing and never block" || die "own repo recorded: $(acts S1)"
for c in "who" "links" "me" "tasks --mine" "task $TK" "read" "status"; do SWITCHBOARD_SESSION_ID=S1 "$B" $c >/dev/null 2>&1; done
[ -z "$(acts S1)" ] && [ -z "$(stopm Stop "$T/alpha" S1 "done")" ] && ok "board commands that only read record nothing" || die "a read recorded: $(acts S1)"

# ---- the owner's terminal and a fake session with the owner's rules print no line
env -u SWITCHBOARD_SESSION_ID "$B" task request --to "$T/beta:implementer" --subject "terminal" --key k5 --no-sign >/dev/null 2>"$T/err"
SWITCHBOARD_TEST_PROPOSE='' SWITCHBOARD_SESSION_ID=S1 "$B" task request --to "$T/beta:implementer" --subject "owner rules" --key k6 --no-sign >/dev/null 2>>"$T/err"
[ ! -s "$T/err" ] && [ -z "$(acts S1)" ] && ok "a terminal, and a test session under the owner's rules, get no line and no act" || die "terminal line: $(cat "$T/err")"

# ---- a session on another machine, same repo
THIS=$("$B" register "$T/alpha" | tail -1 | awk '{print $NF}'); THETA=$THIS remote R1 "alpha on the east" 10
sendto "$T/alpha" S1 "bridge:session_R1" "cross machine" >/dev/null
r=$(stopm Stop "$T/alpha" S1 "done" | reason); echo "$r" | has -F -- "- you sent a message to alpha on west" && ok "a message to a session in the same repo on another machine counts" || die "remote message: $r"

# ---- the transcript when the input has no final text
TR="$T/transcript.jsonl"
printf '%s\n' '{"type":"user","message":{"role":"user","content":"go"}}' \
  "{\"type\":\"assistant\",\"message\":{\"content\":[{\"type\":\"text\",\"text\":\"Asked beta:implementer for the list.\"}]}}" \
  '{"type":"system","subtype":"stop_hook_summary"}' > "$TR"
sendto "$T/alpha" S1 "uds:$T/sock.$P2" "via transcript" >/dev/null
[ -z "$(stopm Stop "$T/alpha" S1 - 0 "$TR")" ] && ok "with no last_assistant_message the assistant text of the turn in the transcript is read" || die "transcript mention blocked"
sendto "$T/alpha" S1 "uds:$T/sock.$P2" "via transcript 2" >/dev/null
[ -n "$(stopm Stop "$T/alpha" S1 - 0 "$T/none.jsonl" | reason)" ] && ok "with neither, the act blocks once" || die "no text, no block"

# ---- said before acting: any assistant text of the turn counts, not one from an earlier turn
asst(){ python3 -c 'import json,sys; print(json.dumps({"type":"assistant","message":{"content":[{"type":"text","text":sys.argv[1]}]}}))' "$1"; }
TURN="$T/turn.jsonl"
{ echo '{"type":"user","message":{"role":"user","content":"regenerate the fixtures"}}'
  asst "This affects beta, I'll ask beta:implementer to regenerate the fixtures."
  echo '{"type":"assistant","message":{"content":[{"type":"tool_use","id":"x1","name":"SendMessage","input":{}}]}}'
  echo '{"type":"user","toolUseResult":{},"message":{"role":"user","content":[{"type":"tool_result","tool_use_id":"x1","content":"sent"}]}}'
  echo '{"type":"user","isMeta":true,"message":{"role":"user","content":"Stop hook feedback: something else"}}'
  asst "Sent. Waiting for the reply."; } > "$TURN"
sendto "$T/alpha" S1 "uds:$T/sock.$P2" "regenerate the fixtures" >/dev/null
[ -z "$(stopm Stop "$T/alpha" S1 "Sent. Waiting for the reply." 0 "$TURN")" ] \
  && ok "a mention in an earlier assistant message of the turn clears the act (tool results and injected text do not end the turn)" || die "announcement before acting blocked"
{ echo '{"type":"user","message":{"role":"user","content":"first"}}'; asst "I'll ask beta:implementer."
  echo '{"type":"user","message":{"role":"user","content":[{"type":"text","text":"second"}]}}'; asst "Sent."; } > "$TURN"
sendto "$T/alpha" S1 "uds:$T/sock.$P2" "second" >/dev/null
[ -n "$(stopm Stop "$T/alpha" S1 "Sent." 0 "$TURN" | reason)" ] && ok "a mention before the turn's prompt, in an earlier turn, does not count" || die "earlier turn counted"
sendto "$T/alpha" S1 "uds:$T/sock.$P2" "third" >/dev/null
[ -z "$(stopm Stop "$T/alpha" S1 "Told beta:implementer." 0 "$T/none.jsonl")" ] && ok "with no transcript, last_assistant_message alone is used" || die "last message alone"

# ---- plurals, '-', '_' and space in names, a peer's title
mkrepo "$T/build-farm"; "$B" register "$T/build-farm" >/dev/null
P9=$(fake S9 "$T/build-farm" "West Builder"); hook SessionStart "$T/build-farm" S9 >/dev/null; SWITCHBOARD_SESSION_ID=S9 "$B" role builder >/dev/null
SWITCHBOARD_SESSION_ID=S1 "$B" task request --to "$T/build-farm:builder" --subject "rerun" --key k8 --no-sign >/dev/null 2>&1
[ -z "$(stopm Stop "$T/alpha" S1 "Asked the build farm builders to rerun.")" ] && ok "a plural role and a repo name with a space for its hyphen count as a mention" || die "plural or separator blocked"
SWITCHBOARD_SESSION_ID=S1 "$B" task request --to "$T/build-farm:builder" --subject "rerun again" --key k9 --no-sign >/dev/null 2>&1
[ -z "$(stopm Stop "$T/alpha" S1 "Queued it on build_farm:builder.")" ] && ok "an address with '_' for '-' counts" || die "underscore address blocked"
sendto "$T/alpha" S1 "uds:$T/sock.$P9" "ping" >/dev/null
[ -z "$(stopm Stop "$T/alpha" S1 "Pinged West Builder about the rerun.")" ] && ok "a message named by the peer session's title counts" || die "title blocked"
mkrepo "$T/zeta"; "$B" register "$T/zeta" >/dev/null; P12=$(fake S12 "$T/zeta" main); hook SessionStart "$T/zeta" S12 >/dev/null
sendto "$T/alpha" S1 "uds:$T/sock.$P12" "ping" >/dev/null
stopm Stop "$T/alpha" S1 "Done on the main branch." | reason | has "zeta" && ok "a peer titled with an ordinary word (main) is not mentioned by that word" || die "short title counted"
mkdir -p "$T/loose1" "$T/loose2"; seat S10 "$T/loose1" loose-a; P11=$(fake S11 "$T/loose2" loose-b)
hook SessionStart "$T/loose1" S10 >/dev/null; hook SessionStart "$T/loose2" S11 >/dev/null
sendto "$T/loose1" S10 "uds:$T/sock.$P11" "hi" >/dev/null
[ -z "$(acts S10)" ] && ok "two sessions outside any repo on one machine are not a cross-repo send" || die "repo-less send recorded: $(acts S10)"

# ---- the cross-repo write obligation names repo:role
w=$(hook PostToolUse "$T/alpha" S1 Write "{\"file_path\":\"$T/beta/notes.txt\"}" | ctx)
echo "$w" | has -F "Then tell Robin in one line that you did, naming beta:implementer in your reply." && ok "the cross-repo write note asks to name repo:role in the reply" || die "write note: $w"
r=$(stopm Stop "$T/alpha" S1 "done" | reason)
echo "$r" | has -F "and tell Robin in one line that you did, naming beta:implementer in your reply." && ok "its Stop reminder asks the same" || die "unmet reminder: $r"

# ---- an open end offered to sessions with no role is guidance; a received proposal that no longer waits is dropped
fx_repos gamma; seat S7 "$T/gamma" g7; seat S8 "$T/gamma" g8
hook SessionStart "$T/gamma" S7 >/dev/null; hook SessionStart "$T/gamma" S8 >/dev/null
LG=$(SWITCHBOARD_SESSION_ID=S1 "$B" link --from "$T/alpha:roadmap" --to "$T/gamma:worker" --scope "open end" --covers "open end" 2>/dev/null | awk 'NR==1{print $2}')
stopm Stop "$T/alpha" S1 "proposed $LG" >/dev/null
hook PostToolUse "$T/gamma" S7 Read '{}' | ctx | has "proposes link $LG" && hook PostToolUse "$T/gamma" S8 Read '{}' | ctx | has "proposes link $LG" \
  && [ -z "$(acts S7)" ] && [ -z "$(acts S8)" ] && ok "the offer of an open end to sessions with no role records nothing" || die "offer recorded: $(acts S7) / $(acts S8)"
SWITCHBOARD_SESSION_ID=S7 "$B" link accept "$LG" >/dev/null 2>&1
[ -z "$(stopm Stop "$T/gamma" S8 "unrelated")" ] && stopm Stop "$T/gamma" S7 "unrelated" | reason | has "you accepted link $LG" \
  && ok "after one of them accepts, the bystander is never blocked; the acceptor is, for its acceptance" || die "bystander blocked"
LW=$(SWITCHBOARD_SESSION_ID=S1 "$B" link --from "$T/alpha:roadmap" --to "$T/beta:implementer" --scope "withdrawn" --covers "withdrawn" 2>/dev/null | awk 'NR==1{print $2}')
hook PostToolUse "$T/beta" S2 Read '{}' | ctx | has "proposes link $LW" && [ "$(acts S2)" = "received$LW" ] || die "setup: S2 did not receive $LW"
SWITCHBOARD_SESSION_ID=S1 "$B" unlink "$LW" >/dev/null 2>&1; stopm Stop "$T/alpha" S1 "withdrew $LW" >/dev/null
[ -z "$(stopm Stop "$T/beta" S2 "unrelated")" ] && ok "a proposal its proposer withdrew before the holder's Stop does not block the holder" || die "withdrawn proposal blocked"
LT=$(SWITCHBOARD_SESSION_ID=S1 "$B" link --from "$T/alpha:roadmap" --to "$T/beta:implementer" --scope "taken" --covers "taken" 2>/dev/null | awk 'NR==1{print $2}')
hook PostToolUse "$T/beta" S2 Read '{}' | ctx | has "proposes link $LT" || die "setup: S2 did not receive $LT"
P13=$(fake S13 "$T/beta" beta2); hook SessionStart "$T/beta" S13 >/dev/null; SWITCHBOARD_SESSION_ID=S13 "$B" role implementer --take >/dev/null
[ -z "$(stopm Stop "$T/beta" S2 "unrelated")" ] && ok "a received proposal whose end another session now holds does not block" || die "taken end blocked"

# ---- errors degrade to no reminder
mkdir -p "$SWITCHBOARD_STATE/tell"
for bad in 'not json{' '[1,2]' '{"x": 5}' '{"x": {"kind": "proposed"}}' '{"x": {"kind": "task", "ts": "soon"}}'; do
  printf '%s' "$bad" > "$SWITCHBOARD_STATE/tell/S1.json"
  out=$(stopm Stop "$T/alpha" S1 "done"; echo "rc=$?")
  [ "$out" = "rc=0" ] || { die "corrupt state $bad: $out"; break; }
done
[ "$out" = "rc=0" ] && grep -q "tell_check" "$SWITCHBOARD_STATE/errors.log" && ok "a corrupt or misshapen state file gives no reminder, exits 0, and tell_check logs its own error" || die "corrupt state not handled in tell_check: $(cat "$SWITCHBOARD_STATE/errors.log" 2>/dev/null)"
rm -rf "$SWITCHBOARD_STATE/tell"; : > "$SWITCHBOARD_STATE/tell"   # a file where the directory should be
out=$(SWITCHBOARD_SESSION_ID=S1 "$B" task request --to "$T/beta:implementer" --subject "no state dir" --key k7 --no-sign 2>/dev/null; echo "rc=$?")
o2=$(sendto "$T/alpha" S1 "uds:$T/sock.$P2" "no state dir" >/dev/null; stopm Stop "$T/alpha" S1 "done"; echo "rc=$?")
echo "$out" | has "requested from beta:implementer" && echo "$out" | has "rc=0" && [ "$o2" = "rc=0" ] && grep -q "tell_act" "$SWITCHBOARD_STATE/errors.log" \
  && ok "an unwritable state dir: the command still runs, the hooks stay silent, the error is logged" || die "unwritable: $out / $o2"
rm -f "$SWITCHBOARD_STATE/tell"
finish
