#!/usr/bin/env bash
# switchboard init: a first run with no setup, init in a fresh HOME, init twice, --update, keys from a session and from
# a terminal, an existing board named with --board left as it is, two HOMEs syncing through a bare repo after
# --remote and --join, a board with no remote that never syncs, --always-on with systemctl and launchctl stubbed, a
# plugin update that deletes the old version, and a CLI planted at a cache-shaped path
source "$(dirname "$0")/../lib.sh"
unset XDG_CONFIG_HOME   # the config file and the systemd unit dir follow it: here they stay under each throwaway HOME
# a run with none of the suite's board variables: the HOME it names and its config file decide
clean(){ env -u SWITCHBOARD_DIR -u SWITCHBOARD_STATE -u SWITCHBOARD_MACHINE -u SWITCHBOARD_OWNER -u SWITCHBOARD_NOSCAN \
  -u XDG_CONFIG_HOME "$@"; }
sb(){ local h=$1; shift; clean HOME="$h" "$B" "$@"; }   # the CLI in a HOME of its own
nh(){ mkdir -p "$T/$1/.claude/sessions"; echo "$T/$1"; }   # a fresh HOME
pj(){ python3 -c "import json,sys; d=json.load(sys.stdin); print(eval(sys.argv[1]))" "$1"; }   # a value of a JSON document
cj(){ pj "$2" < "$1/.config/switchboard/config.json"; }   # a value of a HOME's config file
hk(){ # home event cwd session [VAR=value...]: a hook call in that HOME
  local h=$1 e=$2 cwd=$3 sid=$4; shift 4
  python3 -c "import json,sys; print(json.dumps({'hook_event_name':sys.argv[1],'cwd':sys.argv[2],'session_id':sys.argv[3],'source':'startup','prompt':'x'}))" \
    "$e" "$cwd" "$sid" | clean HOME="$h" "$@" "$B" hook; }
bash_pre(){ # home cli cwd command: that CLI's PreToolUse verdict on a Bash command, in that HOME
  python3 -c "import json,sys; print(json.dumps({'hook_event_name':'PreToolUse','cwd':sys.argv[1],'session_id':'G1','tool_name':'Bash','tool_input':{'command':sys.argv[2]}}))" \
    "$3" "$4" | clean HOME="$1" "$2" hook; }
syncw(){ rm -f "$1/.local/state/switchboard/sync.ok"; clean HOME="$1" SWITCHBOARD_NOSYNC= "$B" sync; waitfor "$1/.local/state/switchboard/sync.ok"; }
cmd_in(){ sed -n 's/^  \(mkdir -p .*keys && printf .*\)$/\1/p'; }   # the command init prints for keys/allowed_signers
HOST=$(python3 -c "import platform,re; print(re.sub(r'[^a-z0-9]+','-',platform.node().split('.')[0].lower()).strip('-') or 'machine')")
SHARED_NEW='["settings.json", "CLAUDE.md", "agents", "commands", "skills", "plugins/known_marketplaces.json", "plugins/installed_plugins.json"]'

# a stand-in Claude process (tests/fakeclaude.py) the CLI finds by walking the real process tree, as a session's Bash
FC="$TESTS/fakeclaude.py"
claude(){ # name: a stand-in Claude process listening on $T/fc-<name>.sock
  python3 "$FC" serve "$T/fc-$1.sock" >/dev/null 2>&1 </dev/null & echo $! >> "$T/pids"
  local n=0; until [ -S "$T/fc-$1.sock" ] || [ $n -gt 50 ]; do python3 -c "import time; time.sleep(0.1)"; n=$((n+1)); done; }
under(){ # home name cwd command: the command as that stand-in's child, in that HOME, with the real process walk
  clean HOME="$1" SWITCHBOARD_NOWALK= python3 "$FC" run "$T/fc-$2.sock" "$3" "$4"; }
seated(){ # home name: a session start through that stand-in, so the hooks record its process as a Claude session
  python3 -c "import json,sys; print(json.dumps({'hook_event_name':'SessionStart','source':'startup','cwd':sys.argv[1],'session_id':'FC-'+sys.argv[2]}))" "$T" "$2" \
    | under "$1" "$2" "$T" "\"$B\" hook" >/dev/null; }
lines(){ cut -d' ' -f1 "$1/keys/allowed_signers" 2>/dev/null | tr '\n' ' '; }   # the principals in a board's allowed_signers
routes(){ # home board stand-in machine-prefix: init run every way a session could leave its process tree or its identity
  local h=$1 b=$2 n=$3 p=$4
  under "$h" "$n" "$T" "\"$B\" init --update --machine $p-plain" </dev/null > "$T/route-plain-$n.out" 2>&1
  under "$h" "$n" "$T" "setsid -f \"$B\" init --update --machine $p-setsid >/dev/null 2>&1" </dev/null
  under "$h" "$n" "$T" "( \"$B\" init --update --machine $p-dfork >/dev/null 2>&1 & )" </dev/null
  under "$h" "$n" "$T" "nohup \"$B\" init --update --machine $p-nohup >/dev/null 2>&1 &" </dev/null
  under "$h" "$n" "$T" "HOME=$T/other-$n \"$B\" init --board $b --machine $p-home --owner x" </dev/null > "$T/route-home-$n.out" 2>&1
  under "$h" "$n" "$T" "SWITCHBOARD_SESSIONS_DIR=$T/none SWITCHBOARD_STATE=$T/st-$n \"$B\" init --update --machine $p-env >/dev/null 2>&1" </dev/null
  python3 -c "import time; time.sleep(3)"; }   # the detached ones finish

