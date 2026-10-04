#!/usr/bin/env bash
# the rename: bin/switchboard the program and no bin/board here, the CLI's name in its output, the notes a machine set
# up before the plugin gets (only ~/.claude/board) as main's, CLI_NAME, both names guarded, STATE/cli, the merge
# drivers and the pre-push hook through STATE/cli or ~/.claude/board and never a foreign switchboard, both signing
# namespaces, the first-run link, the words written into records and the SWITCHBOARD_ switches
source "$(dirname "$0")/../lib.sh"
cap_procs   # it runs pre-push hooks: one that ran itself would stop at the cap
# origin/main's copy runs beside this one below, and reads these switches only by their older names
export AGENT_BOARD_ALLOW_TMP=1 AGENT_BOARD_NOWALK=1
{ git -C "$TESTS/.." show origin/main:bin/switchboard || git -C "$TESTS/.." show origin/main:bin/board; } > "$T/board-main" 2>/dev/null \
  && chmod +x "$T/board-main" || die "setup: origin/main's CLI"
SB=$(realpath "$B"); M="$T/board-main"; BIN="$HOME/.local/bin/switchboard"
pj(){ python3 -c "import json,sys; d=json.load(sys.stdin); print(eval(sys.argv[1]))" "$1"; }   # a value of paths --json
on(){ # cli event cwd session [tool] [tool_input json]: a hook call, as lib.sh's hook, run by the given copy
  local cli=$1; shift
  python3 - "$@" <<'PY' | "$cli" hook
import json,sys
e,cwd,sid=sys.argv[1:4]; d={"hook_event_name":e,"cwd":cwd,"session_id":sid}
if len(sys.argv)>5: d["tool_name"]=sys.argv[4]; d["tool_input"]=json.loads(sys.argv[5])
if e=="UserPromptSubmit": d["prompt"]=sys.argv[4]
if e=="SessionStart": d["source"]="startup"
print(json.dumps(d))
PY
}
cli_link(){ rm -f "$HOME/.claude/board"; ln -s "$1" "$HOME/.claude/board"; }   # ~/.claude/board, as the live machines have it

# ---- 1. the file: bin/switchboard is the program; the code repo has no bin/board, and ~/.claude/board ->
# bin/switchboard runs
[ ! -L "$TESTS/../bin/switchboard" ] && [ ! -e "$TESTS/../bin/board" ] && [ ! -L "$TESTS/../bin/board" ] \
  && [ "$SB" = "$(cd "$TESTS/../bin" && pwd -P)/switchboard" ] && ok "bin/switchboard is the program, and there is no bin/board" || die "bin: $(ls -la "$TESTS/../bin")"
cli_link "$B"
[ "$("$HOME/.claude/board" paths --json | pj 'd["cli"]')" = "$SB" ] && "$HOME/.claude/board" status | has "^board $SWITCHBOARD_DIR " \
  && ok "through ~/.claude/board the CLI runs and paths names its real file" || die "chain: $("$HOME/.claude/board" paths 2>&1)"

# ---- 2. names in output: argparse and the message prefix say switchboard; hints name the CLI as CLI_NAME
u=$("$B" 2>&1) || true; t=$("$B" task t00000000 2>&1) || true; l=$("$B" link accept 2>&1) || true
echo "$u" | has "^usage: switchboard " && [ "$t" = "switchboard: no task t00000000" ] && [ "$l" = "switchboard: ~/.claude/board link accept <id>" ] \
  && ok "usage and messages say switchboard; a hint names the CLI ~/.claude/board while there is no first-run link" || die "names: $u | $t | $l"

# ---- the notes a machine set up before the plugin gets: only ~/.claude/board, and at ~/.local/bin/switchboard a file
# of another program, which no session start replaces. Main's copy and this one read one board; each its own state
# dir, so each is told everything once. The differences are meant: a hint main wrote as `board <cmd>` names the CLI as
# every other note does, `~/.claude/board <cmd>`, and the note prefix agent-board is switchboard
fx_repos alpha beta; mkdir -p "$T/beta/src" "$HOME/.local/bin"; echo other > "$BIN"
seat S1 "$T/alpha" road; seat S2 "$T/beta" impl
for s in "S1 alpha" "S2 beta"; do set -- $s; hook SessionStart "$T/$2" $1 >/dev/null; done
SWITCHBOARD_SESSION_ID=S1 "$B" role lead >/dev/null; SWITCHBOARD_SESSION_ID=S2 "$B" role worker >/dev/null
SWITCHBOARD_NOW=$(date +%s); export SWITCHBOARD_NOW AGENT_BOARD_NOW=$SWITCHBOARD_NOW
TQ=$(SWITCHBOARD_SESSION_ID=S1 "$B" task request --to "$T/beta:worker" --subject "eq task" --key eq1 --no-sign 2>/dev/null | awk '{print $1}')
"$B" hold "$T/beta/src" --until 2d --reason "eq hold" >/dev/null
LP=$(SWITCHBOARD_SESSION_ID=S1 SWITCHBOARD_TEST_PROPOSE=1 "$B" link --from "$T/alpha:lead" --to "$T/beta:worker" --scope "eq scope" --covers "eq scope" 2>/dev/null | awk 'NR==1{print $2}')
[ -n "$TQ" ] && [ -n "$LP" ] || die "setup: task and proposal for the notes"
notes(){ # cli tag: what S2 in beta is told by that copy: its session start, a hold refusal, a link-guard refusal, an
  # unlinked peer's message
  cli_link "$1"; export SWITCHBOARD_STATE="$T/state-$2"
  { on "$1" SessionStart "$T/beta" S2; echo; on "$1" PreToolUse "$T/beta" S2 Write "{\"file_path\":\"$T/beta/src/x.py\",\"content\":\"x\"}"; echo
    on "$1" PreToolUse "$T/beta" S2 Bash '{"command":"~/.claude/board link --from a:b --to c:d --scope x --until 7d"}'; echo
    on "$1" UserPromptSubmit "$T/beta" S2 "$(peer /x/sock other "hello")"; } > "$T/notes-$2"
  export SWITCHBOARD_STATE="$T/state"; }
