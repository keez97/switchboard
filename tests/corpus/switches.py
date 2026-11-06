# The test switches in a board link command (decision D16, round 3 V3-1 and R3-2): the guard finds their names in quoted
# words too, and NOW is one of them. A sourced file or a script carries no names; the CLI's test_board() closes those.
L = "switchboard link --from @D@:x --to @G@:y --scope ab --covers ab"
C = [("D", "env 'SWITCHBOARD_ALLOW_TMP=1' 'SWITCHBOARD_SESSION_ID=V1' 'XDG_CONFIG_HOME=/nonexistent' 'SWITCHBOARD_DIR=@BD@' " + L, "DENY"),
     ("D", "env -S 'SWITCHBOARD_ALLOW_TMP=1 SWITCHBOARD_SESSION_ID=V1' " + L, "DENY"),
     ("D", "env \"SWITCHBOARD_ALLOW_TMP=1\" switchboard link accept l1a2b3c", "DENY"),
     ("D", "env 'AGENT_BOARD_SESSION_ID=V1' " + L, "DENY"),
     ("D", "env 'HOME=/tmp/x' " + L, "DENY"),
     ("D", "env 'SWITCHBOARD_NOW=4102444800' switchboard link accept l1a2b3c", "DENY"),
     ("D", "SWITCHBOARD_NOW=4102444800 switchboard link accept l1a2b3c", "DENY"),
     ("D", "SWITCHBOARD_NOW=4102444800 switchboard link --from @D@:x --to @G@:y --scope ab --covers ab", "DENY"),
     # what stays allowed: a scope or a commit message that names no switch, and the names outside a link command
     ("D", "switchboard link --from @D@:x --to @G@:y --scope 'what NOW means' --covers ab", "allow"),
     ("D", "git commit -m 'gate SWITCHBOARD_NOW on a test board'", "allow"),
     ("D", "grep -n \"SWITCHBOARD_ALLOW_TMP\" bin/switchboard", "allow"),
     ("D", "env 'SWITCHBOARD_NOW=4102444800' switchboard links", "allow")]
