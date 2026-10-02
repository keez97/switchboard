---
description: Live Claude sessions on the board with their role and the to= address to message them. Optional repo name and --role.
argument-hint: "[repo] [--role <role>]"
allowed-tools: Bash(*/bin/switchboard* who), Bash(*/bin/switchboard* who *)
---

Run `"${CLAUDE_PLUGIN_ROOT}/bin/switchboard" who $ARGUMENTS` with the Bash tool, exactly once and nothing else. Use that exact path, quoted. Show its output unchanged in a code block. If it failed, show the error as it came.