# ---- 7. a first run with no setup: a local board, no config, no key, no sync, notes and status that say so
H0=$(nh zero); mkrepo "$T/r0"; S0="$H0/.local/state/switchboard"
out=$(hk "$H0" SessionStart "$T/r0" Z1 SWITCHBOARD_NOSYNC=); hk "$H0" UserPromptSubmit "$T/r0" Z1 SWITCHBOARD_NOSYNC= SWITCHBOARD_PULL_EVERY=0 >/dev/null
[ -d "$H0/.local/share/switchboard/events" ] && [ ! -e "$H0/.local/share/switchboard/.git" ] && [ ! -e "$H0/.config/switchboard" ] && [ ! -e "$H0/.ssh" ] \
  && ! echo "$out" | has systemMessage && [ ! -e "$S0/sync.fail" ] && [ ! -e "$S0/sync.ok" ] && [ ! -s "$S0/errors.log" ] \
  && [ "$(sb "$H0" paths --json | pj 'sorted(set(d["sources"].values()))')" = "['default']" ] \
  && sb "$H0" status | has "^sync: off, the board folder has no remote" \
  && ok "a first run with no setup: a local board from the defaults, no config file, no key, no sync and nothing logged" || die "first run: $out $(cat "$S0/errors.log" "$S0/sync.fail" 2>&1)"

# ---- 1. init in a fresh HOME from a terminal: every field in the config file, a local git repo, the key and its line
H1=$(nh one); B1="$H1/.local/share/switchboard"
# shellcheck disable=SC2088  # init is given ~ unexpanded, and the expected text shows ~ as the CLI prints it
out=$(sb "$H1" init --owner "Ann Lee" --machine "Box One" --scan "~/code" --scan "$T/work")
[ "$(cj "$H1" 'list(d)')" = "['machine', 'owner', 'board_dir', 'state_dir', 'scan', 'shared', 'scope_ids', 'skip']" ] \
  && [ "$(cj "$H1" '"|".join([d["machine"], d["owner"], d["board_dir"], d["state_dir"], json.dumps(d["scan"]), json.dumps(d["shared"]), json.dumps(d["scope_ids"]), json.dumps(d["skip"])])')" \
    = "box-one|Ann Lee|~/.local/share/switchboard|~/.local/state/switchboard|[\"~/code\", \"$T/work\"]|$SHARED_NEW|[]|[]" ] \
  && [ "$(sb "$H1" paths --json | pj '"%s %s %s" % (d["machine"], d["board_dir"], sorted(set(d["sources"].values())))')" = "box-one $B1 ['config']" ] \
  && ok "init writes every field to the config file, and paths reads each from it" || die "config: $out $(cat "$H1/.config/switchboard/config.json")"
pub=$(cut -d' ' -f1,2 "$H1/.ssh/switchboard_box-one.pub")
[ "$(git -C "$B1" log --format=%s)" = "switchboard: init box-one" ] && [ -z "$(git -C "$B1" remote)" ] \
  && [ "$(git -C "$B1" ls-files | tr '\n' ' ')" = ".gitattributes .gitignore defaults.json keys/allowed_signers " ] \
  && [ "$(stat -c %a "$H1/.ssh/switchboard_box-one")" = 600 ] && [ "$(stat -c %a "$H1/.ssh")" = 700 ] \
  && [ "$(cat "$B1/keys/allowed_signers")" = "box-one namespaces=\"switchboard-task\" $pub" ] \
  && sb "$H1" status | has "^key box-one: no expiry" \
  && ok "the board is a local git repo with no remote, its files and this machine's allowed_signers line in one commit; the key is ed25519, mode 600" \
  || die "board: $(git -C "$B1" log --stat 2>&1 | tail -8)"
# shellcheck disable=SC2088  # init is given ~ unexpanded, and the expected text shows ~ as the CLI prints it
echo "$out" | has "^  signers  wrote this machine's line to keys/allowed_signers$" && echo "$out" | has "/reload-plugins" \
  && echo "$out" | has -F "switchboard init --remote <git url>" && echo "$out" | has -F "/switchboard:init --join <git url>" \
  && echo "$out" | has -F '~/.local/bin is not on your PATH' && echo "$out" | has -F 'export PATH="$HOME/.local/bin:$PATH"' \
  && [ "$(echo "$out" | wc -l)" -le 15 ] && ok "init says in a few lines what it did and what comes next, and that ~/.local/bin is not on PATH" || die "summary: $out"
clean HOME="$H1" PATH="$H1/.local/bin:$PATH" "$B" init --update | has "is not on your PATH" && die "the PATH hint with ~/.local/bin on PATH" || true

# ---- init twice refuses and shows what differs; --update rewrites only the fields it names
cp "$H1/.config/switchboard/config.json" "$T/conf-before"
if out=$(sb "$H1" init 2>&1); then die "init twice ran"; else echo "$out" | has "config.json is there, so init wrote nothing. No field differs" \
  && ok "init with a config file there refuses, and says no field differs" || die "twice: $out"; fi
