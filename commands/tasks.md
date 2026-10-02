---
description: Board tasks. With no arguments, the tasks this session requested or holds as worker; otherwise the filters switchboard tasks takes.
argument-hint: "[--mine | --for <repo>:<role> [--open [--unseen]] | --subject <s> | --stale [hours]]"
allowed-tools: Bash(*/bin/switchboard* tasks), Bash(*/bin/switchboard* tasks *)
---

Arguments: "$ARGUMENTS". If they are empty, run `"${CLAUDE_PLUGIN_ROOT}/bin/switchboard" tasks --mine`; otherwise run `"${CLAUDE_PLUGIN_ROOT}/bin/switchboard" tasks $ARGUMENTS`. Use that exact path, quoted, and the Bash tool, exactly once and nothing else. Show its output unchanged in a code block. If it failed, show the error as it came.
