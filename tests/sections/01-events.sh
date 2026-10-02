#!/usr/bin/env bash
# events, delivery, holds and scan
source "$(dirname "$0")/../lib.sh"

mkrepo "$T/alpha"; mkrepo "$T/beta"; mkrepo "$T/gamma"
echo '[{"kind":"json","target":"home:.claude/settings.json","key":"enabledPlugins","tag":"manual"}]' > "$SWITCHBOARD_DIR/defaults.json"
for r in alpha beta gamma; do "$B" register "$T/$r" >/dev/null; done
"$B" watch "$T/beta" path "$T/alpha/VERSION" >/dev/null
"$B" watch "$T/beta" git "$T/alpha" --branches 'candidate/*' >/dev/null
echo 1 > "$T/alpha/VERSION"; git -C "$T/alpha" branch candidate/x
hook SessionStart "$T/alpha" sA >/dev/null      # first snapshot: no events
[ -z "$(ls "$SWITCHBOARD_DIR/events")" ] && ok "first snapshot writes no events" || die "events on first snapshot"

echo 2 > "$T/alpha/VERSION"; git -C "$T/alpha" branch -D candidate/x -q
hook Stop "$T/alpha" sA
[ "$(ls "$SWITCHBOARD_DIR/events" | wc -l)" -eq 2 ] && ok "watched file and branch changes produce two events" || die "expected 2 events"
out=$(hook SessionStart "$T/beta" sB); echo "$out" | has "VERSION content changed" && echo "$out" | has "candidate/x deleted" && ok "subscriber beta receives both" || die "beta did not get events: $out"
[ -z "$(hook PostToolUse "$T/beta" sB Read '{}')" ] && ok "each event is delivered once per session" || die "redelivered"
[ -z "$(hook SessionStart "$T/gamma" sG)" ] && ok "unsubscribed gamma receives nothing" || die "gamma got noise"
[ -z "$(hook SessionStart "$T" sX)" ] && ok "session outside any repo receives nothing" || die "non-repo session got output"

echo '{"enabledPlugins":{"a":false}}' > "$HOME/.claude/settings.json"; hook Stop "$T/alpha" sA
hook SessionStart "$T/gamma" sG2 | has 'a: true to false' && ok "shared config key change reaches every repo with a generated diff" || die "no shared config event"

hook PostToolUse "$T/gamma" sG3 Edit "{\"file_path\":\"$T/alpha/src.py\"}" >/dev/null
hook SessionStart "$T/alpha" sA2 | has "gamma wrote repo:" && ok "cross-boundary write notifies the owner" || die "no crosswrite event"
hook PostToolUse "$T/gamma" sG3 Edit "{\"file_path\":\"$T/gamma/own.py\"}" >/dev/null
[ "$(ls "$SWITCHBOARD_DIR/events" | wc -l)" -eq 4 ] && ok "write inside own repo is not an event" || die "own write produced an event"

# a session alone in a subscribed repo is told of the watch changes it detects itself, at its Stop and at its SessionStart
"$B" watch "$T/gamma" path "$T/alpha/NOTES" >/dev/null; echo 1 > "$T/alpha/NOTES"
hook SessionStart "$T/gamma" sL >/dev/null; echo 2 > "$T/alpha/NOTES"; hook Stop "$T/gamma" sL >/dev/null
hook PostToolUse "$T/gamma" sL Read '{}' | has "NOTES content changed" && ok "a session gets the note of a watch change its own Stop detected" || die "the detecting session got no note of its own watch event"
echo 3 > "$T/alpha/NOTES"
[ "$(hook SessionStart "$T/gamma" sL2 | ctx | grep -c "NOTES content changed")" = 2 ] && ok "the first session to start after a change gets the note its own SessionStart detected" || die "the starting session lost the watch event it detected"
bash_ti(){ python3 -c 'import json,sys; print(json.dumps({"command": sys.argv[1]}))' "$1"; }
refused(){ hook PreToolUse "$1" sG3 Bash "$(bash_ti "$2")" | has '"deny"'; }
runs(){ [ -z "$(hook PreToolUse "$1" sG3 Bash "$(bash_ti "$2")")" ]; }

