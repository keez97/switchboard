#!/usr/bin/env bash
# records are written by the CLI only
source "$(dirname "$0")/../lib.sh"
fx_delta_eps; fx_repos alpha beta theta
P2=$(fake S2 "$T/beta" impl); hook SessionStart "$T/beta" S2 >/dev/null   # a peer to address messages to

BD="$SWITCHBOARD_DIR"; mkdir -p "$BD/bin" "$BD/.claude/worktrees/w1/links"
hook PreToolUse "$T/delta" S5 Write "{\"file_path\":\"$BD/links/lfake.json\"}" | has "written with the board CLI" && ok "a Write into the board's links dir is refused, and the refusal says why" || die "record write not refused"
hook PreToolUse "$BD" S5 Edit '{"file_path":"roles/x.json"}' | has '"deny"' && hook PreToolUse "$T/delta" S5 Write "{\"file_path\":\"$BD/tasks/t1/request.json\"}" | has '"deny"' && ok "a relative path from inside the clone and the tasks dir are covered" || die "relative or tasks write allowed"
[ -z "$(hook PreToolUse "$T/delta" S5 Write "{\"file_path\":\"$BD/bin/board\"}")" ] && [ -z "$(hook PreToolUse "$BD" S5 Edit '{"file_path":"tests/selftest.sh"}')" ] && ok "bin and tests in the board repo stay editable" || die "bin or tests write refused"
[ -z "$(hook PreToolUse "$T/delta" S5 Write "{\"file_path\":\"$BD/.claude/worktrees/w1/links/l.json\"}")" ] && ok "a worktree's record dirs are not the live board" || die "worktree write refused"
[ -z "$(hook PreToolUse "$T/delta" S5 Bash "{\"command\":\"cat $BD/links/$L2.json | head -3\"}")" ] && [ -z "$(hook PreToolUse "$BD" S5 Bash '{"command":"ls links/ && git add links/x.json && git commit -qm x && git pull -q --rebase"}')" ] && ok "reading a record and git commands in the clone still run" || die "read or git blocked"
hook PreToolUse "$BD" S5 Bash '{"command":"echo {} > roles/x.json"}' | has '"deny"' && hook PreToolUse "$T/delta" S5 Bash "{\"command\":\"cd $BD && cp /tmp/x links/l1.json\"}" | has '"deny"' && hook PreToolUse "$T/delta" S5 Bash "{\"command\":\"rm $BD/holds/h1.json\"}" | has '"deny"' && ok "a shell redirect, copy or remove into a record dir is refused" || die "shell record write allowed"
[ -z "$(hook PreToolUse "$BD" S5 Bash '{"command":"python3 tests/x.py > /dev/null; bash tests/selftest.sh 2>&1 | tail -3"}')" ] && [ -z "$(hook PreToolUse "$BD" S5 Bash "{\"command\":\"$B links && $B hold $T/alpha --until 1h --reason x\"}")" ] && ok "other shell work in the clone and the board CLI are not refused" || die "clone shell work blocked"
n=$(ls "$BD/links"/*.json | wc -l); SWITCHBOARD_SESSION_ID=S5 "$B" link --from "$T/delta:lead" --to "$T/theta:cli" --scope "cli still writes" --to-session open >/dev/null
[ "$(ls "$BD/links"/*.json | wc -l)" -eq $((n+1)) ] && ok "the CLI still creates a link" || die "CLI link creation broken"
mkdir -p "$BD/keys"; KW="keys are installed by Robin, not by a session"
hook PreToolUse "$T/delta" S5 Write "{\"file_path\":\"$BD/keys/allowed_signers\"}" | has "$KW" && hook PreToolUse "$BD" S5 Edit '{"file_path":"keys/allowed_signers"}' | has "$KW" && hook PreToolUse "$T/delta" S5 Bash "{\"command\":\"echo east namespaces=x ssh-ed25519 AAAA >> $BD/keys/allowed_signers\"}" | has "$KW" && hook PreToolUse "$BD" S5 Bash '{"command":"cp /tmp/k keys/new"}' | has "$KW" && ok "a Write, Edit or shell write into keys/ from a session is refused as Robin's to install" || die "keys write allowed"
[ -z "$(hook PreToolUse "$T/delta" S5 Bash "{\"command\":\"cat $BD/keys/allowed_signers\"}")" ] && [ -z "$(hook PreToolUse "$BD" S5 Bash '{"command":"ls keys/ && head -1 keys/allowed_signers | cut -c1-40"}')" ] && ok "reading keys/ from a shell is not refused" || die "keys read refused"
# not record writes: a separator or a record dir inside quotes, a read inside $( ), the clone root as a target
[ -z "$(hook PreToolUse "$BD" S6 Bash '{"command":"git commit -q -m \"add tasks/x; see links/y | and events/z\" -- bin/board"}')" ] && ok "a commit message naming record dirs, with separators inside the quotes, is not a record write" || die "quoted commit message refused"
[ -z "$(hook PreToolUse "$BD" S6 Bash '{"command":"for f in $(grep -l t9cb events/*.json); do cat $f; done"}')" ] && ok "a record dir read inside \$( ) in a for loop is not a record write" || die "read substitution refused"
hook PreToolUse "$BD" S6 Bash '{"command":"for f in events/*.json; do rm $f; done"}' | has '"deny"' && ok "the same loop removing the records is still refused" || die "rm loop allowed"
hook PreToolUse "$BD" S6 Bash '{"command":"rm -rf . ; echo {} > roles/x.json"}' | has '"deny"' && refusal S6 | has "roles/x.json" && ! refusal S6 | has "\"target\": \"$(cd "$BD" && pwd -P)\"" && ok "a refusal never records the clone root as its target" || die "clone root recorded: $(refusal S6)"
echo x > "$T/alpha/ROADMAP-core.md"; pre PermissionDenied "$T/alpha" S6 t14 Bash "{\"command\":\"$B link --from a:b --to c:d --scope \\\"execute ROADMAP-core.md in bin/board\\\"\"}" "classifier: Permission Grant" >/dev/null
[ -z "$(send PreToolUse "$T/alpha" S6 "$T/sock.$P2" "read ROADMAP-core.md first, then bin/board")" ] && ok "a refused board command records no file from its arguments, so a message naming them passes" || die "board argument recorded as target: $(refusal S6)"
"$B" read --repo theta | has "cli still writes" && ok "board read --repo resolves a short repo name" || die "read --repo short name"
{ "$B" read --repo nosuch 2>&1 || true; } | has "unknown repo" && ok "board read --repo refuses an unknown name" || die "read --repo unknown name"

# a loop or branch is judged by the commands inside it: one that only lists runs, one that writes is refused
[ -z "$(hook PreToolUse "$BD" S5 Bash '{"command":"ls tasks/; for d in links/*.json; do echo \"$d $(head -c 20 $d)\"; done"}')" ] \
  && [ -z "$(hook PreToolUse "$BD" S5 Bash '{"command":"if [ -d links ]; then ls links/; fi"}')" ] \
  && ok "a for loop and an if that only list records run" || die "record reads in a loop refused"
deny(){ hook PreToolUse "$1" S5 Bash "$(python3 -c 'import json,sys; print(json.dumps({"command": sys.argv[1]}))' "$2")" | has '"deny"'; }
deny "$BD" 'for f in links/*.json; do rm $f; done' && deny "$BD" 'if true; then rm links/x.json; fi' && deny "$BD" "python3 -c 'open(\"links/x.json\",\"w\").write(\"{}\")'" \
  && ok "a loop or branch that deletes records, and a python one-liner that writes one, are refused" || die "record write in a loop, branch or python let through"
deny "$BD" 'for f in a; do echo {}; done > links/x.json' && deny "$BD" '{ echo {}; } > roles/x.json' && deny "$BD" 'if true; then echo {}; fi 2> links/x.json' \
  && deny "$T/delta" "for f in a; do echo {}; done > $BD/links/x.json" \
  && deny "$BD" 'for f in a; do echo {}; done >& links/x.json' && deny "$BD" '{ echo {}; } <> roles/x.json' \
  && [ -z "$(hook PreToolUse "$BD" S5 Bash '{"command":"until cat links/a.json; do echo; done >&2"}')" ] \
  && ok "a redirect into a record after done, } or fi is refused, >& and <> included; >&2 is not a write" || die "redirect after a closing keyword let through"
deny "$BD" 'for f in $(rm links/x.json); do echo; done' && deny "$BD" 'for f in `rm links/x.json`; do echo; done' && deny "$BD" 'echo $(rm links/x.json)' \
  && ok "a command substitution that deletes a record is refused, in a loop header or in a listed command" || die "substitution let through"
deny "$BD" 'for d in 1; do cd links/; echo {} > x.json; done' && deny "$BD" '{ cd links; cp /tmp/x y.json; }' && deny "$T/delta" "if true; then cd $BD/links; cp /tmp/x y.json; fi" \
  && ok "a cd into a record dir behind a keyword still counts" || die "cd behind a keyword let through"

# find, sort, uniq and xxd that write through their arguments are writes; the same commands reading still run
runs(){ [ -z "$(hook PreToolUse "$1" S5 Bash "$(python3 -c 'import json,sys; print(json.dumps({"command": sys.argv[1]}))' "$2")")" ]; }
deny "$BD" 'find links/ -name x.json -delete' && deny "$BD" 'find events/ -type f -exec rm {} +' && deny "$BD" 'find events/ -type f -exec rm {} \;' \
  && deny "$BD" 'find tasks/ -fprint links/x.json' && deny "$BD" 'sort -o roles/x.json /tmp/x' && deny "$BD" 'uniq /tmp/x links/y.json' \
  && deny "$BD" 'xxd -r /tmp/x holds/h.json' \
  && ok "find -delete, -exec rm and -fprint, sort -o, uniq and xxd -r with an output file into a record dir are refused" || die "a find, sort, uniq or xxd record write let through"
runs "$BD" "find links/ -name '*.json' -exec grep -l scope {} +" && runs "$BD" 'sort links/a.json | uniq -c' && runs "$BD" 'xxd holds/h1.json | head' \
  && runs "$BD" "sort -o $T/sorted.txt $T/in.txt" && runs "$BD" "find links/ -name '*.json' | xargs grep -l scope" \
  && ok "find -exec grep, sort | uniq -c, xxd | head, sort -o outside the board and find | xargs grep still run in the clone" || die "a record read refused"
# the whole command is judged: a read naming a record dir that feeds a write elsewhere in it is a write
deny "$BD" 'find links -name x | xargs rm' && deny "$BD" 'for f in $(grep -l x events/*.json); do rm $f; done' && deny "$T/delta" "ls $BD/links/*.json | xargs rm" \
  && ok "a record read piped to xargs rm, or listed by a loop header that removes, is refused" || die "a read feeding a record write let through"
deny "$BD" 'rm -rf links' && deny "$BD" 'find links -delete' && deny "$BD" 'mv ./roles /tmp/r' \
  && runs "$BD" 'python3 tests/x.py --note "tidy links"' && runs "$BD" 'git ls-files links | wc -l' \
  && ok "a record dir named bare from the clone root is refused; the same word quoted in prose is not" || die "bare record dir handled wrong"
deny "$BD" 'echo -delete | xargs find links/' && deny "$T/delta" "echo -delete | xargs find $BD/links" \
  && ok "xargs find with -delete from its input is refused on a record dir, from the clone and from elsewhere" || die "xargs find into records let through"
runs "$BD" 'python3 bin/board links' && runs "$BD" 'python3 bin/board links --json' && runs "$BD" 'python3 bin/board tasks' \
  && runs "$BD" 'python3 bin/board read --repo events' && deny "$BD" 'python3 tests/x.py links' \
  && ok "the board CLI run as python3 bin/board is not a record write; another script naming a record dir is" || die "python3 bin/board judged wrong"
deny "$BD" 'python3 bin/board status > links/x.json' && deny "$BD" 'python3 bin/board links >> roles/r.json' \
  && hook PreToolUse "$BD" S5 Bash '{"command":"python3 bin/board x > keys/allowed_signers"}' | has "$KW" \
  && deny "$T/delta" "python3 $BD/bin/board status > $BD/links/x.json" && deny "$BD" 'python3 /tmp/any/board links/x.json' \
  && deny "$BD" '/tmp/any/board links/x.json' \
  && ok "the CLI under python redirected into a record dir or keys/ is refused, and a script named board elsewhere is not the CLI" || die "python3 board redirect or impostor let through"
# shellcheck disable=SC2088  # the guard is given the command as a session writes it, ~ unexpanded
hook PreToolUse "$BD" S5 Bash '{"command":"bin/board x > keys/allowed_signers"}' | has "$KW" && deny "$BD" './bin/board status > links/x.json' \
  && deny "$T/delta" "~/board/bin/board status > $BD/roles/r.json" \
  && runs "$BD" "python3 bin/board links --json > $T/l.json" && runs "$BD" "$B links > $T/l.txt" \
  && ok "the CLI called directly and redirected into a record dir or keys/ is refused; redirected elsewhere it runs" || die "CLI redirect judged wrong"

finish
