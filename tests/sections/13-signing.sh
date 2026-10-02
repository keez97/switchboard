#!/usr/bin/env bash
# signed requests
source "$(dirname "$0")/../lib.sh"
fx_delta_eps; fx_holder SE2b   # S5 (delta:lead) requests, SE2b holds eps:builder

sreq(){ SWITCHBOARD_SESSION_ID=S5 "$B" task request --to "$T/eps:builder" "$@" 2>"$T/err" | awk '{print $1}'; }
G0=$(sreq --subject "no key" --key g0)
grep -qx "switchboard: no signing key at ~/.ssh/switchboard_east; the request is unsigned" "$T/err" && [ ! -e "$SWITCHBOARD_DIR/tasks/eps--builder/$G0/000-request.sig" ] && "$B" task "$G0" | has -x "  unsigned" && ok "with no key a request is unsigned, says so on stderr once, and shows unsigned" || die "no key: $(cat "$T/err")"
mkdir -p "$HOME/.ssh" "$SWITCHBOARD_DIR/keys"; ssh-keygen -q -t ed25519 -N "" -f "$HOME/.ssh/switchboard_east" -C selftest
echo "east namespaces=\"switchboard-task\" $(cat "$HOME/.ssh/switchboard_east.pub")" > "$SWITCHBOARD_DIR/keys/allowed_signers"   # the owner's file; the CLI never writes keys/
G1=$(sreq --subject "signed" --key g1); GD="$SWITCHBOARD_DIR/tasks/eps--builder/$G1"
[ ! -s "$T/err" ] && head -1 "$GD/000-request.sig" | has -x -- "-----BEGIN SSH SIGNATURE-----" && ssh-keygen -Y verify -f "$SWITCHBOARD_DIR/keys/allowed_signers" -I east -n switchboard-task -s "$GD/000-request.sig" < "$GD/000-request.json" >/dev/null 2>&1 && "$B" task "$G1" | has -x "  signed by east" && ok "with a key the request's bytes are signed into 000-request.sig and verify with ssh-keygen as eval-worker does" || die "signed: $(cat "$T/err"); $("$B" task "$G1")"
"$B" task "$G1" >/dev/null && ! "$B" tasks --for "$T/eps:builder" | has "BAD RECORD" && "$B" tasks --for "$T/eps:builder" --open | has -x "$G1" && SWITCHBOARD_SESSION_ID=SE2b "$B" task working "$G1" | has "001 working" && ok "a .sig is never a bad record: show, list, --open and a transition all pass" || die "sig as record: $("$B" task "$G1")"
G2=$(sreq --subject "not signed" --key g2 --no-sign)
[ ! -s "$T/err" ] && [ ! -e "$SWITCHBOARD_DIR/tasks/eps--builder/$G2/000-request.sig" ] && "$B" task "$G2" | has -x "  unsigned" && ok "--no-sign writes no signature and no stderr line" || die "--no-sign: $(cat "$T/err")"
cp "$GD/000-request.json" "$T/req.bak"; perl -pi -e 's/"subject": "signed"/"subject": "signed!"/' "$GD/000-request.json"
out=$("$B" task "$G1"); echo "$out" | has -x "  BAD SIGNATURE" && echo "$out" | has "^$G1  working" && [ -f "$GD/000-request.sig" ] && ok "a tampered request shows BAD SIGNATURE; the signature stays and the state is unchanged" || die "tampered: $out"
cp "$T/req.bak" "$GD/000-request.json"; "$B" task "$G1" | has -x "  signed by east" || die "restore after tamper"
mv "$SWITCHBOARD_DIR/keys/allowed_signers" "$T/as.bak"; "$B" task "$G1" | has -x "  signed, not verified: no keys/allowed_signers on this machine" && mv "$T/as.bak" "$SWITCHBOARD_DIR/keys/allowed_signers" && ok "a machine without keys/allowed_signers shows signed, not verified" || die "no allowed_signers"

# ---- the namespace: every request is signed with switchboard-task. Verification takes either namespace, so a request
# signed with agent-board-task, before the rename, still reads signed by its machine. ssh-keygen -Y verify checks the
# line's namespaces="..." as well as the key: a line must list the namespace a request was signed in
AS="$SWITCHBOARD_DIR/keys/allowed_signers"; PUB=$(cat "$HOME/.ssh/switchboard_east.pub")
nsof(){ for n in agent-board-task switchboard-task; do   # the namespace a .sig was made in, checked by ssh-keygen itself
  ssh-keygen -Y check-novalidate -n "$n" -s "$1/000-request.sig" < "$1/000-request.json" >/dev/null 2>&1 && echo "$n"; done; }
nsig(){ local k; k=$(sreq --subject "ns $1" --key "ns$1"); echo "$SWITCHBOARD_DIR/tasks/eps--builder/$k"; }   # a signed request's folder
oldsig(){ # a request signed by hand with agent-board-task, as the CLI signed before the rename; its folder
  local k; k=$(sreq --subject "old $1" --key "old$1" --no-sign); local d="$SWITCHBOARD_DIR/tasks/eps--builder/$k"
  ssh-keygen -Y sign -f "$HOME/.ssh/switchboard_east" -n agent-board-task < "$d/000-request.json" > "$d/000-request.sig" 2>/dev/null; echo "$d"; }
[ "$(nsof "$GD")" = switchboard-task ] && ok "a request is signed with switchboard-task and verifies against a line listing it" || die "new: $(nsof "$GD")"
echo "east namespaces=\"agent-board-task,switchboard-task\" $PUB" > "$AS"; OD=$(oldsig both)
[ "$(nsof "$OD")" = agent-board-task ] && "$B" task "$(basename "$OD")" | has -x "  signed by east" && "$B" task "$G1" | has -x "  signed by east" \
  && ok "a line listing both: a request signed with agent-board-task before the rename verifies, and so does a new one" || die "old ns: $(nsof "$OD"); $("$B" task "$(basename "$OD")" | tail -1)"
