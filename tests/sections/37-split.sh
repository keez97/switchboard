#!/usr/bin/env bash
# the code and data split: the CLI run from the plugin cache works against a board folder that also holds code, as a
# board kept beside the code of an earlier version does (the code, PLAN.md, the record .gitattributes, records): paths,
# notes, the record guard, and a sync whose rebase merges through the drivers. init, which writes a board folder's own
# files, is 38-init.sh
source "$(dirname "$0")/../lib.sh"
cap_procs   # it runs pre-push hooks: one that ran itself would stop at the cap
pj(){ python3 -c "import json,sys; d=json.load(sys.stdin); print(eval(sys.argv[1]))" "$1"; }   # a value of paths --json
gc(){ git -C "$1" -c user.email=t@t -c user.name=t "${@:2}"; }
# the plugin as Claude Code installs it: a copy per version under the cache, its hooks run with CLAUDE_PLUGIN_ROOT set
PC="$HOME/.claude/plugins/cache/switchboard/switchboard/0.2.0"; mkdir -p "$PC/bin"; cp "$B" "$PC/bin/switchboard"
C="$PC/bin/switchboard"; CR=$(realpath "$C")
# Claude Code's record of it, with an older version a project still has installed (local scope)
printf '{"version": 2, "plugins": {"switchboard@switchboard": [{"scope": "user", "installPath": "%s"}, {"scope": "local", "projectPath": "/x", "installPath": "%s"}]}}\n' \
  "$PC" "$HOME/.claude/plugins/cache/switchboard/switchboard/0.1.9" > "$HOME/.claude/plugins/installed_plugins.json"
on(){ # event cwd session [tool] [tool_input json]: a hook call as the plugin's hooks make it
  python3 - "$@" <<'PY' | CLAUDE_PLUGIN_ROOT="$PC" "$C" hook
import json,sys
e,cwd,sid=sys.argv[1:4]; d={"hook_event_name":e,"cwd":cwd,"session_id":sid}
if len(sys.argv)>5: d["tool_name"]=sys.argv[4]; d["tool_input"]=json.loads(sys.argv[5])
if e=="SessionStart": d["source"]="startup"
print(json.dumps(d))
PY
}

# ---- a board folder that holds code too: bin/ with a bin/board link, tests/, the plugin files, PLAN.md, the record
# .gitattributes, .gitignore and defaults.json, keys and records, a clone of its remote. Named by the config file's
# board_dir (no SWITCHBOARD_DIR); the CLI runs from the plugin cache
unset SWITCHBOARD_DIR
LB="$HOME/work/board"; git init -q --bare -b main "$T/lb.git"; git clone -q "$T/lb.git" "$LB" 2>/dev/null
mkdir -p "$HOME/.config/switchboard"; echo "{\"board_dir\": \"~/work/board\"}" > "$HOME/.config/switchboard/config.json"
mkdir -p "$LB/bin" "$LB/tests" "$LB/hooks" "$LB/.claude-plugin" "$LB/keys" "$LB/registry"
cp "$B" "$LB/bin/switchboard"; ln -s switchboard "$LB/bin/board"; echo 'echo t' > "$LB/tests/x.sh"; echo '# plan' > "$LB/PLAN.md"
echo '{}' > "$LB/hooks/hooks.json"; echo '{"name": "old-board"}' > "$LB/.claude-plugin/plugin.json"; : > "$LB/keys/allowed_signers"
binit "$LB"; git -C "$LB" config user.email t@t; git -C "$LB" config user.name east
gc "$LB" add -A; gc "$LB" commit -qm seed; git -C "$LB" push -q origin HEAD:main 2>/dev/null
"$C" paths --json | pj '"%s %s %s" % (d["board_dir"], d["sources"]["board_dir"], d["cli"])' | has -xF "$LB config $CR" \
  && ok "run from the plugin cache, the CLI finds the board the config file names and names its own cache path" || die "paths: $("$C" paths)"

