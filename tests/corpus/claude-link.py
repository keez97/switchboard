C = [("D", "rm -rf @A@/build"), ("D", "echo x > @GH@/f"), ("D", "cp /etc/hosts @A@/"), ("A", "git commit -m x"), ("GH", "rm notes.txt"),
     ("D", "find @A@ | xargs rm"), ("D", "cd @GH@ && rm notes.txt"), ("A", "git status"), ("D", "ls @A@"),
     ("D", "rm ~/.claude/lnk/notes.txt"), ("D", "echo x > $HOME/.claude/lnk/f"), ("D", "cat ~/.claude/lnk/notes.txt")]
