#!/usr/bin/env bash
# guard gaps: a bare board after a PATH or alias change, record and held paths
# spelled with quotes, escapes, .., variables, braces or globs, the hold check through links, and a malformed via
source "$(dirname "$0")/../lib.sh"
cap_procs   # it runs pre-push hooks: one that ran itself would stop at the cap
fx_repos alpha gamma delta
BD="$SWITCHBOARD_DIR"; mkdir -p "$BD/links" "$BD/roles" "$BD/tests" "$T/evil" "$T/gamma/held" "$T/outside"
echo '{}' > "$BD/links/la.json"; echo 1 > "$T/alpha/VERSION"; echo n > "$T/gamma/held/notes.txt"
j(){ python3 -c 'import json,sys; print(json.dumps({"command": sys.argv[1]}))' "$1"; }
deny(){ hook PreToolUse "$1" S1 Bash "$(j "$2")" | has '"deny"'; }
runs(){ [ -z "$(hook PreToolUse "$1" S1 Bash "$(j "$2")")" ]; }
wdeny(){ hook PreToolUse "$1" S1 Write "{\"file_path\":\"$2\",\"content\":\"x\"}" | has '"deny"'; }
wruns(){ [ -z "$(hook PreToolUse "$1" S1 Write "{\"file_path\":\"$2\",\"content\":\"x\"}")" ]; }

# 1. a bare `board` is the CLI only while nothing in the command can change what the name runs
deny "$BD" "PATH=$T/evil:\$PATH board links/x.json" && deny "$BD" "export PATH=$T/evil:\$PATH; board links/x.json" \
  && deny "$BD" "PATH+=:$T/evil; board links/x.json" && deny "$BD" "alias board=$T/evil/board; board links/x.json" \
  && deny "$BD" "hash -p $T/evil/board board; board links/x.json" && deny "$BD" "source $T/evil/rc; board links/x.json" \
  && deny "$BD" ". $T/evil/rc && board links/x.json" && deny "$BD" "board() { cat; }; board links/x.json" \
  && deny "$BD" "eval \"PATH=$T/evil:\$PATH\"; board links/x.json" && deny "$T/delta" "PATH=$T/evil:\$PATH board $BD/links/x.json" \
  && runs "$BD" "board links" && runs "$BD" "board links --json | jq ." && runs "$T/delta" "export FOO=1; board links" \
  && runs "$T/delta" "echo \$PATH; board links" && runs "$BD" "python3 bin/board links" \
  && ok "a bare board after a PATH, alias, hash, source, eval or function change is judged as any command; plain CLI calls run" || die "board rebinding judged wrong"
echo '#!/bin/sh' > "$BD/board"
PATH=".:$PATH" deny "$BD" "board links/x.json" && PATH="$PATH:" deny "$T/delta" "cd $T/evil && board $BD/links/x.json" \
  && runs "$BD" "board links/x.json 2>/dev/null; true" \
  && ok "with a relative entry in the hook's PATH, a planted board file or a cd makes a bare board an ordinary command" || die "relative PATH entry"
rm "$BD/board"

# 2. record paths however spelled, from the clone and from a sibling dir
deny "$BD" 'cp /tmp/x "links"/x.json' && deny "$BD" "cp /tmp/x l''inks/x.json" && deny "$BD" 'cp /tmp/x li\nks/x.json' \
  && deny "$BD" 'cp /tmp/x tests/../links/x.json' && deny "$BD" 'D=links; cp /tmp/x $D/x.json' && deny "$BD" 'board status > ${D:-links}/x.json' \
  && deny "$BD" 'board status > $(echo links)/x.json' && deny "$BD" 'cp /tmp/x {links,tests}/y.json' && deny "$BD" 'cp /tmp/x l?nks/y.json' \
  && deny "$BD" 'D=links; cd $D && cp /tmp/x y.json' && deny "$BD" 'pushd links && cp /tmp/x y.json' \
  && ok "a record path in quotes, escaped, through .., in a variable, a substitution, a brace list or a glob, or a cd or pushd into one, is refused" || die "hidden record path let through"
deny "$T/delta" 'cp /tmp/x ../board/links/x.json' && deny "$T/delta" "cp /tmp/x ~/'x'/../../board/./links/x.json" \
  && deny "$T/delta" "export D=$BD; cp /tmp/x \${D}/links/y.json" && deny "$T/delta" "cp /tmp/x \$(echo $BD)/links/y.json" \
  && deny "$T/delta" 'cd .. && cp /tmp/x board/links/y.json' && deny "$T/delta" "bash -c 'cp /tmp/x \"../board\"/links/y.json'" \
  && deny "$T/delta" 'cp /tmp/x "../board"/keys/allowed_signers' && ln -s "$BD/links" "$T/lb" && deny "$T/delta" "cp /tmp/x $T/lb/y.json" \
  && ok "from a sibling dir: .., ~ with quotes, an exported variable, a substitution, cd .., sh -c, a link to links/, and keys/ too" || die "record path from a sibling let through"
runs "$BD" 'cat "links"/la.json' && runs "$BD" 'D=links; cat $D/la.json' && runs "$T/delta" 'cat ../board/links/la.json' \
  && runs "$T/delta" "echo \"see ../alpha/VERSION and links/x\" > $T/note.txt" && runs "$BD" 'python3 tests/x.py > /tmp/out.txt' \
  && runs "$T/delta" "git -C $T/delta commit -m \"move ../alpha/f to links/x\" --allow-empty" && runs "$T/delta" 'cp /tmp/x "$TMPDIR"/y' \
  && runs "$BD" 'for f in tests/*.py; do python3 $f; done' && deny "$BD" 'for d in lin; do cp /tmp/x ${d}ks/y.json; done' \
  && ok "reads, prose naming the paths, a commit message and a loop over the tests still run; a loop whose variable makes a record path does not" || die "a read or prose refused, or a loop let through"
deny "$BD" 'git log --output=links/x.json' && deny "$BD" 'git diff --output links/x.json' && deny "$BD" 'git log > links/x.json' \
  && deny "$T/delta" "git -C $BD show --output=../board/roles/r.json" && deny "$T/delta" 'git -C ../board log --output=links/x.json' \
  && runs "$BD" 'git log --oneline > /tmp/log.txt' && runs "$BD" 'git diff --output=/tmp/d.patch' && runs "$BD" 'git add links/la.json && git commit -qm x' \
  && ok "git writing a record through > or --output is refused; other git in the clone runs" || die "git --output judged wrong"

# the same spellings against a hold
"$B" hold "$T/alpha" --until 1h --reason "alpha frozen" >/dev/null
"$B" hold "$T/gamma/held" --until 1h --reason "held frozen" >/dev/null
deny "$T/delta" 'cp /etc/hosts "../alpha/f"' && deny "$T/delta" "rm ../gamma/'held'/notes.txt" && deny "$T/delta" 'rm ../al\pha/VERSION' \
  && deny "$T/delta" 'D=../alpha; rm $D/VERSION' && deny "$T/delta" 'rm "$HOME"/../alpha/VERSION' && deny "$T/delta" 'rm ../al*/VERSION' \
  && deny "$T/delta" 'rm ../{alpha,delta}/VERSION' && deny "$T/delta" 'D=../gamma/held; cd $D && rm notes.txt' \
  && deny "$T/delta" 'dd if=/dev/zero of=../alpha/f count=1' \
  && runs "$T/delta" "echo \"see ../alpha/VERSION\" > $T/note.txt" && runs "$T/delta" 'D=../delta; echo x > $D/out.txt' \
  && ok "a held path in quotes, escaped, in a variable, a glob, a brace list or a cd target is refused; prose naming it is not" || die "hidden held path let through"

# 3. the hold check follows links, both ways
ln -s "$T/alpha" "$T/delta/toalpha"; ln -s "$T/gamma/held" "$T/lk"
deny "$T/delta" 'rm toalpha/VERSION' && deny "$T/delta" "echo x > $T/delta/toalpha/f" && deny "$T/delta" "rm $T/lk/notes.txt" \
  && deny "$T/delta" "cp /etc/hosts $T/lk/" && deny "$T/delta" "rm $T/delta/to*/VERSION" \
  && runs "$T/delta" 'cat toalpha/VERSION' && runs "$T/delta" "cat $T/lk/notes.txt" && runs "$T/delta" "echo x > $T/delta/out.txt" \
  && ok "a shell write through a link into a held dir is refused, globbed too; reads through it run" || die "link into a held dir let through"
mkdir -p "$T/cfg/skills/s1" "$HOME/.claude/skills" && echo s > "$T/cfg/skills/s1/SKILL.md" && ln -s "$T/cfg/skills/s1" "$HOME/.claude/skills/s1"
HC=$("$B" hold "$HOME/.claude" --until 1h --reason "claude frozen" | awk '{print $2}')
wdeny "$T/delta" "$HOME/.claude/skills/s1/SKILL.md" && hook PreToolUse "$HOME/.claude" S1 Edit '{"file_path":"skills/s1/SKILL.md"}' | has "hold $HC" \
  && wdeny "$T/delta" "$T/lk/new.txt" && wdeny "$T/delta" "toalpha/f" && wruns "$T/delta" "$T/cfg/skills/s1/SKILL.md" && wruns "$T/delta" "$T/delta/f" \
  && deny "$T/delta" "cd ~/'.claude'/skills/s1 && echo x > SKILL.md" && runs "$T/delta" "echo x > $T/cfg/skills/s1/SKILL.md" \
  && ok "a Write or Edit through a link that lives in a held dir (~/.claude/skills/s1) is refused; its target written directly is not" || die "Write through a link in a held dir"
"$B" release "$HC" >/dev/null
# prepush: a commit changing a link that lives in a held dir and points out of it
mkrepo "$T/app"; git init -q --bare -b main "$T/app.git"; git -C "$T/app" remote add origin "$T/app.git"; "$B" register "$T/app" >/dev/null
mkdir -p "$T/app/src" "$T/app/docs"; echo a > "$T/app/src/a.py"; echo d > "$T/app/docs/d.md"
git -C "$T/app" add -A; git -C "$T/app" -c user.email=t@t -c user.name=t commit -qm base; git -C "$T/app" push -q -u origin main 2>/dev/null
ln -s "$B" "$HOME/.claude/board"; "$B" install-prepush "$T/app" >/dev/null   # the hook runs the CLI at ~/.claude/board
HP=$("$B" hold "$T/app/src" --until 1h --reason "src frozen" | awk '{print $2}')
ln -s "$T/outside" "$T/app/src/out"; git -C "$T/app" add -A; git -C "$T/app" -c user.email=t@t -c user.name=t commit -qm "link in src"
out=$(git -C "$T/app" push origin main 2>&1) && die "a push changing a link in a held dir went through" || true
git -C "$T/app" reset -q --hard origin/main; echo d2 >> "$T/app/docs/d.md"; git -C "$T/app" -c user.email=t@t -c user.name=t commit -qam docs
echo "$out" | has "hold $HP: .*changes src/out" && git -C "$T/app" push -q origin main 2>/dev/null \
  && ok "prepush refuses a commit changing a link inside a held dir that points out of it; a push beside the held dir goes through" || die "prepush through a link: $out"
"$B" release "$HP" >/dev/null

# round 2: main's own checks still run beside the helper; heredoc bodies, maybe-assignments, a removed cwd
deny "$T/delta" 'cd ../alpha; cd $X; rm VERSION' && deny "$T/delta" 'rm ../alpha/"my file"' && deny "$T/delta" 'echo "hello world">../alpha/f' \
  && deny "$T/delta" "$(printf 'cat <<EOF >/tmp/o\n$(rm "../alpha"/VERSION)\nEOF')" && deny "$T/delta" "$(printf 'cat <<EOF >/tmp/o; cd ..; cd alpha; rm VERSION\nhi\nEOF')" \
  && deny "$T/delta" 'true && D=../alpha; rm $D/VERSION' && deny "$BD" 'D=links; D=tests true; cp /tmp/x $D/y.json' \
  && deny "$BD" 'read PATH <<< evil; board links/x.json' && runs "$T/gamma" 'gh pr create --title "held/notes.txt: fix typo"' \
  && runs "$T/delta" "$(printf 'gh pr create --title t --body "$(cat <<'"'"'EOF'"'"'\nfix the board hook\nEOF\n)"')" \
  && runs "$T/delta" 'mkdir -p /tmp/board && echo x > /tmp/board/$(date +%s).log' && runs "$T/delta" 'echo "see ../alpha/VERSION" > note.txt' \
  && ok "main's checks still refuse what they did; heredoc bodies, maybe-assignments and quoted paths are read; a body of prose and a dir named like the clone are not" || die "round-2 forms judged wrong"
HC=$("$B" hold "$HOME/.claude" --until 1h --reason "claude frozen" | awk '{print $2}')
mkdir -p "$T/gone"; out=$(cd "$T/gone" && rmdir "$T/gone" && hook PreToolUse "$T/delta" S1 Write "{\"file_path\":\"$HOME/.claude/skills/s1/SKILL.md\",\"content\":\"x\"}" 2>&1)
echo "$out" | has "hold $HC" && ok "with the hook's own cwd removed, a Write through a link in a held dir is still refused" || die "removed cwd: $out"
"$B" release "$HC" >/dev/null

# round 3: opaque words count only as write targets; a backslash-newline; heredocs when unsure; quoted prose
runs "$BD" $'T=/var/tmp/x \\\n  U=1; echo x > $T/a' && deny "$BD" $'T=links \\\n  U=1; cp /tmp/x $T/a' \
  && runs "$T/delta" 'echo x > ~/r4-$(date +%s).log' && runs "$T/delta" 'cd /; rm -rf "$D"' \
  && runs "$BD" 'make -j$(nproc) test' && runs "$BD" 'python3 tests/x.py $1' && runs "$BD" 'echo "$X" > /tmp/x.txt' \
  && runs "$BD" 'cd "$(git rev-parse --show-toplevel)" && python3 tests/x.py' \
  && deny "$BD" 'cp /tmp/x $(echo links)/x.json' && deny "$BD" 'cd $(echo links) && cp /tmp/x y.json' && deny "$BD" 'D=$(cat /tmp/n); rm -rf "$D"' && runs "$BD" 'cp /tmp/x $UNSET_ANYWHERE/y.json' \
  && runs "$BD" 'board tasks --mine --note "source of truth"' && deny "$BD" 'eval "PATH=evil:$PATH"; board links/x.json' \
  && deny "$T/delta" $'echo hi # <<EOF\nrm toalpha/VERSION\nEOF' && deny "$BD" $'echo hi # <<EOF\ncp /tmp/x "links"/y.json\nEOF' \
  && ok "an opaque word counts only where the part writes through it; continuation lines, comments and quoted prose are read as the shell does" || die "round-3 forms judged wrong"
hook PreToolUse "$BD" S1 Bash "$(j 'cd $(echo links) && cp /tmp/x y.json')" | has "records are written" \
  && ok "an opaque refusal from the clone names records, not keys" || die "opaque refusal message"
# timing: main's checks decide first; the helper stops at its deadline; long inputs stay linear
out=$(SWITCHBOARD_GUARD_BUDGET=0 hook PreToolUse "$BD" S1 Bash "$(j 'cp /tmp/x "links"/x.json')")
[ -z "$out" ] && SWITCHBOARD_GUARD_BUDGET=0 deny "$BD" 'cp /tmp/x links/x.json' && grep -q "the path helper ran past" "$SWITCHBOARD_STATE/errors.log" \
  && ok "past its deadline the helper stops, logged: main's verdict stands, allowed where only the helper refuses and refused where main does" || die "deadline: $out"
long=$(python3 -c 'print("".join("export V" + str(i) + "=x; " for i in range(4500)) + "rm ../alpha/VERSION")')
t0=$(python3 -c 'import time; print(int(time.time() * 1000))')
out=$(hook PreToolUse "$T/delta" S1 Bash "$(j "$long")")
t1=$(python3 -c 'import time; print(int(time.time() * 1000))')
echo "$out" | has '"deny"' && [ $((t1 - t0)) -lt 5000 ] \
  && ok "4500 exports then a write into a hold: refused, as main refuses it, under 5 s" || die "pathological command: $((t1 - t0)) ms / $out"
python3 - "$B" "$T" <<'EOP' && ok "long inputs stay linear: 4500 exports, 1000 bare boards, 10000 reads, 100000 [ each judged in-process under 2 s" || die "a long input took too long"
import importlib.machinery, importlib.util, sys, time
ld = importlib.machinery.SourceFileLoader("board", sys.argv[1])
b = importlib.util.module_from_spec(importlib.util.spec_from_loader("board", ld))
ld.exec_module(b)
T = sys.argv[2]
cases = [("".join("export V" + str(i) + "=x; " for i in range(4500)) + "rm ../alpha/VERSION", T + "/delta"),
         ("board x; " * 1000 + "cp /tmp/x links/y.json", T + "/board"), ("read " * 10000, T + "/board"), ("[" * 100000, T + "/board")]
for cmd, cwd in cases:
    t = time.perf_counter()
    b.guard("Bash", {"command": cmd}, cwd)
    if time.perf_counter() - t > 2:
        sys.exit("%.1f s for %s" % (time.perf_counter() - t, cmd[:40]))
EOP

# round 4: shapes that ran past the hook's 5 s; each judged through the hook under 3 s with main's verdict (allow),
# the helper finishing (no deadline line, no RecursionError)
python3 - "$T/delta" > "$T/shapes" <<'EOP'
import json, sys
NL = chr(10)
for c in ["board status" + NL * 20000 + "touch f", "touch f" + NL + ("cat <<X" + NL) * 8000,
          "export " + " ".join("V" + str(i) + "=a" for i in range(15000)), "touch " + "{a,b}" * 40000, "board status; " * 14285,
          "cd -P " + "x/" * 8000 + " && touch f", "pushd -- " + "x/" * 12000 + " && touch f", "cd " + "x/" * 3900 + " && touch f"]:
    print(json.dumps({"hook_event_name": "PreToolUse", "cwd": sys.argv[1], "session_id": "S1", "tool_name": "Bash",
                      "tool_input": {"command": c}}))  # piped: too long for an argument
EOP
late(){ cat "$SWITCHBOARD_STATE/errors.log" 2>/dev/null | grep -cE "ran past|RecursionError" || true; }
before=$(late); slow=""
while IFS= read -r ti <&3; do
  t0=$(python3 -c 'import time; print(int(time.time() * 1000))')
  out=$("$B" hook <<< "$ti")
  t1=$(python3 -c 'import time; print(int(time.time() * 1000))')
  { [ -z "$out" ] && [ $((t1 - t0)) -lt 3000 ]; } || slow="$slow $((t1 - t0))ms"
done 3< "$T/shapes"
[ -z "$slow" ] && [ "$(late)" = "$before" ] \
  && ok "20000 newlines, 8000 heredocs, 15000 exports, 40000 brace lists, 14285 bare boards, deep cd -P, pushd -- and cd: each allowed as main allows it, under 3 s, the helper done" \
  || die "a long shape: $slow / $(late) late lines"

# round 5: a writing part's globs expand, behind wrappers too; a cd glob with one match is followed; >| is a redirect
deny "$T/delta" 'ls | xargs -I {} cp {} ../al*/' && deny "$T/delta" 'env -u FOO touch ../al*/x' && deny "$T/delta" '(touch ../al*/x)' && deny "$T/delta" 'cd ../alp*a/ && touch x' && deny "$T/delta" 'echo x >| ../al*/VERSION' && runs "$T/delta" 'for d in ../*/; do git -C "$d" log -1 --oneline; done; sed -n 1p README.md' && ok "globs in a writing part, behind xargs, env or a subshell, a cd glob with one match and >| reach the hold; a read loop over every repo does not" || die "round-5 forms judged wrong"
# 4. a via that is not ~/.claude or under it is skipped: the hold's own path is enforced, HOME is not frozen, logged once
LOG="$SWITCHBOARD_STATE/errors.log"; NOW=$(date +%s)
i=0; for v in 'home:' 'home:.' 'home:..' 'home:.claude/../x'; do
  i=$((i+1)); mkdir -p "$HOME/keep$i"
  python3 - "$BD/holds/hv$i.json" "$i" "$v" "$((NOW + 3600))" <<'PY'
import json,sys; f,i,v,u=sys.argv[1:5]; json.dump({"id":"hv"+i,"path":"home:keep"+i,"via":v,"until":int(u),"reason":"bad via","shown":"all"},open(f,"w"))
PY
done
mkdir -p "$HOME/x"
for _ in 1 2; do out=$(hook PreToolUse "$T/delta" S1 Write "{\"file_path\":\"$HOME/free.txt\",\"content\":\"x\"}"); done
[ -z "$out" ] && wruns "$T/delta" "$HOME/x/f" && wruns "$T/delta" "$T/delta/y" \
  && wdeny "$T/delta" "$HOME/keep1/f" && wdeny "$T/delta" "$HOME/keep2/f" && wdeny "$T/delta" "$HOME/keep3/f" && wdeny "$T/delta" "$HOME/keep4/f" \
  && ok "holds whose via is home:, home:., home:.. or home:.claude/../x: each hold's own path is refused, HOME and its parent are not frozen" || die "bad via: $out"
bad=0; for i in 1 2 3 4; do [ "$(grep -c "via_paths via_paths:[0-9]* malformed holds/hv$i.json: via" "$LOG")" = 1 ] || bad=1; done
python3 -c 'import os,sys; s=os.stat(sys.argv[1]).st_mtime_ns+10**9; os.utime(sys.argv[1], ns=(s, s))' "$BD/holds/hv2.json"  # a new version
hook PreToolUse "$T/delta" S1 Write "{\"file_path\":\"$HOME/free.txt\",\"content\":\"x\"}" >/dev/null
[ $bad = 0 ] && [ "$(grep -c "malformed holds/hv2.json" "$LOG")" = 2 ] && [ "$(grep -c "malformed holds/hv1.json" "$LOG")" = 1 ] \
  && ok "each bad via is logged once per version of its hold file" || die "via log: $(grep hv "$LOG")"
rm "$BD"/holds/hv*.json

# a guard that raises behaves as before: no output, nothing on stderr, exit 0
out=$(pre PreToolUse "$T/delta" S1 tg1 Write '{"file_path": 5, "content": "g"}' 2>"$T/err"; echo "rc=$?")
[ "$out" = "rc=0" ] && [ ! -s "$T/err" ] && ok "a guard that raises: no output, nothing on stderr, exit 0" || die "guard failure: $out / $(cat "$T/err")"

finish
