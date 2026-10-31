#!/usr/bin/env bash
# link policy: policy() read the same way by the CLI and the PreToolUse guard. In 0.8.0 it is the defaults alone and a
# policy.json on the board is not read or synced; other values run in-process through policy_values (1-03 reads the file)
# shellcheck disable=SC2088  # the guard is given each command as a session writes it
source "$(dirname "$0")/../lib.sh"
fx_repos alpha beta gamma
P1=$(fake S1 "$T/alpha" road); P2=$(fake S2 "$T/beta" impl)
for s in "S1 alpha" "S2 beta"; do set -- $s; hook SessionStart "$T/$2" $1 >/dev/null; done
SWITCHBOARD_SESSION_ID=S1 "$B" role roadmap >/dev/null; SWITCHBOARD_SESSION_ID=S2 "$B" role implementer >/dev/null
try(){ "$@" 2>&1 || true; }   # a refusal exits non-zero; the check reads what it said
L(){ jq -r "$2" "$SWITCHBOARD_DIR/links/$1.json"; }
setl(){ jq "$2" "$SWITCHBOARD_DIR/links/$1.json" > "$T/lx" && mv "$T/lx" "$SWITCHBOARD_DIR/links/$1.json"; }
pol(){ printf '%s\n' "$1" > "$SWITCHBOARD_DIR/policy.json"; }
bashpre(){ python3 -c 'import json,sys; print(json.dumps({"hook_event_name":"PreToolUse","cwd":sys.argv[1],"session_id":sys.argv[2],"tool_name":"Bash","tool_input":{"command":sys.argv[3]}}))' "$@" | "$B" hook; }
toolpre(){ python3 -c 'import json,sys; print(json.dumps({"hook_event_name":"PreToolUse","cwd":sys.argv[1],"session_id":sys.argv[2],"tool_name":sys.argv[3],"tool_input":json.loads(sys.argv[4])}))' "$@" | "$B" hook; }
denied(){ has '"permissionDecision": *"deny"'; }
reap_at(){ SWITCHBOARD_NOW=$1 up "$T/alpha" S1 next >/dev/null; }   # a prompt publishes, and a publish reaps links at that time
propose(){ SWITCHBOARD_TEST_PROPOSE=1 SWITCHBOARD_SESSION_ID=S1 "$B" link --from "$T/alpha:roadmap" --to "$T/beta:implementer" --scope "$1" --covers "$1" "${@:2}"; }
accept(){ SWITCHBOARD_TEST_PROPOSE=1 SWITCHBOARD_SESSION_ID=S2 "$B" link accept "$1" >/dev/null; }
sbp(){ # policy-json expression: the expression's value, in-process, with policy() giving policy_values(policy-json)
  python3 - "$B" "$@" <<'PY'
import importlib.machinery, importlib.util, json, sys
l = importlib.machinery.SourceFileLoader("sb", sys.argv[1]); m = importlib.util.module_from_spec(importlib.util.spec_from_loader("sb", l))
l.exec_module(m); pol = m.policy_values(json.loads(sys.argv[2])); m.policy = lambda: dict(pol)
print(eval(sys.argv[3], {"m": m, "Path": __import__("pathlib").Path}))
PY
}
sb_py(){ sbp '{}' "$@"; }
sbm(){ # policy-json args...: the CLI run in-process with policy() giving policy_values(policy-json)
  python3 - "$B" "$@" <<'PY'
import importlib.machinery, importlib.util, json, sys
l = importlib.machinery.SourceFileLoader("sb", sys.argv[1]); m = importlib.util.module_from_spec(importlib.util.spec_from_loader("sb", l))
l.exec_module(m); pol = m.policy_values(json.loads(sys.argv[2])); m.policy = lambda: dict(pol)
sys.argv = ["switchboard"] + sys.argv[3:]; m.main()
PY
}
LINK="switchboard link --from alpha:roadmap --to beta:implementer --scope x --covers x"
NOW=$(date +%s)