notes "$M" main; notes "$B" branch
python3 - "$T/notes-main" "$T/notes-branch" "$TQ" "$LP" <<'PY' && ok "on a live machine's setup the notes are main's: session start (task, proposal, hold), hold and link refusals, a peer's message; every CLI path is ~/.claude/board, each note begins switchboard" || die "notes differ from main's: $(diff "$T/notes-main" "$T/notes-branch" | head -20)"
import json, re, sys
m, b, tq, lp = open(sys.argv[1]).read(), open(sys.argv[2]).read(), sys.argv[3], sys.argv[4]
cov = " It covers tasks whose subject starts with: eq scope."  # 0.7.0's proposal note names the covers list; main's has none
b = b.replace(cov, "") if b.count(cov) == 1 else "no covers sentence"
acc = "Accept only if the scope and the covers list fit"  # and asks the acceptor to check both
b = b.replace(acc, "Accept only if the scope fits") if b.count(acc) == 1 else "no covers check"
as_branch = lambda t: re.sub(r"agent-board(?=: | hold | skill )", "switchboard", t)  # main's prefix as this copy's
unprefixed = lambda t: re.sub(r"switchboard(?=: | hold | skill )", "", t)
texts = [json.loads(x) for x in b.split("\n") if x.strip()]
say = [t.get("hookSpecificOutput", {}).get("additionalContext") or t["hookSpecificOutput"].get("permissionDecisionReason", "")
       for t in texts]
need = ["Read it now: ~/.claude/board task %s   Then: ~/.claude/board task seen %s" % (tq, tq),
        "Accept: ~/.claude/board link accept %s   Decline: ~/.claude/board link decline %s" % (lp, lp), "is frozen until",
        "propose a link with `~/.claude/board link`", "From a session: `~/.claude/board link ...`"]
sys.exit(not (as_branch(m.replace("`board ", "`~/.claude/board ")) == b and len(say) == 4 and all(say)
              and all(s.startswith("switchboard") for s in say) and "switchboard" not in unprefixed(b)
              and all(n in b for n in need)))
PY
unset SWITCHBOARD_NOW AGENT_BOARD_NOW; rm "$BIN"

# ---- CLI_NAME: switchboard where ~/.local/bin/switchboard links to this CLI, ~/.claude/board otherwise
mkdir -p "$HOME/.local/bin"; ln -s "$SB" "$BIN"
TQ2=$(SWITCHBOARD_SESSION_ID=S1 "$B" task request --to "$T/beta:worker" --subject "named" --key eq2 --no-sign 2>/dev/null | awk '{print $1}')
out=$(hook PostToolUse "$T/beta" S2 Read '{}' | ctx)
echo "$out" | has -xF "Read it now: switchboard task $TQ2   Then: switchboard task seen $TQ2" && echo "$out" | has -F "decline with \`switchboard task rejected $TQ2\`" \
  && [ "$("$B" paths --json | pj '"%s %s %s" % (d["cli_name"], d["bin_link"]["ours"], d["bin_link"]["target"])')" = "switchboard True $SB" ] \
  && "$B" paths | has -x "bin_link  $BIN -> $SB (this CLI)" \
  && ok "with ~/.local/bin/switchboard linking to this CLI, notes name it switchboard and paths shows the link as this CLI's" || die "CLI_NAME switchboard: $out"
rm "$BIN"; ln -s "$M" "$BIN"
# shellcheck disable=SC2088  # the expected text shows ~ as the CLI prints it
[ "$("$B" paths --json | pj 'd["cli_name"] + " " + str(d["bin_link"]["ours"])')" = "~/.claude/board False" ] \
  && "$B" paths | has -x "bin_link  $BIN -> $M (not this CLI's: left as it is)" \
  && ok "a ~/.local/bin/switchboard that is another file's link leaves CLI_NAME at ~/.claude/board" || die "CLI_NAME other: $("$B" paths)"
rm "$BIN"