# shellcheck disable=SC2088  # init is given ~ unexpanded, and the expected text shows ~ as the CLI prints it
if out=$(sb "$H1" init --owner Bob --scan "~/src" 2>&1); then die "init with another owner ran"; else
  echo "$out" | has -xF '  owner: the file has "Ann Lee", this run gives "Bob"' && echo "$out" | has -F "  scan: the file has [\"~/code\", \"$T/work\"], this run gives [\"~/src\"]" \
  && ! echo "$out" | has "  machine:" && cmp -s "$T/conf-before" "$H1/.config/switchboard/config.json" \
  && ok "init with other values refuses, naming each field that differs, and leaves the file" || die "differs: $out"; fi
echo mine > "$B1/defaults.json"; rm "$B1/.gitignore"; ln -s "$T/nothing" "$B1/.gitignore"; n=$(git -C "$B1" rev-list --count HEAD)
out=$(sb "$H1" init --update --owner Bob)
[ "$(cj "$H1" 'd["owner"]')" = Bob ] && [ "$(cj "$H1" 'json.dumps({k: v for k, v in d.items() if k != "owner"})')" = "$(pj 'json.dumps({k: v for k, v in d.items() if k != "owner"})' < "$T/conf-before")" ] \
  && [ "$(cat "$B1/defaults.json")" = mine ] && [ "$(readlink "$B1/.gitignore")" = "$T/nothing" ] && [ "$(git -C "$B1" rev-list --count HEAD)" = "$n" ] \
  && echo "$out" | has "^  key      ~/.ssh/switchboard_box-one (there already)$" && echo "$out" | has "^  signers  keys/allowed_signers has a line for box-one; left as it is$" \
  && [ "$(grep -c box-one "$B1/keys/allowed_signers")" = 1 ] \
  && ok "init --update rewrites the field it names; the board's own files, edited or a dangling link, the key and its line stay" || die "update: $out"
python3 - "$H1/.config/switchboard/config.json" <<'PY'
import json, sys; d = json.load(open(sys.argv[1])); del d["scan"], d["shared"]; json.dump(d, open(sys.argv[1], "w"))
PY
sb "$H1" init --update >/dev/null
[ "$(cj "$H1" 'json.dumps([d["owner"], d["scan"], d["shared"]])')" = "[\"Bob\", [], $SHARED_NEW]" ] \
  && ok "init --update adds the fields a config file lacks, so none falls to a default later" || die "update adds: $(cat "$H1/.config/switchboard/config.json")"
rm "$B1/.gitignore"; git -C "$B1" checkout -q -- .gitignore defaults.json

# ---- keys/ is the owner's: from a session init prints the line and the command, and the guard refuses that command
# from a session; the person runs it in a terminal
H2=$(nh two); B2="$H2/.local/share/switchboard"; HOME="$H2" seat S2 "$T" "set up"
out=$(clean HOME="$H2" SWITCHBOARD_SESSION_ID=S2 SWITCHBOARD_TEST_PROPOSE=1 "$B" init --machine sess-box); cmd=$(echo "$out" | cmd_in)
[ -f "$H2/.ssh/switchboard_sess-box" ] && [ ! -e "$B2/keys" ] && echo "$out" | has "a Claude session never writes it" \
  && echo "$cmd" | has -F "'sess-box namespaces=\"switchboard-task\" ssh-ed25519 " \
  && echo "$cmd" | has -F "mkdir -p ~/.local/share/switchboard/keys && printf '%s\n' 'sess-box namespaces=" \
  && echo "$cmd" | has -F ">> ~/.local/share/switchboard/keys/allowed_signers && git -C ~/.local/share/switchboard add keys/allowed_signers" \
  && ok "init from a session makes the key but writes nothing in keys/: it prints the line and the command" || die "session: $out"
bash_pre "$H2" "$B" "$T" "$cmd" | has '"deny".*keys are installed by the user, not by a session' \
  && ok "that command, run from a session, is refused by the guard" || die "guard: $(bash_pre "$H2" "$B" "$T" "$cmd")"
(cd "$T" && HOME="$H2" bash -c "$cmd") && [ "$(git -C "$B2" log -1 --format=%s)" = "switchboard: key for sess-box" ] \
  && sb "$H2" status | has "^key sess-box: no expiry, installed 0m ago$" && ok "run by the person in a terminal, it adds and commits the line" \
  || die "person: $(git -C "$B2" log --format=%s 2>&1)"

# ---- P1: init writes keys/allowed_signers only into a board the same run made from an absent or empty folder with no
# remote. Every other run prints the line, however the caller looks: a plain session, setsid, a double fork, nohup,
# another HOME naming the board, the session and state variables changed
HK=$(nh keys); BK="$HK/.local/share/switchboard"; sb "$HK" init --machine k-box >/dev/null; claude K; seated "$HK" K
n=$(git -C "$BK" rev-list --count HEAD); routes "$HK" "$BK" K k
[ "$(lines "$BK")" = "k-box " ] && [ "$(git -C "$BK" rev-list --count HEAD)" = "$n" ] && ! git -C "$BK" log --format=%s | has "key for" \
  && has "a Claude session never writes it" < "$T/route-plain-K.out" && has -F "  mkdir -p $BK/keys && printf" < "$T/route-home-K.out" \
  && [ -f "$HK/.ssh/switchboard_k-setsid" ] && [ -f "$HK/.ssh/switchboard_k-env" ] \
  && ok "on a board init made earlier, no route writes a line: plain session, setsid, double fork, nohup, another HOME, the session and state variables" \
  || die "routes: lines [$(lines "$BK")], $(git -C "$BK" log --format=%s | head -3 | tr '\n' ';') $(cat "$T/route-plain-K.out" "$T/route-home-K.out")"
