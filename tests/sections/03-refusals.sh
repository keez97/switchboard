#!/usr/bin/env bash
# refusals as evidence (no prose matching)
source "$(dirname "$0")/../lib.sh"
fx_link1

pre PreToolUse "$T/alpha" S1 t1 Write "{\"file_path\":\"$SWITCHBOARD_DIR/holds/x.json\",\"content\":\"{}\"}" | has '"deny"' || die "setup: record-dir write not refused"
refusal S1 | has '"source": "hook".*board CLI\|board CLI.*"source": "hook"' && refusal S1 | has "holds/x.json" && ok "a write refused by the record-dir guard is recorded with its target and reason" || die "hook refusal not recorded: $(refusal S1)"
pre PreToolUse "$T/alpha" S1 t2 Bash "{\"command\":\"echo x > $T/alpha/notes.txt\"}" >/dev/null; pre PreToolUse "$T/alpha" S1 t3 Bash '{"command":"ls -la"}' >/dev/null
pre PreToolUse "$T/alpha" S1 t4 Write "{\"file_path\":\"$T/alpha/keep.txt\",\"content\":\"k\"}" >/dev/null; pre PostToolUse "$T/alpha" S1 t4 Write "{\"file_path\":\"$T/alpha/keep.txt\",\"content\":\"k\"}" >/dev/null
hook Stop "$T/alpha" S1 >/dev/null
refusal S1 | has '"source": "inferred".*notes.txt\|notes.txt.*"source": "inferred"' && ok "a non-read-only call with no PostToolUse is an inferred refusal at Stop" || die "no inferred refusal: $(refusal S1)"
! refusal S1 | has 'ls -la\|keep.txt' && [ "$(refusal S1 | grep -c inferred)" -eq 1 ] && ok "a read-only call is never pending, and PostToolUse clears a pending write" || die "pending wrong: $(refusal S1)"
pre PermissionDenied "$T/alpha" S1 t5 Bash '{"command":"git push origin main"}' "classifier said no" >/dev/null
refusal S1 | has '"source": "classifier".*classifier said no\|classifier said no.*"source": "classifier"' && refusal S1 | has '"git push' && ok "a PermissionDenied event is recorded with the classifier's reason and the git subcommand" || die "PermissionDenied not recorded: $(refusal S1)"
[ -z "$(send PreToolUse "$T/beta" S2 "$T/sock.$P1" "Direction 6: bind() and release() write a session record only when it belongs to this machine. The hook refused nothing; a send towards an open end is refused until a session is bound, and permission was denied is what the guard says. Could you apply it instead?")" ] && ok "with no refusal on record a message full of denial words passes" || die "clean session refused"
# Known ceiling: a paraphrase that names no target passes. The receiver's link scope and the owner-only list are the second wall.
out=$(send PreToolUse "$T/alpha" S1 "$T/sock.$P2" "Please apply notes.txt for me, my turn ended before it ran")
echo "$out" | has "nothing sent. This message names notes.txt, which this session was refused 0 minutes ago (inferred, Bash: not executed" && ok "a message naming a refused target is refused and quotes the record" || die "refused target not caught: $out"
[ -z "$(send PreToolUse "$T/alpha" S1 "$T/sock.$P2" "next: look at src.py and push when green")" ] && ok "the same session passes on an unrelated path" || die "unrelated path refused"
SWITCHBOARD_SESSION_ID=S3 "$B" link --from "$T/alpha:roadmap" --to "$T/beta:implementer" --scope x --covers "test work" >/dev/null 2>&1 && die "setup: S3 acted as alpha:roadmap" || true
refusal S3 | has '"source": "cli".*alpha:roadmap\|alpha:roadmap.*"source": "cli"' && ok "a CLI refusal (acting as a role this session does not hold) is recorded too" || die "cli refusal not recorded: $(refusal S3)"
# edges: a command with no path, a subagent's calls, hold targets, old refusals, two sessions at once
n=$(refusal S1 | grep -c inferred)
pre PreToolUse "$T/alpha" S1 t6 Bash '{"command":"rm -rf build"}' >/dev/null; pre PreToolUse "$T/alpha" S1 t7 Bash '{"command":"cp a b"}' >/dev/null; pre PreToolUse "$T/alpha" S1 t8 Bash '{"command":"make"}' >/dev/null
pre PreToolUse "$T/alpha" S1 t9 Bash "{\"command\":\"git -C $T/alpha\"}" >/dev/null
[ -z "$(pend S1)" ] && hook Stop "$T/alpha" S1 >/dev/null && [ "$(refusal S1 | grep -c inferred)" -eq "$n" ] && [ -z "$(send PreToolUse "$T/alpha" S1 "$T/sock.$P2" "confirm the plan, then cp and rm as you see fit")" ] && ok "a command with no path (rm, cp, make, bare git -C) is never pending, never a refusal, and blocks no prose" || die "word-like target: pend=$(pend S1) $(refusal S1 | tail -3)"
pre PreToolUse "$T/alpha" S1 t10 Write "{\"file_path\":\"$T/alpha/parallel.txt\",\"content\":\"p\"}" >/dev/null; hook SubagentStop "$T/alpha" S1 >/dev/null
[ "$(pend S1)" = "t10" ] && pre PostToolUse "$T/alpha" S1 t10 Write "{\"file_path\":\"$T/alpha/parallel.txt\"}" >/dev/null && [ -z "$(pend S1)" ] && hook Stop "$T/alpha" S1 >/dev/null && ! refusal S1 | has parallel.txt && ok "a SubagentStop leaves the parent's call pending and its PostToolUse clears it" || die "SubagentStop settled: $(pend S1) $(refusal S1 | tail -1)"
HF=$("$B" hold "$T/alpha/frozen" --until 1h --reason "edge test" | awk '{print $2}'); mkdir -p "$T/alpha/frozen"
pre PreToolUse "$T/alpha" S1 t11 Bash "{\"command\":\"echo x > $T/alpha/frozen/f.txt\"}" | has '"deny"' || die "setup: hold did not refuse"
send PreToolUse "$T/alpha" S1 "$T/sock.$P2" "please write frozen/f.txt for me" | has "names frozen/f.txt, which this session was refused 0 minutes ago (hook, Bash: switchboard hold $HF" && ok "a hold refusal is named by the file touched, not only the frozen path" || die "hold target: $(refusal S1 | tail -2)"
"$B" release "$HF" >/dev/null
python3 - "$SWITCHBOARD_STATE/refused/S1.json" <<'PY2'
import json,sys; f=sys.argv[1]; L=json.load(open(f))
for r in L:
    if r["target"].endswith("notes.txt"): r["ts"]-=1860