# ---- t1: no policy.json, a session asks for more than 24 hours
out=$(try propose "t1 scope" --until 2d)
echo "$out" | has "switchboard: refused. A link made from a session runs at most 24 hours from acceptance. This asked for --until 2d (more than 24 hours)" \
  && ! ls "$SWITCHBOARD_DIR/links/" | has . && ok "t1 with no policy.json a session's link --until 2d is refused at 24 hours and nothing is written" || die "t1: $out"
bashpre "$T/alpha" S1 "$LINK --until 2d" | denied && bashpre "$T/alpha" S1 "$LINK --until 2d" | has "more than 24 hours" \
  && ok "t1 the guard refuses the same command, naming 24 hours" || die "t1 guard: $(bashpre "$T/alpha" S1 "$LINK --until 2d")"

# ---- t2: --until never from a session, refused by the CLI and by the guard
out=$(try propose "t2 scope" --until never)
echo "$out" | has "This asked for --until never (no end)" && ! ls "$SWITCHBOARD_DIR/links/" | has . \
  && ok "t2 a session's link --until never is refused by the CLI as having no end" || die "t2 cli: $out"
for c in "$LINK --until never" "$LINK --until=never" "$LINK --until NEVER" "bash -c '$LINK --until never'" "~/.local/bin/$LINK --until never"; do
  bashpre "$T/alpha" S1 "$c" | denied || die "t2 guard allowed: $c"
done
bashpre "$T/alpha" S1 "$LINK --until never" | has "asks for a link with --until never, which has no end" && ok "t2 the guard refuses --until never in every spelling" || die "t2 guard text: $(bashpre "$T/alpha" S1 "$LINK --until never")"
[ -z "$(bashpre "$T/alpha" S1 "$LINK --until 12h")" ] && [ -z "$(bashpre "$T/alpha" S1 "$LINK --scope 'never --until never'")" ] \
  && ok "t2 --until 12h, and never inside a quoted scope, still run" || die "t2 allowed forms refused"

# ---- t3: a terminal link with no --until has no end and no idle close
out=$("$B" link --from "$T/alpha:roadmap" --to "$T/gamma:builder" --scope "t3 owner" --covers "t3 owner" --to-session open)
L3=$(echo "$out" | awk 'NR==1{print $2}')
[ "$(L "$L3" .ends)" = never ] && [ "$(L "$L3" 'has("until")')" = false ] && [ "$(L "$L3" 'has("idle_days") and .idle_days == null')" = true ] \
  && [ "$(L "$L3" .cap)" = 100 ] && [ "$(L "$L3" .v)" = 1 ] && ok "t3 a terminal link with no --until is written with ends never, no until, idle_days null and cap 100" || die "t3 record: $(cat "$SWITCHBOARD_DIR/links/$L3.json")"
reap_at $((NOW + 30*86400))
[ "$(L "$L3" '.revoked // 0')" = 0 ] && SWITCHBOARD_NOW=$((NOW + 30*86400)) "$B" links --json | jq -e --arg l "$L3" '.links[] | select(.id == $l) | .active and .ends == "never"' >/dev/null \
  && ok "t3 30 days on with no message it is open and active" || die "t3 closed: $(cat "$SWITCHBOARD_DIR/links/$L3.json")"
"$B" links | grep -A1 "^$L3 " | has -x "    ends never" && ok "t3 board links shows it ends never" || die "t3 listing: $("$B" links | grep -A1 "^$L3 ")"
out=$("$B" link --from "$T/alpha:roadmap" --to "$T/gamma:other" --scope "t3 dated" --covers "t3 dated" --to-session open --until 5d)
L3b=$(echo "$out" | awk 'NR==1{print $2}'); u=$(L "$L3b" .until)
[ "$u" -gt $((NOW + 5*86400 - 120)) ] && [ "$u" -lt $((NOW + 5*86400 + 120)) ] && [ "$(L "$L3b" 'has("ends")')" = false ] \
  && ok "t3 a terminal link with --until 5d ends then and has no ends field" || die "t3 dated: $(cat "$SWITCHBOARD_DIR/links/$L3b.json")"