# STATE/cli: a session start through the plugin's hooks links it to the cache copy; the same copy run with no
# CLAUDE_PLUGIN_ROOT (by hand, not as the hooks run it) leaves a state dir's link alone
mkrepo "$T/alpha"; mkdir -p "$T/alpha/src"; "$C" register "$T/alpha" >/dev/null; seat S1 "$T/alpha" road
HID=$("$C" hold "$T/alpha/src" --until 2d --reason "split hold" | awk '{print $2}')
note=$(on SessionStart "$T/alpha" S1 | ctx)
python3 -c "import json,sys; print(json.dumps({'hook_event_name':'SessionStart','source':'startup','cwd':sys.argv[1],'session_id':'S2'}))" "$T/alpha" \
  | SWITCHBOARD_STATE="$T/state-hand" "$C" hook >/dev/null
[ "$(readlink "$SWITCHBOARD_STATE/cli")" = "$CR" ] && [ ! -e "$T/state-hand/cli" ] && [ ! -L "$T/state-hand/cli" ] \
  && "$C" paths | has -x "state_cli $SWITCHBOARD_STATE/cli -> $CR (this CLI)" \
  && ok "a session start through the plugin's hooks links STATE/cli to the cache copy; the copy run by hand makes no link" || die "state cli: $(ls -la "$SWITCHBOARD_STATE/cli" "$T/state-hand" 2>&1)"
echo "$note" | has "^switchboard" && echo "$note" | has -F "HOLD until" && echo "$note" | has -F "split hold" \
  && on PreToolUse "$T/alpha" S1 Write "{\"file_path\":\"$T/alpha/src/x.py\",\"content\":\"x\"}" | has "hold $HID: .* is frozen" \
  && ok "notes: the session start shows the hold, and an edit under it is refused" || die "notes: $note"
# the pre-push hook install-prepush writes from the cache copy runs STATE/cli, that copy, and refuses a held push
git init -q --bare -b main "$T/alpha.git"; git -C "$T/alpha" remote add origin "$T/alpha.git"; git -C "$T/alpha" push -q -u origin main 2>/dev/null
"$C" install-prepush "$T/alpha" >/dev/null; echo x > "$T/alpha/src/x.py"; gc "$T/alpha" add -A; gc "$T/alpha" commit -qm held
if out=$(git -C "$T/alpha" push origin main 2>&1); then die "pre-push: a held push went through"
else echo "$out" | has "hold $HID: .* is frozen" && grep -qF "$SWITCHBOARD_STATE/cli" "$T/alpha/.git/hooks/pre-push" \
  && ok "the pre-push hook installed from the plugin cache refuses a held push through STATE/cli" || die "pre-push: $out"; fi

# the record guard in a board folder that holds code, through the plugin's hooks
cl(){ python3 -c 'import json,sys; print(json.dumps({"command": sys.argv[1]}))' "$1"; }
deny(){ on PreToolUse "$LB" S1 "$@" | has '"deny"'; }
runs(){ [ -z "$(on PreToolUse "$LB" S1 "$@")" ]; }
deny Write "{\"file_path\":\"$LB/links/lf.json\",\"content\":\"x\"}" && deny Edit '{"file_path":"roles/x.json"}' \
  && runs Edit "{\"file_path\":\"$LB/bin/switchboard\"}" && runs Edit '{"file_path":"tests/x.sh"}' && runs Write "{\"file_path\":\"$LB/PLAN.md\",\"content\":\"x\"}" \
  && runs Edit "{\"file_path\":\"$LB/.claude-plugin/plugin.json\"}" && runs Write "{\"file_path\":\"$LB/.claude/worktrees/w1/links/x.json\",\"content\":\"x\"}" \
  && ok "records are refused; the code, PLAN.md, the plugin files and a worktree's record dirs stay editable" || die "record guard on files"
