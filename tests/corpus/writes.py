A, GH = "@A@", "@GH@"
C = []
def add(cwd, *cmds):
    for c in cmds: C.append((cwd, c))
# --- hold: redirects naming the held path, from delta
for tgt in (A + "/f", GH + "/f", "~/alpha/f", "$HOME/alpha/f", "${HOME}/gamma/held/n"):
    add("D", "echo x > %s" % tgt, "echo x >> %s" % tgt, "cat /etc/hosts > %s" % tgt, "ls 2> %s" % tgt, "echo x &> %s" % tgt,
        "printf x >| %s" % tgt, "cat <> %s" % tgt, "echo x >& %s" % tgt, ": > %s" % tgt, "echo x | tee %s" % tgt,
        "echo x | tee -a %s | wc -l" % tgt, "sort /etc/hosts > %s" % tgt, "grep x /etc/hosts >%s" % tgt, "jq . /dev/null > %s" % tgt)
# --- hold: cp/mv/rm/other writers
for c in ("cp /etc/hosts @A@/", "cp -r /tmp/x @A@/x", "mv @A@/a @A@/b", "mv /tmp/x @A@/", "rm @A@/f", "rm -rf @A@", "rm -rf @A@/build",
          "rmdir @A@/d", "mkdir @A@/new", "mkdir -p @GH@/a/b", "touch @GH@/f", "ln -s /etc @A@/l", "chmod +x @A@/f", "truncate -s0 @A@/VERSION",
          "install -m644 /etc/hosts @A@/h", "rsync -a /tmp/x/ @A@/", "dd if=/dev/zero of=@A@/f count=1", "unlink @A@/f", "shred @A@/f",
          "tar -xf /tmp/x.tar -C @A@", "unzip /tmp/x.zip -d @A@", "patch -p1 -d @A@ < /tmp/p", "curl -o @A@/f http://x", "wget -O @GH@/f http://x",
          "awk '{print > \"@A@/f\"}' /etc/hosts", "cp @GH@/notes.txt @GH@/n2", "rm ~/gamma/held/notes.txt", "rm $HOME/alpha/VERSION",
          "sed -i s/a/b/ @A@/README.md", "sed -i.bak s/a/b/ @GH@/notes.txt", "sed --in-place s/a/b/ @A@/VERSION", "sed -n p @A@/README.md",
          "perl -pi -e s/a/b/ @A@/README.md", "python3 -c \"open('@A@/f','w').write('x')\"", "python3 x.py @A@/f", "python3 - <<'EOF'\nopen('@GH@/f','w').write('x')\nEOF",
          "node -e \"require('fs').writeFileSync('@A@/f','x')\"", "bash -c 'rm @A@/f'", "sh -c \"echo > @GH@/f\"", "env rm @A@/f", "nohup rm @A@/f",
          "timeout 5 rm @A@/f", "npm install --prefix @A@", "make -C @A@", "cargo build --manifest-path @A@/Cargo.toml", "cat @A@/README.md | python3 x.py",
          "ls @A@ && npm test", "git -C @A@ commit -m x", "git -C @A@ checkout -b x", "git -C @A@ rm VERSION", "git -C @A@ add -A", "git -C @A@ apply /tmp/p",
          "git -C @A@ reset --hard", "git -C @A@ stash", "git -C @A@ worktree add @T@/wt1", "cd @A@ && git commit -m x", "cd @A@ && git add -A && git commit -qm x",
          "cd @GH@ && rm notes.txt", "cd @GH@; touch x",
          # loops, branches, groups, subshells
          "for f in @A@/*; do rm $f; done", "for f in a b; do echo x > @A@/$f; done", "while read f; do rm \"$f\"; done < @A@/list",
          "if true; then rm @A@/f; fi", "for f in $(ls @A@); do rm @A@/$f; done", "{ rm @A@/f; }", "(rm @A@/f)", "until false; do touch @GH@/x; done",
          "for f in a; do echo; done > @A@/f", "{ echo; } > @GH@/f",
          # substitutions
          "echo $(rm @A@/f)", "echo `rm @A@/f`", "cat <(rm @A@/f)", "x=$(touch @A@/f)", "ls $(rm -rf @A@)", "diff <(ls) >(tee @A@/f)", "echo $(ls $(rm @A@/f))",
          # xargs (the brief's list and variants)
          "find @A@ | xargs rm", "find @A@ -name x | xargs -I{} cp {} /tmp/", "find @A@ | xargs sh -c 'rm $0'", "xargs -a @A@/list rm",
          "ls @A@ | xargs rm -f", "find @A@ -print0 | xargs -0 rm", "find @A@ | xargs -n1 rm", "find @A@ | xargs -P4 rm", "find @A@ | xargs -- rm",
          "find @A@ | xargs -i rm {}", "find @A@ | xargs --arg-file=/tmp/l rm", "find @A@ | xargs -d '\\n' rm", "find @A@ | xargs env rm",
          "find @A@ | xargs xargs rm", "find @A@ | xargs -I% mv % %.bak", "find @A@ | xargs chmod +x", "find @A@ | xargs sed -i s/a/b/",
          "find @A@ | xargs touch", "find @A@ | xargs git rm", "find @A@ | xargs -L1 rm", "find @GH@ -type f | xargs -I{} sh -c 'echo > {}'",
          "xargs -a @GH@/notes.txt -I{} cp /etc/hosts {}", "xargs --arg-file @A@/list rm", "find @A@ | xargs -E x rm", "find @A@ | xargs -s 100 rm",
          # stdin supplies xargs's arguments: the probes for a looser xargs
          "echo -delete | xargs find @A@", "printf '%s\\n' @A@ -delete | xargs find", "echo rm @A@/VERSION | xargs xargs",
          "echo -o @A@/x /etc/hosts | xargs sort", "echo /etc/hosts @A@/out | xargs uniq", "echo -r /tmp/x @A@/y | xargs xxd",
          "echo --pre=rm x @A@ | xargs rg", "echo -exec rm {} + | xargs find @GH@", "echo @A@/VERSION | xargs -I{} xargs rm {}",
          "echo -fprint @A@/o | xargs find /etc",
          ):
    add("D", c)