# ---- 3. both names guarded (the corpus's twins check every board probe; these are the forms named in the plan)
deny(){ on "$B" PreToolUse "$1" S1 Bash "$(python3 -c 'import json,sys; print(json.dumps({"command": sys.argv[1]}))' "$2")" | has '"deny"'; }
runs(){ [ -z "$(on "$B" PreToolUse "$1" S1 Bash "$(python3 -c 'import json,sys; print(json.dumps({"command": sys.argv[1]}))' "$2")")" ]; }
BD="$SWITCHBOARD_DIR"; mkdir -p "$BD/bin"; ln -s "$SB" "$BD/bin/switchboard"
for c in switchboard "$BIN" '$HOME/.local/bin/switchboard' "$BD/bin/switchboard" "python3 $BD/bin/switchboard"; do
  deny "$T/alpha" "$c link --from a:b --to c:d --scope x --until 7d" && deny "$T/alpha" "setsid $c link accept $LP" \
    && deny "$T/alpha" "SWITCHBOARD_SESSIONS_DIR=/tmp/x $c link accept $LP" && runs "$T/alpha" "$c link accept $LP" \
    || die "link guard on $c"
done && ok "the link guard refuses switchboard link commands by every name and path, and lets the plain ones run"
(cd "$BD" && deny "$BD" "switchboard status > links/x.json") && runs "$BD" "switchboard links" && runs "$BD" "bin/switchboard links" \
  && runs "$BD" "python3 bin/switchboard tasks" && deny "$BD" "switchboard() { cat; }; switchboard links/x.json" \
  && deny "$BD" "$T/elsewhere/switchboard links/x.json" \
  && ok "the record guard takes switchboard for the CLI, as board, and a function or another script of that name for a write" || die "record guard"
rm "$BD/bin/switchboard"

# ---- STATE/cli: the CLI's own link in its state dir, made or turned to this CLI at a session start; a file of
# another kind there is left as it is, and nothing runs it. A foreign program at ~/.local/bin/switchboard never runs
foreign(){ mkdir -p "$1/.local/bin"; printf '#!/bin/sh\necho "$0" >> "%s/foreign-ran"\nexit 0\n' "$T" > "$1/.local/bin/switchboard"; chmod +x "$1/.local/bin/switchboard"; }
SQ="$T/st a'b \"c"   # a state dir with a space and both quotes
[ "$(readlink "$SWITCHBOARD_STATE/cli")" = "$SB" ] && "$B" paths --json | pj 'd["state_cli"]["ours"]' | has -x True \
  && "$B" paths | has -x "state_cli $SWITCHBOARD_STATE/cli -> $SB (this CLI)" \
  && ok "a session start links STATE/cli to this CLI, and paths shows it" || die "state cli: $(ls -la "$SWITCHBOARD_STATE/cli" 2>&1)"
# only the CLI the hooks run takes the link: one under CLAUDE_PLUGIN_ROOT, or the one ~/.claude/board leads to. A
# worktree's copy fed a session start by hand with this HOME (~/.claude/board to this CLI) leaves it, with no
# CLAUDE_PLUGIN_ROOT or with another plugin's, which the copy is not under
mkdir -p "$T/wt/bin" "$T/ab-plugin"; cp "$SB" "$T/wt/bin/switchboard"; WT=$(realpath "$T/wt/bin/switchboard")
on "$WT" SessionStart "$T/alpha" S1 >/dev/null; a=$(readlink "$SWITCHBOARD_STATE/cli")
CLAUDE_PLUGIN_ROOT="$T/ab-plugin" on "$WT" SessionStart "$T/alpha" S1 >/dev/null; b=$(readlink "$SWITCHBOARD_STATE/cli")
CLAUDE_PLUGIN_ROOT="$T/ab-plugin" on "$B" SessionStart "$T/alpha" S1 >/dev/null; c=$(readlink "$SWITCHBOARD_STATE/cli")
[ "$a" = "$SB" ] && [ "$b" = "$SB" ] && [ "$c" = "$SB" ] \
  && ok "a worktree's copy run as a session start by hand leaves STATE/cli on the CLI ~/.claude/board runs" || die "bound: $a $b $c"
mkdir -p "$T/moved"; cp "$SB" "$T/moved/switchboard"; MV=$(realpath "$T/moved/switchboard")
CLAUDE_PLUGIN_ROOT="$T/moved" on "$MV" SessionStart "$T/alpha" S1 >/dev/null; a=$(readlink "$SWITCHBOARD_STATE/cli")
on "$B" SessionStart "$T/alpha" S1 >/dev/null; b=$(readlink "$SWITCHBOARD_STATE/cli")
[ "$a" = "$MV" ] && [ "$b" = "$SB" ] && ok "a copy under CLAUDE_PLUGIN_ROOT (the plugin's hooks) takes STATE/cli; the next session start through ~/.claude/board turns it back" || die "refresh: $a $b"
PF="$T/st-plain"; mkdir -p "$PF"; echo mine > "$PF/cli"
SWITCHBOARD_STATE="$PF" on "$B" SessionStart "$T/alpha" S1 >/dev/null
[ ! -L "$PF/cli" ] && [ "$(cat "$PF/cli")" = mine ] && grep -q "malformed $(basename "$PF")/cli: not a link; left as it is" "$PF/errors.log" \
  && SWITCHBOARD_STATE="$PF" "$B" paths | has -x "state_cli $PF/cli: not a link, left as it is and not run" \
  && ok "a file at STATE/cli that is not a link is left as it is, logged, and paths says it is not run" || die "plain cli: $(cat "$PF/errors.log" 2>&1)"