under "$HK" K "$T" "\"$B\" init --update --board $T/freshk --machine k-fresh" </dev/null > "$T/route-fresh.out" 2>&1
[ "$(lines "$T/freshk")" = "" ] && has "a Claude session never writes it" < "$T/route-fresh.out" \
  && ok "a board made from a session gets no line either: the session check stays as an extra" || die "fresh from a session: $(cat "$T/route-fresh.out")"

# ---- P1: a git repo that is not a board is refused, so sync never pushes records to its origin
mkrepo "$T/code"; git init -q --bare -b main "$T/code.git"; git -C "$T/code" remote add origin "$T/code.git"; HR=$(nh coderepo)
if out=$(sb "$HR" init --board "$T/code" 2>&1); then die "init took a code repo as the board"; else
  echo "$out" | has "is a git repo that is not a board .*links/\*.json merge=board-link" && [ ! -e "$HR/.config/switchboard" ] \
  && [ -z "$(git -C "$T/code" status --porcelain)" ] && [ -z "$(git -C "$T/code" config --local user.email)" ] \
  && ok "init --board on a code repo with an origin refuses and writes nothing, not even a git identity" || die "code repo: $out"; fi

# ---- an existing board named with --board: a git repo whose .gitattributes has the board's rule, holding code and
# PLAN.md beside its records, this machine's line in keys/allowed_signers and its key under the name before the rename
# (~/.ssh/agent-board_<machine>). init writes the config file and leaves the board, its key and its line as they are
HL=$(nh existing); LB="$HL/work/board"; git init -q -b main "$LB"; mkdir -p "$LB/registry" "$LB/keys" "$HL/.ssh"
binit "$LB"; echo "# plan" > "$LB/PLAN.md"; ssh-keygen -q -t ed25519 -N "" -C t -f "$HL/.ssh/agent-board_west"
echo "west namespaces=\"agent-board-task,switchboard-task\" $(cat "$HL/.ssh/agent-board_west.pub")" > "$LB/keys/allowed_signers"
git -C "$LB" add -A; git -C "$LB" -c user.email=t@t -c user.name=t commit -qm seed
tree(){ (cd "$LB" && find . -path ./.git -prune -o -type f -print | sort | xargs sha1sum; git rev-parse HEAD; git status --porcelain); }
before=$(tree); out=$(clean HOME="$HL" SWITCHBOARD_TEST_PLATFORM=Linux "$B" init --machine west --owner Ann --board "$LB")
[ "$(cj "$HL" '"|".join([d["machine"], d["owner"], d["board_dir"], d["state_dir"], json.dumps(d["scan"]), json.dumps(d["shared"]), json.dumps(d["scope_ids"]), json.dumps(d["skip"])])')" \
  = "west|Ann|~/work/board|~/.local/state/switchboard|[]|$SHARED_NEW|[]|[]" ] \
  && [ "$(tree)" = "$before" ] && [ ! -e "$HL/.ssh/switchboard_west" ] && echo "$out" | has "^  key      ~/.ssh/agent-board_west (there already)$" \
  && [ "$(clean HOME="$HL" "$B" paths --json | pj '"%s %s" % (d["board_dir"], sorted(set(d["sources"].values())))')" = "$LB ['config']" ] \
  && ok "init --board on an existing board writes the config file and leaves the board, its key and its line as they are" || die "existing: $out"
# a session start through the plugin there: STATE/cli turns to the plugin's copy, and ~/.local/bin/switchboard, a link to
# the board folder's own bin/switchboard (not a plugin copy), is left as it is
mkdir -p "$LB/bin"; cp "$B" "$LB/bin/switchboard"; mkdir -p "$HL/.local/bin"; ln -s "$LB/bin/switchboard" "$HL/.local/bin/switchboard"
ssl(){ python3 -c "import json,sys; print(json.dumps({'hook_event_name':'SessionStart','source':'startup','cwd':sys.argv[1],'session_id':sys.argv[2]}))" "$T" "$1"; }
CL="$HL/.claude/plugins/cache/switchboard/switchboard/0.4.0"; mkdir -p "$CL/bin"; cp "$B" "$CL/bin/switchboard"
printf '{"version": 2, "plugins": {"switchboard@switchboard": [{"scope": "user", "installPath": "%s"}]}}\n' "$CL" > "$HL/.claude/plugins/installed_plugins.json"
ssl L2 | clean HOME="$HL" CLAUDE_PLUGIN_ROOT="$CL" "$CL/bin/switchboard" hook >/dev/null
[ "$(readlink "$HL/.local/bin/switchboard")" = "$LB/bin/switchboard" ] && [ "$(readlink "$HL/.local/state/switchboard/cli")" = "$CL/bin/switchboard" ] \
  && ok "a session start through the plugin links STATE/cli to its copy and leaves a ~/.local/bin/switchboard that links elsewhere" \
  || die "bin link: $(readlink "$HL/.local/bin/switchboard") $(readlink "$HL/.local/state/switchboard/cli")"

