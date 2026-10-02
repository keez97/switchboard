#!/usr/bin/env bash
# End-to-end check of bin/board. Runs every section in tests/sections/, each in its own throwaway HOME and board,
# and keeps going after a failure. Prints each section's checks, then every failure, the pass count and the failure
# count; exits 1 on any failure.
#   tests/selftest.sh                 every section
#   tests/selftest.sh tasks cursor    the sections named (04-binding.sh, binding and 04 all name the same file)
#   JOBS=1 tests/selftest.sh          one section at a time (default: 4 at once)
#   KEEP=1 tests/selftest.sh ...      keep each section's throwaway dir
set -uo pipefail
D="$(cd "$(dirname "$0")" && pwd)/sections"
files=()
if [ $# -eq 0 ]; then
  files=("$D"/*.sh)
else
  for want in "$@"; do
    hit=""; for f in "$D"/*.sh; do
      if [[ $(basename "$f") =~ ^(${want%.sh}\.sh|[0-9]+-${want%.sh}\.sh|${want%.sh}-.*\.sh)$ ]]; then hit=$(basename "$f"); break; fi
    done
    [ -n "$hit" ] || { echo "selftest: no section $want (have: $(ls "$D" | sed 's/\.sh$//' | tr '\n' ' '))"; exit 2; }
    files+=("$D/$hit")
  done
fi
OUT="$(mktemp -d)"; trap 'rm -rf "$OUT"' EXIT
run(){ bash "$1" > "$OUT/$(basename "$1").log" 2>&1; echo $? > "$OUT/$(basename "$1").rc"; }
jobs_max=${JOBS:-4}; start=$(date +%s)
for f in "${files[@]}"; do
  while [ "$(jobs -rp | wc -l)" -ge "$jobs_max" ]; do wait -n 2>/dev/null || true; done
  run "$f" &
done
wait
pass=0; fail=0; failures=()
for f in "${files[@]}"; do
  n=$(basename "$f"); log="$OUT/$n.log"; rc=$(cat "$OUT/$n.rc" 2>/dev/null || echo 99)
  echo "== ${n%.sh}"
  grep -E "^  (ok|FAIL) |^kept " "$log" || true
  p=$(grep -c "^  ok " "$log"); x=$(grep -c "^  FAIL " "$log")
  pass=$((pass + p)); fail=$((fail + x))
  while IFS= read -r l; do failures+=("${n%.sh}: ${l#  FAIL }"); done < <(grep "^  FAIL " "$log")
  [ "$x" = 0 ] || grep -v -E '^  (ok|FAIL) |^kept |^T=' "$log" | tail -8 | sed 's/^/    | /'   # stderr of a failing section
  if [ "$rc" != 0 ] && [ "$x" = 0 ]; then   # stopped by a command that failed outside any check
    fail=$((fail + 1)); failures+=("${n%.sh}: stopped with exit $rc after $p checks: $(grep -v -E '^  (ok|FAIL) ' "$log" | tail -3 | tr '\n' ' ')")
    echo "  FAIL stopped with exit $rc"
  fi
done
echo
for l in "${failures[@]+"${failures[@]}"}"; do echo "FAIL $l"; done
echo "selftest: $pass passed, $fail failed, ${#files[@]} sections, $(( $(date +%s) - start ))s"
[ "$fail" -eq 0 ] && echo "selftest: all passed"
[ "$fail" -eq 0 ]