# ---- 5. the merge driver: STATE/cli while it is a link, else ~/.claude/board, else git's own merge, in a real rebase;
# never ~/.local/bin/switchboard
drv(){ SWITCHBOARD_STATE="$1" python3 - "$B" <<'PY'
import importlib.machinery, importlib.util, sys
loader = importlib.machinery.SourceFileLoader("b", sys.argv[1])
m = importlib.util.module_from_spec(importlib.util.spec_from_loader("b", loader)); sys.argv = [sys.argv[1]]; loader.exec_module(m)
print(m.driver_cmd("merge-link", "%O", "%A", "%B"))
PY
}
gc(){ git -C "$1" -c user.email=t@t -c user.name=t "${@:2}"; }
rebase(){ # case home state: a clone where main took the cap of link l1 to 4 and a side branch to 3, the side rebased
  # onto main with the driver as it is written for that state dir
  local R="$T/rb-$1"; mkdir -p "$R/links"; git -C "$R" init -q -b main; binit "$R"
  echo '{"id":"l1","cap":5}' > "$R/links/l1.json"; git -C "$R" config merge.board-link.driver "$(drv "$3")"
  gc "$R" add -A; gc "$R" commit -qm base; gc "$R" checkout -qb side; echo '{"id":"l1","cap":3}' > "$R/links/l1.json"; gc "$R" commit -qam side
  gc "$R" checkout -q main; echo '{"id":"l1","cap":4}' > "$R/links/l1.json"; gc "$R" commit -qam main; gc "$R" checkout -q side
  HOME="$2" gc "$R" rebase main >/dev/null 2>&1; echo "$? $(jq -c .cap "$R/links/l1.json" 2>/dev/null || echo conflict)"; }
for h in claude statecli neither plain quoted; do mkdir -p "$T/h-$h/.claude" "$T/st-$h"; foreign "$T/h-$h"; done
ln -s "$B" "$T/h-claude/.claude/board"; ln -s "$B" "$T/h-plain/.claude/board"
HOME="$T/h-statecli" SWITCHBOARD_STATE="$T/st-statecli" CLAUDE_PLUGIN_ROOT="$(dirname "$(dirname "$SB")")" on "$B" SessionStart "$T/alpha" S1 >/dev/null
printf '#!/bin/sh\necho ran >> "%s/plain-ran"\nexit 0\n' "$T" > "$T/st-plain/cli"; chmod +x "$T/st-plain/cli"
mkdir -p "$SQ"; printf '#!/bin/sh\necho ran >> "%s/quoted-ran"\nexec "%s" "$@"\n' "$T" "$B" > "$T/quoted-stub"; chmod +x "$T/quoted-stub"
ln -s "$T/quoted-stub" "$SQ/cli"; rm -f "$T/foreign-ran"
r1=$(rebase claude "$T/h-claude" "$T/st-claude"); r2=$(rebase statecli "$T/h-statecli" "$T/st-statecli")
r3=$(rebase neither "$T/h-neither" "$T/st-neither"); r4=$(rebase plain "$T/h-plain" "$T/st-plain"); r5=$(rebase quoted "$T/h-quoted" "$SQ")
[ "$r1 | $r2 | $r3 | $r4 | $r5" = "0 3 | 0 3 | 1 conflict | 0 3 | 0 3" ] && grep -q "<<<<<<<" "$T/rb-neither/links/l1.json" \
  && [ ! -e "$T/foreign-ran" ] && [ ! -e "$T/plain-ran" ] && [ -s "$T/quoted-ran" ] && drv "$SQ" | has -F "switchboard '$T/st a'\"'\"'b \"c/cli' %O %A %B" \
  && ok "the driver merges through ~/.claude/board alone, through STATE/cli, from a state dir with a space and quotes, falls to git's conflict with neither, and never runs ~/.local/bin/switchboard or a STATE/cli that is not a link" \
  || die "driver: $r1 | $r2 | $r3 | $r4 | $r5; foreign $(cat "$T/foreign-ran" 2>&1); plain $(cat "$T/plain-ran" 2>&1)"
HOME="$T/h-neither" drv "$T/st-neither" | has -v ".claude/board" && drv "$T/st-neither" | has -F '"$HOME/.claude/board"' \
  && ok "the driver names ~/.claude/board only where it is there when the drivers are set" || die "driver text: $(HOME="$T/h-neither" drv "$T/st-neither")"

# ---- 6. pre-push: install-prepush chains the hook there; the new hook runs STATE/cli or ~/.claude/board, never
# ~/.local/bin/switchboard
mkrepo "$T/pp"; git init -q --bare -b main "$T/pp.git"; git -C "$T/pp" remote add origin "$T/pp.git"; mkdir -p "$T/pp/src"
echo a > "$T/pp/src/a.py"; gc "$T/pp" add -A; gc "$T/pp" commit -qm base; git -C "$T/pp" push -q -u origin main 2>/dev/null
"$B" register "$T/pp" >/dev/null; H="$T/pp/.git/hooks"
printf '#!/bin/sh\ncat > "%s/theirs-ran"\n' "$T" > "$H/pre-push"; chmod +x "$H/pre-push"; cp "$H/pre-push" "$T/their-hook"
cli_link "$B"; HP=$("$B" hold "$T/pp/src" --until 1h --reason "pp" | awk '{print $2}')
echo b >> "$T/pp/src/a.py"; gc "$T/pp" commit -qam held
"$B" install-prepush "$T/pp" | has -x "installed the switchboard pre-push hook in $H; the hook that was there runs after it as pre-push.agent-board-chained" \
  && grep -q "^# switchboard pre-push " "$H/pre-push" && cmp -s "$H/pre-push.agent-board-chained" "$T/their-hook" \
  && "$B" install-prepush "$T/pp" | has -x "already installed in $H" && ! grep -q "local/bin" "$H/pre-push" \
  && ok "install-prepush puts its hook in front of the one there, chained under the name installed hooks call; a second run changes nothing" || die "install: $(cat "$H/pre-push")"
