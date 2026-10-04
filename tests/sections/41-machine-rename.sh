#!/usr/bin/env bash
# a machine renamed by init: the first session starts register and publish under the hostname's name, then init picks
# another. This machine's records move to the new name and a repo with no remote keeps its id, so the open sessions
# keep their roles, holds, watches and tasks with no new start. init with the same name moves nothing, another
# machine's records never move, and a repo known only under another machine's name is named as such
source "$(dirname "$0")/../lib.sh"
unset SWITCHBOARD_MACHINE   # the hostname's name, until init writes the config file
HOST=$(python3 -c "import platform,re; print(re.sub(r'[^a-z0-9]+','-',platform.node().split('.')[0].lower()).strip('-') or 'machine')")
for n in laptop west oak elm ash box5; do [ "$HOST" != $n ] || die "setup: the hostname is a name this section uses"; done
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
L=$(SWITCHBOARD_SESSION_ID=A1 "$B" link --from "$T/api:backend" --to "$T/web:frontend" --scope "client" --covers "client" | awk 'NR==1{print $2}')
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

# ---- F-001: a rename keeps the machine's key, so the owner's key line for the new name vouches that both names are
# one machine; requests made over agent links under the old name count again. First a machine with no key (laptop,
# its key from the first init put aside), then oak with a key the owner lists, renamed to elm (the key reused), then
# elm renamed as 0.6.0 did it, with a new key (ash)
setmachine(){ python3 - "$HOME/.config/switchboard/config.json" "$1" <<'PY'
import json, sys; d = json.load(open(sys.argv[1])); d["machine"] = sys.argv[2]; json.dump(d, open(sys.argv[1], "w"))
PY
}
setmachine laptop; mkdir -p "$T/aside" "$D/keys"; mv "$HOME"/.ssh/switchboard_laptop* "$T/aside/"
AS="$D/keys/allowed_signers"; : > "$AS"; S="$HOME/.ssh"
export SWITCHBOARD_TEST_PROPOSE=1
seat P1 "$T/api" "api lead"; seat P2 "$T/web" "web builder"; seat P3 "$T/api" "api lead2"; seat P4 "$T/web" "web builder2"
seat P5 "$T/api" "api no role"
for s in "P1 api lead" "P2 web builder" "P3 api lead2" "P4 web builder2"; do set -- $s
  hook SessionStart "$T/$2" $1 >/dev/null; SWITCHBOARD_SESSION_ID=$1 "$B" role $3 >/dev/null; done
hook SessionStart "$T/api" P5 >/dev/null
alink(){ local l; l=$(SWITCHBOARD_SESSION_ID=$1 "$B" link --from "$T/api:$2" --to "$T/web:$4" --scope "fix" --covers "fix" 2>/dev/null | awk 'NR==1{print $2}')
  SWITCHBOARD_SESSION_ID=$3 "$B" link accept "$l" >/dev/null 2>&1; echo "$l"; }
LA=$(alink P1 lead P2 builder); LB=$(alink P3 lead2 P4 builder2)
[ "$(pj 'd["state"]' "$D/links/$LA.json")" = active ] && [ "$(pj 'd["state"]' "$D/links/$LB.json")" = active ] \
  || die "setup: agent links $LA $LB not active"
rqf(){ # session worker-role subject key [link]: a task request (its key apart from the ones above); its id
  SWITCHBOARD_SESSION_ID=$1 "$B" task request --to "web:$2" --subject "$3" --key "f001-$4" ${5:+--link "$5"} 2>/dev/null | awk '{print $1}'; }
tf(){ echo "$D/tasks/$(basename "$(dirname "$(ls -d "$D"/tasks/*/"$1")")")/$1"; }   # a task's folder
jv(){ "$B" task "$1" --json | python3 -c "import json,sys; print(json.load(sys.stdin)['link']['verdict'])"; }
js(){ "$B" task "$1" --json | python3 -c "import json,sys; print(json.load(sys.stdin)['signature'])"; }
note(){ # session tid: that worker session's next note for the task, from its first line on
  hook PostToolUse "$T/web" "$1" Read '{}' | ctx | grep -A3 -F ": $2 " || true; }
