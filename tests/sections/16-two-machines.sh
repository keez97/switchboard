#!/usr/bin/env bash
# two machines, one remote
source "$(dirname "$0")/../lib.sh"
mkrepo "$T/eps"; fx_key   # a worker repo and this machine's signing key

# To cover a new record kind: add its dir to KINDS and one line to put().
KINDS="events holds tasks"; LOG="links/lshared.log.jsonl"
git init -q --bare -b main "$T/two.git"; git clone -q "$T/two.git" "$T/seed" 2>/dev/null
( cd "$T/seed" && mkdir -p links && echo '*.jsonl merge=union' > .gitattributes && echo '{"line":"seed"}' > "$LOG" && git add -A && git -c user.email=t@t -c user.name=t commit -qm seed && git push -q origin HEAD:main )
for m in east west; do git clone -q "$T/two.git" "$T/clone-$m"; git -C "$T/clone-$m" config user.email t@t; git -C "$T/clone-$m" config user.name "$m"; done
on(){ local m=$1; shift; SWITCHBOARD_DIR="$T/clone-$m" SWITCHBOARD_STATE="$T/state-$m" SWITCHBOARD_MACHINE="$m" SWITCHBOARD_NOSYNC='' "$@"; }   # run a command as that machine
put(){ # machine tag -> one record of every kind and one log line for the shared link
  local d="$T/clone-$1"; mkdir -p "$d/events" "$d/holds" "$d/links"
  echo "{\"id\":\"e-$1-$2\",\"machine\":\"$1\"}" > "$d/events/e-$1-$2.json"
  echo "{\"id\":\"h-$1-$2\",\"machine\":\"$1\"}" > "$d/holds/h-$1-$2.json"
  mkdir -p "$d/tasks/w-shared--r" && echo "{\"machine\":\"$1\",\"polled\":\"$2\",\"seen\":{}}" > "$d/tasks/w-shared--r/cursor-$1.json"   # mutable, one writer per machine
  mkdir -p "$d/tasks/w-$1-$2--r/t-$1-$2" && echo "{\"id\":\"t-$1-$2\",\"machine\":\"$1\"}" > "$d/tasks/w-$1-$2--r/t-$1-$2/000-request.json" && echo '{"seq": 1}' > "$d/tasks/w-$1-$2--r/t-$1-$2/001-working.json"
  echo "{\"line\":\"$1-$2\",\"machine\":\"$1\"}" >> "$d/$LOG"; }
syncw(){ rm -f "$T/state-$1/sync.ok"; on "$1" "$B" sync; waitfor "$T/state-$1/sync.ok"; }
listing(){ (cd "$T/clone-$1" && find $KINDS -type f | sort; sort "$LOG"); }
converged(){ # tag -> both clones hold every record and both log lines of this round, and nothing is left half done
  [ "$(listing east)" = "$(listing west)" ] || return 1
  python3 -c "import json,sys; [json.loads(l) for l in open(sys.argv[1])]" "$T/clone-east/$LOG" 2>/dev/null || return 1   # a merge without union leaves conflict markers in the log
  for m in east west; do
    for k in $KINDS; do [ "$(find "$T/clone-east/$k" -mindepth 1 -maxdepth 1 -name "*-$m-$1*" | grep -c .)" -eq 1 ] || return 1; done
    grep -q "\"$m-$1\"" "$T/clone-west/$LOG" || return 1
    [ ! -e "$T/clone-$m/.git/rebase-merge" ] && [ ! -e "$T/clone-$m/.git/rebase-apply" ] && [ -z "$(git -C "$T/clone-$m" status --porcelain)" ] || return 1
    on "$m" "$B" status | grep "last successful push 20" | has -v "NOT RECOVERED" || return 1
  done
  [ "$(git -C "$T/clone-east" rev-parse HEAD)" = "$(git -C "$T/clone-west" rev-parse HEAD)" ]; }
put east r1; put west r1; syncw east; syncw west; syncw east
converged r1 && ok "two machines write records and a log line for the same link, sync east first, and both clones end identical" || die "two-clone sync, east first: $(listing east | tr '\n' ' ') vs $(listing west | tr '\n' ' ') $(on east "$B" status | tail -1) $(on west "$B" status | tail -1)"
[ -f "$T/clone-east/machines/east.json" ] && [ -f "$T/clone-east/machines/west.json" ] && on east "$B" status | has "machines: east synced .* ago; west synced .* ago" && ok "each sync stamps its machine hourly and status shows both" || die "machine stamps: $(ls "$T/clone-east/machines" 2>&1) $(on east "$B" status | tail -1)"
syncw east; [ -f "$T/state-east/sync-job.lock" ] && ! held "$T/state-east/sync-job.lock" && ok "a finished sync job leaves its lock file and no lock on it" || die "sync lock still held"
hold "$T/state-east/sync-job.lock" 5; rm -f "$T/state-east/sync.ok"; on east "$B" sync; sleep 3; [ ! -f "$T/state-east/sync.ok" ] && kill -0 "$HOLDER" 2>/dev/null && ok "a lock held by a live job makes the next sync step aside" || die "live lock ignored"
kill "$HOLDER"; wait "$HOLDER" 2>/dev/null || true
put east r2; put west r2; syncw west; syncw east; syncw west
converged r2 && converged r1 && ok "the other order converges too, with no rebase left and a successful push shown on both" || die "two-clone sync, west first: $(listing east | tr '\n' ' ') vs $(listing west | tr '\n' ' ')"
# a signed request through two clones; the owner installs keys/allowed_signers by a commit of their own
mkdir -p "$T/clone-east/keys" && cp "$SWITCHBOARD_DIR/keys/allowed_signers" "$T/clone-east/keys/" && git -C "$T/clone-east" add keys && git -C "$T/clone-east" commit -qm keys && git -C "$T/clone-east" push -q origin HEAD:main
on east "$B" register "$T/eps" >/dev/null; RT=$(cd "$T" && on east "$B" task request --to "$T/eps:builder" --subject "round trip" --key rt1 2>/dev/null | awk '{print $1}')
syncw east; syncw west
[ -f "$T/clone-west/tasks/eps--builder/$RT/000-request.sig" ] && on west "$B" task "$RT" | has -x "  signed by east" && perl -pi -e 's/round trip/round trip!/' "$T/clone-west/tasks/eps--builder/$RT/000-request.json" && on west "$B" task "$RT" | has -x "  BAD SIGNATURE" && ok "a request signed on one machine verifies on the other after sync, and a change on the way shows BAD SIGNATURE" || die "signed round trip: $(on west "$B" task "$RT")"
git -C "$T/clone-west" checkout -q -- "tasks/eps--builder/$RT/000-request.json"

finish