hid=$("$B" hold "$T/alpha" --until 2d --reason "eval running" | awk '{print $2}')
out=$(hook SessionStart "$T/gamma" sG4); ! echo "$out" | has "HOLD until" && hook SessionStart "$T/alpha" sA3 | has "HOLD until .* on repo:.*: eval running (edits there are refused)" \
  && ok "a hold's line reaches a session in the held repo and not one in another repo" || die "hold delivery: $out"
hh=$("$B" hold "$HOME/.claude/agents" --until 1d --reason "agents rewrite" | awk '{print $2}')
hook PostToolUse "$T/gamma" sG4 Read '{}' | has "HOLD until .* on home:.claude/agents: agents rewrite" && ok "a hold outside any repo reaches every repo" || die "home hold not delivered"
"$B" release "$hh" >/dev/null
# a hold on a ~/.claude entry that links into a repo (skills from a config repo): enforced at the resolved target as
# before, on every machine that has the repo; delivered to every repo; the link's own spellings are refused too
mkrepo "$T/cfg"; git -C "$T/cfg" remote add origin https://github.com/test/cfg.git; "$B" register "$T/cfg" >/dev/null
mkdir -p "$T/cfg/skills/s1" "$HOME/.claude/skills" && echo s > "$T/cfg/skills/s1/SKILL.md" && ln -s "$T/cfg/skills/s1" "$HOME/.claude/skills/s1"
hsk=$("$B" hold "$HOME/.claude/skills/s1" --until 1h --reason "skill rewrite" | awk '{print $2}')
# shellcheck disable=SC2088  # the message names ~/.claude as written
[ "$(jq -r .path "$SWITCHBOARD_DIR/holds/$hsk.json")" = "repo:github.com/test/cfg:skills/s1" ] && [ "$(jq -r .via "$SWITCHBOARD_DIR/holds/$hsk.json")" = "home:.claude/skills/s1" ] \
  && hook PostToolUse "$T/gamma" sG4 Read '{}' | has "HOLD until .* on home:.claude/skills/s1 (repo:github.com/test/cfg:skills/s1): skill rewrite" \
  && ok "a hold on a linked ~/.claude entry keeps the resolved path for the guard, names the link, and reaches every repo" || die "~/.claude link hold: $(cat "$SWITCHBOARD_DIR/holds/$hsk.json")"
g(){ hook PreToolUse "$T/gamma" sG4 "$@" | has "hold $hsk"; }
g Edit "{\"file_path\":\"$HOME/.claude/skills/s1/SKILL.md\"}" && g Write "{\"file_path\":\"$T/cfg/skills/s1/SKILL.md\"}" \
  && g Bash '{"command":"echo x > ~/.claude/skills/s1/SKILL.md"}' && g Bash '{"command":"echo x > $HOME/.claude/skills/s1/SKILL.md"}' \
  && g Bash "{\"command\":\"echo x > $HOME/.claude/skills/s1/SKILL.md\"}" && ! g Bash '{"command":"cat ~/.claude/skills/s1/SKILL.md"}' \
  && ok "the guard refuses a write through the link, at its target, and a shell write naming the link as ~, \$HOME or absolute" || die "guard through the ~/.claude link"
g Bash '{"command":"cd ~/.claude/skills && rm s1/SKILL.md"}' && g Bash "{\"command\":\"cd $T/cfg && rm skills/s1/SKILL.md\"}" && ! g Bash '{"command":"cd ~/.claude/skills && ls s1"}' \
  && ok "through a cd and a relative path, the link and its target are both held" || die "cd and relative path to a ~/.claude link hold"
mkrepo "$T/cfg2"; mkdir -p "$T/home2" "$T/cfg2/skills/s1"
echo "{\"id\": \"github.com/test/cfg\", \"name\": \"cfg\", \"root\": \"$T/cfg2\"}" > "$SWITCHBOARD_DIR/registry/github.com_test_cfg.west.json"
HOME="$T/home2" SWITCHBOARD_MACHINE=west hook PreToolUse "$T/cfg2" sH1 Write "{\"file_path\":\"$T/cfg2/skills/s1/SKILL.md\"}" | has "hold $hsk" \
  && ok "another machine with the same repo and no link refuses the write in its own checkout" || die "second machine allowed the write"