info(){ has -F "does not cover this request ($1), so it is information"; }
instr(){ has -F "The link's scope makes this an instruction you act on"; }
wk(){ # tid session: wakes_for for a change event on the task, with that session's presence record and no role
  python3 - "$B" "$1" "$D/sessions/$(python3 -c "import json; print(json.load(open('$HOME/.config/switchboard/config.json'))['machine'])")-$2.json" <<'PY'
import importlib.machinery, importlib.util, json, sys
l = importlib.machinery.SourceFileLoader("sb", sys.argv[1]); m = importlib.util.module_from_spec(importlib.util.spec_from_loader("sb", l))
l.exec_module(m); print(m.wakes_for({"kind": "task", "target": "task:" + sys.argv[2]}, dict(json.load(open(sys.argv[3])), role=""), "other"))
PY
}
forge(){ # tid machine seat-machine [key]: the request rewritten in machine's name with that seat machine, signed with key
  python3 - "$(tf "$1")/000-request.json" "$2" "$3" <<'PY'
import json, sys; f, m, s = sys.argv[1:4]; r = json.load(open(f)); r["machine"] = m; r["seat"]["machine"] = s
open(f, "w").write(json.dumps(r, indent=1, sort_keys=True) + "\n")
PY
  rm -f "$(tf "$1")/000-request.sig"
  [ -z "${4:-}" ] || ssh-keygen -Y sign -f "$4" -n switchboard-task < "$(tf "$1")/000-request.json" > "$(tf "$1")/000-request.sig" 2>/dev/null; }
ssh-keygen -q -t ed25519 -N "" -f "$T/otherk" -C other; ssh-keygen -q -t ed25519 -N "" -f "$T/westk" -C west

# keyless: laptop signs nothing, so its requests over links are lost to a rename; init lists the open ones
K1=$(rqf P1 builder "fix: k1" k1 "$LA"); K2=$(rqf A1 frontend "client: k2" k2 "$L");
[ "$(jv "$K1")" = ok ] && [ "$(jv "$K2")" = ok ] && [ "$(js "$K1")" = unsigned ] || die "setup: keyless requests $(jv "$K1") $(jv "$K2")"
out=$("$B" init --update --machine oak)
echo "$out" | has -F "  tasks    2 open, requested over a link under laptop, a name keys/allowed_signers has no key of this machine's for, so they now count as information" \
  && echo "$out" | has -x "           $K1  fix: k1" && echo "$out" | has -x "           $K2  client: k2" \
  && [ "$(jv "$K2")" = "unsigned request from another machine (unsigned)" ] \
  && [ "$(jv "$K1")" = "requester is not the session that agreed to the link" ] \
  && ok "a rename with no key: init lists the open linked tasks under the old name; over the owner link they read (unsigned), over the agent link the seat fails" \
  || die "keyless: $(jv "$K1") / $(jv "$K2") / $out"
[ "$(pj 'd["state"]' "$D/links/$LA.json")" = active ] && [ "$(pj 'd["proposed_by"]["machine"]' "$D/links/$LA.json")" = oak ] \
  || die "setup: $LA after the rename: $(cat "$D/links/$LA.json")"
echo "oak namespaces=\"switchboard-task\" $(cut -d' ' -f1,2 "$S/switchboard_oak.pub")" > "$AS"   # the owner adds oak's line

# oak, with a key the owner lists, renamed to elm: the key is reused
R1=$(rqf P1 builder "fix: r1" r1 "$LA"); R2=$(rqf P3 builder2 "fix: r2" r2 "$LB"); R3=$(rqf P1 builder "fix: r3" r3 "$LA")
R4=$(rqf A1 frontend "client: r4" r4 "$L"); R5=$(rqf P5 builder "plain r5" r5)
[ "$(js "$R1")" = "signed by oak" ] && [ "$(jv "$R1")" = ok ] && [ "$(wk "$R5" P5)" = True ] || die "setup: oak's requests $(js "$R1") $(jv "$R1")"
out=$("$B" init --update --machine elm)
[ "$S/switchboard_elm" -ef "$S/switchboard_oak" ] && cmp -s "$S/switchboard_elm.pub" "$S/switchboard_oak.pub" \
  && [ -f "$S/switchboard_oak" ] && echo "$out" | has -x "  key      ~/.ssh/switchboard_elm (the key of oak, linked from ~/.ssh/switchboard_oak)" \
  && echo "$out" | has -F "elm namespaces=\"switchboard-task\" $(cut -d' ' -f1,2 "$S/switchboard_oak.pub")" \
  && ! echo "$out" | has "^  tasks " && ! echo "$out" | has "lists this machine's key for" \
  && ok "a rename links the old key and its .pub to the new name, leaves the old one, and the printed key line for the new name carries it" \
  || die "reuse: $(ls -li "$S"); $out"
