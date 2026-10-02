C = []
def add(cwd, *cmds):
    for c in cmds: C.append((cwd, c))
common = ["git status", "git status --short", "git log --oneline -5", "git diff", "git diff HEAD~1 -- VERSION", "git show HEAD --stat", "git branch -a",
          "git rev-parse HEAD", "git ls-files | wc -l", "git blame README.md | head", "ls", "ls -la", "cat README.md", "head -5 README.md",
          "tail -n 3 README.md", "wc -l README.md", "grep -rn hello .", "grep -c x README.md 2>/dev/null", "rg hello", "rg -l hello .",
          "find . -name '*.md'", "find . -type f -newer VERSION", "find . -name '*.md' -exec grep -l hello {} +", "find . -name '*.md' -exec grep -l hello {} \\;",
          "find . -type f | xargs grep -l hello", "find . -type f -print0 | xargs -0 wc -l", "sort README.md | uniq -c", "sort -u README.md", "cut -d, -f1 README.md | sort | uniq -c | sort -rn | head",
          "stat VERSION", "du -sh .", "diff README.md VERSION", "xxd VERSION | head", "file README.md", "echo $PWD", "pwd", "realpath .",
          "git status 2>&1 | head", "ls | head && cat VERSION", "for f in *.md\\; do echo $f\\; done", "if [ -f VERSION ]\\; then cat VERSION\\; fi",
          "cat VERSION 2>/dev/null || echo none", "git log -p -1 | head -40", "git worktree list", "git stash list", "git remote -v",
          "ls | xargs -n1 echo", "tr a-z A-Z < README.md", "jq . @A@/data.json", "od -c VERSION | head", "sha256sum VERSION"]
for c in common: add("A", c)
for c in ["cd held && ls && cat notes.txt", "sort held/notes.txt | uniq -c", "grep -rn n held", "find held -type f", "cat held/notes.txt | wc -l",
          "git status", "git diff held", "python3 src/x.py", "python3 -c 'print(1)'", "rm VERSION.bak", "echo x > @T@/out.txt",
          "cd src && python3 x.py > out.txt", "find held -name '*.txt' | xargs grep -l n", "ls held | xargs -I{} echo {}"]:
    add("G", c)
for c in ["git status", "git log --oneline -3", "ls links/", "cat links/la.json", "cat links/la.json | head -3", "jq . links/la.json", "jq -r .scope links/la.json",
          "grep -l scope links/*.json", "rg scope links", "find links -name '*.json'", "find links/ -name '*.json' -exec grep -l scope {} +",
          "ls links | wc -l", "for f in links/*.json\\; do echo \"$f $(head -c 20 $f)\"\\; done", "for f in $(grep -l x links/*.json)\\; do cat $f\\; done",
          "cat links/la.json | python3 -m json.tool", "python3 -m json.tool links/la.json", "ls links/ && python3 bin/board status",
          "python3 bin/board links", "bin/board links", "git ls-files links | wc -l", "git log --oneline -- links | head", "wc -l links/*.json",
          "sort links/la.json | uniq -c", "diff links/la.json roles/r.json", "python3 tests/x.py", "bash tests/selftest.sh 2>&1 | tail -3",
          "find events -name '*.json' | xargs cat | jq -s length", "cat links/la.json | jq .", "head -1 keys/allowed_signers | cut -c1-40",
          "ls links/ | python3 -c 'import sys\\; print(len(sys.stdin.read().split()))'", "grep -h scope links/*.json | sort | uniq -c",
          "stat links/la.json", "xxd links/la.json | head"]:
    add("BD", c)
for c in ["cat @BD@/links/la.json | head -3", "ls @A@ | head", "git -C @A@ status", "git -C @A@ log --oneline -3", "grep -rn hello @A@",
          "find @A@ -name '*.py' -exec grep -l print {} +", "rg print @A@", "sort @GH@/notes.txt | uniq -c", "wc -l @A@/README.md",
          "python3 @A@/src/x.py", "cat @A@/data.json | python3 -m json.tool", "python3 -c 'import json\\; print(json.load(open(\"@A@/data.json\")))'",
          "diff @A@/VERSION @D@/VERSION", "cp @A@/README.md @T@/r.md", "find @A@ -type f | xargs grep -l hello", "~/board/bin/board links"]:
    add("D", c)
