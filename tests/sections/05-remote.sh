#!/usr/bin/env bash
# remote sessions: liveness unknown
source "$(dirname "$0")/../lib.sh"
fx_delta

mkrepo "$T/theta"
# shellcheck disable=SC2034  # THETA is read by lib.sh's remote()
THETA=$("$B" register "$T/theta" | tail -1 | awk '{print $NF}')
remote R1 "theta ghost" 72000
n=$(ls "$SWITCHBOARD_DIR/links" | wc -l)
out=$(SWITCHBOARD_SESSION_ID=S5 "$B" link --from "$T/delta:lead" --to "$T/theta:runner" --scope "remote test" --covers "remote test" 2>&1) && die "remote sole candidate was bound" || true
echo "$out" | has "to=bridge:session_R1.*liveness unknown" && [ "$(ls "$SWITCHBOARD_DIR/links" | wc -l)" -eq "$n" ] && ok "a remote session alone in the repo is listed, never picked" || die "remote ghost handling wrong: $out"
remote R2 "theta @runner" 60
out=$(SWITCHBOARD_SESSION_ID=S5 "$B" link --from "$T/delta:lead" --to "$T/theta:runner" --scope "remote test" --covers "remote test" 2>&1) && die "remote tagged session was bound" || true
echo "$out" | has "session_R2" && ok "a remote @tag does not bind on its own" || die "remote tag handling wrong: $out"
SWITCHBOARD_SESSION_ID=S5 "$B" link --from "$T/delta:lead" --to "$T/theta:runner" --scope "remote test" --covers "remote test" --to-session bridge:session_R2 | has 'theta:runner bound to "theta @runner" to=bridge:session_R2' && ok "--to-session binds a remote address on Robin's say" || die "--to-session did not bind the remote"
"$B" who "$T/theta" --role runner | has "west .*role=runner .*to=bridge:session_R2 .*last seen 20.*liveness unknown" && ok "board who prints a remote row with its address and says liveness is unknown" || die "who wording: $("$B" who "$T/theta")"
! hook PreToolUse "$T/delta" S5 SendMessage '{"to":"bridge:session_R2","message":"go"}' | has "end open" && ok "a send to an end bound on another machine is not refused as open" || die "remote-bound end refused"
"$B" links | grep "remote test" | has "theta:runner (bound on west, last seen 20.*liveness unknown)" && ok "board links says where a remote end is bound, when it was last seen and that liveness is unknown" || die "links wording: $("$B" links)"
# one writer per record: the role file alone carries a binding
RF=$(ls "$SWITCHBOARD_DIR"/roles/*theta*--runner.json); cp "$RF" "$T/runner.role"; R2F="$SWITCHBOARD_DIR/sessions/west-R2.json"
python3 - "$R2F" <<'PY2'
import json,sys; r=json.load(open(sys.argv[1])); r["role"]="runner"; json.dump(r,open(sys.argv[1],"w"))   # as west itself would have published it
PY2
h0=$(shasum "$R2F"); PT=$(fake ST1 "$T/theta" "theta local"); hook SessionStart "$T/theta" ST1 >/dev/null
SWITCHBOARD_SESSION_ID=ST1 "$B" role runner --take >/dev/null
[ "$(shasum "$R2F")" = "$h0" ] && "$B" who "$T/theta" --role runner | has "to=uds:$T/sock.$PT" && ! "$B" who "$T/theta" --role runner | has session_R2 && "$B" who "$T/theta" | has "role=- .*session_R2" && ok "a bind that displaces a remote holder leaves its session file alone, and lookups follow the role file" || die "remote displaced: $("$B" who "$T/theta")"
cp "$T/runner.role" "$RF"   # west moved the end back; this machine's session learns it from the role file
"$B" who "$T/theta" | has "role=- .*sock.$PT" && grep -q '"role": "runner"' "$SWITCHBOARD_DIR/sessions/east-ST1.json" || die "setup: stale field expected before the publish"
hook UserPromptSubmit "$T/theta" ST1 >/dev/null
grep -q '"role": ""' "$SWITCHBOARD_DIR/sessions/east-ST1.json" && ok "a session that lost its binding clears its own role field at its next publish" || die "stale role kept: $(cat "$SWITCHBOARD_DIR/sessions/east-ST1.json")"
kill $PT; wait $PT 2>/dev/null || true
out=$(hook SessionStart "$T/delta" S5)
echo "$out" | has 'theta:runner at .*bridge:session_R2.* (bound on west, last seen 20.*liveness unknown)' && ! echo "$out" | has "days ago" && ok "the holder note gives a remote counterpart the same wording, and no way-out line while it was seen lately" || die "holder note: $out"
remote R2 "theta @runner" 400000
out=$(hook UserPromptSubmit "$T/delta" S5)
echo "$out" | has "theta:runner is bound on west and was last seen 20.*more than 3 days ago" && echo "$out" | has "board bind" && echo "$out" | has "board unlink" && ok "a remote end not seen for 3 days adds one line naming board bind and board unlink" || die "no 3-day line: $out"
! hook UserPromptSubmit "$T/delta" S5 | has "days ago" && ok "the 3-day line appears once per session" || die "3-day line repeated"
remote R2 "theta @runner" 60
remote R3 "theta old" 400000; "$B" who "$T/theta" | has "1 remote rows not seen for 3 days are hidden" && ! "$B" who "$T/theta" | has session_R3 && ok "old remote rows are hidden as a display cutoff, and the listing says so" || die "display cutoff: $("$B" who "$T/theta")"
SWITCHBOARD_SESSION_ID=S5 "$B" link --from "$T/delta:lead" --to "$T/theta:idle" --scope "open by choice" --covers "open by choice" --to-session open | has "theta:idle open" && ok "--to-session open creates the link with that end open" || die "--to-session open failed"

finish
