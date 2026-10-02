# The rename: the CLI run as switchboard, by name, from the clone's bin/ and under python. A
# link command from a session is judged as the board form is, the identity variable added with the rename refuses a
# link command, and the CLI by its new name is not taken for a write; a script of that name elsewhere is.
# (~/.local/bin is held in the fixture, as ~/.claude is: the CLI is called bare or from the clone here)
C = []
for cli in ("switchboard", "@BD@/bin/switchboard", "python3 @BD@/bin/switchboard", "$HOME/board/bin/switchboard"):
    C += [("D", "%s link --from a:b --to c:d --scope x --until 7d" % cli, "DENY"),
          ("D", "%s link --from a:b --to c:d --scope x --to-session open" % cli, "DENY"),
          ("D", "%s bind la x --session uds:/x" % cli, "DENY"),
          ("D", "%s link-cap la 0" % cli, "DENY"),
          ("D", "%s link-cap la 500" % cli, "DENY"),
          ("D", "setsid %s link accept la" % cli, "DENY"),
          ("D", "SWITCHBOARD_SESSIONS_DIR=@T@/x %s link accept la" % cli, "DENY"),
          ("D", "SWITCHBOARD_OFF=1 %s link accept la" % cli, "allow"),
          ("D", "%s link accept la" % cli, "allow"),
          ("D", "%s link-cap la 5" % cli, "allow"),
          ("D", "%s link --from a:b --to c:d --scope x --until 12h" % cli, "allow")]
C += [("D", "bash -c 'switchboard link --from a:b --to c:d --scope x --until 7d'", "DENY"),
      ("D", "eval switchboard bind la x --session uds:/x", "DENY"),
      ("D", "x=$(switchboard link-cap la 0)", "DENY"),
      ("D", "AGENT_BOARD_SESSIONS_DIR=@T@/x switchboard link accept la", "DENY"),
      ("D", "SWITCHBOARD_SESSIONS_DIRX=x switchboard link accept la", "allow"),
      # the CLI by its new name in the clone, reading (switchboard links), is in the twins: main, which does not know
      # the name, refuses it as a write to a record dir, so here it would count as looser
      ("BD", "switchboard status > links/x.json", "DENY"), ("BD", "bin/switchboard status >> roles/r.json", "DENY"),
      ("BD", "switchboard() { cat; }; switchboard links/x.json", "DENY"),
      ("BD", "function switchboard { cat; }; switchboard links/x.json", "DENY"),
      ("BD", "alias switchboard=@T@/evil/switchboard; switchboard links/x.json", "DENY"),
      ("BD", "PATH=@T@/evil:$PATH switchboard links/x.json", "DENY"),
      ("BD", "@T@/evil/switchboard links/x.json", "DENY"), ("BD", "python3 @T@/evil/switchboard links/x.json", "DENY"),
      ("D", "~/.local/bin/switchboard status > @BD@/links/x.json", "DENY")]
