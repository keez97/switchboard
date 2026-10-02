#!/usr/bin/env bash
# machine-readable reads
source "$(dirname "$0")/../lib.sh"
fx_delta_eps; fx_repos zeta; fx_holder SE2b; fx_key   # S5 (delta:lead) requests, SE2b holds eps:builder
rq(){ SWITCHBOARD_SESSION_ID=S5 "$B" task request --to "$T/eps:builder" --subject "$1" --key "$2" 2>/dev/null | awk '{print $1}'; }
G1=$(rq signed g1); SWITCHBOARD_SESSION_ID=SE2b "$B" task working "$G1" >/dev/null
for k in o1 o2 o3; do rq "open $k" "$k" >/dev/null; done; SWITCHBOARD_SESSION_ID=SE2b "$B" task seen "$(rq "open o1" o1)" >/dev/null
CUR="$SWITCHBOARD_DIR/tasks/eps--builder/cursor-east.json"; [ -f "$CUR" ] || die "setup: no cursor at eps:builder"

SWITCHBOARD_SESSION_ID=S5 "$B" task cancel "$G1" --note "stop" >/dev/null; SWITCHBOARD_SESSION_ID=SE2b "$B" task input-required "$G1" --note "need a key" >/dev/null
"$B" task "$G1" --json > "$T/g1.json"; txt=$("$B" task "$G1")
python3 - "$T/g1.json" "$G1" "$CUR" <<'PY2' && echo "$txt" | has "^$G1  input-required (cancel requested)  signed$" && echo "$txt" | has -x "  signed by east" && ok "board task --json parses and matches the text view: state, cancel flag, signature, seen, two transitions" || die "task --json: $(cat "$T/g1.json")"
import json,sys; j=json.load(open(sys.argv[1])); tid=sys.argv[2]; cur=json.load(open(sys.argv[3]))
t=j["transitions"]
ok = (j["id"]==tid and j["state"]=="input-required" and j["cancel_requested"] is True and j["subject"]=="signed" and j["key"]=="g1"
      and j["signature"]=="signed by east" and j["worker"]=={"repo":j["worker"]["repo"],"role":"builder","name":"eps"} and j["requester"]["name"]=="delta"
      and j["requester"]["role"]=="lead" and j["machine"]=="east" and j["session"]=="S5" and j["bad_records"]==[]
      and [x["seq"] for x in t]==[1,2] and [x["state"] for x in t]==["working","input-required"] and t[1]["note"]=="need a key"
      and t[1]["waiting_on"]=="robin" and t[0]["artifacts"]==[] and t[1]["session"]=="SE2b"
      and j["seen"]=={m:v for m,v in {"east":cur["seen"].get(tid)}.items() if v})
sys.exit(0 if ok else 1)
PY2
"$B" tasks --for "$T/eps:builder" --open --json > "$T/open.json"; "$B" tasks --for "$T/eps:builder" --open > "$T/open.txt"
python3 -c "import json,sys; a=json.load(open(sys.argv[1])); ids=open(sys.argv[2]).read().split(); sys.exit(0 if [x['id'] for x in a]==ids and len(ids)>2 and all(x['state']=='submitted' for x in a) and [x['ts'] for x in a]==sorted(x['ts'] for x in a) else 1)" "$T/open.json" "$T/open.txt" && [ "$("$B" tasks --for "$T/zeta:tester" --open --json)" = "[]" ] && [ "$("$B" tasks --for "$T/eps:builder" --open --unseen --json | python3 -c "import json,sys; print(' '.join(x['id'] for x in json.load(sys.stdin)))")" = "$("$B" tasks --for "$T/eps:builder" --open --unseen | tr '\n' ' ' | sed 's/ $//')" ] && ok "tasks --open --json is the --open list as a JSON array, oldest first; [] on nothing; --unseen still narrows" || die "--open --json: $(cat "$T/open.json" | head -5)"

finish