echo "east namespaces=\"agent-board-task\" $PUB" > "$AS"; D=$(nsig narrow)
[ "$(nsof "$D")" = switchboard-task ] && "$B" task "$(basename "$D")" | has -x "  BAD SIGNATURE" && "$B" task "$(basename "$OD")" | has -x "  signed by east" \
  && ok "a line listing only agent-board-task: a new request is still signed with switchboard-task and reads BAD SIGNATURE; the old one verifies" \
  || die "narrow: $(nsof "$D"); $("$B" task "$(basename "$D")" | tail -1)"
case_ns(){ # label line...: keys/allowed_signers holds the lines; a new request is signed in switchboard-task and reads signed by east
  local label=$1 D; shift; printf '%s\n' "$@" > "$AS"; D=$(nsig "$label")
  [ "$(nsof "$D")" = switchboard-task ] && "$B" task "$(basename "$D")" | has -x "  signed by east" && ok "$label: signed with switchboard-task and verifies" \
    || die "$label: signed with '$(nsof "$D")', $("$B" task "$(basename "$D")" | tail -1)"; }
case_ns "a quoted principal list, valid-before before namespaces" "\"west,east\" valid-before=\"20991231\",namespaces=\"agent-board-task,switchboard-task\" $PUB"
case_ns "an unquoted principal list, switchboard-task listed first, valid-after last" "west,east namespaces=\"switchboard-task,agent-board-task\",valid-after=\"20200101\" $PUB"
case_ns "a line with no namespaces= option" "east $PUB"
: > "$AS"; D=$(nsig noline); [ "$(nsof "$D")" = switchboard-task ] && ok "no line for this machine: signed with switchboard-task" || die "no line: $(nsof "$D")"
rm "$AS"; D=$(nsig nofile); [ "$(nsof "$D")" = switchboard-task ] && ok "no keys/allowed_signers: signed with switchboard-task" || die "no file: $(nsof "$D")"

# ---- two machines sharing one board through a bare repo, each with its own HOME and key
git init -q --bare -b main "$T/ns.git"
for m in east west; do
  mkdir -p "$T/h-$m/.ssh" "$T/h-$m/.claude/sessions"; ssh-keygen -q -t ed25519 -N "" -f "$T/h-$m/.ssh/switchboard_$m" -C "$m"
  git clone -q "$T/ns.git" "$T/c-$m" 2>/dev/null; git -C "$T/c-$m" config user.email t@t; git -C "$T/c-$m" config user.name "$m"; done
on(){ local m=$1; shift; HOME="$T/h-$m" SWITCHBOARD_DIR="$T/c-$m" SWITCHBOARD_STATE="$T/s-$m" SWITCHBOARD_MACHINE="$m" "$@"; }
lines(){ for m in east west; do echo "$m namespaces=\"$1\" $(cat "$T/h-$m/.ssh/switchboard_$m.pub")"; done; }
push(){ git -C "$T/c-$1" add "${@:2}" && git -C "$T/c-$1" commit -qm "$1" -- "${@:2}" && git -C "$T/c-$1" push -q origin HEAD:main; }
pull(){ git -C "$T/c-$1" pull -q --rebase origin main; }
treq(){ (cd "$T" && on "$1" "$B" task request --to "$T/eps:builder" --subject "two $2" --key "two$2" "${@:3}" 2>/dev/null) | awk '{print $1}'; }
tf(){ echo "$T/c-$1/tasks/eps--builder/$2"; }
mkdir -p "$T/c-east/keys"; lines switchboard-task > "$T/c-east/keys/allowed_signers"; for m in east west; do on $m "$B" register "$T/eps" >/dev/null; done   # eps has no remote: each machine registers its own
push east keys registry; pull west; push west registry; pull east
R1=$(treq east 1); push east tasks; pull west
R2=$(treq west 2); push west tasks; pull east
[ "$(nsof "$(tf west "$R1")")" = switchboard-task ] && on west "$B" task "$R1" | has -x "  signed by east" \
  && [ "$(nsof "$(tf east "$R2")")" = switchboard-task ] && on east "$B" task "$R2" | has -x "  signed by west" \
  && ssh-keygen -Y verify -f "$T/c-east/keys/allowed_signers" -I west -n switchboard-task -s "$(tf east "$R2")/000-request.sig" < "$(tf east "$R2")/000-request.json" >/dev/null 2>&1 \
  && ok "two machines with lines listing switchboard-task: each signs with it and the other verifies it" \
  || die "two: $(nsof "$(tf west "$R1")") / $(on west "$B" task "$R1" | tail -1) / $(on east "$B" task "$R2" | tail -1)"
# a request east signed with agent-board-task before the rename: west verifies it once the shared lines list both
R3=$(treq east 3 --no-sign); ssh-keygen -Y sign -f "$T/h-east/.ssh/switchboard_east" -n agent-board-task < "$(tf east "$R3")/000-request.json" > "$(tf east "$R3")/000-request.sig" 2>/dev/null
lines agent-board-task,switchboard-task > "$T/c-east/keys/allowed_signers"; push east keys tasks; pull west
[ "$(nsof "$(tf west "$R3")")" = agent-board-task ] && on west "$B" task "$R3" | has -x "  signed by east" && on west "$B" task "$R1" | has -x "  signed by east" \
  && ok "lines listing both: a request signed with agent-board-task on the other machine still verifies, beside the new ones" \
  || die "two old: $(nsof "$(tf west "$R3")") / $(on west "$B" task "$R3" | tail -1)"

finish