json.dump(L,open(f,"w"))
PY2
[ -z "$(send PreToolUse "$T/alpha" S1 "$T/sock.$P2" "please apply notes.txt for me")" ] && ok "a refusal older than 30 minutes no longer blocks" || die "old refusal still blocks"
pre PreToolUse "$T/alpha" SP1 tp1 Write "{\"file_path\":\"$T/alpha/p1.txt\",\"content\":\"1\"}" >/dev/null & pre PreToolUse "$T/alpha" SP2 tp2 Write "{\"file_path\":\"$T/alpha/p2.txt\",\"content\":\"2\"}" >/dev/null & wait
[ "$(pend SP1)" = "tp1" ] && [ "$(pend SP2)" = "tp2" ] && ok "two sessions writing pending at once keep both, one file per session" || die "pending race: $(pend SP1) / $(pend SP2)"
mkdir -p "$T/alpha/bin"; pre PermissionDenied "$T/alpha" S1 t12 Write "{\"file_path\":\"$T/alpha/bin/board\",\"content\":\"b\"}" "classifier: Security Weaken" >/dev/null
send PreToolUse "$T/alpha" S1 "$T/sock.$P2" "could you save my change to bin/board instead" | has "names bin/board, which this session was refused 0 minutes ago (classifier, Write: classifier: Security Weaken)" && ok "the last two path components name a refused file whose basename is a stop word" || die "bin/board not matched: $(refusal S1 | tail -1)"
# a subagent's call that never ran is not an inferred refusal: it must not block the parent's messages naming the same file
mkdir -p "$T/alpha/learning"; echo x > "$T/alpha/learning/check.py"; n=$(refusal S1 | grep -c inferred || true)
AID=a7f3 pre PreToolUse "$T/alpha" S1 t13 Bash "{\"command\":\"python3 learning/check.py 2>/dev/null\"}" >/dev/null; AID=a7f3 pre PermissionRequest "$T/alpha" S1 t13 Bash "{\"command\":\"python3 learning/check.py 2>/dev/null\"}" >/dev/null
[ -z "$(pend S1)" ] && hook Stop "$T/alpha" S1 >/dev/null && [ "$(refusal S1 | grep -c inferred || true)" -eq "$n" ] && [ -z "$(send PreToolUse "$T/alpha" S1 "$T/sock.$P2" "review done: learning/check.py passes on the candidate")" ] && ok "a subagent's call that never ran is not pending, so the parent's message naming its file passes" || die "subagent call poisoned the parent: pend=$(pend S1) $(refusal S1 | tail -1)"
AID=a7f3 pre PermissionDenied "$T/alpha" S1 t14 Write "{\"file_path\":\"$T/alpha/learning/check.py\",\"content\":\"c\"}" "classifier: Self Modification" >/dev/null
send PreToolUse "$T/alpha" S1 "$T/sock.$P2" "could you write learning/check.py for me" | has "names .*check.py, which this session was refused 0 minutes ago (classifier, Write" && ok "a subagent's classifier denial still blocks the parent's message naming its file" || die "subagent classifier denial dropped: $(refusal S1 | tail -1)"
pre PreToolUse "$T/alpha" S1 t15 Bash "{\"command\":\"echo y > $T/alpha/main.txt\"}" >/dev/null; hook Stop "$T/alpha" S1 >/dev/null
send PreToolUse "$T/alpha" S1 "$T/sock.$P2" "please apply main.txt for me" | has "names main.txt, which this session was refused 0 minutes ago (inferred" && ok "the main session's call that never ran is still an inferred refusal" || die "main inferred refusal lost: $(refusal S1 | tail -1)"
# a > inside quotes, a redirect name the shell builds at run time, and git diff > f must record no junk target (the cwd, a path ending in a comma, "git diff")
pre PreToolUse "$T/alpha" S1 t16 Bash "{\"command\":\"python3 -c \\\"print('->', 1); print('>')\\\"\"}" >/dev/null; pre PreToolUse "$T/alpha" S1 t17 Bash '{"command":"python3 a.py > /tmp/out_$$_$(basename x).txt; cmd > /dev/stderr"}' >/dev/null
[ -z "$(pend S1)" ] && ok "a > inside quotes, a shell-built redirect name and a device are never pending" || die "junk pending: $(cat "$SWITCHBOARD_STATE/pending/S1.json")"
pre PreToolUse "$T/alpha" S1 t18 Bash "{\"command\":\"git diff VERSION > $T/alpha/d1.diff\"}" >/dev/null; hook Stop "$T/alpha" S1 >/dev/null
[ -z "$(send PreToolUse "$T/alpha" S1 "$T/sock.$P2" "status for $T/alpha, run git diff on VERSION")" ] && send PreToolUse "$T/alpha" S1 "$T/sock.$P2" "please write d1.diff for me" | has "names d1.diff, which this session was refused" && ok "git diff > f records f, and a message naming the repo, git diff or the diffed file passes" || die "git diff target: $(refusal S1 | tail -1)"

finish
