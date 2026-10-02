#!/usr/bin/env bash
# holds at git push: the pre-push hook refuses a push whose commits touch a held path, and install-prepush chains
# to a hook already there and respects core.hooksPath
source "$(dirname "$0")/../lib.sh"
cap_procs   # it runs pre-push hooks: one that ran itself would stop at the cap
ln -s "$B" "$HOME/.claude/board"   # the hook runs the state dir's cli link or ~/.claude/board; here, with no session start, the latter
Z40=0000000000000000000000000000000000000000
gc(){ git -C "$1" -c user.email=t@t -c user.name=t "${@:2}"; }
remote_main(){ git -C "$T/$1.git" rev-parse -q --verify "refs/heads/${2:-main}" || true; }
fx_repos app other
for r in app other; do git init -q --bare -b main "$T/$r.git"; git -C "$T/$r" remote add origin "$T/$r.git"; done
mkdir -p "$T/app/src" "$T/app/docs"; echo a > "$T/app/src/a.py"; echo b > "$T/app/src/b.py"; echo d > "$T/app/docs/d.md"
gc "$T/app" add -A; gc "$T/app" commit -qm base; git -C "$T/app" push -q -u origin main 2>/dev/null
gc "$T/app" checkout -q -b side; echo c > "$T/app/src/c.py"; gc "$T/app" add -A; gc "$T/app" commit -qm "side, before any hold"
git -C "$T/app" push -q origin side 2>/dev/null; gc "$T/app" checkout -q main

"$B" install-prepush "$T/app" | has -x "installed the switchboard pre-push hook in $T/app/.git/hooks" && [ -x "$T/app/.git/hooks/pre-push" ] && [ ! -e "$T/app/.git/hooks/pre-push.agent-board-chained" ] \
  && ok "install-prepush writes the hook into the repo's own hooks dir" || die "install: $(ls -la "$T/app/.git/hooks")"
HID=$("$B" hold "$T/app/src" --until 2d --reason "eval running" | awk '{print $2}')
echo a2 >> "$T/app/src/a.py"; gc "$T/app" commit -qam "touch held"; C1=$(git -C "$T/app" rev-parse --short=10 HEAD)
out=$(git -C "$T/app" push origin main 2>&1) && die "a push touching a held path went through" || true
echo "$out" | has "switchboard hold $HID: repo:.*:src is frozen until 20[0-9-]* [0-9:]*\. Reason: eval running\. This push (refs/heads/main) changes src/a.py in commit $C1\. Nothing was pushed" \
  && [ "$(remote_main app)" != "$(git -C "$T/app" rev-parse HEAD)" ] && ok "a push whose commit touches a held path is refused, naming the hold, its date, its reason, the file and the commit" || die "held push: $out"
sam=$(SWITCHBOARD_OWNER=Sam git -C "$T/app" push origin main 2>&1) || true
unset_=$(env -u SWITCHBOARD_OWNER git -C "$T/app" push origin main 2>&1) || true   # no config file: the default owner
echo "$sam" | has "tell Sam if this blocks you" && ! echo "$sam" | has Robin && echo "$out" | has "tell Robin if this blocks you" \
  && echo "$unset_" | has "tell the user if this blocks you" \
  && ok "the refusal names the owner from SWITCHBOARD_OWNER, the default (the user) when unset" || die "owner: $sam / $unset_"
gc "$T/app" reset -q --hard origin/main; echo d2 >> "$T/app/docs/d.md"; gc "$T/app" commit -qam docs
git -C "$T/app" push -q origin main 2>/dev/null && [ "$(remote_main app)" = "$(git -C "$T/app" rev-parse HEAD)" ] && ok "a push that touches no held path goes through" || die "unrelated push refused"
git -C "$T/app" push -q origin main:refs/heads/copy 2>/dev/null && [ -n "$(remote_main app copy)" ] && ok "a new branch holding only commits the remote has goes through, though its history touched the held path" || die "new branch of known commits refused"
gc "$T/app" checkout -q -b feature; echo b2 >> "$T/app/src/b.py"; gc "$T/app" commit -qam "feature touches held"
! git -C "$T/app" push -q origin feature 2>/dev/null && [ -z "$(remote_main app feature)" ] && ok "a new branch with a commit touching the held path is refused" || die "new branch pushed"
git -C "$T/app" push -q origin :copy 2>/dev/null && [ -z "$(remote_main app copy)" ] && ok "deleting a remote branch is never refused" || die "delete refused"
gc "$T/app" checkout -q main; echo m > "$T/app/docs/m.md"; gc "$T/app" add -A; gc "$T/app" commit -qm main2; gc "$T/app" merge -q --no-edit origin/side
git -C "$T/app" push -q origin main 2>/dev/null && [ "$(remote_main app)" = "$(git -C "$T/app" rev-parse HEAD)" ] && ok "a merge that brings in commits the remote already has goes through, though they touched the held path" || die "merge of pushed commits refused"
gc "$T/app" checkout -q -b notes origin/main; echo n > "$T/app/docs/n.md"; gc "$T/app" add -A; gc "$T/app" commit -qm notes; gc "$T/app" checkout -q main
gc "$T/app" merge -q --no-commit notes; echo edited-in-merge >> "$T/app/src/a.py"; gc "$T/app" add -A; gc "$T/app" commit -qm "merge notes, editing src"
out=$(git -C "$T/app" push origin main 2>&1) && die "a merge that edits a held file went through" || true
echo "$out" | has "changes src/a.py in commit $(git -C "$T/app" rev-parse --short=10 HEAD)" && ok "a merge that itself edits a held file is refused" || die "evil merge: $out"
gc "$T/app" reset -q --hard origin/main
gc "$T/app" worktree add -q "$T/app-wt" -b wt origin/main 2>/dev/null; echo w >> "$T/app-wt/src/a.py"; gc "$T/app-wt" commit -qam "from a worktree"
out=$(git -C "$T/app-wt" push origin wt 2>&1) && die "a worktree push touching the held path went through" || true
echo "$out" | has "hold $HID: .*changes src/a.py" && ok "a push from a linked worktree is judged against the main checkout's holds" || die "worktree push: $out"
"$B" release "$HID" >/dev/null
git -C "$T/app-wt" push -q origin wt 2>/dev/null && git -C "$T/app" push -q origin feature 2>/dev/null && ok "after the hold is released the same pushes go through" || die "still refused after release"
HF=$("$B" hold "$T/app/src/a.py" --until 1h --reason "one file" | awk '{print $2}')
gc "$T/app" checkout -q main; echo b3 >> "$T/app/src/b.py"; gc "$T/app" commit -qam "sibling"; git -C "$T/app" push -q origin main 2>/dev/null \
  && echo a3 >> "$T/app/src/a.py" && gc "$T/app" commit -qam "the file" && ! git -C "$T/app" push -q origin main 2>/dev/null \
  && ok "a hold on one file refuses a push changing it and lets its sibling through" || die "file hold"