[ "$(pj 'd["state"]' "$D/links/$LA.json")" = active ] && [ "$(pj 'd["accepted_by"]["machine"]' "$D/links/$LB.json")" = elm ] \
  || die "setup: links after the rename: $(cat "$D/links/$LA.json")"
[ "$(jq -c .accepted_by.covers "$D/links/$LB.json")" = '["fix"]' ] && ok "the rename keeps the covers list stamped on the acceptance" \
  || die "stamp after the rename: $(cat "$D/links/$LB.json")"
n=$(note P2 "$R1")
[ "$(jv "$R1")" = "requester is not the session that agreed to the link" ] && echo "$n" | info "requester is not the session that agreed to the link" \
  && [ "$(wk "$R5" P5)" = False ] \
  && ok "before the owner adds the new name's line: the old requests fail the seat check, the worker's note is information, no wake" \
  || die "before the line: $(jv "$R1") / $n"
echo "* namespaces=\"switchboard-task\" $(cut -d' ' -f1,2 "$S/switchboard_oak.pub")" >> "$AS"
[ "$(jv "$R3")" = "requester is not the session that agreed to the link" ] \
  && ok "a * line with the same key makes no name an alias" || die "star: $(jv "$R3")"
echo "oak namespaces=\"switchboard-task\" $(cut -d' ' -f1,2 "$S/switchboard_oak.pub")" > "$AS"
echo "elm namespaces=\"switchboard-task\" $(cut -d' ' -f1,2 "$S/switchboard_elm.pub")" >> "$AS"   # the owner adds elm's line
n=$(note P4 "$R2")
[ "$(jv "$R2")" = ok ] && [ "$(js "$R2")" = "signed by oak" ] && echo "$n" | has -F ": $R2 " && echo "$n" | instr \
  && [ "$(jv "$R1")" = ok ] && [ "$(wk "$R5" P5)" = True ] \
  && ok "after the owner adds elm's line with the same key: the old requests are ok and signed by oak, the note is an instruction, the requester is woken" \
  || die "after the line: $(jv "$R2") $(js "$R2") / $n"
cp -R "$D" "$T/west-board"
wv=$(SWITCHBOARD_DIR="$T/west-board" SWITCHBOARD_STATE="$T/west-state" SWITCHBOARD_MACHINE=west "$B" task "$R1" --json \
  | python3 -c "import json,sys; d=json.load(sys.stdin); print(d['link']['verdict'], d['signature'])")
[ "$wv" = "ok signed by oak" ] && ok "a second machine with a copy of the board agrees" || die "west: $wv"

# forgeries naming oak, and west copying the seat
F1=$(rqf P1 builder "fix: f1" f1 "$LA"); forge "$F1" oak oak
F2=$(rqf P1 builder "fix: f2" f2 "$LA"); forge "$F2" oak oak "$T/otherk"
echo "west namespaces=\"switchboard-task\" $(cut -d' ' -f1,2 "$T/westk.pub")" >> "$AS"
F3=$(rqf P1 builder "fix: f3" f3 "$LA"); forge "$F3" west oak "$T/westk"
F4=$(rqf P1 builder "fix: f4" f4 "$LA"); forge "$F4" west elm "$T/westk"
[ "$(jv "$F1")" = "unsigned request from another machine (unsigned)" ] \
  && [ "$(jv "$F2")" = "unsigned request from another machine (BAD SIGNATURE)" ] \
  && ok "a request forged in oak's name with the agreeing seat: unsigned reads (unsigned), signed with another key (BAD SIGNATURE)" \
  || die "forged: $(jv "$F1") / $(jv "$F2")"
[ "$(js "$F3")" = "signed by west" ] && [ "$(jv "$F3")" = "the request's seat names another machine" ] \
  && [ "$(jv "$F4")" = "the request's seat names another machine" ] \
  && ok "west, with its own key, copying the seat under the old or the new name is refused" || die "west copies: $(jv "$F3") / $(jv "$F4")"
N1=$(rqf P1 builder "fix: n1" n1 "$LA")
[ "$(jv "$N1")" = ok ] && [ "$(js "$N1")" = "signed by elm" ] && ok "a new request after the rename is ok, signed by elm" || die "new: $(jv "$N1") $(js "$N1")"
grep -v "^oak " "$AS" > "$T/as" && cat "$T/as" > "$AS"   # the owner deletes oak's line
[ "$(js "$R1")" = "BAD SIGNATURE" ] && [ "$(jv "$R1")" = "requester is not the session that agreed to the link" ] \
  && [ "$(jv "$R4")" = "unsigned request from another machine (BAD SIGNATURE)" ] && [ "$(jv "$N1")" = ok ] \
  && ok "with oak's line deleted its requests read BAD SIGNATURE: no alias over the agent link, (BAD SIGNATURE) over the owner link" \
  || die "oak deleted: $(js "$R1") $(jv "$R1") / $(jv "$R4")"

