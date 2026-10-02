C = [("BD", "python3 bin/board tasks"), ("BD", "python3 bin/board links --json"), ("BD", "python3 bin/board read --repo events"),
     ("BD", "ls tasks/ && python3 -c 'print(1)'"), ("BD", "cat events/*.json | python3 -c 'import sys; print(len(sys.stdin.read()))'"),
     ("D", "xargs " * 3000 + "grep x"), ("D", "find . " + "-exec find . " * 1500 + "-print"), ("D", "uniq -f"), ("D", "xargs -a"),
     ("D", "sort 'unterminated"), ("D", "uniq 'a b"), ("D", "cd \x00 && rm @A@/x"), ("GH", "cd ''"), ("D", "find -exec"), ("D", "xargs --"),
     ("D", "cd ~nosuchuser/x && rm y"), ("D", "rm " + "../" * 400 + "@A@/VERSION"), ("A", "echo $(echo $(echo x))")]