# ---- 2. two HOMEs and a bare repo: init and --remote on the first, a session start and --join on the second
git init -q --bare -b main "$T/board.git"; HA=$(nh ma); HB=$(nh mb); BA="$HA/.local/share/switchboard"; BB="$HB/.local/share/switchboard"
sb "$HA" init --owner Ann --machine alpha-box >/dev/null; out=$(sb "$HA" init --remote "$T/board.git")
[ "$(git -C "$T/board.git" log main --format=%s)" = "switchboard: init alpha-box" ] && echo "$out" | has "now syncs with $T/board.git (branch main)" \
  && git -C "$T/board.git" ls-tree -r --name-only main | has -x keys/allowed_signers && [ "$(git -C "$BA" rev-parse --abbrev-ref '@{u}')" = origin/main ] \
  && sb "$HA" status | has "^sync: last successful push 20" && ok "init --remote pushes the board to an empty repo, sync is on and status shows that push" || die "remote: $out"
if out=$(sb "$HA" init --remote "$T/other.git" 2>&1); then die "a second remote was set"; else echo "$out" | has "already syncs with $T/board.git" \
  && ok "a board that has a remote keeps it" || die "other remote: $out"; fi
if out=$(sb "$H1" init --remote "$T/board.git" 2>&1); then die "a push onto another board went through"; else
  echo "$out" | has "The remote was not kept, so sync stays off" && [ -z "$(git -C "$B1" remote)" ] && [ "$(git -C "$T/board.git" log main --format=%s)" = "switchboard: init alpha-box" ] \
  && ok "--remote onto a repo that holds another board fails and keeps no remote" || die "foreign push: $out"; fi
