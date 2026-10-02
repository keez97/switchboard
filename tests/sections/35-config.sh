#!/usr/bin/env bash
# the config file and identity: the config file and the variables in their order, each variable's older name, a config
# file that cannot be used, a new user's defaults, board paths, the identity guard and the merge drivers
source "$(dirname "$0")/../lib.sh"
# a run with none of the suite's board variables: only what a test sets and the HOME it names count
clean(){ env -u SWITCHBOARD_DIR -u SWITCHBOARD_STATE -u SWITCHBOARD_MACHINE -u SWITCHBOARD_OWNER -u SWITCHBOARD_NOSCAN \
  -u XDG_CONFIG_HOME "$@"; }
pj(){ python3 -c "import json,sys; d=json.load(sys.stdin); print(eval(sys.argv[1]))" "$1"; }   # a value of board paths --json
conf(){ mkdir -p "$1/.config/switchboard"; printf '%s' "$2" > "$1/.config/switchboard/config.json"; }

# ---- the rules that are fields (scope_ids, skip) and the waiting_on default: a new user gets the generic defaults
# lc.py board-file subject scope: whether that copy's link_check finds the scope names the subject
cat > "$T/lc.py" <<'PY'
import importlib.machinery, importlib.util, json, sys
path, subject, scope = sys.argv[1:4]
loader = importlib.machinery.SourceFileLoader("boardcopy", path)
m = importlib.util.module_from_spec(importlib.util.spec_from_loader("boardcopy", loader))
sys.argv = [path]
loader.exec_module(m)
e = {"repo": "github.com/you/alpha", "role": "builder"}
(m.BOARD / "links").mkdir(parents=True, exist_ok=True)
(m.BOARD / "links" / "l5c09e1d.json").write_text(json.dumps({"id": "l5c09e1d", "scope": scope, "from": e, "to": e, "state": "active"}))
print(m.link_check({"link": "l5c09e1d", "subject": subject, "requester": e, "worker": e, "machine": m.MACHINE})["scope_covers_subject"])
PY
covers(){ clean HOME="$1" "${@:4}" python3 "$T/lc.py" "$2" "$3" "evaluate run-2026-01-01-01 and T-12" 2>&1; }   # home cli subject [VAR=value ...]
regd(){ clean HOME="$1" "${@:4}" "$2" register "$3" >/dev/null 2>&1; find "$(clean HOME="$1" "$B" paths --json | pj 'd["board_dir"]')/registry" -mindepth 1 -maxdepth 1 -name "*$(basename "$3")*" | grep -c .; }
wo(){ # home cli: the waiting_on an input-required transition records when none is given, from a terminal in the worker repo
  local tid k="k$RANDOM"
  tid=$(clean HOME="$1" "$2" task request --to "$1/w:builder" --subject "wait $k" --key "$k" --no-sign 2>/dev/null | awk '{print $1}')
  (cd "$1/w" && clean HOME="$1" "$2" task input-required "$tid" >/dev/null 2>&1)
  jq -r .waiting_on "$(clean HOME="$1" "$B" paths --json | pj 'd["board_dir"]')"/tasks/*/"$tid"/001-input-required.json 2>&1; }
NH="$T/nu2"; mkrepo "$NH/w"; mkrepo "$NH/work/scratch-workspaces/sw1"; clean HOME="$NH" "$B" register "$NH/w" >/dev/null
[ "$(covers "$NH" "$B" "run-2026-01-01-01 rerun")" = False ] && [ "$(regd "$NH" "$B" "$NH/work/scratch-workspaces/sw1")" = 1 ] && [ "$(wo "$NH" "$B")" = "the user" ] \
  && ok "new user: no scope ids, no skipped folders, input-required waits on the user" || die "new-user rules: $(covers "$NH" "$B" "run-2026-01-01-01 rerun") $(wo "$NH" "$B")"
[ "$(covers "$NH" "$B" "T-12 rerun" SWITCHBOARD_SCOPE_IDS='T-[0-9]+:(')" = True ] && [ "$(covers "$NH" "$B" "run-2026-01-01-01 rerun" SWITCHBOARD_SCOPE_IDS='T-[0-9]+')" = False ] \
  && [ "$(clean HOME="$NH" SWITCHBOARD_SCOPE_IDS='T-[0-9]+:(' "$B" paths --json | pj 'd["scope_ids"]')" = "['T-[0-9]+']" ] \
  && ok "SWITCHBOARD_SCOPE_IDS names the ids a scope may name; a pattern that does not compile is dropped" || die "scope ids var: $(covers "$NH" "$B" "T-12 rerun" SWITCHBOARD_SCOPE_IDS='T-[0-9]+:(')"
WH="$T/webuser"; mkrepo "$WH/w"; mkrepo "$WH/src/app"; mkrepo "$WH/web/site"; mkrepo "$WH/scratch-workspaces-old/r3"; clean HOME="$WH" "$B" register "$WH/w" >/dev/null
[ "$(regd "$WH" "$B" "$WH/src/app" SWITCHBOARD_SKIP=web)" = 1 ] && [ "$(regd "$WH" "$B" "$WH/web/site" SWITCHBOARD_SKIP=web)" = 0 ] \
  && [ "$(regd "$WH" "$B" "$WH/scratch-workspaces-old/r3" SWITCHBOARD_SKIP=scratch-workspaces)" = 1 ] \
  && ok "skip matches whole folder names: web keeps the repos under a HOME named webuser and drops one under a folder named web; scratch-workspaces keeps scratch-workspaces-old" \
  || die "skip components: $(ls "$WH/.local/share/switchboard/registry")"

# ---- the config file is used, field by field, in the order SWITCHBOARD_ variables, their older AGENT_BOARD_ names
# (machine, dir, state and owner), config, defaults
H="$T/c1"; mkdir -p "$H"
conf "$H" '{"machine": "Lab Box", "board_dir": "~/b", "state_dir": "~/s", "owner": "Ann", "scan": ["~/src"], "shared": ["settings.json", "notes.md"], "scope_ids": ["T-[0-9]+"], "skip": ["tmpwork"]}'
out=$(clean HOME="$H" "$B" paths --json)
[ "$(echo "$out" | pj '"%s|%s|%s|%s|%s|%s|%s|%s|%s|%s" % (d["machine"], d["board_dir"], d["state_dir"], d["owner"], d["scan"], d["shared"], d["scope_ids"], d["skip"], set(d["sources"].values()), d["config"]["valid"])')" \
  = "lab-box|$H/b|$H/s|Ann|['~/src']|['settings.json', 'notes.md']|['T-[0-9]+']|['tmpwork']|{'config'}|True" ] \
  && ok "every config field is used, the machine name slugged, ~ expanded" || die "config: $out"
clean HOME="$H" "$B" status | has "^board $H/b  machine lab-box " && ok "board status runs on the configured board and machine" || die "status: $(clean HOME="$H" "$B" status 2>&1)"
mkrepo "$H/app"; clean HOME="$H" SWITCHBOARD_ALLOW_TMP=1 "$B" hold "$H/app" --until 1h --reason "config owner" >/dev/null
out=$(clean HOME="$H" SWITCHBOARD_ALLOW_TMP=1 "$B" hook <<<"{\"hook_event_name\":\"PreToolUse\",\"cwd\":\"$H/app\",\"session_id\":\"C1\",\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$H/app/x\",\"content\":\"x\"}}")
echo "$out" | has "deny" && echo "$out" | has "Ann" && ! echo "$out" | has "the user" && [ -d "$H/s" ] && [ ! -e "$H/.local/state/switchboard" ] \
  && ok "a hook refuses with the configured owner's name and keeps its state in the configured state dir" || die "hook owner: $out"
X="$T/xdg"; conf "$X" '{"owner": "Xavier", "board_dir": "~/xb"}'; mv "$X/.config/switchboard" "$X/switchboard"
[ "$(clean HOME="$H" XDG_CONFIG_HOME="$X" "$B" paths --json | pj 'd["owner"]+"|"+d["config"]["path"]')" = "Xavier|$X/switchboard/config.json" ] \
  && ok "XDG_CONFIG_HOME picks the config file" || die "xdg: $(clean HOME="$H" XDG_CONFIG_HOME="$X" "$B" paths --json)"
out=$(clean HOME="$H" SWITCHBOARD_MACHINE=Env-Box SWITCHBOARD_OWNER=Eve SWITCHBOARD_DIR="$T/eb" "$B" paths --json)
[ "$(echo "$out" | pj '"%s|%s|%s|%s|%s" % (d["machine"], d["owner"], d["board_dir"], d["sources"]["machine"], d["sources"]["state_dir"])')" = "env-box|Eve|$T/eb|env|config" ] \
  && ok "SWITCHBOARD_ variables win over the config file, field by field, and an env machine name is slugged" || die "env over config: $out"
out=$(clean HOME="$H" AGENT_BOARD_MACHINE=ab SWITCHBOARD_MACHINE=sw AGENT_BOARD_OWNER=A SWITCHBOARD_OWNER=S AGENT_BOARD_DIR="$T/abd" \
  SWITCHBOARD_DIR="$T/swd" AGENT_BOARD_STATE="$T/abs" SWITCHBOARD_STATE="$T/sws" SWITCHBOARD_SCAN="~/one:~/two" SWITCHBOARD_SHARED="a.md:b" \
  SWITCHBOARD_SCOPE_IDS="x-[0-9]+:y" SWITCHBOARD_SKIP="t1:t2" "$B" paths --json)
[ "$(echo "$out" | pj '"%s|%s|%s|%s|%s|%s|%s|%s|%s" % (d["machine"], d["owner"], d["board_dir"], d["state_dir"], d["scan"], d["shared"], d["scope_ids"], d["skip"], set(d["sources"].values()))')" \
  = "sw|S|$T/swd|$T/sws|['~/one', '~/two']|['a.md', 'b']|['x-[0-9]+', 'y']|['t1', 't2']|{'env'}" ] \
  && ok "SWITCHBOARD_ variables win over their older AGENT_BOARD_ names; lists split on :" || die "switchboard over agent_board: $out"
out=$(clean HOME="$H" AGENT_BOARD_MACHINE=Old-Box AGENT_BOARD_OWNER=Olga AGENT_BOARD_DIR="$T/ob" AGENT_BOARD_STATE="$T/os" "$B" paths --json)
[ "$(echo "$out" | pj '"%s|%s|%s|%s|%s" % (d["machine"], d["owner"], d["board_dir"], d["state_dir"], set(d["sources"][k] for k in ("machine", "owner", "board_dir", "state_dir")))')" \
  = "old-box|Olga|$T/ob|$T/os|{'env'}" ] && ok "with no SWITCHBOARD_ variable, the older AGENT_BOARD_ names still win over the config file" || die "old names: $out"
[ "$(clean HOME="$H" AGENT_BOARD_OWNER= SWITCHBOARD_OWNER= "$B" paths --json | pj 'd["owner"]')" = Ann ] && ok "an empty variable counts as unset" || die "empty var"

# ---- a config file that is there but cannot be used (not JSON, not an object, a link to nothing, no board_dir, a wrong
# machine, board_dir or state_dir, a config folder that is a file): the board, state dir and machine come from it, so
# nothing runs on the defaults instead. Every command exits 1 naming the file and writes nothing; a hook does nothing,
# and a session start says so once per version of the file, logged beside the fallback log. The pre-push check warns
# and lets the push and the chained hook go on
H="$T/bad"; mkdir -p "$H"; mkrepo "$H/r"; conf "$H" "{\"board_dir\": \"$T/bad-board\", \"state_dir\": \"$T/bad-state\"}"
clean HOME="$H" SWITCHBOARD_ALLOW_TMP=1 "$B" hold "$H/r" --until 1h --reason "bad config" >/dev/null || die "setup: a hold on the configured board"
FB="$T/tmp/switchboard-$(id -u)"; mkdir -p "$T/tmp"; Z=0000000000000000000000000000000000000000
bh(){ clean HOME="$H" TMPDIR="$T/tmp" SWITCHBOARD_ALLOW_TMP=1 "$B" hook <<<"{\"hook_event_name\":\"$1\",\"cwd\":\"$H/r\",\"session_id\":\"B1\",\"source\":\"startup\",\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$H/r/x\",\"content\":\"x\"}}"; }
snap(){ find "$H" "$T/bad-board" "$T/bad-state" | sort; }
bad_runs(){ # what fault: under HOME=$H, two session starts, a PreToolUse on the held path and a PostToolUse; status,
  # paths and prepush
  local h1 h2 h3 rc_s rc_p rc_pp s p pp before c0; before=$(snap)
  c0=$(grep -c "config_broken .*config.json: $2" "$FB/errors.log" 2>/dev/null || true)
  h1=$(bh SessionStart; echo "rc=$?"); h2=$(bh SessionStart; echo "rc=$?"); h3=$(bh PreToolUse; bh PostToolUse; echo "rc=$?")
  s=$(clean HOME="$H" "$B" status 2>&1) && rc_s=0 || rc_s=$?; p=$(clean HOME="$H" "$B" paths --json 2>&1) && rc_p=0 || rc_p=$?
  pp=$(cd "$H/r" && echo "refs/heads/main $(git rev-parse HEAD) refs/heads/main $Z" | clean HOME="$H" "$B" prepush origin x 2>&1) && rc_pp=0 || rc_pp=$?
  echo "$h1" | head -1 | pj 'd["systemMessage"]' | has -F "$H/.config/switchboard/config.json: $2" && [ "$(echo "$h1" | wc -l)" = 2 ] \
    && [ "$h2" = "rc=0" ] && [ "$h3" = "rc=0" ] && [ "$rc_s" = 1 ] && [ "$rc_p" = 1 ] && [ "$rc_pp" = 0 ] \
    && echo "$pp" | has -x "switchboard: .*config.json: .*This push was not checked against holds." \
    && echo "$s" | has -F "switchboard: $H/.config/switchboard/config.json: $2" && echo "$s" | has "Nothing was run.$" && echo "$p" | has -F "config.json: $2" \
    && [ "$(snap)" = "$before" ] && [ "$(grep -c "config_broken .*config.json: $2" "$FB/errors.log")" = $(( ${c0:-0} + 1 )) ] \
    && ok "$1" || die "$1: hook [$h1] [$h2] [$h3] status $rc_s [$s] paths $rc_p [$p] prepush $rc_pp [$pp] wrote [$(diff <(echo "$before") <(snap))] log [$(cat "$FB/errors.log" 2>/dev/null)]"; }
mv "$H/.config/switchboard/config.json" "$T/good.json"; conf "$H" '{"machine": '
bad_runs "not JSON: commands exit 1 naming the file, hooks do nothing (no hold refusal, no note), one line at the first session start, nothing written" "not readable as JSON"
conf "$H" '[1, 2]'; touch -d '+1 min' "$H/.config/switchboard/config.json"
bad_runs "a JSON list: the same, the line again once for the new version of the file" "not a JSON object"
rm "$H/.config/switchboard/config.json"; ln -s "$T/nothing.json" "$H/.config/switchboard/config.json"
bad_runs "a link to a file that is not there: the same" "a link to a file that is not there"
n=2; for c in '{}' '{"owner": "Ann", "machine": "m1"}' "{\"board_dir\": \"rel/b\"}" "{\"board_dir\": \"$T/bad-board\", \"machine\": 5}" \
  "{\"board_dir\": \"$T/bad-board\", \"state_dir\": [\"x\"], \"owner\": \"Ann\"}"; do
  rm -f "$H/.config/switchboard/config.json"; conf "$H" "$c"; touch -d "+$n min" "$H/.config/switchboard/config.json"; n=$((n + 1))
  case $c in *rel/b*) f="board_dir is not an absolute path";; *'"machine": 5'*) f="machine is not a non-empty text";;
    *state_dir*) f="state_dir is not an absolute path";; *) f="no board_dir";; esac
  bad_runs "$c: the same, as a file that does not say which board this is" "$f"
done
rm -rf "$H/.config/switchboard"; echo x > "$H/.config/switchboard"
bad_runs "a file at ~/.config/switchboard, where the config folder goes: the same" "$H/.config/switchboard is a file, not a folder"
rm "$H/.config/switchboard"; mkdir -p "$H/.config/switchboard"
[ "$(grep -c config_broken "$FB/errors.log")" = 9 ] && [ ! -e "$H/.local/share/switchboard" ] && [ ! -e "$H/.local/state/switchboard" ] \
  && ok "no default board or state dir was made beside the configured ones" || die "defaults made: $(ls -a "$H/.local/share" "$H/.local/state" 2>&1)"
mv "$T/good.json" "$H/.config/switchboard/config.json"
bh PreToolUse | has '"deny"' && ok "fixed, the same file's hold refuses again" || die "fixed: $(bh PreToolUse)"

# ---- a usable config file with wrong fields other than machine, board_dir and state_dir: never a crash, logged once
# per version of the file, the rest still used
L="$T/bad-state/errors.log"
fault_runs(){ # what fault lines: a hook and board status twice each under HOME=$H; neither fails, the hook says nothing,
  # status names the fault on stderr, and $L holds that many lines on the config file
  local h s
  h=$(clean HOME="$H" SWITCHBOARD_ALLOW_TMP=1 SWITCHBOARD_NOSCAN=1 "$B" hook <<<"{\"hook_event_name\":\"PostToolUse\",\"cwd\":\"$H/r\",\"session_id\":\"B1\",\"tool_name\":\"Read\",\"tool_input\":{}}" 2>&1; echo "rc=$?")
  clean HOME="$H" SWITCHBOARD_ALLOW_TMP=1 SWITCHBOARD_NOSCAN=1 "$B" hook <<<"{\"hook_event_name\":\"SessionStart\",\"cwd\":\"$H/r\",\"session_id\":\"B1\"}" >/dev/null 2>&1 || h="$h hook2 failed"
  s=$(clean HOME="$H" "$B" status 2>&1 >/dev/null; echo "rc=$?"); clean HOME="$H" "$B" status >/dev/null 2>&1 || s="$s status2 failed"
  [ "$h" = "rc=0" ] && echo "$s" | has "config.json: .*$2" && echo "$s" | has "^rc=0$" && [ "$(grep -c "malformed switchboard/config.json" "$L")" = "$3" ] \
    && ok "$1" || die "$1: hook [$h] status [$s] log [$(cat "$L" 2>/dev/null)]"; }
conf "$H" "{\"board_dir\": \"$T/fault-board\", \"state_dir\": \"$T/bad-state\", \"owner\": 7, \"scan\": \"~/code\", \"shared\": [\"/etc/passwd\"], \"scope_ids\": [\"(\"], \"skip\": [\"a/b\"], \"colour\": 1}"
touch -d '+20 min' "$H/.config/switchboard/config.json"
fault_runs "wrong-typed fields: run as before, logged once" "owner is not a non-empty text; .*Those fields are ignored" 1
out=$(clean HOME="$H" "$B" paths --json)
[ "$(echo "$out" | pj '"%s|%s|%s|%s|%s" % (d["owner"], d["sources"]["owner"], d["sources"]["board_dir"], d["board_dir"], len(d["config"]["faults"]))')" = "the user|default|config|$T/fault-board|6" ] \
  && ok "the good fields are used and each bad one falls to the new-user default; paths lists the six faults" || die "fields: $out"
grep -q "malformed switchboard/config.json: owner is not a non-empty text; .*unknown field colour; skipped" "$L" \
  && ok "the log line names each bad field" || die "log line: $(tail -1 "$L")"
# a session start says so too, once per version of the file, and the hooks keep running
fh(){ clean HOME="$H" SWITCHBOARD_ALLOW_TMP=1 SWITCHBOARD_NOSCAN=1 "$B" hook <<<"{\"hook_event_name\":\"$1\",\"cwd\":\"$H/r\",\"session_id\":\"B2\",\"source\":\"startup\",\"tool_name\":\"Read\",\"tool_input\":{}}"; }
touch -d '+21 min' "$H/.config/switchboard/config.json"; s1=$(fh SessionStart); s2=$(fh SessionStart); s3=$(fh PostToolUse)
echo "$s1" | pj 'd["systemMessage"]' | has -xF "switchboard: $H/.config/switchboard/config.json: owner is not a non-empty text; scan is not a list of folders; shared is not a list of relative paths under ~/.claude; scope_ids is not a list of regular expressions; skip is not a list of folder names; unknown field colour. Those fields are ignored and take their defaults until the file is fixed; the rest of it is used." \
  && ! echo "$s2" | has systemMessage && [ -z "$s3" ] && [ -d "$T/fault-board/sessions" ] \
  && ok "a session start names the file and its bad fields once per version of the file; the hooks keep running on the configured board" || die "field note: [$s1] [$s2] [$s3]"
touch -d '+22 min' "$H/.config/switchboard/config.json"
fh SessionStart | pj 'd["systemMessage"]' | has "owner is not a non-empty text" && ok "a new version of the file is named again" || die "field note again"

# ---- a new user: no config file
H="$T/nu"; mkdir -p "$H/.claude"
before=$(find "$H" | sort); out=$(clean HOME="$H" "$B" paths --json); after=$(find "$H" | sort)
want=$(python3 -c "import platform,re; print(re.sub(r'[^a-z0-9]+','-',platform.node().split('.')[0].lower()).strip('-') or 'machine')")
[ "$(echo "$out" | pj '"%s|%s|%s|%s|%s|%s|%s|%s|%s" % (d["machine"], d["board_dir"], d["state_dir"], d["owner"], d["scan"], " ".join(d["shared"]), d["scope_ids"], d["skip"], set(d["sources"].values()))')" \
  = "$want|$H/.local/share/switchboard|$H/.local/state/switchboard|the user|[]|settings.json CLAUDE.md agents commands skills plugins/known_marketplaces.json plugins/installed_plugins.json|[]|[]|{'default'}" ] \
  && ok "new-user defaults: the hostname slugged, ~/.local/share and ~/.local/state/switchboard, owner the user, no scan folders, scope ids or skipped folders" || die "new user: $out"
[ "$before" = "$after" ] && ok "board paths --json writes nothing, not even the state dir" || die "paths wrote: $(diff <(echo "$before") <(echo "$after"))"
[ "$(echo "$out" | pj '"%s|%s|%s" % (d["cli"], d["config"]["exists"], d["link"])')" = "$(realpath "$B")|False|None" ] && ! clean HOME="$H" "$B" paths | has "claude/board" \
  && ok "board paths names the CLI, the missing config file and no ~/.claude/board link; its text does not name that path" || die "paths cli: $out"
ln -s "$B" "$H/.claude/board"; clean HOME="$H" "$B" paths | has "^link      $H/.claude/board -> $B$" && ok "board paths shows where ~/.claude/board links" || die "paths link: $(clean HOME="$H" "$B" paths)"
clean HOME="$H" "$B" status | has "^board $H/.local/share/switchboard  machine $want " && [ -d "$H/.local/share/switchboard/events" ] \
  && ok "a new user's board runs with no setup: board status makes the board dir" || die "new user status"
python3 - "$B" <<'PY' && ok "machine names are slugged: lowercase, digits and inner dashes, west and east unchanged, a fallback" || die "slug cases"
import importlib.machinery, importlib.util, sys
loader = importlib.machinery.SourceFileLoader("b", sys.argv[1]); m = importlib.util.module_from_spec(importlib.util.spec_from_loader("b", loader))
sys.argv = [sys.argv[1]]; loader.exec_module(m)
cases = {"west": "west", "east": "east", "Robins-MacBook-Pro": "robins-macbook-pro", "--Lab_Box..2--": "lab-box-2",
         "my east": "my-east", "": "machine", "___": "machine", "Ünï": "n"}
bad = {k: m.machine_slug(k) for k, v in cases.items() if m.machine_slug(k) != v}
if bad:
    print(bad)
sys.exit(1 if bad else 0)
PY

# ---- scanning: off for a new user whatever the board is; the scan folders govern it, not the board's .git
H="$T/scan"; mkdir -p "$H/.claude"; mkrepo "$H/code/r1"; mkrepo "$H/projects/r2"; git init -q "$H/.local/share/switchboard"
clean HOME="$H" SWITCHBOARD_ALLOW_TMP=1 "$B" hook <<<"{\"hook_event_name\":\"SessionStart\",\"cwd\":\"$H\",\"session_id\":\"N1\"}" >/dev/null
SB="$H/.local/share/switchboard"; SS="$H/.local/state/switchboard"
[ -s "$SS/daily.json" ] && ! ls "$SB/registry" | has "r[12]" && [ ! -e "$SS/scan.json" ] \
  && ok "a new user's board, a git clone, registers and scans nothing under ~/code or ~/projects" || die "new user scanned: $(ls "$SB/registry") $(cat "$SS/scan.json" 2>/dev/null)"
rm -rf "$SB/.git" "$SS/daily.json"; conf "$H" '{"scan": ["~/code"], "board_dir": "~/.local/share/switchboard"}'
clean HOME="$H" SWITCHBOARD_ALLOW_TMP=1 "$B" hook <<<"{\"hook_event_name\":\"SessionStart\",\"cwd\":\"$H\",\"session_id\":\"N1\"}" >/dev/null
ls "$SB/registry" | has "r1" && ! ls "$SB/registry" | has "r2" && ok "configured scan folders register their repos on a board that is not a git clone" || die "config scan: $(ls "$SB/registry")"
n=0; until ls "$SB"/subs/*.auto.*.json >/dev/null 2>&1 || [ $n -gt 40 ]; do python3 -c "import time; time.sleep(0.25)"; n=$((n+1)); done   # the scan of r1 runs detached
[ -s "$SS/scan.json" ] && ls "$SB"/subs/*.auto.*.json >/dev/null 2>&1 && ok "and scan them" || die "config scan: no scan of r1"
rm -f "$SS/daily.json" "$SB"/registry/*; clean HOME="$H" SWITCHBOARD_ALLOW_TMP=1 SWITCHBOARD_NOSCAN=1 "$B" hook <<<"{\"hook_event_name\":\"SessionStart\",\"cwd\":\"$H\",\"session_id\":\"N1\"}" >/dev/null
[ -s "$SS/daily.json" ] && [ -z "$(ls "$SB/registry")" ] && ok "SWITCHBOARD_NOSCAN stops it" || die "noscan: $(ls "$SB/registry")"

# ---- every variable the CLI reads under its older AGENT_BOARD_ name has a SWITCHBOARD_ twin that wins; the older name
# alone still counts, and an empty one counts as unset
python3 - "$B" <<'PY' && ok "each older AGENT_BOARD_ name the CLI reads has a SWITCHBOARD_ twin that wins, and is read alone" || die "twins"
import importlib.machinery, importlib.util, os, re, sys
src = open(sys.argv[1]).read()
names = {"MACHINE", "DIR", "STATE", "OWNER", "ALLOW_TMP", "NOW", "SESSION_ID", "TEST_PROPOSE", "SESSIONS_DIR", "NOSYNC",
         "NOSCAN", "OFF", "PULL_EVERY", "NOWALK", "GUARD_BUDGET", "WAIT_TIMEOUT"}
used = set(re.findall(r'board_env\("(\w+)"\)', src)) | set(re.findall(r'setting\("\w+", .*?"(\w+)", old=True\)', src))
literal = set(re.findall(r'AGENT_BOARD_\w+', src)) - {"AGENT_BOARD_"}
if used != names or literal - {"AGENT_BOARD_" + n for n in names}:
    print("read:", sorted(used ^ names), "literal:", sorted(literal))
    sys.exit(1)
for k in list(os.environ):
    if k.startswith(("SWITCHBOARD_", "AGENT_BOARD_")):
        del os.environ[k]
loader = importlib.machinery.SourceFileLoader("b", sys.argv[1]); m = importlib.util.module_from_spec(importlib.util.spec_from_loader("b", loader))
sys.argv = [sys.argv[1]]; loader.exec_module(m)
bad = []
for n in sorted(names):
    os.environ["AGENT_BOARD_" + n] = "old"
    a = m.board_env(n)
    os.environ["SWITCHBOARD_" + n] = "new"
    b = m.board_env(n)
    os.environ["SWITCHBOARD_" + n] = ""
    c = m.board_env(n)
    del os.environ["AGENT_BOARD_" + n]
    d = m.board_env(n)
    del os.environ["SWITCHBOARD_" + n]
    if (a, b, c, d) != ("old", "new", "old", None):
        bad.append((n, a, b, c, d))
if bad:
    print(bad)
sys.exit(1 if bad else 0)
PY

# ---- the guard: a link command run with a variable that changes who the CLI is
bashpre(){ python3 -c 'import json,sys; print(json.dumps({"hook_event_name":"PreToolUse","cwd":sys.argv[1],"session_id":sys.argv[2],"tool_name":"Bash","tool_input":{"command":sys.argv[3]}}))' "$@" | "$B" hook; }
mkrepo "$T/alpha"; bad=""
for v in {SWITCHBOARD,AGENT_BOARD}_{MACHINE,DIR,STATE,OWNER,SESSION_ID,ALLOW_TMP,TEST_PROPOSE,SESSIONS_DIR} XDG_CONFIG_HOME; do
  for c in "$v=x ~/.claude/board link accept l1" "env $v=x board link --from a:b --to c:d --scope x" "export $v=x; board unlink l1"; do
    bashpre "$T/alpha" G1 "$c" | has "identity variables set ($v)" || bad="$bad [$c]"
  done
  bashpre "$T/alpha" G1 "$v=x board links" | has deny && bad="$bad [allowed form refused: $v board links]"
done
[ -z "$bad" ] && ok "a link command run with any machine, board dir, state, owner, session or config-file variable, by either name, is refused; other board commands run" || die "guard: $bad"
bashpre "$T/alpha" G1 "board link accept l1" | has "identity variables" && die "a plain link accept is refused" || ok "a plain link command is not refused as an identity spoof"

# ---- the merge drivers: a minimal environment, the config file's state dir, a bad config file
H="$T/md"; mkdir -p "$H/w"; conf "$H" "{\"state_dir\": \"$T/mstate\", \"board_dir\": \"$T/mboard\"}"
mdrive(){ printf '' > "$H/w/o"; echo '{"ts": 1, "machine": "a"}' > "$H/w/.merge_file_a"; echo '{"ts": 2, "machine": "b"}' > "$H/w/t"
  (cd "$H/w" && env -i PATH="$PATH" HOME="$H" "$B" merge-task o .merge_file_a t tasks/x--y/t1/001-working.json 2>&1; echo "rc=$?"); }
out=$(mdrive)
[ "$out" = "rc=0" ] && ls "$T/mstate/dropped" | has "001-working.json.2.json" && grep -q '"machine": "a"' "$H/w/.merge_file_a" \
  && ok "merge-task under env -i keeps the earlier record and drops the other into the config file's state dir" || die "merge driver: $out $(ls "$T/mstate" 2>&1)"
conf "$H" '{"state_dir": '; rm -rf "$T/mstate"; out=$(mdrive)
[ "$out" = "rc=0" ] && [ -d "$H/.local/state/switchboard/dropped" ] && ok "with a bad config file the driver still merges, silently, into the default state dir" || die "bad config driver: $out"
finish
