# Link policy (1-02): --until is read by one parser in the CLI and the guard. `--until never` from a session moves from
# allow to deny (stricter); --until 7d stays refused and 12h allowed at the default 24 hours, as in rename.py. A session
# writes neither the policy record nor grants/, by Write or by Bash, from the clone or from elsewhere; reading them runs.
# (switchboard names only: a board form gets a twin that must match main, which allowed --until never)
C = []
for cli in ("switchboard", "@BD@/bin/switchboard", "python3 @BD@/bin/switchboard"):
    C += [("D", "%s link --from a:b --to c:d --scope x --until never" % cli, "DENY"),
          ("D", "%s link --from a:b --to c:d --scope x --until=never" % cli, "DENY"),
          ("D", "%s link --from a:b --to c:d --scope x --until Never" % cli, "DENY"),
          ("D", "%s link --from a:b --to c:d --scope x --until 7d" % cli, "DENY"),
          ("D", "%s link --from a:b --to c:d --scope x --until=7d" % cli, "DENY"),
          ("D", "%s link --from a:b --to c:d --scope x --until 25h" % cli, "DENY"),
          ("D", "%s link --from a:b --to c:d --scope x --until 12h" % cli, "allow"),
          ("D", "%s link --from a:b --to c:d --scope x --until 24h" % cli, "allow"),
          ("D", "%s link --from a:b --to c:d --scope 'until never'" % cli, "allow"),
          ("D", "%s link accept la" % cli, "allow")]
C += [("D", "bash -c 'switchboard link --from a:b --to c:d --scope x --until never'", "DENY"),
      ("D", "eval switchboard link --from a:b --to c:d --scope x --until never", "DENY"),
      ("D", "x=$(switchboard link --from a:b --to c:d --scope x --until never)", "DENY"),
      ("D", "Write:@BD@/policy.json", "DENY"),
      ("D", "Write:@BD@/grants/g1.json", "DENY"),
      ("BD", "Write:policy.json", "DENY"),
      ("BD", "Write:grants/g1.json", "DENY"),
      ("D", "echo '{}' > @BD@/policy.json", "DENY"),
      ("D", "echo '{}' >> ~/board/policy.json", "DENY"),
      ("D", "tee @BD@/policy.json < /dev/null", "DENY"),
      ("D", "sed -i s/24/9999/ @BD@/policy.json", "DENY"),
      ("D", "cp /dev/null @BD@/grants/g1.json", "DENY"),
      ("D", "mkdir -p @BD@/grants", "DENY"),
      ("D", "rm -rf @BD@/grants", "DENY"),
      ("BD", "echo '{}' > policy.json", "DENY"),
      ("BD", "echo '{}' >policy.json", "DENY"),
      ("BD", "rm policy.json", "DENY"),
      ("BD", "mv /dev/null grants/g1.json", "DENY"),
      ("BD", "rm -rf grants", "DENY"),
      ("D", "cat @BD@/policy.json", "allow"),
      ("BD", "cat policy.json", "allow"),
      ("BD", "ls grants", "allow"),
      ("BD", "git log -- policy.json", "allow"),
      ("D", "echo '{}' > @D@/policy.json", "allow"),
      ("D", "Write:@D@/policy.json", "allow")]