mkrepo "$T/rb"; HOME="$HB" seat BS "$T/rb" "first run"; hk "$HB" SessionStart "$T/rb" BS >/dev/null; ls "$BB"/sessions/*-BS.json >/dev/null 2>&1 || die "setup: no first-run board on the second HOME"
out=$(sb "$HB" init --join "$T/board.git" --owner Ann --machine beta-box); cmd=$(echo "$out" | cmd_in)
[ "$(git -C "$BB" remote get-url origin)" = "$T/board.git" ] && [ "$(git -C "$BB" rev-parse HEAD)" = "$(git -C "$T/board.git" rev-parse main)" ] \
  && ls "$BB"/sessions/*-BS.json >/dev/null && grep -q "^alpha-box " "$BB/keys/allowed_signers" && ! grep -q beta-box "$BB/keys/allowed_signers" \
  && [ -f "$HB/.ssh/switchboard_beta-box" ] && echo "$out" | has "This machine cannot vouch for itself" \
  && echo "$cmd" | has -F "mkdir -p keys && printf '%s\n' 'beta-box namespaces=" \
  && echo "$cmd" | has -F ">> keys/allowed_signers && git add keys/allowed_signers && git commit -q -m 'switchboard: key for beta-box' -- keys/allowed_signers && git push -q" \
  && echo "$out" | has -x "  records  moved from the machine name $HOST to beta-box: registry 1, sessions 1" \
  && ls "$BB"/sessions/beta-box-BS.json >/dev/null && ! ls "$BB"/sessions/"$HOST"-*.json >/dev/null 2>&1 \
  && ok "init --join clones into the board a session start made, keeps its records (moved from the hostname's name, and says so), makes the key and prints the line for the first machine" \
  || die "join: $out"
# the joined machine's sessions cannot vouch for it either: no route writes its line
claude KB; seated "$HB" KB; n=$(git -C "$BB" rev-list --count HEAD); routes "$HB" "$BB" KB beta
sb "$HB" init --update --machine beta-box >/dev/null 2>&1
[ "$(lines "$BB")" = "alpha-box " ] && [ "$(git -C "$BB" rev-list --count HEAD)" = "$n" ] && [ -z "$(git -C "$BB" status --porcelain keys)" ] \
  && ok "on a joined board no route writes a line, so nothing reaches the first machine" || die "joined routes: lines [$(lines "$BB")]"
NB="$T/notboard"; mkdir -p "$NB"; echo x > "$NB/README.md"; mkrepo "$T/otherrepo"; git -C "$T/otherrepo" remote add origin "$T/x.git"; HC=$(nh mc)
if out=$(sb "$HC" init --join "$T/board.git" --board "$NB" 2>&1); then die "join into a foreign folder"; else
  echo "$out" | has "holds README.md, which a board folder does not" && [ ! -e "$NB/.git" ] && [ ! -e "$HC/.config/switchboard" ] || die "foreign folder: $out"; fi
if out=$(sb "$HC" init --join "$T/board.git" --board "$T/otherrepo" 2>&1); then die "join into another repo"; else
  echo "$out" | has "is a git repo with origin $T/x.git, not a clone of $T/board.git" && [ ! -e "$HC/.config/switchboard" ] \
  && ok "init --join refuses a folder that is not a board and a repo with another origin, and writes nothing" || die "other repo: $out"; fi

# the person on the first machine adds the line; then a task signed on each verifies on the other, and records sync
# both ways
(cd "$BA" && HOME="$HA" bash -c "$cmd") && git -C "$T/board.git" show main:keys/allowed_signers | has "^beta-box " \
  && ok "the line, added and pushed on the first machine, reaches the board repo" || die "key push: $(git -C "$BA" log --format=%s | head -3)"
syncw "$HB"; grep -q "^beta-box " "$BB/keys/allowed_signers" || die "setup: the second machine did not pull the key line"
sb "$HB" register "$T/rb" >/dev/null; sb "$HA" register "$T/rb" >/dev/null
TB=$(cd "$T" && sb "$HB" task request --to "$T/rb:builder" --subject "from beta" --key jb1 2>/dev/null | awk '{print $1}')
TA=$(cd "$T" && sb "$HA" task request --to "$T/rb:builder" --subject "from alpha" --key ja1 2>/dev/null | awk '{print $1}')
HID=$(sb "$HA" hold "$T/rb" --until 1d --reason "held on alpha" | awk '{print $2}')
syncw "$HB"; syncw "$HA"; syncw "$HB"
sb "$HA" task "$TB" | has -x "  signed by beta-box" && sb "$HB" task "$TA" | has -x "  signed by alpha-box" \
  && sb "$HB" read | has "^HOLD $HID .*held on alpha" && ls "$BA"/sessions/*-BS.json >/dev/null \
  && ok "after sync both ways, a request signed on either machine verifies on the other, and records travel both ways" \
  || die "two homes: $(sb "$HA" task "$TB" 2>&1 | tail -3) | $(sb "$HB" task "$TA" 2>&1 | tail -3) | $(cat "$HA/.local/state/switchboard/sync.fail" "$HB/.local/state/switchboard/sync.fail" 2>&1)"

# ---- a board with no remote never syncs: no job, no fetch, no sync.fail, nothing logged, nothing committed
S1="$H1/.local/state/switchboard"; rm -f "$S1"/sync.* "$S1/errors.log"; n=$(git -C "$B1" rev-list --count HEAD); mkrepo "$T/r1"
for e in SessionStart UserPromptSubmit PostToolUse Stop SessionEnd; do hk "$H1" $e "$T/r1" N1 SWITCHBOARD_NOSYNC= SWITCHBOARD_PULL_EVERY=0 >/dev/null; done
clean HOME="$H1" SWITCHBOARD_NOSYNC= "$B" sync; clean HOME="$H1" SWITCHBOARD_NOSYNC= "$B" sync-job; python3 -c "import time; time.sleep(1.5)"
[ ! -e "$S1/sync.fail" ] && [ ! -e "$S1/sync.ok" ] && [ ! -e "$S1/sync-job.lock" ] && [ ! -s "$S1/errors.log" ] && [ "$(git -C "$B1" rev-list --count HEAD)" = "$n" ] \
  && [ -z "$(git -C "$B1" config --get-regexp '^merge\.board-')" ] && sb "$H1" status | has "^sync: off, the board folder has no remote" \
  && ok "a board with no remote never syncs: hooks, sync and sync-job start nothing, write no sync.fail and log nothing" || die "no remote: $(cat "$S1/sync.fail" "$S1/errors.log" 2>&1)"
# a remote added by hand to an empty repo: the sync.fail line says how to push the board there
HE=$(nh hand); SE="$HE/.local/state/switchboard"; sb "$HE" init --machine e-box >/dev/null; git init -q --bare -b main "$T/empty.git"
git -C "$HE/.local/share/switchboard" remote add origin "$T/empty.git"; clean HOME="$HE" SWITCHBOARD_NOSYNC= "$B" sync; waitfor "$SE/sync.fail"
grep -qF "origin has no branch main yet: \`switchboard init --remote $T/empty.git\` pushes this board there first" "$SE/sync.fail" \
  && sb "$HE" status | has "init --remote $T/empty.git" && ok "a remote added by hand to an empty repo: sync.fail and status say to run init --remote" \
  || die "hand remote: $(cat "$SE/sync.fail" 2>&1)"

# ---- 3. --always-on: a systemd user timer or a launchd agent, with systemctl and launchctl stubbed; --remove
STUB="$T/stub"; mkdir -p "$STUB"
for c in systemctl launchctl; do printf '#!/bin/sh\necho "%s $*" >> "%s/stub.log"\n' "$c" "$T" > "$STUB/$c"; chmod +x "$STUB/$c"; done
ao(){ local h=$1 os=$2; shift 2; clean HOME="$h" SWITCHBOARD_TEST_PLATFORM="$os" PATH="$STUB:$PATH" "$B" init --always-on "$@"; }
U="$HA/.config/systemd/user"; SA="$HA/.local/state/switchboard"; : > "$T/stub.log"
out=$(ao "$HA" Linux)
grep -qxF "ExecStart=\"$SA/cli\" sync" "$U/switchboard-sync.service" && grep -qxF "ConditionFileIsExecutable=$SA/cli" "$U/switchboard-sync.service" \
  && grep -qxF "Type=oneshot" "$U/switchboard-sync.service" && grep -qxF "KillMode=process" "$U/switchboard-sync.service" && grep -qxF "Nice=10" "$U/switchboard-sync.service" \
  && grep -q '^Environment="PATH=.*/usr/bin' "$U/switchboard-sync.service" && grep -qxF "OnUnitActiveSec=2min" "$U/switchboard-sync.timer" \
  && grep -qxF "WantedBy=timers.target" "$U/switchboard-sync.timer" && head -1 "$U/switchboard-sync.timer" | has "^# switchboard always-on sync, written by switchboard init" \
  && [ "$(cat "$T/stub.log")" = "$(printf 'systemctl --user daemon-reload\nsystemctl --user enable --now switchboard-sync.timer')" ] \
  && echo "$out" | has -x "Remove it: switchboard init --always-on --remove" && echo "$out" | has "runs nothing until a session start has made ~/.local/state/switchboard/cli" \
  && echo "$out" | has -F "loginctl enable-linger" \
  && ok "--always-on on Linux writes a user service and a 2-minute timer that run STATE/cli sync at Nice 10, and enables the timer" \
  || die "systemd: $out $(cat "$T/stub.log") $(cat "$U/switchboard-sync.service" 2>&1)"
