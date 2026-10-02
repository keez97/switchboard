# The config and identity unit: a board link command run with a variable that picks the
# machine, board dir, state dir, owner or config file is refused like one run with the session variables; the same
# variables on other board commands, and link commands with none, keep running.
# (the fixture holds ~/.claude, so the CLI is called bare here: ~/.claude/board would be refused by that hold)
NEW = ["AGENT_BOARD_MACHINE", "AGENT_BOARD_DIR", "AGENT_BOARD_OWNER", "SWITCHBOARD_MACHINE", "SWITCHBOARD_DIR",
       "SWITCHBOARD_STATE", "SWITCHBOARD_OWNER", "XDG_CONFIG_HOME"]
C = []
for v in NEW:
    C += [("D", "%s=@T@/x board link accept l1" % v, "DENY"),
          ("D", "%s=east board link --from a:b --to c:d --scope x" % v, "DENY"),
          ("D", "env %s=x board unlink l1" % v, "DENY"),
          ("D", "export %s=x; board link decline l1 --reason no" % v, "DENY"),
          ("D", "%s=x board links" % v, "allow"),
          ("D", "%s=x board status" % v, "allow")]
C += [("D", "board link accept l1", "allow"),
      ("D", "board link --from a:b --to c:d --scope x", "allow"),
      ("D", "board unlink l1", "allow"),
      ("D", "AGENT_BOARD_STATE=x board link accept l1", "DENY"),
      ("D", "HOME=@T@/x board link accept l1", "DENY"),
      ("D", "AGENT_BOARD_MACHINEX=x board link accept l1", "allow"),
      ("D", "MY_SWITCHBOARD_DIR=x board link accept l1", "allow")]
# SWITCHBOARD_SESSION_ID, SWITCHBOARD_ALLOW_TMP and SWITCHBOARD_TEST_PROPOSE are read since the older names became their
# fallback. Main never read them and allows these (stricter); called as switchboard, so no board twin expects main's verdict
for v in ("SWITCHBOARD_SESSION_ID", "SWITCHBOARD_ALLOW_TMP", "SWITCHBOARD_TEST_PROPOSE"):
    C += [("D", "%s=x switchboard link accept l1" % v, "DENY"),
          ("D", "env %s=x switchboard unlink l1" % v, "DENY"),
          ("D", "%s=x switchboard links" % v, "allow")]