foreign "$HOME"; rm -f "$T/foreign-ran"
push(){ out=$(git -C "$T/pp" push origin main 2>&1) && die "$1: a held push went through" || true; echo "$out" | has "switchboard hold $HP:" || die "$1: $out"; }
push "STATE/cli and ~/.claude/board"; rm "$SWITCHBOARD_STATE/cli"; push "only ~/.claude/board"
[ ! -e "$T/foreign-ran" ] && ok "the new hook refuses through STATE/cli, and through ~/.claude/board alone, and never runs the program at ~/.local/bin/switchboard" || die "foreign ran: $(cat "$T/foreign-ran")"
rm "$HOME/.claude/board"; printf '#!/bin/sh\necho ran >> "%s/plain-ran"\nexit 0\n' "$T" > "$SWITCHBOARD_STATE/cli"; chmod +x "$SWITCHBOARD_STATE/cli"
out=$(git -C "$T/pp" push origin main 2>&1) && echo "$out" | has "switchboard: no CLI link in the state dir and no ~/.claude/board; the push was not checked against holds" \
  && [ -s "$T/theirs-ran" ] && [ ! -e "$T/foreign-ran" ] && [ ! -e "$T/plain-ran" ] \
  && ok "with neither the push goes through unchecked, says so, the chained hook still runs, and a STATE/cli that is not a link is not run" || die "no CLI: $out"
echo d >> "$T/pp/src/a.py"; gc "$T/pp" commit -qam held3
"$B" install-prepush "$T/pp" | has -x "updated the switchboard pre-push hook in $H; pre-push.agent-board-chained still runs after it" && ! grep -q "claude/board" "$H/pre-push" \
  && out=$(git -C "$T/pp" push origin main 2>&1) && echo "$out" | has -x "switchboard: no CLI link in the state dir; the push was not checked against holds" \
  && ok "with no ~/.claude/board, install-prepush writes a hook that does not name it, and its message does not either" || die "hook without the old link: $out"
rm "$SWITCHBOARD_STATE/cli" "$BIN"; echo c >> "$T/pp/src/a.py"; gc "$T/pp" commit -qam held2; rm -f "$T/quoted-ran"
SWITCHBOARD_STATE="$SQ" "$B" install-prepush "$T/pp" | has -x "updated the switchboard pre-push hook in $H; pre-push.agent-board-chained still runs after it" || die "update for another state dir"
push "a state dir with a space and quotes"; [ -s "$T/quoted-ran" ] && ok "a hook written for a state dir with a space and quotes runs that dir's cli link" || die "quoted hook: $(grep -n cli "$H/pre-push")"
"$B" release "$HP" >/dev/null; cli_link "$B"
"$B" install-prepush "$T/pp" --remove | has "the earlier hook is back" && cmp -s "$H/pre-push" "$T/their-hook" && ok "--remove restores the chained hook" || die "remove"

# ---- 6b. hooks installed before the rename (agent-board's text: the mark # agent-board pre-push, ~/.claude/board, then
# the chained hook by name). The old hook still refuses; install-prepush replaces it in place, with a chained hook or
# none, and --remove takes it out. Chained under its own name, that text would run itself until fork fails, so no
# chained hook ever runs itself: every push here runs under cap_procs and a timeout
oldhook(){ python3 - "$H/pre-push" "$HOME/.claude/board" <<'PY'
import os, sys
open(sys.argv[1], "w").write("""#!/bin/sh
# agent-board pre-push (installed by `board install-prepush`): refuses a push whose commits touch a path
# held on the agent board. A pre-push hook that was here before runs after the check, as pre-push.agent-board-chained,
# with the same arguments and input. `board install-prepush --remove` puts it back.
input=$(cat)
board=%s
if [ -x "$board" ]; then
  printf '%%s\\n' "$input" | "$board" prepush "$@" || exit 1
else
  echo "agent-board: $board is missing; the push was not checked against holds" >&2
fi
chained="$(dirname "$0")/pre-push.agent-board-chained"
if [ -x "$chained" ]; then
  printf '%%s\\n' "$input" | "$chained" "$@" || exit $?
fi
exit 0
""" % sys.argv[2])
os.chmod(sys.argv[1], 0o755)
PY
}
tpush(){ timeout 60 git -C "$T/pp" push origin main 2>&1; }
CH="$H/pre-push.agent-board-chained"
HQ=$("$B" hold "$T/pp/src" --until 1h --reason "pp2" | awk '{print $2}'); echo e >> "$T/pp/src/a.py"; gc "$T/pp" commit -qam held4
mv "$H/pre-push" "$CH"; oldhook   # the old hook in front of theirs, as the CLI left it before the rename
out=$(tpush) && die "the old hook let a held push through" || true
echo "$out" | has "switchboard hold $HQ: .*src is frozen" && ok "an old hook (# agent-board pre-push, ~/.claude/board) still refuses with this CLI behind the link" || die "old hook: $out"
"$B" install-prepush "$T/pp" | has -x "replaced the pre-push hook installed before the rename in $H; pre-push.agent-board-chained still runs after it" \
  && grep -q "^# switchboard pre-push " "$H/pre-push" && ! grep -q "# agent-board pre-push" "$H/pre-push" && cmp -s "$CH" "$T/their-hook" \
  && "$B" install-prepush "$T/pp" | has -x "already installed in $H" \
  && ok "install-prepush takes the old mark as its own and replaces that hook in place, the chained one kept; a second run changes nothing" || die "replace: $(cat "$H/pre-push")"
