C = []
E = "@T@/evil"
bd = ["PATH=%s:$PATH board links/x.json" % E, "PATH=%s:$PATH board status > links/x.json" % E, "env PATH=%s:$PATH board links/x.json" % E,
      "export PATH=%s:$PATH; board links/x.json" % E, "export PATH=%s:$PATH && board rm links/la.json" % E, "alias board=%s/board; board links/x.json" % E,
      "board(){ rm links/la.json; }; board", "board() { cp /tmp/x links/y.json; }; board links", "function board { rm -rf links; }; board",
      "command board links/x.json", "exec board links/x.json", "\\board links/x.json", "%s/board links/x.json" % E, "@T@/evil2/board links/x.json",
      "python3 %s/board links/x.json" % E, "../x/board links/x.json", "python3 ../x/board links/x.json", "hash -p %s/board board; board links/x.json" % E,
      "source %s/rc; board links/x.json" % E, ". %s/rc && board links/x.json" % E, "eval board links/x.json", "builtin board links/x.json",
      "nohup board links/x.json", "time board links/x.json", "D=links; board status > $D/x.json", "board status > $(echo links)/x.json",
      "board status > `echo links`/x.json", "board status > ${D:-links}/x.json", "board status > \"links\"/x.json", "board status > l''inks/x.json",
      "board status > ../board/links/x.json", "board status > ./links/../links/x.json", "board status > ~/board/links/x.json",
      "board status > $HOME/board/links/x.json", "board status >links/x.json", "board status 2>links/x.json", "board status &>links/x.json",
      "board status >| links/x.json", "board status <> links/x.json", "board status >> links/x.json", "board status > keys/allowed_signers",
      "board status > @A@/f", "board status > @GH@/n", "board status | tee links/x.json", "{ board status; } > links/x.json", "(board status) > links/x.json",
      "board status > /tmp/ok && cp /tmp/ok links/x.json", "board links 2>&1 > links/x.json", "board links >links/x.json 2>/dev/null",
      "bin/board status > links/x.json", "./bin/board status > links/x.json", "python3 bin/board status > links/x.json", "python3 bin/board status >> roles/r.json",
      "python3 bin/board x > keys/allowed_signers", "python3 ./bin/board status > \"links/x.json\"", "python3 bin/board status > @A@/f",
      "~/.claude/board status > links/x.json", "$HOME/board/bin/board status > links/x.json", "python3 -u bin/board status > links/x.json",
      # the general quoting and .. forms, not the CLI
      "cp /tmp/x \"links\"/x.json", "cp /tmp/x l''inks/x.json", "cp /tmp/x ../board/links/x.json", "cp /tmp/x ./links/../links/x.json", "cp /tmp/x li\\nks/x.json",
      # must run
      "board links > /tmp/l.txt", "python3 bin/board links --json > @T@/l.json", "bin/board links > /tmp/l.txt", "board links --json | jq .",
      "python3 bin/board links", "python3 bin/board tasks", "board read --repo events", "board status 2>/dev/null"]
for c in bd: C.append(("BD", c))
for c in ["board status > @BD@/links/x.json", "cd @BD@ && board status > links/x.json", "cd @BD@/links && board status > x.json",
          "board status > ~/board/roles/r.json", "python3 @BD@/bin/board status > @BD@/links/x.json", "PATH=%s:$PATH board @BD@/links/x.json" % E,
          "%s/board @BD@/links/x.json" % E, "cd %s && ./board @BD@/links/x.json" % E, "cd %s && board @BD@/links/x.json" % E, "board status > @A@/x",
          "cp /tmp/x ../board/links/x.json", "board links > /tmp/l.txt", "~/board/bin/board links > /tmp/l.txt", "board hold @A@ --until 1h --reason x",
          "board links --json > @T@/l.json"]:
    C.append(("D", c))
