#!/usr/bin/env bash
# key expiry
source "$(dirname "$0")/../lib.sh"
fx_delta_eps; fx_key; NOW=$(date +%s)
git -C "$SWITCHBOARD_DIR" init -q -b main; git -C "$SWITCHBOARD_DIR" config user.email t@t; git -C "$SWITCHBOARD_DIR" config user.name t   # key ages come from the git log

AS="$SWITCHBOARD_DIR/keys/allowed_signers"; PUB=$(cat "$HOME/.ssh/switchboard_east.pub"); ymd(){ python3 -c "import time,sys; print(time.strftime('%Y%m%d', time.gmtime(int(sys.argv[1]))))" "$1"; }
KO=$(SWITCHBOARD_NOW=$((NOW - 10*86400)) SWITCHBOARD_SESSION_ID=S5 "$B" task request --to "$T/eps:builder" --subject "key old" --key k-old 2>/dev/null | awk '{print $1}')
KN=$(SWITCHBOARD_SESSION_ID=S5 "$B" task request --to "$T/eps:builder" --subject "key new" --key k-new 2>/dev/null | awk '{print $1}')
VB=$(ymd $((NOW - 5*86400))); VD="${VB:0:4}-${VB:4:2}-${VB:6:2}"
echo "east namespaces=\"switchboard-task\",valid-before=\"$VB\" $PUB" > "$AS"
"$B" task "$KN" | has -x "  key expired $VD" && "$B" task "$KN" --json | has "\"signature\": \"key expired $VD\"" && ok "a key whose valid-before has passed makes a fresh request show key expired" || die "expired key: $("$B" task "$KN" | sed -n 5p)"
"$B" task "$KO" | has -x "  signed by east" && ok "a request made inside the key's window still shows signed: verification uses the request's time" || die "old request: $("$B" task "$KO" | sed -n 5p)"
"$B" status | has -x "key east: valid to $VD (expired), installed 0m ago (not committed)" && ok "board status shows a key's window, and when it has passed" || die "status window: $("$B" status | grep '^key')"
echo "east namespaces=\"switchboard-task\" $PUB" > "$AS"
ssh-keygen -q -t ed25519 -N "" -f "$T/k2" -C k2; echo "west namespaces=\"switchboard-task\",valid-before=\"20991231\" $(cat "$T/k2.pub")" >> "$AS"
git -C "$SWITCHBOARD_DIR" add keys/allowed_signers && GIT_AUTHOR_DATE="@$((NOW - 100*86400))" GIT_COMMITTER_DATE="@$((NOW - 100*86400))" git -C "$SWITCHBOARD_DIR" commit -qm "keys" -- keys/allowed_signers
echo "west namespaces=\"switchboard-task\",valid-before=\"20991231\" $(cat "$T/k2.pub")" > "$T/k2.line"; ssh-keygen -q -t ed25519 -N "" -f "$T/k3" -C k3
echo "east namespaces=\"switchboard-task\" $PUB" > "$AS"; echo "west namespaces=\"switchboard-task\",valid-before=\"20991231\" $(cat "$T/k3.pub")" >> "$AS"; git -C "$SWITCHBOARD_DIR" commit -qm "rotate west" -- keys/allowed_signers
out=$("$B" status | grep '^key'); echo "$out" | has -x "key east: no expiry, installed 100d ago (WARN: older than 90 days)" && echo "$out" | has -x "key west: valid to 2099-12-31, installed 0m ago" && ok "a key with no expiry shows its age from the git log, with a warning past 90 days; a fresh key has none" || die "status keys: $out"

finish
