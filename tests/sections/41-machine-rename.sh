#!/usr/bin/env bash
# a machine renamed by init: the first session starts register and publish under the hostname's name, then init picks
# another. This machine's records move to the new name and a repo with no remote keeps its id, so the open sessions
# keep their roles, holds, watches and tasks with no new start. init with the same name moves nothing, another
# machine's records never move, and a repo known only under another machine's name is named as such
source "$(dirname "$0")/../lib.sh"
unset SWITCHBOARD_MACHINE   # the hostname's name, until init writes the config file
HOST=$(python3 -c "import platform,re; print(re.sub(r'[^a-z0-9]+','-',platform.node().split('.')[0].lower()).strip('-') or 'machine')")
[ "$HOST" != laptop ] && [ "$HOST" != west ] || die "setup: the hostname is a name this section uses"
D="$SWITCHBOARD_DIR"
pj(){ python3 -c "import json,sys; d=json.load(open(sys.argv[2])); print(eval(sys.argv[1]))" "$@"; }
recs(){ (cd "$D" && find registry sessions roles links holds subs machines tasks -type f 2>/dev/null | sort | xargs sha1sum); }
others(){ (cd "$D" && sha1sum registry/*.west.json sessions/west-*.json machines/west.json "sessions/$HOST-2-R2.json"); }

# ---- before init: a repo with no remote (web) and one with a remote (api), a session and a role in each, a hold in
# web and one outside HOME and any repo, a watch on a file in web, an auto watch, a link, a task web has read
mkrepo "$T/web"; mkrepo "$T/api"; git -C "$T/api" remote add origin git@github.com:you/api.git; mkdir -p "$T/web/src" "$T/outside"
echo 1 > "$T/web/schema.json"; echo "$T/web" > "$T/api/deps.txt"; git -C "$T/api" add deps.txt
git -C "$T/api" -c user.email=t@t -c user.name=t commit -qm deps
PW=$(fake W1 "$T/web" "web session"); fake A1 "$T/api" "api session" >/dev/null
hook SessionStart "$T/web" W1 >/dev/null; hook SessionStart "$T/api" A1 >/dev/null
SWITCHBOARD_SESSION_ID=W1 "$B" role frontend >/dev/null; SWITCHBOARD_SESSION_ID=A1 "$B" role backend >/dev/null
WEB=$(pj 'd["id"]' "$D"/registry/local-*."$HOST".json); case "$WEB" in "local-$HOST-web-"*) ;; *) die "setup: web's id is $WEB";; esac
"$B" hold "$T/web/src" --until 2d --reason "web frozen" >/dev/null; "$B" hold "$T/outside" --until 2d --reason "outside frozen" >/dev/null
grep -l "\"abs:$HOST:$T/outside\"" "$D"/holds/*.json >/dev/null || die "setup: the hold outside HOME is not an abs: path"
"$B" watch "$T/api" path "$T/web/schema.json" >/dev/null; "$B" scan github.com/you/api
[ -f "$D/subs/github.com_you_api.auto.$HOST.json" ] || die "setup: no auto watch for api"
L=$(SWITCHBOARD_SESSION_ID=A1 "$B" link --from "$T/api:backend" --to "$T/web:frontend" --scope "client" | awk 'NR==1{print $2}')
T1=$(SWITCHBOARD_SESSION_ID=A1 "$B" task request --to web:frontend --subject "client: one" --key k1 --body one 2>/dev/null | awk '{print $1}')
SWITCHBOARD_SESSION_ID=W1 "$B" task "$T1" >/dev/null; [ -f "$D/tasks/web--frontend/cursor-$HOST.json" ] || die "setup: web did not read $T1"
hook Stop "$T/api" A1 >/dev/null   # the watch's first snapshot
# by hand, as their own machines write them: this machine's sync stamp, and another machine's (west's) registry,
# session and stamp on the shared board, and a session of a machine whose name starts with this one's and a dash
python3 - "$D" "$HOST" "$T" <<'PY'
import json, os, sys, time
d, host, t = sys.argv[1:4]; now = int(time.time()); os.makedirs(d + "/machines", exist_ok=True)
w = lambda p, o: json.dump(o, open("%s/%s" % (d, p), "w"))
w("machines/%s.json" % host, {"machine": host, "synced": now})
w("machines/west.json", {"machine": "west", "synced": now})
w("registry/local-west-tools-abc123.west.json", {"id": "local-west-tools-abc123", "name": "tools", "root": "~/tools"})
w("registry/github.com_you_api.west.json", {"id": "github.com/you/api", "name": "api", "root": "~/api"})
for sid, m in (("R1", "west"), ("R2", host + "-2")):
    w("sessions/%s-%s.json" % (m, sid), {"session_id": sid, "machine": m, "repo": "github.com/you/api", "cwd": "/x", "name": "api on " + m,
      "pid": 4242, "procStart": "1", "uds": "/x", "bridge": "session_" + sid, "started": now, "seen": now, "role": ""})
PY
before=$(others)

out=$("$B" init --machine laptop --owner Robin)
echo "$out" | has -x "  records  moved from the machine name $HOST to laptop: holds 1, links 1, machines 1, registry 2, roles 2, sessions 2, subs 1, tasks 1" \
  && ! echo "$out" | has "^Note:" && ok "init says in one line which records it moved from the old machine name to the new one" || die "init: $out"
[ -z "$(cd "$D" && ls registry/*."$HOST".json "sessions/$HOST-W1.json" "sessions/$HOST-A1.json" "machines/$HOST.json" "tasks/web--frontend/cursor-$HOST.json" 2>/dev/null)" ] \
  && [ "$(pj 'd["id"]' "$D/registry/$WEB.laptop.json")" = "$WEB" ] && [ -f "$D/registry/github.com_you_api.laptop.json" ] \
  && [ "$(pj 'd["machine"]' "$D/sessions/laptop-W1.json")" = laptop ] && [ "$(pj 'd["machine"]' "$D/tasks/web--frontend/cursor-laptop.json")" = laptop ] \
  && [ -f "$D/subs/github.com_you_api.auto.laptop.json" ] && [ "$(pj 'd["machine"]' "$D/links/$L.json")" = laptop ] \
  && [ "$(cat "$D"/roles/*.json | grep -c "\"$HOST\"")" = 0 ] && grep -l "\"abs:laptop:$T/outside\"" "$D"/holds/*.json >/dev/null \
  && ok "registry and auto watch records are renamed, sessions, stamps and cursors get the new name, roles, links and abs: holds too; web keeps its id" \
  || die "moved: $(cd "$D" && ls registry sessions machines subs; cat roles/*.json)"
[ "$(others)" = "$before" ] && ok "another machine's records, and one whose name starts with this one's and a dash, are left as they are" \
  || die "others: $(others)"
[ -z "$(git -C "$D" status --porcelain -- registry sessions roles links holds subs machines tasks)" ] \
  && ok "a board init has just made a git repo holds the moved records in its first commit" || die "commit: $(git -C "$D" status --porcelain | head -5)"

# ---- after init, with no new session start: the role is there for who and for a task, the holds refuse, the watch
# fires, the task web had read stays read, and status has no row for the old name
"$B" who > "$T/who"; has "^laptop \+web \+role=frontend \+to=uds:$T/sock.$PW" < "$T/who" && has "^laptop \+api \+role=backend " < "$T/who" \
  && ! has "^$HOST " < "$T/who" && ok "who shows both sessions under the new name with their roles, and no row under the old one" || die "who: $(cat "$T/who")"
T2=$(SWITCHBOARD_SESSION_ID=A1 "$B" task request --to web:frontend --subject "client: two" --key k2 --body two 2>&1 | awk '{print $1}')
[ -d "$D/tasks/web--frontend/$T2" ] && [ "$(pj 'd["worker"]["repo"]' "$D/tasks/web--frontend/$T2/000-request.json")" = "$WEB" ] \
  && ok "a task request to web:frontend from an open session reaches web's id" || die "request: $T2"
notes=$(hook PostToolUse "$T/web" W1 Read '{}' | ctx)
echo "$notes" | has "a task for you (you hold web:frontend): $T2" && ! echo "$notes" | has "a task for you .*: $T1" \
  && ok "web's session is told of the new task, and not again of the one it read before init" || die "notes: $notes"
pre PreToolUse "$T/web" W1 x1 Write "{\"file_path\":\"$T/web/src/a.py\",\"content\":\"x\"}" | has '"deny"' \
  && pre PreToolUse "$T/web" W1 x2 Write "{\"file_path\":\"$T/outside/b.txt\",\"content\":\"x\"}" | has '"deny"' \
  && ok "the hold in web and the hold outside HOME still refuse an edit" || die "holds: $(cat "$D"/holds/*.json)"
echo 2 > "$T/web/schema.json"; hook Stop "$T/web" W1 >/dev/null
hook PostToolUse "$T/api" A1 Read '{}' | ctx | has "schema.json content changed" && ok "the watch on web's file still fires for api" \
  || die "watch: $(ls "$D/events")"
"$B" status > "$T/status"; has "machines: laptop synced 0m ago; west synced 0m ago$" < "$T/status" \
  && has "repos here 2 .* live sessions 2 " < "$T/status" && ok "status shows the stamp under the new name, west's, and no row for the old name" \
  || die "status: $(cat "$T/status")"

# ---- init with the same name moves nothing
before=$(recs); out=$("$B" init --update --machine laptop)
! echo "$out" | has "records" && [ "$(recs)" = "$before" ] && ok "init with the same machine name moves nothing" || die "same name: $out"

# ---- a repo known only under another machine's name: the config file edited by hand, so init moved nothing
python3 - "$HOME/.config/switchboard/config.json" <<'PY'
import json, sys; d = json.load(open(sys.argv[1])); d["machine"] = "edited"; json.dump(d, open(sys.argv[1], "w"))
PY
out=$(SWITCHBOARD_SESSION_ID=A1 "$B" task request --to web:frontend --subject "client: three" --key k3 --body three 2>&1 || true)
echo "$out" | has -xF "switchboard: repo 'web' is not registered under this machine's name, edited; the board has it under the machine name laptop as $WEB. Name it by that id to reach it there. Nothing was written." \
  && { "$B" read --repo tools 2>&1 || true; } | has -F "repo 'tools' is not registered under this machine's name, edited; the board has it under the machine name west as local-west-tools-abc123." \
  && { "$B" read --repo nosuch 2>&1 || true; } | has -xF "switchboard: unknown repo 'nosuch'" \
  && ok "a repo known only under another machine name is named with that name and its id, not as unregistered" \
  || die "elsewhere: $out $("$B" read --repo tools 2>&1) $("$B" read --repo nosuch 2>&1)"

# ---- a name keys/allowed_signers gives to a key this machine does not have is another machine's: nothing moves
mkdir -p "$D/keys"; ssh-keygen -q -t ed25519 -N "" -f "$T/westkey" -C west
echo "west namespaces=\"switchboard-task\" $(cut -d' ' -f1,2 "$T/westkey.pub")" > "$D/keys/allowed_signers"
before=$(recs); out=$(SWITCHBOARD_MACHINE=west "$B" init --update --machine box5)
echo "$out" | has -x "  records  left under west: keys/allowed_signers has that name with a key this machine does not have, so they are another machine's" \
  && [ "$(recs)" = "$before" ] && ok "init run under a name another machine's key holds moves none of that machine's records" || die "guard: $out"

finish