: > "$T/stub.log"; out=$(ao "$HA" Linux --remove)
[ ! -e "$U/switchboard-sync.service" ] && [ ! -e "$U/switchboard-sync.timer" ] && echo "$out" | has "removed the systemd user timer switchboard-sync.timer" \
  && [ "$(cat "$T/stub.log")" = "$(printf 'systemctl --user disable --now switchboard-sync.timer\nsystemctl --user daemon-reload')" ] \
  && ao "$HA" Linux --remove | has "no always-on sync is installed here" && ok "--always-on --remove disables the timer and removes both files" || die "systemd remove: $out"
mkdir -p "$U"; echo mine > "$U/switchboard-sync.timer"
out=$(ao "$HA" Linux 2>&1) && die "--always-on ran over a foreign unit file"; out2=$(ao "$HA" Linux --remove 2>&1) && die "--remove ran over a foreign unit file"
[ "$(cat "$U/switchboard-sync.timer")" = mine ] && [ ! -e "$U/switchboard-sync.service" ] \
  && echo "$out" | has "was not written by init --always-on; left as it is" && echo "$out2" | has "Nothing was removed" \
  && ok "a unit file of that name init did not write is neither replaced nor removed" || die "foreign unit: $out | $out2"
rm "$U/switchboard-sync.timer"; : > "$T/stub.log"
if out=$(ao "$H1" Linux 2>&1); then die "--always-on on a board with no remote"; else echo "$out" | has "has no remote, so there is nothing to keep current" \
  && [ ! -e "$H1/.config/systemd" ] && [ ! -s "$T/stub.log" ] && ok "--always-on refuses a board with no remote" || die "no remote always-on: $out"; fi
PL="$HA/Library/LaunchAgents/switchboard.sync.plist"; out=$(ao "$HA" Darwin)
python3 - "$PL" "$SA/cli" <<'PY' && ok "--always-on on macOS writes a launchd agent: every 120 s, STATE/cli sync at Nice 10 through sh, loaded with bootstrap" || die "launchd: $out $(cat "$T/stub.log")"
import plistlib, sys
d = plistlib.load(open(sys.argv[1], "rb"))
assert d["Label"] == "switchboard.sync" and d["ProgramArguments"][0] == "/bin/sh" and d["ProgramArguments"][3] == sys.argv[2], d
assert d["StartInterval"] == 120 and d["Nice"] == 10 and d["RunAtLoad"] is True and "/usr/bin" in d["EnvironmentVariables"]["PATH"], d
assert open(sys.argv[1]).read().count("<!-- switchboard always-on sync, written by switchboard init") == 1
PY
uid=$(id -u); [ "$(cat "$T/stub.log")" = "$(printf 'launchctl bootout gui/%s/switchboard.sync\nlaunchctl bootstrap gui/%s %s' "$uid" "$uid" "$PL")" ] \
  || die "launchctl calls: $(cat "$T/stub.log")"
: > "$T/stub.log"; ao "$HA" Darwin --remove >/dev/null && [ ! -e "$PL" ] && [ "$(cat "$T/stub.log")" = "launchctl bootout gui/$uid/switchboard.sync" ] \
  && ok "--always-on --remove on macOS boots the agent out and removes its plist" || die "launchd remove: $(cat "$T/stub.log")"
if out=$(ao "$HA" Windows 2>&1); then die "--always-on on another system"; else echo "$out" | has "knows systemd (Linux) and launchd (macOS), not Windows" \
  && ok "--always-on elsewhere says what it knows and writes nothing" || die "other os: $out"; fi

# ---- 5. a plugin update, 0.2.0 to 0.2.1, with the old version's folder deleted: the next session start through the new
# version turns ~/.local/bin/switchboard and STATE/cli to it; CLI_NAME never names a ~/.claude/board that is not there
HU=$(nh upd); CA="$HU/.claude/plugins/cache/switchboard/switchboard"; BIN="$HU/.local/bin/switchboard"; SU="$HU/.local/state/switchboard"
inst(){ printf '{"version": 2, "plugins": {"switchboard@switchboard": [{"scope": "user", "installPath": "%s"}]}}\n' "$CA/$1" > "$HU/.claude/plugins/installed_plugins.json"; }
ph(){ # version: a session start through the plugin's hooks at that version
  python3 -c "import json,sys; print(json.dumps({'hook_event_name':'SessionStart','source':'startup','cwd':sys.argv[1],'session_id':'U1'}))" "$T/rb" \
    | clean HOME="$HU" CLAUDE_PLUGIN_ROOT="$CA/$1" "$CA/$1/bin/switchboard" hook >/dev/null; }