rm "$H/pre-push" "$CH"; oldhook
"$B" install-prepush "$T/pp" | has -x "replaced the pre-push hook installed before the rename in $H" && [ ! -e "$CH" ] || die "old hook alone: $(ls "$H")"
s0=$(date +%s); out=$(tpush) && die "old hook alone: a held push went through" || true
[ "$(echo "$out" | grep -c "switchboard hold $HQ:")" = 1 ] && [ $(( $(date +%s) - s0 )) -lt 30 ] && ! echo "$out" | has -i "fork\|resource" \
  && ok "an old hook with no chained hook is replaced in place, never chained under its own name: the push is refused once and ends" || die "old hook alone: $out"
rm "$H/pre-push"; cp "$T/their-hook" "$CH"; oldhook
"$B" install-prepush "$T/pp" --remove | has "the earlier hook is back" && cmp -s "$H/pre-push" "$T/their-hook" \
  && ok "--remove also takes an old-mark hook out and restores the one it chained" || die "remove old"
# a chained hook that is the hook itself, by a link or as a copy of its text, is skipped with a warning
"$B" release "$HQ" >/dev/null; "$B" install-prepush "$T/pp" >/dev/null; rm "$CH"; ln -s pre-push "$CH"
echo f >> "$T/pp/src/a.py"; gc "$T/pp" commit -qam self1
out=$(tpush) && [ "$(echo "$out" | grep -c "pre-push.agent-board-chained is this hook itself; not run again")" = 1 ] \
  && ok "a chained hook that is a link to the hook itself is skipped with a warning, and the push goes through" || die "self link: $out"
rm "$CH"; cp "$H/pre-push" "$CH"; echo g >> "$T/pp/src/a.py"; gc "$T/pp" commit -qam self2
out=$(tpush) && [ "$(echo "$out" | grep -c "pre-push.agent-board-chained runs pre-push.agent-board-chained itself; not run")" = 1 ] \
  && ok "a copy of the hook as the chained hook is not run, with one warning, and the push goes through" || die "self copy: $out"
# a copy of a hook 0.3.1 wrote as the chained hook: that text has no guard of its own and would run itself
python3 - "$CH" "$SWITCHBOARD_STATE/cli" "$HOME/.claude/board" <<'PY'
import os, shlex, sys
open(sys.argv[1], "w").write("""#!/bin/sh
# switchboard pre-push (installed by `switchboard install-prepush`): refuses a push whose commits touch a path
# held on the agent board. A pre-push hook that was here before runs after the check, as pre-push.agent-board-chained,
# with the same arguments and input. `switchboard install-prepush --remove` puts it back.
input=$(cat)
board=
if [ -L %(cli)s ] && [ -x %(cli)s ]; then
  board=%(cli)s
elif [ -x %(old)s ]; then
  board=%(old)s
fi
if [ -n "$board" ]; then
  printf '%%s\\n' "$input" | "$board" prepush "$@" || exit 1
else
  echo "switchboard: no CLI link in the state dir and no ~/.claude/board; the push was not checked against holds" >&2
fi
chained="$(dirname "$0")/pre-push.agent-board-chained"
if [ -x "$chained" ]; then
  printf '%%s\\n' "$input" | "$chained" "$@" || exit $?
fi
exit 0
""" % {"cli": shlex.quote(sys.argv[2]), "old": shlex.quote(sys.argv[3])})
os.chmod(sys.argv[1], 0o755)
PY
echo h >> "$T/pp/src/a.py"; gc "$T/pp" commit -qam self3
out=$(tpush) && [ "$(echo "$out" | grep -c "runs pre-push.agent-board-chained itself; not run")" = 1 ] && ! echo "$out" | has -i "fork\|resource" \
  && ok "a copy of a hook 0.3.1 wrote, as the chained hook, is not run, with one warning, and the push goes through" || die "0.3.1 copy: $out"
# a chained hook that runs pre-push again: the depth guard stops the fourth nested run, once, checking nothing more
printf '#!/bin/sh\nexec "$(dirname "$0")/pre-push" "$@"\n' > "$CH"; chmod +x "$CH"; echo i >> "$T/pp/src/a.py"; gc "$T/pp" commit -qam loop1
out=$(tpush) && [ "$(echo "$out" | grep -c "pre-push hooks ran each other more than 3 deep; this run stops")" = 1 ] && ! echo "$out" | has -i "fork\|resource" \
  && ok "a chained hook that runs pre-push again stops at the fourth nested run with one warning, and the push goes through" || die "loop: $out"
