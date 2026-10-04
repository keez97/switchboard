#!/usr/bin/env bash
# the CLI checks who is calling
source "$(dirname "$0")/../lib.sh"
fx_delta_eps

n=$(ls "$SWITCHBOARD_DIR/links"/*.json | wc -l)
out=$(SWITCHBOARD_SESSION_ID=S6 "$B" link --from "$T/delta:lead" --to "$T/eps:builder" --scope "not mine" --covers "not mine" 2>&1) && die "link from another repo's role was created" || true
echo "$out" | has "refused. Acting as delta:lead needs a session in that repo; this session is in eps" && [ "$(ls "$SWITCHBOARD_DIR/links"/*.json | wc -l)" -eq "$n" ] && ok "link --from with another repo's role exits non-zero with the reason and writes nothing" || die "foreign --from: $out"
seat SD2 "$T/delta" "second in delta"; hook SessionStart "$T/delta" SD2 >/dev/null
out=$(SWITCHBOARD_SESSION_ID=SD2 "$B" link --from "$T/delta:lead" --to "$T/eps:builder" --scope "not mine either" --covers "not mine either" 2>&1) && die "link in a role held by another session was created" || true
echo "$out" | has 'delta:lead is held by another session ("planner")' && "$B" who "$T/delta" --role lead | has "sock.$P5" && ok "a session in the right repo cannot act as a role another session holds, and the holder keeps it" || die "same-repo impostor: $out"
SWITCHBOARD_SESSION_ID=SD2 "$B" link --from "$T/delta:scout" --to "$T/eps:builder" --scope "taking it now" --covers "taking it now" | has 'delta:scout bound to "second in delta"' && ok "from the caller's own repo it works as before, taking a free role in the same command" || die "own-repo link failed"

finish
