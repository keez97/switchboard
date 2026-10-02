---
description: Set up switchboard on this machine. Asks for your name and a machine name, then writes the config file, makes the board folder a local git repo and makes this machine's signing key. With --join <git url>, this machine joins a board another machine shares.
argument-hint: "[--join <git url>]"
allowed-tools: Bash(*/bin/switchboard* paths), Bash(*/bin/switchboard* init *)
---

Arguments: "$ARGUMENTS". The CLI is `"${CLAUDE_PLUGIN_ROOT}/bin/switchboard"`: use that exact path, quoted, in every command below, never a bare `switchboard`.

1. Run `"${CLAUDE_PLUGIN_ROOT}/bin/switchboard" paths` with the Bash tool. Its `machine` and `owner` lines are the defaults.
2. Ask the person, in one message, for two things and wait for the answer:
   - their name, which the board's notes use for whose approval counts (default: the `owner` value);
   - a name for this machine, which goes into file names, task records and the signing key (default: the `machine` value; lowercase letters, digits and dashes).
   If the arguments hold `--join <git url>`, say that this machine will clone the board at that url. An empty answer takes the default.
3. Run `"${CLAUDE_PLUGIN_ROOT}/bin/switchboard" init --owner <name> --machine <machine>`, adding `--join <git url>` when the arguments hold one, with the Bash tool, exactly once. Pass each value as one shell word in single quotes, and write a single quote inside a value as `'\''`: the name O'Brien is `'O'\''Brien'`. Pass the values exactly as given; never let one end the command or add another.
4. Show its output unchanged in a code block. If it failed, show the error as it came. If it says the config file is there, ask whether to rerun with `--update` and the same options, and rerun only on a yes.
5. If the output prints a command for `keys/allowed_signers`, explain it in two or three plain sentences: that file lists whose signed task requests are trusted, so init writes it only into a board it has just made from a terminal, and a Claude session never writes it. The person runs the command themselves in a terminal: on this machine after a plain init, on the first machine after `--join` (this machine cannot vouch for itself). Do not run it.
6. End with the next step the output names: `/reload-plugins` in each open session, or a new session.
