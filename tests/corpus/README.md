# Guard corpora

Commands run through the real PreToolUse hook of two copies of the CLI (`bin/switchboard`; `bin/board` before the rename), usually origin/main's and a branch's. A guard change must refuse everything main refuses: `run.py` exits 1 when the branch allows a command main refuses, or when either copy crashes. New refusals are listed for review.

```
tests/corpus/run.py                      # origin/main against this checkout, every corpus (about 4 minutes)
tests/corpus/run.py writes cli-hidden    # only these corpora
tests/corpus/run.py --main /path/board --branch /path/board --out /tmp/x
tests/corpus/run.py --no-twins           # without the switchboard twins
tests/corpus/perf.py                     # hook time on common and 1000-line commands, main against branch
```

Twins: every command that runs the CLI by a board name gets a twin with the switchboard name in its place: bare `board` becomes `switchboard`, `~/.claude/board` becomes `~/.local/bin/switchboard`, `bin/board` becomes `bin/switchboard`, and a script named board (`@T@/evil/board`) one named switchboard. The branch's verdict on the twin must be main's on the board form. Main never knew the name switchboard, so looser-vs-main alone would pass a guard that misses it. `~/board/`, `../board/`, `cd board` and the like name the fixture's board clone and are left as they are. The summary line counts the twins, those the branch gets wrong (must be 0), and those main itself gets wrong, which shows the twins test something.

| Corpus | What it holds |
|---|---|
| writes | 277 writes into held paths and record dirs: redirects, writers, loops, substitutions, xargs |
| reads | 114 reads that must keep running, in repos, the held dir and the board clone |
| xargs-stash-cli | xargs with each read command, `git stash` forms, the CLI with redirects, `find -exec {}` |
| cli-paths | the CLI called by path with a redirect, PATH tricks |
| cli-hidden | the CLI after PATH, alias, hash or source changes; record paths hidden by quotes, `..` or variables |
| edges | parser edge cases: long nests, bad quoting, NUL, deep `..` |
| claude-link | a hold posted on a `~/.claude` entry that links into a repo |
| config | link commands run with a machine, board dir, state dir, owner, config-file or session variable (refused), and the same variables on other board commands (allowed) |
| rename | the CLI as switchboard: link commands from a session, SWITCHBOARD_SESSIONS_DIR on a link command, the CLI by its new name and paths (not a write) and a script of that name elsewhere (a write) |

The fixture (built by `run.py` with main's copy) is a throwaway HOME with repos alpha (held whole), gamma (gamma/held held) and delta, a board clone with record dirs, and `~/.claude/lnk` linking to gamma/held with its own hold. `~/.claude` and `~/.local/bin` are held too, so `~/.claude/board` and its twin `~/.local/bin/switchboard` stand under a hold alike. A corpus file sets `C = [(where, command)]`; see `run.py` for the placeholders.

Add the probes for each guard change to the corpus it fits, or a new file. The commands in cli-hidden that main allows are known gaps in its guard, kept so a change that closes one shows as stricter.