HL=$("$B" hold "$T/pp/src" --until 1h --reason "loop hold" | awk '{print $2}'); echo j >> "$T/pp/src/a.py"; gc "$T/pp" commit -qam loop2
out=$(tpush) && die "loop with a hold: the push went through" || true
[ "$(echo "$out" | grep -c "switchboard hold $HL:")" = 1 ] && ! echo "$out" | has "more than 3 deep" \
  && ok "with a hold the first run refuses as before, and nothing nested runs" || die "loop with a hold: $out"
"$B" release "$HL" >/dev/null
rm "$H/pre-push" "$CH"; printf '#!/bin/sh\nexec "$(dirname "$0")/pre-push.agent-board-chained" "$@"\n' > "$H/pre-push"; chmod +x "$H/pre-push"
if out=$("$B" install-prepush "$T/pp" 2>&1); then die "a hook that runs the chained name was chained"; else
  echo "$out" | has "runs pre-push.agent-board-chained itself, so chained under that name it would run itself" && [ ! -e "$CH" ] \
    && ok "a hook whose text runs the chained hook's name is never chained under it" || die "self-naming hook: $out"; fi
rm "$H/pre-push"; cp "$T/their-hook" "$H/pre-push"


# ---- 7. signing: in switchboard-task; either namespace verifies; main's and this copy's signatures read alike
mkdir -p "$HOME/.ssh" "$SWITCHBOARD_DIR/keys"; ssh-keygen -q -t ed25519 -N "" -f "$HOME/.ssh/agent-board_east" -C selftest
echo "east namespaces=\"agent-board-task,switchboard-task\" $(cat "$HOME/.ssh/agent-board_east.pub")" > "$SWITCHBOARD_DIR/keys/allowed_signers"
sreq(){ SWITCHBOARD_SESSION_ID=S1 AGENT_BOARD_SESSION_ID=S1 "$1" task request --to "$T/beta:worker" --subject "sig $2" --key "sig$2" "${@:3}" 2>/dev/null | awk '{print $1}'; }
tdir(){ echo "$SWITCHBOARD_DIR/tasks/beta--worker/$1"; }
K1=$(sreq "$B" 1); K2=$(sreq "$M" 2)
ssh-keygen -Y verify -f "$SWITCHBOARD_DIR/keys/allowed_signers" -I east -n switchboard-task -s "$(tdir "$K1")/000-request.sig" < "$(tdir "$K1")/000-request.json" >/dev/null 2>&1 \
  && "$M" task "$K1" | has -x "  signed by east" && "$B" task "$K2" | has -x "  signed by east" \
  && ok "with a line listing both, this copy signs in switchboard-task: main verifies its request, and it verifies main's" || die "cross: $("$M" task "$K1" | tail -3)"
sign(){ K=$(sreq "$B" "$1" --no-sign); ssh-keygen -Y sign -f "$HOME/.ssh/agent-board_east" -n "$2" < "$(tdir "$K")/000-request.json" > "$(tdir "$K")/000-request.sig" 2>/dev/null; echo "$K"; }
K3=$(sign 3 switchboard-task); K4=$(sign 4 other-task)
"$B" task "$K3" | has -x "  signed by east" && "$B" task "$K4" | has -x "  BAD SIGNATURE" \
  && ok "a switchboard-task signature verifies; another namespace is bad" || die "namespaces"
K5=$(sreq "$B" 5); before=$(cat "$SWITCHBOARD_STATE/sigs.json"); "$M" task "$K5" >/dev/null; mid=$(cat "$SWITCHBOARD_STATE/sigs.json")
"$B" task "$K5" | has -x "  signed by east" && [ "$before" != "$mid" ] && [ "$(cat "$SWITCHBOARD_STATE/sigs.json")" = "$mid" ] \
  && ok "a status main's code cached is read from the cache as it is, not verified again" || die "cache"
ssh-keygen -q -t ed25519 -N "" -f "$HOME/.ssh/switchboard_east" -C selftest2
echo "east namespaces=\"switchboard-task\" $(cat "$HOME/.ssh/switchboard_east.pub")" > "$SWITCHBOARD_DIR/keys/allowed_signers"
K6=$(sreq "$B" 6)
# shellcheck disable=SC2088  # the message names ~/.ssh as written
"$B" task "$K6" | has -x "  signed by east" && "$B" task "$K1" | has -x "  BAD SIGNATURE" \
  && ok "~/.ssh/switchboard_east signs once it is there, in place of ~/.ssh/agent-board_east, the name before the rename" || die "key file: $("$B" task "$K6" | tail -3)"
rm "$HOME/.ssh/switchboard_east" "$HOME/.ssh/switchboard_east.pub"

# ---- 8. the first-run link: never over a file or link that is there
first(){ mkdir -p "$1/.claude/sessions"; HOME="$1" hook SessionStart "$T/alpha" FR >/dev/null; }
NU="$T/newuser"; first "$NU"
[ "$(readlink "$NU/.local/bin/switchboard")" = "$SB" ] && [ "$(HOME="$NU" "$B" paths --json | pj 'd["cli_name"]')" = switchboard ] \
  && first "$NU" && [ "$(readlink "$NU/.local/bin/switchboard")" = "$SB" ] \
  && ok "a new user's first session start links ~/.local/bin/switchboard to this CLI, and CLI_NAME is switchboard" || die "new user: $(ls -la "$NU/.local/bin" 2>&1)"