# --- hold: commands run inside the held repo or the held dir
for c in ("git commit -m x", "git commit -am x", "git checkout -b x", "git checkout -- VERSION", "git rm VERSION", "git add .", "git reset --hard",
          "git stash", "git merge x", "git rebase main", "git pull", "git push", "git mv VERSION V2", "git restore VERSION", "git switch -c y",
          "git clean -fd", "git tag v1", "git cherry-pick x", "git revert x", "rm VERSION", "touch x", "echo > f", "python3 src/x.py", "make",
          "npm test", "mkdir d", "mv VERSION V", "cp VERSION V", "sed -i s/1/2/ VERSION", "tee f < VERSION", "ls | xargs rm", "cat VERSION | xargs touch",
          "echo -delete | xargs find .", "echo rm VERSION | xargs xargs", "echo -o VERSION VERSION | xargs sort"):
    add("A", c)
for c in ("rm notes.txt", "touch x", "echo x > notes.txt", "python3 ../src/x.py", "ls | xargs rm", "echo -delete | xargs find ."):
    add("GH", c)
# --- records: from the clone root (relative) and from delta (absolute / ~)
for c in ("echo {} > links/x.json", "cp /tmp/x links/l1.json", "rm holds/h1.json", "mv links/la.json links/lb.json", "tee roles/x.json < /dev/null",
          "touch events/e.json", "mkdir tasks/t1", "rm -rf sessions/", "sed -i s/a/b/ links/la.json", "python3 -c 'open(\"links/x.json\",\"w\")'",
          "for f in links/*.json; do rm $f; done", "if true; then rm links/x.json; fi", "for f in a; do echo {}; done > links/x.json",
          "{ echo {}; } > roles/x.json", "if true; then echo {}; fi 2> links/x.json", "for f in a; do echo {}; done >& links/x.json",
          "{ echo {}; } <> roles/x.json", "for f in $(rm links/x.json); do echo; done", "for f in `rm links/x.json`; do echo; done",
          "echo $(rm links/x.json)", "for d in 1; do cd links/; echo {} > x.json; done", "{ cd links; cp /tmp/x y.json; }", "cd links && rm la.json",
          "ln -s /tmp/x links/y.json", "chmod 000 links/la.json", "truncate -s0 links/la.json", "dd if=/dev/zero of=links/la.json count=1",
          "cat /tmp/x > registry/r.json", "echo x >> subs/s.json", "rm archive/*", "rm machines/east.json", "jq . links/la.json > links/b.json",
          "perl -pi -e s/a/b/ links/la.json", "rm -rf . ; echo {} > roles/x.json", "cp /tmp/k keys/new", "echo k >> keys/allowed_signers",
          "echo -delete | xargs find links/", "echo /tmp/x links/y.json | xargs uniq", "echo -o links/la.json links/la.json | xargs sort",
          "for f in events/*.json; do rm $f; done", "python3 - <<'EOF'\nopen('links/x.json','w').write('{}')\nEOF", "cat > links/h.json <<'EOF'\n{}\nEOF",
          "echo {} > tasks/eps--builder/t1/001-completed.json"):
    add("BD", c)
for c in ("rm @BD@/links/la.json", "cp /tmp/x @BD@/roles/", "echo {} > ~/board/links/x.json", "rm $HOME/board/holds/h.json", "cd @BD@ && cp /tmp/x links/l1.json",
          "if true; then cd @BD@/links; cp /tmp/x y.json; fi", "for f in a; do echo {}; done > @BD@/links/x.json", "echo east x >> @BD@/keys/allowed_signers",
          "cd @BD@/links && rm la.json", "mv @BD@/roles /tmp/r", "echo -delete | xargs find @BD@/links", "tee @BD@/events/e.json < /dev/null"):
    add("D", c)
