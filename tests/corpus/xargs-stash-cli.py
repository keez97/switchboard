C = []
R = ["grep", "cat", "wc", "head", "tail", "echo", "ls", "stat", "du", "basename", "dirname", "realpath", "readlink", "shasum", "sha1sum",
     "sha256sum", "md5", "od", "diff", "cut", "printf", "test", "true", "jq"]
for c in R:
    C += [("D", "echo @A@/VERSION | xargs %s" % c),
          ("D", "echo rm | xargs -I %s %s @A@/VERSION" % (c, c)),
          ("D", "echo rm | xargs -I{} %s {} @A@/VERSION" % c),
          ("D", "echo @A@/VERSION | xargs @T@/evil/%s" % c),
          ("D", "echo @A@/VERSION | xargs --process-slot-var=PATH %s" % c),
          ("D", "echo @A@/VERSION | xargs -- %s" % c),
          ("D", "xargs -a @A@/list %s" % c),
          ("BD", "echo -delete | xargs %s links/" % c),
          ("A", "ls | xargs %s" % c)]
C += [("D", "echo --files0-from=@A@/list | xargs wc"), ("D", "echo -f @A@/VERSION @A@/README.md | xargs grep"), ("D", "echo --files0-from=- | xargs du"),
      ("D", "echo --rawfile x @A@/VERSION -n '$x' | xargs jq"), ("D", "echo -X @A@/VERSION . | xargs du"), ("D", "echo -c @A@/VERSION | xargs sha256sum"),
      ("D", "echo @A@/VERSION | xargs 'grep'"), ("D", "echo @A@/VERSION | xargs \\rm"), ("D", "echo @A@/VERSION | xargs \"g\"rep x"),
      ("D", "echo @A@/VERSION | xargs -I{} sh -c 'cat {}'"), ("D", "echo @A@ | xargs -I{} find {} -delete"), ("D", "echo @A@/x | xargs -0 -n1 -P2 cat"),
      ("D", "git -C @A@ stash -m show"), ("D", "git -C @A@ stash -m list"), ("A", "git stash -m show"), ("A", "git stash --message list"),
      ("A", "git stash list"), ("A", "git stash show -p"), ("A", "git stash show"), ("A", "git stash"), ("A", "git stash push -m list"),
      ("A", "git stash pop"), ("A", "git stash drop"), ("A", "git stash -q list"), ("A", "git stash -- show"),
      ("BD", "python3 bin/board status > links/x.json"), ("BD", "python3 bin/board links >> roles/r.json"), ("BD", "bin/board status > links/x.json"),
      ("BD", "python3 bin/board x > keys/allowed_signers"), ("BD", "python3 @T@/board links/x.json"), ("BD", "python3 bin/board links"),
      ("BD", "python3 bin/board tasks"), ("BD", "python3 bin/board read --repo events"), ("BD", "python3 bin/board status | tee links/x.json"),
      ("D", "python3 @BD@/bin/board status > @BD@/links/x.json"), ("D", "python3 @BD@/bin/board hold @A@ --until 1h --reason x > @A@/f"),
      ("D", "find @A@ -exec {} \\;"), ("D", "find @A@ -exec \\;"), ("D", "find @A@ -name x -exec grep -l y {} +"), ("D", "find @A@ -execdir {} +"),
      ("D", "find @A@ -exec '{}' \\;"), ("D", "find @A@ -exec ./{} \\;"), ("D", "find @A@ -exec bash {} \\;"), ("D", "find @A@ -exec cat {} \\;")]
