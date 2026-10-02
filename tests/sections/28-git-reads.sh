#!/usr/bin/env bash
# git branch, remote and config are reads only in their listing forms; log, diff and show --output and grep -O write
source "$(dirname "$0")/../lib.sh"
fx_repos alpha gamma
A="$T/alpha"; echo hello > "$A/README.md"
hid=$("$B" hold "$A" --until 2d --reason "alpha frozen" | awk '{print $2}')
[ -n "$hid" ] || die "setup: hold on alpha"
bash_ti(){ python3 -c 'import json,sys; print(json.dumps({"command": sys.argv[1]}))' "$1"; }
refused(){ hook PreToolUse "$1" sR1 Bash "$(bash_ti "$2")" | has "hold $hid"; }
runs(){ [ -z "$(hook PreToolUse "$1" sR1 Bash "$(bash_ti "$2")")" ]; }

refused "$A" "git branch -D x" && refused "$A" "git branch newb" && refused "$A" "git branch -m main m2" \
  && refused "$A" "git branch --set-upstream-to=origin/main" && refused "$A" "git branch --edit-description" \
  && refused "$T/gamma" "git -C $A branch -D x" \
  && runs "$A" "git branch" && runs "$A" "git branch -a" && runs "$A" "git branch -vv" && runs "$A" "git branch --show-current" \
  && runs "$A" "git branch --list 'f*'" && runs "$A" "git branch --contains HEAD" && runs "$A" "git branch -r --merged main" \
  && ok "git branch that deletes, creates, renames or sets an upstream is refused on a held repo; its listing forms run" \
  || die "git branch judged wrong on a held repo"
refused "$A" "git branch --dele x" && refused "$A" "git branch -aD x" && refused "$A" "git branch --column xx" \
  && refused "$A" "git branch --list -D x" && refused "$A" "git branch \"-D\" x" \
  && runs "$A" "git branch -avv" && runs "$A" "git branch --sort=-committerdate --format '%(refname) x'" \
  && runs "$A" "git branch --color=always --column=auto" && runs "$A" "git branch -l 'f*' 'g*'" \
  && ok "an abbreviated or bundled branch option, --column's bare word and a quoted -D are writes" \
  || die "git branch spelling let through or a listing refused"
refused "$A" "git remote add o https://x" && refused "$A" "git remote set-url origin https://x" \
  && refused "$A" "git remote remove origin" && refused "$A" "git remote -v add x y" && refused "$A" "git remote update" \
  && refused "$T/gamma" "git -C $A remote add o https://x" \
  && runs "$A" "git remote" && runs "$A" "git remote -v" && runs "$A" "git remote show origin" \
  && runs "$A" "git remote get-url origin" && runs "$A" "git remote -v show -n origin" \
  && ok "git remote add, set-url, remove and update are refused on a held repo; list, show and get-url run" \
  || die "git remote judged wrong on a held repo"
refused "$A" "git config user.name x" && refused "$A" "git config --unset user.name" && refused "$A" "git config --add a.b c" \
  && refused "$A" "git config set user.name x" && refused "$A" "git config edit" && refused "$A" "git config -e" \
  && refused "$A" "git config --unse user.name" && refused "$A" "git config --file f k.v x" \
  && refused "$T/gamma" "git -C $A config user.name x" \
  && runs "$A" "git config user.name" && runs "$A" "git config --get user.name" && runs "$A" "git config -l" \
  && runs "$A" "git config --list --show-origin" && runs "$A" "git config --get-regexp user" && runs "$A" "git config get user.name" \
  && runs "$A" "git config -f .git/config --list" && runs "$A" "git config --type=bool core.bare" \
  && ok "git config that sets, unsets, adds or edits is refused on a held repo; get, list and a lone key run" \
  || die "git config judged wrong on a held repo"
refused "$A" "git log --output=f" && refused "$A" "git diff --output f" && refused "$A" "git show --output=f HEAD" \
  && refused "$T/gamma" "git -C $A log --output=f" \
  && runs "$A" "git log --oneline -3" && runs "$A" "git log --format='%h %s' -- --output=x" && runs "$A" "git diff HEAD" \
  && ok "git log, diff and show with --output are refused on a held repo; without it they run" \
  || die "git --output judged wrong on a held repo"
refused "$A" "git grep -Orm x" && refused "$A" "git grep --open-files-in-pager=rm x" && refused "$A" "git grep -nO x" \
  && refused "$A" "git grep --op=rm x" && refused "$T/gamma" "git -C $A grep -Orm x" \
  && runs "$A" "git grep -n hello" && runs "$A" "git grep -e -O" && runs "$A" "git grep -C 3 -n hello" \
  && ok "git grep -O runs a command and is refused on a held repo in any spelling; a pattern -O still runs" \
  || die "git grep -O judged wrong on a held repo"
