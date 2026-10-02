#!/usr/bin/env bash
# sync outcome
source "$(dirname "$0")/../lib.sh"
fx_delta_eps   # S5 (delta:lead) requests, S6 holds eps:builder
TID=$(SWITCHBOARD_SESSION_ID=S5 "$B" task request --to "$T/eps:builder" --subject "app@abc123" --key k1 | awk '{print $1}'); TD="$SWITCHBOARD_DIR/tasks/eps--builder/$TID"
SWITCHBOARD_SESSION_ID=S6 "$B" task working "$TID" >/dev/null; SWITCHBOARD_SESSION_ID=S6 "$B" task completed "$TID" >/dev/null; [ -f "$TD/002-completed.json" ] || die "setup: task not completed"
echo '[]' > "$SWITCHBOARD_DIR/defaults.json"; mkdir -p "$SWITCHBOARD_DIR/archive/2026-01/events"; echo '{"id":"e-old"}' > "$SWITCHBOARD_DIR/archive/2026-01/events/e-old.json"   # removed below

git init -q --bare -b main "$T/remote.git"; git -C "$SWITCHBOARD_DIR" init -q -b main; git -C "$SWITCHBOARD_DIR" config user.email t@t; git -C "$SWITCHBOARD_DIR" config user.name t
git -C "$SWITCHBOARD_DIR" remote add origin "$T/remote.git"; git -C "$SWITCHBOARD_DIR" commit -q --allow-empty -m init; git -C "$SWITCHBOARD_DIR" push -q -u origin main
SWITCHBOARD_NOSYNC='' "$B" sync; waitfor "$SWITCHBOARD_STATE/sync.ok"
[ -n "$(git -C "$T/remote.git" log --oneline -1 --grep 'switchboard: east')" ] && "$B" status | has "last successful push 20" && ok "a sync pushes to the tracked remote and status shows when" || die "push not recorded: $("$B" status)"
binit "$SWITCHBOARD_DIR"; echo '{"half": ' > "$TD/.000-request.json.tmp1"; echo '{"half": ' > "$TD/.002-completed.json.tmp1"; rm -f "$SWITCHBOARD_STATE/sync.ok"
SWITCHBOARD_NOSYNC='' "$B" sync; waitfor "$SWITCHBOARD_STATE/sync.ok"
git -C "$T/remote.git" ls-tree -r main --name-only | has "tasks/eps--builder/$TID/002-completed.json" && [ -z "$(git -C "$T/remote.git" ls-tree -r main --name-only | grep '\.tmp1$')" ] && ok "sync carries task records and never stages a half-written record's temp file" || die "tmp staged: $(git -C "$T/remote.git" ls-tree -r main --name-only | grep tasks/)"
rm -rf "$SWITCHBOARD_DIR/archive" "$SWITCHBOARD_DIR/defaults.json"; echo '{"id":"e-missing"}' > "$SWITCHBOARD_DIR/events/e-missing.json"; rm -f "$SWITCHBOARD_STATE/sync.ok"
SWITCHBOARD_NOSYNC='' "$B" sync; waitfor "$SWITCHBOARD_STATE/sync.ok"
[ -n "$(git -C "$T/remote.git" ls-tree -r main --name-only | grep events/e-missing.json)" ] && [ -z "$(git -C "$T/remote.git" ls-tree -r main --name-only | grep -e '^archive/' -e defaults.json)" ] && ! "$B" status | has "last failure" && ok "a board missing a synced dir still commits and pushes a new event, and removals are carried" || die "missing dir stopped the commit: $("$B" status)"
echo x > "$SWITCHBOARD_DIR/events/e-unreadable.json"; chmod 000 "$SWITCHBOARD_DIR/events/e-unreadable.json"; echo '{"id":"h2"}' > "$SWITCHBOARD_DIR/holds/h2.json"
SWITCHBOARD_NOSYNC='' "$B" sync; waitfor "$SWITCHBOARD_STATE/sync.fail"
"$B" status | has "last failure .*NOT RECOVERED.*git add events" && [ -n "$(git -C "$T/remote.git" ls-tree -r main --name-only | grep holds/h2.json)" ] && ok "a staging failure is a recorded failure in status, and the other paths still go out" || die "staging failure not shown: $("$B" status)"
rm -f "$SWITCHBOARD_DIR/events/e-unreadable.json" "$SWITCHBOARD_STATE/sync.fail"
git -C "$SWITCHBOARD_DIR" remote set-url origin "$T/gone.git"; echo x > "$SWITCHBOARD_DIR/holds/x.json"
SWITCHBOARD_NOSYNC='' "$B" sync; waitfor "$SWITCHBOARD_STATE/sync.fail"
"$B" status | has "last failure .*NOT RECOVERED" && ok "a failed push is retried, recorded with its reason and shown in status" || die "failed push not shown: $("$B" status)"

finish