"$B" release "$HF" >/dev/null

# chaining to an existing hook, and core.hooksPath
H="$T/other/.git/hooks"; printf '#!/bin/sh\ncat > "%s/their-input"; echo "$1" > "%s/their-args"; exit ${THEIRS_RC:-0}\n' "$T" "$T" > "$H/pre-push"; chmod +x "$H/pre-push"; cp "$H/pre-push" "$T/their-hook"
"$B" install-prepush "$T/other" | has "the hook that was there runs after it as pre-push.agent-board-chained" && cmp -s "$H/pre-push.agent-board-chained" "$T/their-hook" && [ -x "$H/pre-push.agent-board-chained" ] \
  && ok "install-prepush keeps an existing pre-push hook, byte for byte, and chains to it" || die "chain install: $(ls -la "$H")"
"$B" install-prepush "$T/other" | has "already installed" && cmp -s "$H/pre-push.agent-board-chained" "$T/their-hook" && ok "installing twice changes nothing" || die "second install"
echo o > "$T/other/f"; gc "$T/other" add -A; gc "$T/other" commit -qm o; git -C "$T/other" push -q -u origin main 2>/dev/null
grep -q "^refs/heads/main $(git -C "$T/other" rev-parse HEAD) refs/heads/main $Z40" "$T/their-input" && [ "$(cat "$T/their-args")" = origin ] && ok "the chained hook runs after the check with the same arguments and input" || die "chained input: $(cat "$T/their-input" "$T/their-args" 2>&1)"
echo o2 >> "$T/other/f"; gc "$T/other" commit -qam o2
! THEIRS_RC=1 git -C "$T/other" push -q origin main 2>/dev/null && [ "$(remote_main other)" != "$(git -C "$T/other" rev-parse HEAD)" ] && ok "the chained hook can still refuse a push" || die "chained refusal ignored"
"$B" install-prepush "$T/other" --remove | has "the earlier hook is back" && cmp -s "$H/pre-push" "$T/their-hook" && [ ! -e "$H/pre-push.agent-board-chained" ] && ok "--remove puts the earlier hook back as it was" || die "remove: $(ls -la "$H")"
mkdir -p "$T/shared-hooks"; git -C "$T/other" config core.hooksPath "$T/shared-hooks"
"$B" install-prepush "$T/other" | has "in $T/shared-hooks" && [ -x "$T/shared-hooks/pre-push" ] && ! grep -q "agent-board" "$H/pre-push" && ok "with core.hooksPath set for the repo the hook goes where git runs hooks" || die "hooksPath: $(ls -la "$T/shared-hooks")"
git -C "$T/other" config core.hooksPath .githooks; mkdir -p "$T/other/.githooks"; before=$(ls -A "$T/other/.githooks")
out=$("$B" install-prepush "$T/other" 2>&1) && die "installed into the work tree" || true
echo "$out" | has "hooks live in its own files .*Nothing was installed" && [ "$(ls -A "$T/other/.githooks")" = "$before" ] && ok "a hooks dir inside the work tree is the repo's own: nothing is written there" || die "in-tree hooksPath: $out"
git -C "$T/other" config --unset core.hooksPath; git config --global core.hooksPath "$T/shared-hooks"
out=$("$B" install-prepush "$T/other" 2>&1) && die "installed into a global hooks dir" || true
echo "$out" | has "comes from a config shared with other repos" && ok "a core.hooksPath from the global config is refused" || die "global hooksPath: $out"
git config --global --unset core.hooksPath

finish