mkdir -p "$CA/0.2.0/bin"; cp "$B" "$CA/0.2.0/bin/switchboard"; inst 0.2.0; ph 0.2.0
[ "$(readlink "$BIN")" = "$CA/0.2.0/bin/switchboard" ] && [ "$(readlink "$SU/cli")" = "$CA/0.2.0/bin/switchboard" ] || die "setup: 0.2.0's links"
mkdir -p "$CA/0.2.1/bin"; cp "$B" "$CA/0.2.1/bin/switchboard"; inst 0.2.1; rm -r "$CA/0.2.0"
N=$(clean HOME="$HU" "$CA/0.2.1/bin/switchboard" paths --json | pj 'd["cli_name"]'); l=$(clean HOME="$HU" "$CA/0.2.1/bin/switchboard" link accept 2>&1 || true)
# shellcheck disable=SC2088  # init is given ~ unexpanded, and the expected text shows ~ as the CLI prints it
[ -L "$BIN" ] && [ ! -e "$BIN" ] && [ "$N" = "~/.claude/plugins/cache/switchboard/switchboard/0.2.1/bin/switchboard" ] \
  && [ "$l" = "switchboard: $N link accept <id>" ] && ok "after the update, before a session start: the old link dangles, and the new copy names itself by its path, not ~/.claude/board" \
  || die "between: $N | $l | $(ls -la "$BIN" 2>&1)"
hk "$HU" SessionStart "$T/rb" U2 >/dev/null   # a worktree's copy fed a session start by hand: not the hooks' CLI
[ "$(readlink "$BIN")" = "$CA/0.2.0/bin/switchboard" ] || die "a copy the hooks do not run turned the link"
ph 0.2.1
[ "$(readlink "$BIN")" = "$CA/0.2.1/bin/switchboard" ] && [ "$(readlink "$SU/cli")" = "$CA/0.2.1/bin/switchboard" ] \
  && [ "$(clean HOME="$HU" "$BIN" paths --json | pj 'd["cli_name"]')" = switchboard ] \
  && ok "the first session start through 0.2.1 turns ~/.local/bin/switchboard and STATE/cli to it, and CLI_NAME is switchboard again" \
  || die "after: $(ls -la "$BIN" "$SU/cli" 2>&1)"
for k in link file; do rm -f "$BIN"; case $k in link) ln -s /bin/true "$BIN";; file) echo mine > "$BIN";; esac
  before=$(ls -l "$BIN" | awk '{print $1, $NF}'); ph 0.2.1
  [ "$(ls -l "$BIN" | awk '{print $1, $NF}')" = "$before" ] || die "the plugin's session start replaced a $k at ~/.local/bin/switchboard"
done && ok "a link elsewhere or a file at ~/.local/bin/switchboard is never replaced" || true
rm -f "$BIN"; ph 0.2.1

# ---- 6. plugin_cli trusts only the install Claude Code records: a real copy planted at a cache-shaped path is a script
# like any other, and with no readable installed_plugins.json no cache copy is trusted (once ~/.local/bin/switchboard,
# itself one of the CLI's paths, no longer leads to it)
P9="$HU/.claude/plugins/cache/evil/switchboard/9.9.9/bin/switchboard"; mkdir -p "$(dirname "$P9")"; cp "$B" "$P9"
BU="$HU/.local/share/switchboard"; C1="$CA/0.2.1/bin/switchboard"
deny(){ bash_pre "$HU" "$1" "$BU" "$2" | has '"deny"'; }
runs(){ [ -z "$(bash_pre "$HU" "$1" "$BU" "$2")" ]; }
deny "$C1" "$P9 links" && deny "$B" "$P9 links" && deny "$B" "python3 $P9 links" && runs "$C1" "$C1 links" && runs "$B" "$C1 links" \
  && runs "$B" "python3 $C1 links" && ok "a real copy of the CLI planted at a cache-shaped path is not the CLI; the installed one is" || die "planted"
rm "$BIN"; mv "$HU/.claude/plugins/installed_plugins.json" "$T/inst"; deny "$B" "$C1 links" && runs "$C1" "$C1 links" \
  && echo '{"plugins": ' > "$HU/.claude/plugins/installed_plugins.json" && deny "$B" "$C1 links" \
  && echo '{"plugins": {"switchboard@x": [{"installPath": "'"$T/elsewhere"'"}]}}' > "$HU/.claude/plugins/installed_plugins.json" \
  && mkdir -p "$T/elsewhere/bin" && cp "$B" "$T/elsewhere/bin/switchboard" && deny "$B" "$T/elsewhere/bin/switchboard links" \
  && ok "with installed_plugins.json missing or unreadable no cache copy is trusted but the running one, and an install path outside the cache never is" \
  || die "no record"
mv "$T/inst" "$HU/.claude/plugins/installed_plugins.json"

finish
