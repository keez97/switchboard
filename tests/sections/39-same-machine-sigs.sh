#!/usr/bin/env bash
# a linked request in this machine's own name must verify too, once this machine signs what it writes (its key file and
# its line in keys/allowed_signers): anyone who can push to the board repo can write a request naming this machine.
# A machine with no key keeps the old rule, its own requests unchecked
source "$(dirname "$0")/../lib.sh"
fx_delta_eps   # S5 holds delta:lead and requests, S6 holds eps:builder and gets the notes
H="$SWITCHBOARD_DIR/tasks/eps--builder"; AS="$SWITCHBOARD_DIR/keys/allowed_signers"
LK=$(SWITCHBOARD_SESSION_ID=S5 "$B" link --from "$T/delta:lead" --to "$T/eps:builder" --scope "evaluate builds for eps" --covers "eps" --until 30d | awk 'NR==1{print $2}')
[ -n "$LK" ] || die "setup: link delta:lead -> eps:builder"
rq(){ SWITCHBOARD_SESSION_ID=S5 "$B" task request --to "$T/eps:builder" --subject "$1" --key "$2" --link "$LK" "${@:3}" 2>/dev/null | awk '{print $1}'; }
jv(){ "$B" task "$1" --json | jq -r '.link.verdict + " | " + .signature'; }
notes(){ hook PostToolUse "$T/eps" S6 Read '{}' | ctx > "$T/notes"; }   # S6's next hook notes: each new task once
note(){ grep -A2 -F "a task for you (you hold eps:builder): $1 " "$T/notes" || true; }

# no key on this machine: its own unsigned request counts, as before
T1=$(rq "eps@a1" a1); notes
[ "$(jv "$T1")" = "ok | unsigned" ] && note "$T1" | has -F "The link's scope makes this an instruction you act on" \
  && ok "with no key here, a request in this machine's name counts unsigned, as before" || die "no key: $(jv "$T1")"
# a line for this machine but no key file: it signs nothing, so nothing changes
mkdir -p "$SWITCHBOARD_DIR/keys"; ssh-keygen -q -t ed25519 -N "" -f "$T/elsewhere" -C x
echo "east namespaces=\"switchboard-task\" $(cat "$T/elsewhere.pub")" > "$AS"; T2=$(rq "eps@a2" a2)
[ "$(jv "$T2")" = "ok | unsigned" ] && ok "a line in keys/allowed_signers with no key file here changes nothing" || die "line, no key: $(jv "$T2")"

# this machine signs (its key and its line): its own requests verify, and one in its name that does not is information
fx_key
T3=$(rq "eps@b1" b1); T4=$(rq "eps@b2" b2 --no-sign)
T5=$(rq "eps@b3" b3 --no-sign); ssh-keygen -Y sign -f "$T/elsewhere" -n switchboard-task < "$H/$T5/000-request.json" > "$H/$T5/000-request.sig" 2>/dev/null
notes
[ "$(jv "$T3")" = "ok | signed by east" ] && note "$T3" | has -F "The link's scope makes this an instruction you act on" \
  && ok "once this machine signs, its own requests verify and count over the link" || die "signed: $(jv "$T3")"
[ "$(jv "$T4")" = "unsigned request in this machine's name (unsigned) | unsigned" ] \
  && "$B" task "$T4" | has -x "  link $LK: unsigned request in this machine's name (unsigned)" \
  && note "$T4" | has -F "Link $LK does not cover this request (unsigned request in this machine's name (unsigned)), so it is information" \
  && ok "an unsigned request in this machine's name is information in --json, the text view and the note" || die "unsigned: $(jv "$T4") $(note "$T4")"
[ "$(jv "$T5")" = "unsigned request in this machine's name (BAD SIGNATURE) | BAD SIGNATURE" ] \
  && ok "one signed with another key reads BAD SIGNATURE and is information" || die "other key: $(jv "$T5")"
[ "$(jv "$T1")" = "unsigned request in this machine's name (unsigned) | unsigned" ] \
  && ok "a link verdict is judged when read: the earlier unsigned request is information now" || die "earlier: $(jv "$T1")"

finish