CH="$T/confhome"; mkdir -p "$CH/.config/switchboard"; echo '{"owner": "Ann", "board_dir": "~/b"}' > "$CH/.config/switchboard/config.json"
first "$CH"; [ "$(readlink "$CH/.local/bin/switchboard")" = "$SB" ] && ok "a machine with a config file gets the link too" || die "config home"
for k in file link dangling; do F="$T/foreign-$k"; mkdir -p "$F/.local/bin"
  case $k in file) echo mine > "$F/.local/bin/switchboard";; link) ln -s /bin/true "$F/.local/bin/switchboard";; dangling) ln -s "$T/nothing" "$F/.local/bin/switchboard";; esac
  before=$(ls -l "$F/.local/bin/switchboard" | awk '{print $1, $NF}'); first "$F"
  [ "$(ls -l "$F/.local/bin/switchboard" | awk '{print $1, $NF}')" = "$before" ] || die "first-run link replaced a $k"
done && [ "$(cat "$T/foreign-file/.local/bin/switchboard")" = mine ] && HOME="$T/foreign-link" "$B" paths | has -x "bin_link  $T/foreign-link/.local/bin/switchboard -> /bin/true (not this CLI's: left as it is)" \
  && ok "a file, another link or a dangling link at ~/.local/bin/switchboard is left as it is, and paths says whose it is" || die "foreign"

# ---- 9. words written into records say switchboard; old records keep theirs
LX=$("$B" link --from "$T/alpha:lead" --to "$T/beta:worker" --scope "short" --covers "short" --until 1h | awk 'NR==1{print $2}')
SWITCHBOARD_NOW=$(( $(date +%s) + 7200 )) up "$T/alpha" S1 "next" >/dev/null   # a prompt publishes, and the publish reaps
[ "$(jq -r .closed_by "$SWITCHBOARD_DIR/links/$LX.json")" = switchboard ] && ok "a link the board closes says closed_by switchboard" || die "closed_by: $(cat "$SWITCHBOARD_DIR/links/$LX.json")"
(cd "$T/beta" && SWITCHBOARD_SESSION_ID=S2 SWITCHBOARD_TEST_PROPOSE=1 "$B" link --from "$T/beta:other" --to "$T/alpha:lead" --scope x --covers "test work" >/dev/null 2>&1) && die "proposal from an end not held"
refusal S2 | jq -r .tool | has -x switchboard && ok "a refusal the CLI records names its tool switchboard" || die "refusal: $(refusal S2)"

# ---- 10. SWITCHBOARD_ switches: OFF, SESSIONS_DIR, NOSYNC
W='{"file_path":"'"$T/beta/src/y.py"'","content":"x"}'; "$B" hold "$T/beta/src" --until 1h --reason "env" >/dev/null
hook PreToolUse "$T/beta" S2 Write "$W" | has '"deny"' && [ -z "$(SWITCHBOARD_OFF=1 hook PreToolUse "$T/beta" S2 Write "$W")" ] \
  && [ -z "$(env -u AGENT_BOARD_ALLOW_TMP AGENT_BOARD_OFF=1 hook PreToolUse "$T/beta" S2 Write "$W")" ] \
  && ok "SWITCHBOARD_OFF switches the hooks off, as its older name AGENT_BOARD_OFF does" || die "OFF"
P9=$(fake S9 "$T/alpha" alt); mkdir -p "$T/alt-sessions"; mv "$HOME/.claude/sessions/$P9.json" "$T/alt-sessions/"
(cd "$T/alpha" && SWITCHBOARD_SESSION_ID=S9 "$B" me | has "^terminal ") && (cd "$T/alpha" && SWITCHBOARD_SESSIONS_DIR="$T/alt-sessions" SWITCHBOARD_SESSION_ID=S9 "$B" me | has "^session S9 ") \
  && ok "SWITCHBOARD_SESSIONS_DIR names where Claude Code's session files are" || die "SESSIONS_DIR"
CL="$T/clone"; mkdir -p "$CL"; git -C "$CL" init -q -b main; git -C "$CL" remote add origin "$T/nowhere.git"
env -u SWITCHBOARD_NOSYNC SWITCHBOARD_NOSYNC=1 SWITCHBOARD_DIR="$CL" SWITCHBOARD_STATE="$T/st-nosync" "$B" sync
[ -z "$(git -C "$CL" config --get merge.board-link.driver)" ] && [ ! -e "$T/st-nosync/sync-job.lock" ] || die "SWITCHBOARD_NOSYNC synced"
env -u SWITCHBOARD_NOSYNC SWITCHBOARD_DIR="$CL" SWITCHBOARD_STATE="$T/st-sync" "$B" sync; waitfor "$T/st-sync/sync.fail"
[ "$(git -C "$CL" config --get merge.board-link.driver)" = "$(drv "$T/st-sync")" ] && [ -s "$T/st-sync/sync.fail" ] \
  && ok "SWITCHBOARD_NOSYNC stops a sync before it touches the clone; without it the same sync (the job started from its __file__) sets the drivers with that state dir's cli link and runs its job" || die "NOSYNC control"

finish