mkdir -p "$T/evil" "$HOME/.claude/plugins/cache/switchboard/switchboard/0.1.9/bin" "$HOME/.claude/plugins/cache/x/switchboard/9.9/bin"
printf '#!/bin/sh\ncat "$@"\n' > "$T/evil/switchboard"; chmod +x "$T/evil/switchboard"; cp "$B" "$HOME/.claude/plugins/cache/switchboard/switchboard/0.1.9/bin/switchboard"
ln -s "$T/evil/switchboard" "$HOME/.claude/plugins/cache/x/switchboard/9.9/bin/switchboard"
# shellcheck disable=SC2088  # the guard is given the command as a session writes it, ~ unexpanded
runs Bash "$(cl "$C links")" && runs Bash "$(cl "$C tasks --mine")" && runs Bash "$(cl "~/.claude/plugins/cache/switchboard/switchboard/0.1.9/bin/switchboard links")" \
  && runs Bash "$(cl "bin/switchboard links")" && runs Bash "$(cl "bin/board links")" && runs Bash "$(cl "python3 bin/switchboard links")" \
  && deny Bash "$(cl "$C status > links/x.json")" && deny Bash "$(cl "$T/evil/switchboard links/x.json")" \
  && deny Bash "$(cl "~/.claude/plugins/cache/x/switchboard/9.9/bin/switchboard links/x.json")" && deny Bash "$(cl "echo x > roles/r.json")" \
  && ok "the CLI from the plugin cache (this version or another installed one), the clone's bin/switchboard and bin/board are the CLI; a script elsewhere, or a cache link to one, is a write" \
  || die "record guard on commands"

# a sync job from the plugin cache, the first clone (east) and a second clone (west), each changing one link's cap:
# the second sync's rebase merges the record through the driver at that machine's STATE/cli (the lower cap wins); with
# no ~/.claude/board here git's own merge would stop on a conflict
H="$T/clone-h"; git clone -q "$T/lb.git" "$H"; git -C "$H" config user.email t@t; git -C "$H" config user.name west
hl(){ SWITCHBOARD_DIR="$H" SWITCHBOARD_STATE="$T/state-h" SWITCHBOARD_MACHINE=west "$@"; }
hl on SessionStart "$H" S9 >/dev/null
printf '{"id":"lx","from":{"repo":"r","role":"a"},"to":{"repo":"r","role":"b"},"scope":"x","until":%s,"cap":5,"created":%s,"machine":"east"}\n' \
  $(( $(date +%s) + 86400 )) "$(date +%s)" > "$LB/links/lx.json"
gc "$LB" add links/lx.json; gc "$LB" commit -qm lx; git -C "$LB" push -q origin HEAD:main 2>/dev/null; git -C "$H" pull -q 2>/dev/null
code(){ git -C "$T/lb.git" ls-tree -r main -- bin tests hooks .claude-plugin PLAN.md .gitattributes .gitignore defaults.json keys; }
code0=$(code); "$C" link-cap lx 3 >/dev/null; hl "$C" link-cap lx 4 >/dev/null
rm -f "$T/state-h/sync.ok"; SWITCHBOARD_NOSYNC='' hl "$C" sync; waitfor "$T/state-h/sync.ok"
rm -f "$SWITCHBOARD_STATE/sync.ok"; SWITCHBOARD_NOSYNC='' "$C" sync; waitfor "$SWITCHBOARD_STATE/sync.ok"
[ ! -e "$HOME/.claude/board" ] && [ "$(readlink "$T/state-h/cli")" = "$CR" ] && [ "$(jq -c .cap "$LB/links/lx.json")" = 3 ] \
  && [ "$(git -C "$T/lb.git" show main:links/lx.json | jq -c .cap)" = 3 ] && [ ! -e "$LB/.git/rebase-merge" ] && [ -z "$(git -C "$LB" status --porcelain)" ] \
  && git -C "$LB" config --get merge.board-link.driver | has -F "$SWITCHBOARD_STATE/cli" \
  && [ "$(git -C "$T/lb.git" log --format=%H main -- links/lx.json | wc -l)" = 3 ] && [ "$(code)" = "$code0" ] && [ "$(code | wc -l)" = 10 ] \
  && ok "two syncs from the plugin cache, one on a board folder that holds code: the rebase merges the link through STATE/cli's driver, the code files ride along unchanged" \
  || die "sync: $(cat "$SWITCHBOARD_STATE/sync.fail" "$T/state-h/sync.fail" 2>&1); cap $(jq -c .cap "$LB/links/lx.json" 2>&1); $(git -C "$LB" status --short | head -5)"
hl "$C" paths --json | pj '"%s %s %s" % (d["board_dir"], d["sources"]["board_dir"], d["state_cli"]["ours"])' | has -xF "$H env True" \
  && ok "paths on the second clone: its board from the variable, STATE/cli this CLI" || die "paths west: $(hl "$C" paths)"

finish