refused "$A" "git -cdiff.external=cmd diff" && refused "$A" "git --config-env=diff.external=V diff" \
  && refused "$A" "git --exec-path=$T/evil log" && refused "$A" "git --no-pager -ccore.pager=cmd log" \
  && refused "$T/gamma" "git -C $A -cdiff.external=cmd diff" \
  && runs "$A" "git --no-pager log" && runs "$A" "git -P log -1" && runs "$A" "git --no-optional-locks status" \
  && runs "$A" "git --git-dir=.git log -1" && runs "$T/gamma" "git -C $A status" \
  && ok "a git option before the subcommand that can run a command is refused on a held repo; -C, --no-pager and -P run" \
  || die "git global option judged wrong on a held repo"
refused "$A" "GIT_EXTERNAL_DIFF=cmd git diff" && refused "$A" "GIT_PAGER=less git log" && refused "$A" "PAGER=cmd; git log" \
  && refused "$A" "GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=diff.external GIT_CONFIG_VALUE_0=cmd git diff" \
  && refused "$A" "LD_PRELOAD=$T/evil/x.so cat README.md" && refused "$A" "BASH_ENV=$T/evil/rc ls" \
  && refused "$A" "LESSOPEN='|cmd %s' cat README.md" && refused "$A" "DYLD_INSERT_LIBRARIES=$T/evil/x ls" \
  && refused "$T/gamma" "GIT_PAGER=cmd git -C $A log" \
  && runs "$A" "LC_ALL=C grep hello README.md" && runs "$A" "LC_ALL=C sort README.md" && runs "$A" "FOO=1 ls" \
  && ok "a GIT_*, pager, editor, loader or BASH_ENV assignment in front of a read is refused on a held repo; LC_ALL=C still runs" \
  || die "an assignment in front of a read judged wrong on a held repo"
refused "$A" "RIPGREP_CONFIG_PATH=$T/evil/rgrc rg hello" && refused "$T/gamma" "RIPGREP_CONFIG_PATH=$T/evil/rgrc rg hello $A" \
  && runs "$A" "rg hello" && runs "$A" "LC_ALL=C rg hello README.md" \
  && ok "rg with RIPGREP_CONFIG_PATH, whose file can add --pre=cmd, is refused on a held repo; plain rg runs" \
  || die "RIPGREP_CONFIG_PATH in front of rg judged wrong on a held repo"
refused "$A" "git stash list --output=f" && refused "$A" "git stash show -p --output=f" \
  && refused "$T/gamma" "git -C $A stash show -p --output=f" \
  && runs "$A" "git stash list" && runs "$A" "git stash show -p" \
  && ok "git stash list and show pass --output on to log and diff: refused on a held repo; without it they run" \
  || die "git stash --output judged wrong on a held repo"
refused "$A" "HOME=$T/evil git diff" && refused "$A" "XDG_CONFIG_HOME=$T/evil git diff" \
  && refused "$A" "PATH=$T/evil:\$PATH cat README.md" && refused "$A" "SSH_ASKPASS=$T/evil/x git remote show origin" \
  && refused "$A" "printf -v HOME $T/evil; git diff" && refused "$A" "printf -vPATH '%s' $T/evil; cat README.md" \
  && runs "$A" "printf '%s\\n' a b" && runs "$A" "HOMEDIR=1 ls" \
  && ok "HOME, XDG_CONFIG_HOME, PATH and SSH_ASKPASS in front of a read, and printf -v, are refused on a held repo" \
  || die "a HOME, PATH or printf -v change judged wrong on a held repo"
runs "$A" "GIT_PAGER=cat git log" && runs "$A" "PAGER=cat git log" && runs "$A" "GIT_PAGER= git log" \
  && runs "$A" "GIT_OPTIONAL_LOCKS=0 git status" && runs "$A" "GIT_TERMINAL_PROMPT=0 git remote -v" \
  && refused "$A" "GIT_PAGER=cmd git log" && refused "$A" "GIT_OPTIONAL_LOCKS=1 git status" \
  && refused "$A" "git -C x\\ log branch -D main" && refused "$A" "git -C 'x log' branch -D main" \
  && ok "a pager set to cat or nothing, no optional locks and no prompt run; git words are split as the shell splits them" \
  || die "a quiet git habit refused or a quoted -C dir misread on a held repo"
finish