out=$(try "$B" link --from "$T/alpha:roadmap" --to "$T/gamma:third" --scope "t3 never" --covers "t3 never" --to-session open --until never)
[ "$(L "$(echo "$out" | awk 'NR==1{print $2}')" '.ends + " " + (has("until") | tostring)')" = "never false" ] \
  && ok "t3 a terminal link with --until never has no end" || die "t3 never: $out"

# ---- t4: an agent link accepted today has idle_days 3 and closes after 3 idle days
L4=$(propose "t4 idle" | awk 'NR==1{print $2}'); accept "$L4"
u=$(L "$L4" .until)
[ "$(L "$L4" .idle_days)" = 3 ] && [ "$u" -gt $((NOW + 86400 - 120)) ] && [ "$u" -lt $((NOW + 86400 + 120)) ] && [ "$(L "$L4" 'has("ends")')" = false ] \
  && ok "t4 an accepted agent link runs 24 hours and has idle_days 3" || die "t4 record: $(cat "$SWITCHBOARD_DIR/links/$L4.json")"
setl "$L4" ".created = $((NOW - 4*86400)) | .until = $((NOW + 10*86400))"
reap_at "$NOW"
[ "$(L "$L4" .closed_reason)" = "idle for 3 days" ] && ok "t4 with no message for 4 days it closes as idle for 3 days" || die "t4 not closed: $(cat "$SWITCHBOARD_DIR/links/$L4.json")"

# ---- t5: a link written before policy (no idle_days) still closes after 3 idle days, as does a bad idle_days
out=$("$B" link --from "$T/alpha:roadmap" --to "$T/gamma:old" --scope "t5 old" --covers "t5 old" --to-session open)
L5=$(echo "$out" | awk 'NR==1{print $2}')
setl "$L5" "del(.ends, .idle_days, .v) | .created = $((NOW - 4*86400)) | .until = $((NOW + 10*86400))"
out=$("$B" link --from "$T/alpha:roadmap" --to "$T/gamma:bad" --scope "t5 bad" --covers "t5 bad" --to-session open)
L5b=$(echo "$out" | awk 'NR==1{print $2}')
setl "$L5b" ".idle_days = \"x\" | .created = $((NOW - 4*86400))"
out=$("$B" link --from "$T/alpha:roadmap" --to "$T/gamma:fresh" --scope "t5 fresh" --covers "t5 fresh" --to-session open)
L5c=$(echo "$out" | awk 'NR==1{print $2}')
setl "$L5c" "del(.ends, .idle_days) | .created = $((NOW - 2*86400)) | .until = $((NOW + 10*86400))"
reap_at "$NOW"
[ "$(L "$L5" .closed_reason)" = "idle for 3 days" ] && [ "$(L "$L5b" .closed_reason)" = "idle for 3 days" ] && [ "$(L "$L5c" '.revoked // 0')" = 0 ] \
  && ok "t5 a link with no idle_days, or one that is not a number of days, closes after 3 idle days; one idle 2 days stays" \
  || die "t5: $(L "$L5" .closed_reason) / $(L "$L5b" .closed_reason) / $(L "$L5c" '.revoked // 0')"

# ---- t6: a session does not write policy.json or grants/
BD=$SWITCHBOARD_DIR
for ti in "{\"file_path\":\"$BD/policy.json\",\"content\":\"{}\"}" "{\"file_path\":\"$BD/grants/g1.json\",\"content\":\"{}\"}"; do
  toolpre "$T/alpha" S1 Write "$ti" | denied || die "t6 Write allowed: $ti"
done
toolpre "$T/alpha" S1 Edit "{\"file_path\":\"$BD/policy.json\",\"old_string\":\"a\",\"new_string\":\"b\"}" | denied || die "t6 Edit allowed"
for c in "echo '{}' > $BD/policy.json" "cd $BD && echo '{}' > policy.json" "cd $BD && tee policy.json < /dev/null" \
         "mkdir -p $BD/grants && echo x > $BD/grants/g.json" "cp /tmp/x $BD/./policy.json" "cd $BD; rm -rf grants" \
         "python3 -c 'open(\"$BD/policy.json\",\"w\")'" "sed -i s/24/9999/ $BD/policy.json"; do
  bashpre "$T/alpha" S1 "$c" | denied || die "t6 Bash allowed: $c"