# elm renamed as 0.6.0 did it: a new key for ash. The owner command that adds ash with elm's key is printed, never run
E1=$(rqf P3 builder2 "fix: e1" e1 "$LB")
ssh-keygen -q -t ed25519 -N "" -f "$S/switchboard_ash" -C ash
out=$("$B" init --update --machine ash)
echo "ash namespaces=\"switchboard-task\" $(cut -d' ' -f1,2 "$S/switchboard_ash.pub")" >> "$AS"   # the owner adds ash's new key
st=$("$B" status); EL="ash namespaces=\"switchboard-task\" $(cut -d' ' -f1,2 "$S/switchboard_elm.pub")"
fix=$(echo "$st" | grep -A1 -F "lists this machine's key for elm, and not for ash" | tail -1 || true)
[ "$(js "$E1")" = "signed by elm" ] && [ "$(jv "$E1")" = "requester is not the session that agreed to the link" ] \
  && echo "$out" | has -F "lists this machine's key for elm, and not for ash" && echo "$out" | has -F "$EL" \
  && echo "$fix" | has -F "$EL" && [ "$(echo "$st" | grep -c "lists this machine's key for")" = 1 ] && ! grep -qF "$EL" "$AS" \
  && ok "a 0.6.0-style rename: the old requests fail the seat check; init and status print the one command that adds ash with elm's key" \
  || die "0.6.0 rename: $(jv "$E1") / $out / $st"
bash -c "$fix" && [ "$(jv "$E1")" = ok ] && ! "$B" status | has "lists this machine's key for" \
  && ok "once the owner runs it the old requests are ok, and status prints it no more" || die "recovered: $(jv "$E1"); $(cat "$AS")"
unset SWITCHBOARD_TEST_PROPOSE

# ---- a key init cannot give the new name: init still finishes the move and leaves no partial key file
cfg(){ python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["machine"])' "$HOME/.config/switchboard/config.json"; }
cp "$S/switchboard_ash" "$T/ash.key"; chmod 000 "$S/switchboard_ash"   # ash's key unreadable, and no hard links
out=$(SWITCHBOARD_TEST_NOLINK=1 "$B" init --update --machine fir 2>&1) && rc=0 || rc=$?
chmod 600 "$S/switchboard_ash"
[ "$rc" = 0 ] && ! echo "$out" | has Traceback && echo "$out" | has "^switchboard: the key of ash was not given to fir (Permission denied" \
  && [ "$(cfg)" = fir ] && [ -f "$D/machines/fir.json" ] && [ ! -e "$D/machines/ash.json" ] \
  && [ -s "$S/switchboard_fir" ] && ssh-keygen -y -f "$S/switchboard_fir" >/dev/null 2>&1 && ! cmp -s "$S/switchboard_fir" "$T/ash.key" \
  && ! ls -a "$S" | grep -q '\.tmp$' && echo "$out" | has -x "  key      ~/.ssh/switchboard_fir (made now)" \
  && ok "an unreadable old key: init says so in one line, leaves no empty key file, makes a new key and moves the records" \
  || die "unreadable key: rc $rc; $(cfg); $(ls -la "$S"); $out"
chmod 500 "$S"   # ~/.ssh not writable
out=$("$B" init --update --machine gum 2>&1) && rc=0 || rc=$?
chmod 700 "$S"
[ "$rc" = 0 ] && ! echo "$out" | has Traceback && echo "$out" | has "^switchboard: the key of fir was not given to gum (Permission denied" \
  && [ "$(cfg)" = gum ] && [ -f "$D/machines/gum.json" ] && [ ! -e "$D/machines/fir.json" ] && [ ! -e "$S/switchboard_gum" ] \
  && echo "$out" | has -x "  key      none" && echo "$out" | has "^  records  moved from the machine name fir to gum" \
  && ok "~/.ssh not writable: init finishes, the config and the records both say the new name, and it says there is no key" \
  || die "read-only ~/.ssh: rc $rc; $(cfg); $(ls "$D/machines"); $out"

# ---- the new name's .pub must match the key placed, or ssh-keygen -Y sign refuses and every request goes unsigned
ssh-keygen -q -t ed25519 -N "" -f "$S/switchboard_gum" -C gum
pubok(){ [ ! -L "$S/switchboard_$1.pub" ] && [ "$(cut -d' ' -f1,2 "$S/switchboard_$1.pub")" = "$(ssh-keygen -y -f "$S/switchboard_$1" | cut -d' ' -f1,2)" ]; }
signs(){ echo "$1 namespaces=\"switchboard-task\" $(cut -d' ' -f1,2 "$S/switchboard_$1.pub")" >> "$AS"
  [ "$(js "$(rqf P5 builder "plain $1" "pub-$1")")" = "signed by $1" ]; }
cp "$T/otherk.pub" "$S/switchboard_hob.pub"   # a stale .pub of another key at the new name
out=$("$B" init --update --machine hob 2>&1)
[ "$S/switchboard_hob" -ef "$S/switchboard_gum" ] && pubok hob && signs hob && ! echo "$out" | has "not given\|not written" \
  && echo "$out" | has -x "  key      ~/.ssh/switchboard_hob (the key of gum, linked from ~/.ssh/switchboard_gum)" \
  && ok "a stale .pub at the new name is replaced by the placed key's, and the new name's requests are signed" \
  || die "stale .pub: $(ls -l "$S"); $out"
echo VICTIM > "$T/victim"; ln -s "$T/victim" "$S/switchboard_ivy.pub"   # a symlink there, to a file of someone's
out=$("$B" init --update --machine ivy 2>&1)
[ "$(cat "$T/victim")" = VICTIM ] && pubok ivy && signs ivy && ! echo "$out" | has "not given\|not written" \
  && ok "a symlink at the new name's .pub is replaced, never written through: its target is left as it is" \
  || die "symlink .pub: $(cat "$T/victim"); $(ls -l "$S"); $out"
chmod 000 "$S/switchboard_ivy.pub"   # the old .pub unreadable, and no hard links
out=$(SWITCHBOARD_TEST_NOLINK=1 "$B" init --update --machine jay 2>&1)
chmod 644 "$S/switchboard_ivy.pub"
! echo "$out" | has "not given\|not written" && echo "$out" | has -x "  key      ~/.ssh/switchboard_jay (the key of ivy, copied from ~/.ssh/switchboard_ivy)" \
  && pubok jay && signs jay && ! ls -a "$S" | grep -q '\.tmp$' \
  && ok "an unreadable old .pub with no hard links: the .pub is read from the key copied, and init and stderr agree the key was given" \
  || die "unreadable .pub: $(ls -la "$S"); $out"
# a temporary file another run left where this run's own would go is never removed
r=$(python3 - "$B" <<'PY'
import importlib.machinery, importlib.util, os, sys
l = importlib.machinery.SourceFileLoader("sb", sys.argv[1]); m = importlib.util.module_from_spec(importlib.util.spec_from_loader("sb", l))
l.exec_module(m); s = m.HOME / ".ssh"
def nolink(*a, **k):
    raise OSError(18, "no hard links")
os.link = nolink
theirs = [s / (".switchboard_kim%s.%d.tmp" % (x, os.getpid())) for x in ("", ".pub")]
for f in theirs:
    f.write_text("another run's file\n")
r = m.reuse_key("jay", "kim")
print(r, all(f.exists() and f.read_text() == "another run's file\n" for f in theirs))
for f in theirs:
    f.exists() and f.unlink()
PY
)
[ "$r" = "copied from ~/.ssh/switchboard_jay True" ] && cmp -s "$S/switchboard_kim" "$S/switchboard_jay" && pubok kim \
  && ok "another run's temporary file where this run's would go is left as it is, and the key and .pub are still placed" \
  || die "their tmp: $r; $(ls -la "$S")"

# ---- a name keys/allowed_signers gives to a key this machine does not have is another machine's: nothing moves
mkdir -p "$D/keys"; ssh-keygen -q -t ed25519 -N "" -f "$T/westkey" -C west
echo "west namespaces=\"switchboard-task\" $(cut -d' ' -f1,2 "$T/westkey.pub")" > "$D/keys/allowed_signers"
before=$(recs); out=$(SWITCHBOARD_MACHINE=west "$B" init --update --machine box5)
echo "$out" | has -x "  records  left under west: keys/allowed_signers has that name with a key this machine does not have, so they are another machine's" \
  && [ "$(recs)" = "$before" ] && ok "init run under a name another machine's key holds moves none of that machine's records" || die "guard: $out"

finish