"$B" release "$hsk" >/dev/null
hdd=$("$B" hold "$HOME/.claude/skills/s1/.." --until 1h --reason "skills tree" | awk '{print $2}')
[ "$(jq -r .path "$SWITCHBOARD_DIR/holds/$hdd.json")" = "repo:github.com/test/cfg:skills" ] && hook PreToolUse "$T/gamma" sG4 Write "{\"file_path\":\"$T/cfg/skills/other.md\"}" | has "hold $hdd" \
  && ok "a hold on <link>/.. holds the link target's parent" || die "dot-dot hold: $(cat "$SWITCHBOARD_DIR/holds/$hdd.json")"
"$B" release "$hdd" >/dev/null
hook PreToolUse "$T/gamma" sG3 Edit "{\"file_path\":\"$T/alpha/x\"}" | has '"deny"' && ok "hold refuses an edit from another repo" || die "edit not refused"
hook PreToolUse "$T/gamma" sG3 Bash "{\"command\":\"rm -rf $T/alpha/build\"}" | has '"deny"' && ok "hold refuses a shell command naming the path" || die "bash not refused"
hook PreToolUse "$T/alpha" sA Bash '{"command":"git commit -m x"}' | has '"deny"' && ok "hold refuses a mutating command run inside the path" || die "inside bash not refused"
[ -z "$(hook PreToolUse "$T/alpha" sA Bash '{"command":"git status 2>/dev/null && ls | head && tail -n 3 README.md 2>&1"}')" ] && ok "read-only commands inside a held path still run" || die "read-only blocked"
[ -z "$(hook PreToolUse "$T/gamma" sG3 Edit "{\"file_path\":\"$T/gamma/x\"}")" ] && ok "other paths are unaffected" || die "unrelated edit blocked"
refused "$T/gamma" "find $T/alpha -name '*.tmp' -delete" && refused "$T/gamma" "find $T/alpha -type f -exec rm {} \\;" \
  && ok "hold refuses find -delete and find -exec rm on the held path" || die "find writing into a held path let through"
refused "$T/gamma" "git -C $T/alpha worktree add $T/alpha/wt" && refused "$T/gamma" "git worktree add $T/alpha/wt2" \
  && ok "hold refuses git worktree add under the held path" || die "git worktree add into a held path let through"
runs "$T/gamma" "find $T/alpha -name '*.py'" && runs "$T/gamma" "find $T/alpha -name '*.py' -exec grep -l x {} +" \
  && runs "$T/gamma" "sort $T/alpha/VERSION | uniq -c" && runs "$T/gamma" "git -C $T/alpha worktree list" \
  && runs "$T/gamma" "sort -o $T/gamma/sorted.txt $T/gamma/in.txt" \
  && ok "find, find -exec grep, sort | uniq -c, git worktree list and sort -o outside the hold still run on a held path" || die "a read of a held path refused"
# xargs takes arguments from its input, so it may run only a command no argument makes write
A="$T/alpha"
refused "$T/gamma" "echo -delete | xargs find $A" && refused "$T/gamma" "printf '%s\\n' $A -delete | xargs find" \
  && refused "$T/gamma" "echo -fprint $A/o | xargs find /etc" && refused "$A" "echo -delete | xargs find ." \
  && ok "xargs running find, with -delete or -fprint from its input, is refused on a held path" || die "xargs find let through on a held path"
refused "$T/gamma" "echo rm $A/VERSION | xargs xargs" && refused "$A" "echo rm VERSION | xargs xargs" \
  && refused "$T/gamma" "echo -o $A/x /etc/hosts | xargs sort" && refused "$A" "echo -o VERSION VERSION | xargs sort" \
  && refused "$T/gamma" "echo /etc/hosts $A/out | xargs uniq" && refused "$T/gamma" "echo -r /tmp/x $A/y | xargs xxd" \
  && refused "$T/gamma" "echo --pre=rm x $A | xargs rg" \
  && ok "xargs running xargs, sort, uniq, xxd or rg is refused on a held path" || die "xargs with a writer-by-argument let through on a held path"
refused "$T/gamma" "find $A -name '*.sh' -exec {} \\;" && refused "$T/gamma" "find $A -name '*.sh' -execdir {} +" \
  && ok "find -exec {} runs each file found and is refused on a held path" || die "find -exec {} let through"
runs "$T/gamma" "find $A | xargs -0 wc -l" && runs "$A" "git stash list" && runs "$A" "git stash show -p" && refused "$A" "git stash pop" \
  && ok "xargs wc, git stash list and git stash show still run on a held path; git stash pop does not" || die "stash or xargs wc judged wrong"
refused "$A" "git stash -m show" && refused "$A" "git stash -m list" && refused "$A" "git stash --message list" \
  && refused "$T/gamma" "git -C $A stash -m show" && refused "$A" "git stash -- show" && refused "$A" "git worktree --foo list" \
  && ok "git stash with an option before list or show is a push, and is refused on a held path" || die "git stash push read as list or show"
refused "$T/gamma" "find $A | xargs /tmp/evil/cat" && refused "$T/gamma" "find $A | xargs --process-slot-var=PATH cat" \
  && runs "$T/gamma" "find $A | xargs cat" \
  && ok "xargs trusts only a bare reader name, and --process-slot-var is a write" || die "xargs with a path or slot variable let through"
"$B" release "$hid" >/dev/null
[ -z "$(hook PreToolUse "$T/gamma" sG3 Edit "{\"file_path\":\"$T/alpha/x\"}")" ] && ok "released hold stops blocking" || die "still blocked after release"
# the hold check follows a cd and relative paths within one command
mkdir -p "$T/gamma/held" "$T/gamma/src"; echo n > "$T/gamma/held/notes.txt"; echo o > "$T/gamma/other.txt"
hid=$("$B" hold "$T/gamma/held" --until 2d --reason "notes frozen" | awk '{print $2}')
refused "$T/gamma" "cd held && rm notes.txt" && refused "$T/gamma" "rm held/notes.txt" && refused "$T/gamma" "git -C held commit -qm x" \
  && refused "$T/gamma" "cd src && cd ../held && python3 x.py" && ok "hold refuses a write after a relative cd into the path, or naming it relatively" || die "relative write into a held path let through"
runs "$T/gamma" "cd held && ls && cat notes.txt" && runs "$T/gamma" "rm other.txt" && runs "$T/gamma" "cd src && python3 -c 'print(1)' > out.txt" \
  && runs "$T/gamma" "git add -A && git commit -qm 'notes in held stay'" && runs "$T/gamma" "sort held/notes.txt | uniq -c" \
  && ok "reads of the held path and ordinary commands elsewhere in the repo still run" || die "ordinary command refused near a held path"
refused "$T/beta" "echo -exec rm {} + | xargs find $T/gamma/held" && refused "$T/gamma/held" "echo -delete | xargs find ." \
  && ok "xargs find with -exec rm or -delete from its input is refused on a held dir and inside it" || die "xargs find let through on a held dir"
"$B" release "$hid" >/dev/null

mkdir -p "$T/gamma/scripts" && echo "REPO=\${REPO:-$T/alpha}" > "$T/gamma/scripts/run.sh" && git -C "$T/gamma" add -A && git -C "$T/gamma" -c user.email=t@t -c user.name=t commit -qm ref
"$B" scan "$("$B" register "$T/gamma" | tail -1 | awk '{print $NF}')"
grep -q "alpha" "$SWITCHBOARD_DIR/subs/"*gamma*.auto.east.json && ok "scan finds a hardcoded path to another repo and adds an auto watch" || die "scan missed the reference"
git -C "$T/gamma" rm -q scripts/run.sh && git -C "$T/gamma" -c user.email=t@t -c user.name=t commit -qm unref && "$B" scan "$("$B" register "$T/gamma" | tail -1 | awk '{print $NF}')"
grep -q '"watches": \[\]' "$SWITCHBOARD_DIR/subs/"*gamma*.auto.east.json && ok "auto watch disappears when the reference does" || die "stale auto watch"

# a json watch on a scalar key names the values; a deleted file is gone, not changed; a secret-looking value is hidden
"$B" watch "$T/beta" json "$T/alpha/cfg.json" --key version >/dev/null
echo '{"version": 1}' > "$T/alpha/cfg.json"; hook Stop "$T/alpha" sA >/dev/null
echo '{"version": 2}' > "$T/alpha/cfg.json"; hook Stop "$T/alpha" sA >/dev/null
out=$(hook SessionStart "$T/beta" sBj); echo "$out" | has "cfg.json#version changed: 1 to 2" && ok "a json watch on a number says from what to what" || die "scalar diff: $out"
echo "{\"version\": \"gh""p_$(printf 'a%.0s' $(seq 36))\"}" > "$T/alpha/cfg.json"; hook Stop "$T/alpha" sA >/dev/null
out=$(hook PostToolUse "$T/beta" sBj Read '{}'); echo "$out" | has "cfg.json#version changed (value hidden: it matches a secret pattern)" && ! grep -rq "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" "$SWITCHBOARD_DIR/events" \
  && ok "a value that matches a secret pattern is not written into the event" || die "secret value: $out"
rm "$T/alpha/cfg.json"; hook Stop "$T/alpha" sA >/dev/null
out=$(hook PostToolUse "$T/beta" sBj Read '{}'); echo "$out" | has "cfg.json#version is gone" && ok "a deleted json file is gone, not changed" || die "json gone: $out"
# values under a key that names a credential never reach events/, whatever they look like; long dict values are cut
"$B" watch "$T/beta" json "$T/alpha/app.json" --key password >/dev/null; "$B" watch "$T/beta" json "$T/alpha/app.json" --key db >/dev/null
echo '{"password": "hunter2-old", "db": {"api_key": "plainvalue-old", "token": "0123456789abcdef0123456789abcdef", "host": "a", "note": "x"}}' > "$T/alpha/app.json"; hook Stop "$T/alpha" sA >/dev/null
python3 -c "import json; print(json.dumps({'password': 'hunter2-new', 'db': {'api_key': 'plainvalue-new', 'token': 'fedcba9876543210fedcba9876543210', 'host': 'b', 'note': 'y'*400}}))" > "$T/alpha/app.json"; hook Stop "$T/alpha" sA >/dev/null
out=$(hook PostToolUse "$T/beta" sBj Read '{}' | ctx)
echo "$out" | has "app.json#password changed (value hidden)" && echo "$out" | has "api_key changed (value hidden)" && echo "$out" | has "token changed (value hidden)" && echo "$out" | has 'host: "a" to "b"' \
  && ! grep -rqE "hunter2|plainvalue|0123456789abcdef|fedcba98765" "$SWITCHBOARD_DIR/events" && ok "a value under password, api_key or token is hidden, plain or hex; other keys still show" || die "key-named secrets: $out"
for k in nest apiToken passed keyboard; do "$B" watch "$T/beta" json "$T/alpha/app2.json" --key $k >/dev/null; done
echo '{"nest": {"db": {"password": "nestpw-old"}, "list": [{"token": "nesttok-old"}], "author": "ann", "session_count": 1, "sessionToken": "st-old"}, "apiToken": "at-old", "passed": 1, "keyboard": "us"}' > "$T/alpha/app2.json"; hook Stop "$T/alpha" sA >/dev/null
echo '{"nest": {"db": {"password": "nestpw-new"}, "list": [{"token": "nesttok-new"}], "author": "bob", "session_count": 2, "sessionToken": "st-new"}, "apiToken": "at-new", "passed": 2, "keyboard": "fr"}' > "$T/alpha/app2.json"; hook Stop "$T/alpha" sA >/dev/null
out=$(hook PostToolUse "$T/beta" sBj Read '{}' | ctx)
! grep -rqE "nestpw|nesttok|st-old|st-new|at-old|at-new" "$SWITCHBOARD_DIR/events" && echo "$out" | has "app2.json#apiToken changed (value hidden)" && echo "$out" | has "sessionToken changed (value hidden)" \
  && echo "$out" | has "db changed (value hidden)" && echo "$out" | has "list changed (value hidden)" && ok "a credential nested in a dict or a list is hidden too, and apiToken or sessionToken by its last word" || die "nested secrets: $out"
echo "$out" | has 'author: "ann" to "bob"' && echo "$out" | has "app2.json#passed changed: 1 to 2" && echo "$out" | has 'app2.json#keyboard changed: "us" to "fr"' && echo "$out" | has "session_count: 1 to 2" \
  && ok "author, passed, keyboard and session_count are not taken for credentials" || die "key words over-matched: $out"
for k in more url; do "$B" watch "$T/beta" json "$T/alpha/app3.json" --key $k >/dev/null; done
echo '{"more": {"passphrase": "pp-old", "privkey": "pk-old", "authorization": "az-old", "mfa_seed": "ms-old", "otp_seed": "os-old", "otp": "ot-old", "n": 1}, "url": "https://u:dbpw-old@h/x"}' > "$T/alpha/app3.json"; hook Stop "$T/alpha" sA >/dev/null
echo '{"more": {"passphrase": "pp-new", "privkey": "pk-new", "authorization": "az-new", "mfa_seed": "ms-new", "otp_seed": "os-new", "otp": "ot-new", "n": 2}, "url": "run --password=dbpw-new"}' > "$T/alpha/app3.json"; hook Stop "$T/alpha" sA >/dev/null
out=$(hook PostToolUse "$T/beta" sBj Read '{}' | ctx)
! grep -rqE "pp-|pk-|az-|ms-|os-|ot-|dbpw" "$SWITCHBOARD_DIR/events" && echo "$out" | has "n: 1 to 2" && echo "$out" | has "app3.json#url changed (value hidden" \
  && ok "passphrase, privkey, authorization, a seed, otp, a URL with a password and password= are hidden" || die "more secrets: $out"
for k in c1 c2 c3 c4 w; do "$B" watch "$T/beta" json "$T/alpha/app4.json" --key $k >/dev/null; done
echo '{"c1": "run", "c2": "a", "c3": "b", "c4": "c", "w": {"seedphrase": "sp-old", "n": 1}}' > "$T/alpha/app4.json"; hook Stop "$T/alpha" sA >/dev/null
echo '{"c1": "run --api-key=vk1-x", "c2": "token: vk2", "c3": "secret = vk3", "c4": "admin:vk4pw@db.example.com", "w": {"seedphrase": "sp-new", "n": 2}}' > "$T/alpha/app4.json"; hook Stop "$T/alpha" sA >/dev/null
out=$(hook PostToolUse "$T/beta" sBj Read '{}' | ctx)
! grep -rqE "vk1|vk2|vk3|vk4pw|sp-old|sp-new" "$SWITCHBOARD_DIR/events" && echo "$out" | has "n: 1 to 2" && [ "$(echo "$out" | grep -c 'app4.json#c[1-4] changed (value hidden')" = 4 ] \
  && ok "--api-key=, token:, secret =, user:pass@host without a scheme, and a seedphrase key are hidden" || die "value patterns: $out"
python3 - "$SWITCHBOARD_DIR/events" <<'PY' && ok "a long dict value is cut and the whole summary is capped" || die "long dict value: $(grep -h -o '"summary": "[^"]*app.json#db[^"]*' "$SWITCHBOARD_DIR"/events/*.json | head -1 | cut -c1-200)"
import glob,json,sys
s=[json.load(open(f))["summary"] for f in glob.glob(sys.argv[1]+"/*.json") if "app.json#db" in json.load(open(f))["summary"]]
sys.exit(0 if len(s)==1 and len(s[0])<=600 and "y"*81 not in s[0] and "..." in s[0] else 1)
PY

finish