done
# the path helper fails open on its deadline: with it out of time at once, the check before it refuses these alone
for c in "echo '{}' > $BD/policy.json" "cd $BD && echo '{}' > policy.json" "cd $BD && tee policy.json < /dev/null" \
         "mkdir -p $BD/grants && echo x > $BD/grants/g.json" "cd $BD; rm -rf grants" \
         "python3 -c 'open(\"$BD/policy.json\",\"w\")'" "sed -i s/24/9999/ $BD/policy.json"; do
  SWITCHBOARD_GUARD_BUDGET=0.000001 bashpre "$T/alpha" S1 "$c" | has "the link policy (policy.json) and grants/ are Robin's" || die "t6 allowed with the helper out of time: $c"
done
toolpre "$T/alpha" S1 Write "{\"file_path\":\"$BD/policy.json\",\"content\":\"{}\"}" | has "the link policy (policy.json) and grants/ are Robin's" \
  && ok "t6 Write, Edit and Bash writes to policy.json and grants/ from a session are refused, naming whose they are" || die "t6 text: $(toolpre "$T/alpha" S1 Write "{\"file_path\":\"$BD/policy.json\",\"content\":\"{}\"}")"
[ -z "$(bashpre "$T/alpha" S1 "cat $BD/policy.json")" ] && [ -z "$(bashpre "$T/alpha" S1 "cd $BD && jq . policy.json")" ] && [ -z "$(toolpre "$T/alpha" S1 Write "{\"file_path\":\"$T/alpha/policy.json\",\"content\":\"{}\"}")" ] \
  && ok "t6 reading policy.json, and a policy.json in a repo, are not refused" || die "t6 reads refused"

# ---- a policy.json on the board changes nothing in 0.8.0 (a session could plant it through 0.7.0's guard)
pol '{"v": 1, "agent_link_hours": null, "owner_cap": 1, "proposal_hours": 1000}'
out=$(try propose "p planted" --until never)
echo "$out" | has "This asked for --until never (no end)" && bashpre "$T/alpha" S1 "$LINK --until never" | denied && bashpre "$T/alpha" S1 "$LINK --until 2d" | denied \
  && ok "a planted policy.json with agent_link_hours null: a session's --until never and --until 2d are still refused by the CLI and the guard" || die "planted refusal: $out"
LQ=$(propose "p planted ok" | awk 'NR==1{print $2}'); accept "$LQ"; u=$(L "$LQ" .until); e=$(L "$LQ" .expires)
[ "$u" -gt $((NOW + 86400 - 120)) ] && [ "$u" -lt $((NOW + 86400 + 120)) ] && [ "$(L "$LQ" 'has("ends")')" = false ] && [ "$e" -lt $((NOW + 86400 + 120)) ] \
  && [ "$(sb_py 'm.policy() == m.POLICY_DEFAULTS')" = True ] && ok "with it, an accepted agent link still runs 24 hours and policy() is the defaults" || die "planted accept: $(cat "$SWITCHBOARD_DIR/links/$LQ.json")"
LR=$("$B" link --from "$T/alpha:roadmap" --to "$T/gamma:planted" --scope "p planted owner" --covers "p planted owner" --to-session open | awk 'NR==1{print $2}')
[ "$(L "$LR" .cap)" = 100 ] && ok "and an owner link with no --cap still gets cap 100" || die "planted cap: $(L "$LR" .cap)"
rm -f "$SWITCHBOARD_DIR/policy.json"

# ---- other policy values, run in-process through policy_values: the CLI and the guard read them alike (1-03 reads the file)
P48='{"v": 1, "agent_link_hours": 48, "agent_idle_days": 5, "proposal_hours": 2, "owner_cap": 7, "owner_link_days": 10, "owner_idle_days": 4}'
LP=$(SWITCHBOARD_TEST_PROPOSE=1 SWITCHBOARD_SESSION_ID=S1 sbm "$P48" link --from "$T/alpha:roadmap" --to "$T/beta:implementer" --scope "p accept" --covers "p accept" --until 2d | awk 'NR==1{print $2}')
e=$(L "$LP" .expires); [ -n "$LP" ] && [ "$(L "$LP" .span)" -gt $((48*3600 - 120)) ] && [ "$e" -gt $((NOW + 7200 - 120)) ] && [ "$e" -lt $((NOW + 7200 + 120)) ] \
  && ok "agent_link_hours 48 lets a session propose --until 2d; proposal_hours 2 sets its expiry" || die "policy propose: $LP $(cat "$SWITCHBOARD_DIR/links/$LP.json" 2>/dev/null)"
[ "$(sbp "$P48" "m.link_guard('$LINK --until 2d')")" = "" ] && sbp "$P48" "m.link_guard('$LINK --until 3d')" | has "more than 48 hours" \
  && SWITCHBOARD_TEST_PROPOSE=1 SWITCHBOARD_SESSION_ID=S1 try sbm "$P48" link --from "$T/alpha:roadmap" --to "$T/beta:implementer" --scope "p 3d" --covers "p 3d" --until 3d | has "runs at most 48 hours from acceptance" \
  && ok "the guard and the CLI both refuse 3d and allow 2d at 48 hours" || die "policy 48: $(sbp "$P48" "m.link_guard('$LINK --until 3d')")"
SWITCHBOARD_TEST_PROPOSE=1 SWITCHBOARD_SESSION_ID=S2 sbm "$P48" link accept "$LP" >/dev/null
[ "$(L "$LP" .idle_days)" = 5 ] && ok "agent_idle_days 5 is stamped at acceptance" || die "policy idle: $(L "$LP" .idle_days)"
setl "$LP" ".created = $((NOW - 4*86400))"; reap_at "$NOW"
[ "$(L "$LP" '.revoked // 0')" = 0 ] && ok "a link stamped idle_days 5 stays open after 4 idle days" || die "policy idle closed: $(L "$LP" .closed_reason)"
LO=$(sbm "$P48" link --from "$T/alpha:roadmap" --to "$T/gamma:pol" --scope "p owner" --covers "p owner" --to-session open | awk 'NR==1{print $2}')
u=$(L "$LO" .until)
[ "$(L "$LO" .cap)" = 7 ] && [ "$(L "$LO" .idle_days)" = 4 ] && [ "$u" -gt $((NOW + 10*86400 - 120)) ] && [ "$u" -lt $((NOW + 10*86400 + 120)) ] && [ "$(L "$LO" 'has("ends")')" = false ] \
  && ok "owner_cap 7, owner_link_days 10 and owner_idle_days 4 decide a terminal link with no --cap or --until" || die "policy owner: $(cat "$SWITCHBOARD_DIR/links/$LO.json")"
setl "$LO" ".created = $((NOW - 5*86400))"; reap_at "$NOW"
[ "$(L "$LO" .closed_reason)" = "idle for 4 days" ] && ok "a terminal link with idle_days 4 closes after 4 idle days" || die "owner idle: $(L "$LO" .closed_reason)"
sbp "$P48" 'm.still_owners()' | has "a link beyond 48 hours or extending one, raising" && sb_py 'm.still_owners()' | has "a link beyond 24 hours or extending one, raising" \
  && ok "the owner's acts name the policy's hours" || die "still_owners: $(sbp "$P48" 'm.still_owners()')"

# values policy_ok rejects, and records of a later format, fall back to the defaults key by key
[ "$(sb_py 'm.policy_values({"v": 1, "agent_link_hours": "48", "agent_idle_days": 0, "proposal_hours": None, "owner_cap": True, "owner_link_days": 2.5, "owner_idle_days": 1000001, "x": 1}) == m.POLICY_DEFAULTS')" = True ] \
  && ok "bad values (a string, 0, null where not allowed, a bool, a float, over 10**6) give the defaults" || die "bad values"
[ "$(sb_py 'm.policy_values({"v": 1, "agent_link_hours": 12, "owner_link_days": "x"})["agent_link_hours"]')" = 12 ] && ok "a good key stands beside a bad one" || die "per key"
[ "$(sb_py 'all(m.policy_values(p) == m.POLICY_DEFAULTS for p in ({"v": 99, "agent_link_hours": 240}, {"v": "1", "agent_link_hours": 240}, [1], None, "x"))')" = True ] \
  && ok "a policy record of a later format, or not an object, gives the defaults" || die "later format"

# agent_link_hours null (the owner's alone): a session's link then has no end, kept a number for 0.7.0
PN='{"v": 1, "agent_link_hours": null}'
LN=$(SWITCHBOARD_TEST_PROPOSE=1 SWITCHBOARD_SESSION_ID=S1 sbm "$PN" link --from "$T/alpha:roadmap" --to "$T/beta:implementer" --scope "p none" --covers "p none" --until never | awk 'NR==1{print $2}')
[ -n "$LN" ] && SWITCHBOARD_TEST_PROPOSE=1 SWITCHBOARD_SESSION_ID=S2 sbm "$PN" link accept "$LN" >/dev/null
[ -n "$LN" ] && [ "$(L "$LN" .ends)" = never ] && [ "$(L "$LN" .until)" = 253402300799 ] && [ "$(sbp "$PN" "m.link_guard('$LINK --until never')")" = "" ] \
  && sbp "$PN" "m.link_guard('$LINK --until 1d --to-session open')" | has "Widening a link is Robin's" \
  && ok "with agent_link_hours null a session's --until never is accepted with until 9999-12-31 and ends never" || die "null hours: $LN $(cat "$SWITCHBOARD_DIR/links/$LN.json" 2>/dev/null)"

# ---- .gitattributes: the template has the policy lines; board_attrs appends them to a board made before
binit "$T/newboard"
has -x "policy.json merge=board-record" < "$T/newboard/.gitattributes" && has -x "grants/\*\* -merge" < "$T/newboard/.gitattributes" \
  && ok "the init template's .gitattributes has policy.json merge=board-record and grants/** -merge" || die "template: $(cat "$T/newboard/.gitattributes")"
mkdir -p "$T/oldboard"; grep -v -e '^policy.json' -e '^grants' "$T/newboard/.gitattributes" | head -c -1 > "$T/oldboard/.gitattributes"
[ "$(sb_py "m.board_attrs(Path('$T/oldboard'))")" = "['policy.json merge=board-record', 'grants/** -merge']" ] \
  && [ "$(sb_py "m.board_attrs(Path('$T/oldboard'))")" = "[]" ] && [ "$(tail -3 "$T/oldboard/.gitattributes" | head -1)" = "tasks/**/000-request.json !merge" ] \
  && [ "$(grep -c . "$T/oldboard/.gitattributes")" = "$(grep -c . "$T/newboard/.gitattributes")" ] \
  && ok "board_attrs appends the two lines once to a board's .gitattributes that lacks them, on a line of their own" || die "attrs: $(cat "$T/oldboard/.gitattributes")"
mkdir -p "$T/notboard"; echo "*.c diff" > "$T/notboard/.gitattributes"
[ "$(sb_py "m.board_attrs(Path('$T/notboard'))")" = "[]" ] && [ "$(cat "$T/notboard/.gitattributes")" = "*.c diff" ] && ok "a folder that is not a board is left as it is" || die "notboard"

# ---- a sync pass on a board made from the 0.7.0 template: it commits the two lines, never a policy.json or grants/
grep -v -e '^policy.json' -e '^grants' "$T/newboard/.gitattributes" > "$SWITCHBOARD_DIR/.gitattributes"
git init -q --bare -b main "$T/remote.git"; git -C "$SWITCHBOARD_DIR" init -q -b main; git -C "$SWITCHBOARD_DIR" config user.email t@t; git -C "$SWITCHBOARD_DIR" config user.name t
git -C "$SWITCHBOARD_DIR" remote add origin "$T/remote.git"; git -C "$SWITCHBOARD_DIR" add .gitattributes; git -C "$SWITCHBOARD_DIR" commit -q -m init; git -C "$SWITCHBOARD_DIR" push -q -u origin main
pol '{"v": 1, "agent_link_hours": null}'; mkdir -p "$SWITCHBOARD_DIR/grants"; echo '{"v": 1}' > "$SWITCHBOARD_DIR/grants/g1.json"
SWITCHBOARD_NOSYNC='' "$B" sync; waitfor "$SWITCHBOARD_STATE/sync.ok"
remote_attrs=$(git -C "$T/remote.git" show main:.gitattributes 2>&1)
echo "$remote_attrs" | has -x "policy.json merge=board-record" && echo "$remote_attrs" | has -x "grants/\*\* -merge" && git -C "$T/remote.git" ls-tree -r main --name-only | has "^links/" \
  && ok "a sync on a board made before policy commits and pushes the two .gitattributes lines" || die "sync attrs: $remote_attrs"
[ -z "$(git -C "$T/remote.git" ls-tree -r main --name-only | grep -e '^policy.json' -e '^grants/')" ] && [ -z "$(git -C "$SWITCHBOARD_DIR" ls-files policy.json grants)" ] \
  && ok "a policy.json and grants/ planted in the clone are not committed or pushed" || die "planted synced: $(git -C "$T/remote.git" ls-tree -r main --name-only | grep -e policy -e grants)"
rm -rf "$SWITCHBOARD_DIR/policy.json" "$SWITCHBOARD_DIR/grants"

# ---- sessions still running an older switchboard's hooks are named in status
mark(){ python3 - "$SWITCHBOARD_STATE/claude/pid-$1.json" "$1" "$("$B" _procstart "$1")" "$2" "$3" <<'PY'
import json,sys; f,pid,ps,sid,v=sys.argv[1:6]; d={"pid":int(pid),"procStart":ps,"sessions":{sid:1}}
if v: d["version"]=v
json.dump(d,open(f,"w"))
PY
}
VER=$(jq -r .version "$(dirname "$B")/../.claude-plugin/plugin.json")
mkdir -p "$SWITCHBOARD_STATE/claude"; mark "$P1" S1 ""; mark "$P2" S2 "$VER"
P9=$(fake S9 "$T/gamma" oldie); mark "$P9" S9 0.7.0; mark 999999 S8 ""
st=$("$B" status)
echo "$st" | has "^hooks: 2 sessions still run an older switchboard's hooks: reload them with /reload-plugins: " && echo "$st" | has "(pid $P1, no version)" \
  && echo "$st" | has "(pid $P9, 0.7.0)" && ! echo "$st" | has "pid $P2," && ! echo "$st" | has "pid 999999" \
  && ok "status names live sessions whose process mark has no version or an older one, not this version's or a dead one's" || die "status hooks: $st"
mark "$P1" S1 "$VER"; rm -f "$SWITCHBOARD_STATE/claude/pid-$P9.json"
! "$B" status | has "^hooks:" && ok "with every live session on this version, status has no hooks line" || die "hooks line stays: $("$B" status)"
# a hook writes its version into the mark it makes, and rewrites a mark that has none
python3 - "$B" "$P2" "$SWITCHBOARD_STATE/claude/pid-$P2.json" <<'PY' && ok "a hook's process mark carries this version, rewriting one without it" || die "mark_process version"
import importlib.machinery, importlib.util, json, sys
l = importlib.machinery.SourceFileLoader("sb", sys.argv[1]); m = importlib.util.module_from_spec(importlib.util.spec_from_loader("sb", l))
l.exec_module(m); pid, f = int(sys.argv[2]), sys.argv[3]
d = json.load(open(f)); d.pop("version"); json.dump(d, open(f, "w"))
m.hook_process = lambda: pid; m.mark_process("S2")
sys.exit(0 if json.load(open(f)).get("version") == m.plugin_version() and m.plugin_version() else 1)
PY

finish
