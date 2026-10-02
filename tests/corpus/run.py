#!/usr/bin/env python3
"""Run the guard corpora through two copies of bin/board's PreToolUse hook and compare the verdicts.

    tests/corpus/run.py                          origin/main's bin/board against this checkout's
    tests/corpus/run.py --main X --branch Y      any two copies
    tests/corpus/run.py writes reads             only the corpora named (file names without .py)
    tests/corpus/run.py --out DIR                keep each corpus's verdicts as DIR/<name>.json

Each corpus file sets C = [(where, command)] or [(where, command, "DENY"|"allow")], the third an expected branch verdict. `where` is A (alpha, held whole), G (gamma), GH (gamma/held, held),
D (delta, not held) or BD (the board clone). In a command, @A@, @G@, @GH@, @D@, @BD@ and @T@ (the throwaway root)
are replaced by the fixture's paths. A command "Write:<path>" is a Write tool call on that path. HOME is the fixture's h/, so ~/alpha and $HOME/alpha name alpha too.

Exit 1 when the branch allows a command main refuses, misses an expected verdict, or when either copy crashes. A command the branch refuses
and main allows is listed for review but does not fail the run: a fix is expected to add refusals.

Twins (on unless --no-twins): each command that runs the CLI as board (bare, ~/.claude/board, bin/board, a script named board)
is also run through the branch with that name as switchboard (switchboard, ~/.local/bin/switchboard, bin/switchboard), and the twin
must get main's verdict on the board form. Main never knew the name switchboard, so looser-vs-main alone cannot catch a guard that
misses it. Exit 1 too when a twin's verdict differs.
"""
import argparse, itertools, json, os, re, runpy, shutil, subprocess, sys, tempfile
from concurrent.futures import ThreadPoolExecutor

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(HERE))
# the board form of the CLI and its switchboard twin. Only the CLI's names: ~/board/, ../board/, cd board and $(printf board)
# name the fixture's board clone, and agent-board or /tmp/board are not the CLI
TWIN = [(re.compile(r"\.claude/board(?![\w.-])"), ".local/bin/switchboard"),
        (re.compile(r"(?<=[\w@.])(?<!\.\.)(?<!tmp)/board(?![\w./'\"-])"), "/switchboard"),
        (re.compile(r"(?<![\w./~$@-])(?<!/')(?<!cd )(?<!pushd )(?<!printf )board(?![\w./-])"), "switchboard")]


def twin(cmd):
    """The command with each board form of the CLI named as its switchboard twin; the command itself when it names none."""
    for rx, new in TWIN:
        cmd = rx.sub(new, cmd)
    return cmd


def main_copy(root):
    """origin/main's CLI as a file in root: bin/switchboard, or bin/board before the rename (after it, that is a link)."""
    for p in ("bin/switchboard", "bin/board"):
        r = subprocess.run(["git", "-C", REPO, "show", "origin/main:" + p], capture_output=True)
        if r.returncode == 0:
            open(root + "/board-main", "wb").write(r.stdout)
            os.chmod(root + "/board-main", 0o755)
            return root + "/board-main"
    raise SystemExit("run.py: origin/main has neither bin/switchboard nor bin/board")


def fixture(root, board):
    """The throwaway HOME, repos, holds and board clone every corpus assumes, built with `board` (main's copy)."""
    h = root + "/h"
    env = env_for(root)
    env["AGENT_BOARD_STATE"] = root + "/setup-state"
    os.makedirs(h + "/.claude/sessions")
    open(h + "/.claude/settings.json", "w").write('{"enabledPlugins":{"a":true}}')
    git = lambda *a: subprocess.run(["git", *a], check=True, capture_output=True, env=env)
    for r in ("alpha", "gamma", "delta"):
        d = h + "/" + r
        os.makedirs(d)
        git("-C", d, "init", "-q", "-b", "main")
        open(d + "/README.md", "w").write("hello\n")
        open(d + "/VERSION", "w").write("1\n")
        git("-C", d, "add", "-A")
        git("-C", d, "-c", "user.email=t@t", "-c", "user.name=t", "commit", "-qm", "init")
        subprocess.run([board, "register", d], check=True, capture_output=True, env=env)
    for d in ("gamma/held", "gamma/src", "alpha/src", "evil"):
        os.makedirs(h + "/" + d if d != "evil" else root + "/evil", exist_ok=True)
    open(h + "/gamma/held/notes.txt", "w").write("n\n")
    for r in ("gamma", "alpha"):
        open(h + "/%s/src/x.py" % r, "w").write("print(1)\n")
    open(h + "/alpha/data.json", "w").write('{"a":1}\n')
    os.symlink(h + "/gamma/held", h + "/.claude/lnk")  # a ~/.claude entry that links into a repo
    os.symlink(h + "/alpha", h + "/delta/toalpha")  # links from outside into held paths
    os.symlink(h + "/gamma/held", root + "/lk")
    os.makedirs(root + "/cfg/skills/s1")  # a ~/.claude/skills entry that links out, as skills can link into a config repo
    open(root + "/cfg/skills/s1/SKILL.md", "w").write("x\n")
    os.makedirs(h + "/.claude/skills")
    os.symlink(root + "/cfg/skills/s1", h + "/.claude/skills/s1")
    d = h + "/delta"  # the holds verifier's links (guard-gaps): chains, a link mid-path, relative, a loop, dangling
    for src, dst in ((d + "/toalpha", d + "/l2"), (d + "/l2", d + "/l3"), (root + "/lk", d + "/tolk"), (h, d + "/mid"),
                     ("../alpha", d + "/rel"), (d + "/loop2", d + "/loop1"), (d + "/loop1", d + "/loop2"),
                     (d + "/nothing", d + "/dang"), (h + "/alpha/newfile", d + "/dang2"), (root + "/evil", d + "/out")):
        os.symlink(src, dst)
    for x in (h + "/alpha2", h + "/gamma/held-old", d + "/sp ace"):
        os.makedirs(x, exist_ok=True)
    os.makedirs(h + "/.local/bin")  # where ~/.local/bin/switchboard would be, held as ~/.claude is: a twin keeps its standing
    for path, reason in ((h + "/alpha", "alpha frozen"), (h + "/gamma/held", "held frozen"), (h + "/.claude/lnk", "link frozen"),
                         (h + "/.claude", "claude frozen"), (h + "/.local/bin", "bin frozen")):
        subprocess.run([board, "hold", path, "--until", "2d", "--reason", reason], check=True, capture_output=True, env=env)
    bd = h + "/board"
    for d in ("links", "roles", "events", "tasks", "keys", "bin", "tests"):
        os.makedirs(bd + "/" + d, exist_ok=True)
    open(bd + "/links/la.json", "w").write('{"id":"la","scope":"x"}')
    open(bd + "/roles/r.json", "w").write("{}")
    open(bd + "/keys/allowed_signers", "w").write("x\n")
    open(bd + "/tests/x.py", "w").write("print(1)\n")
    shutil.copy(board, bd + "/bin/board")
    git("-C", bd, "init", "-q", "-b", "main")
    git("-C", bd, "add", "-A")
    git("-C", bd, "-c", "user.email=t@t", "-c", "user.name=t", "commit", "-qm", "init")
    return dict(A=h + "/alpha", G=h + "/gamma", GH=h + "/gamma/held", D=h + "/delta", BD=bd, T=root)


def env_for(root):
    h = root + "/h"
    env = dict(os.environ, HOME=h, AGENT_BOARD_DIR=h + "/board", AGENT_BOARD_NOSYNC="1", AGENT_BOARD_ALLOW_TMP="1",
               AGENT_BOARD_NOSCAN="1", AGENT_BOARD_NOWALK="1", AGENT_BOARD_MACHINE="vt")
    for k in ("AGENT_BOARD_SESSION_ID", "AGENT_BOARD_OFF", "AGENT_BOARD_NOW", "AGENT_BOARD_SESSIONS_DIR"):
        env.pop(k, None)
    return env


def verdict(board, env, state, cwd, cmd, n):
    os.makedirs(state)
    tool, ti = ("Write", {"file_path": cmd[6:], "content": "x"}) if cmd.startswith("Write:") else ("Bash", {"command": cmd})
    d = {"hook_event_name": "PreToolUse", "cwd": cwd, "session_id": "V1", "tool_use_id": "t%d" % n,
         "tool_name": tool, "tool_input": ti}
    r = subprocess.run([board, "hook"], input=json.dumps(d), capture_output=True, text=True,
                       env=dict(env, AGENT_BOARD_STATE=state), cwd=cwd)
    err = open(state + "/errors.log").read() if os.path.exists(state + "/errors.log") else ""
    v = "DENY" if '"deny"' in r.stdout else "allow"
    if err or r.stderr.strip() or r.returncode:
        v += "!CRASH(%s|%s)" % (err.strip()[:200], r.stderr.strip()[-200:])
    kind = ("hold" if "frozen" in r.stdout else "rec" if "records are written" in r.stdout else
            "keys" if "keys are installed" in r.stdout else "other" if v.startswith("DENY") else "")
    return v, kind


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("corpora", nargs="*")
    ap.add_argument("--main", help="the reference copy (default: origin/main's bin/switchboard, or bin/board before the rename)")
    ap.add_argument("--branch", default=REPO + "/bin/switchboard")
    ap.add_argument("--out")
    ap.add_argument("--jobs", type=int, default=8)
    ap.add_argument("--no-twins", dest="twins", action="store_false", help="skip the switchboard twins")
    a = ap.parse_args()
    root = tempfile.mkdtemp(prefix="ab-corpus-")
    try:
        main_board = a.main or main_copy(root)
        boards = {"main": os.path.abspath(main_board), "br": os.path.abspath(a.branch)}
        paths = fixture(root, boards["main"])
        env = env_for(root)
        names = a.corpora or sorted(f[:-3] for f in os.listdir(HERE) if f.endswith(".py") and f not in ("run.py", "perf.py"))
        ctr, bad, ntwins = itertools.count(), 0, [0, 0, 0]

        def place(cmd):
            for k, v in sorted(paths.items(), key=lambda kv: -len(kv[0])):
                cmd = cmd.replace("@%s@" % k, v)
            return cmd

        for name in names:
            items, twins = [], []
            for where, cmd, *want in runpy.run_path(os.path.join(HERE, name + ".py"))["C"]:
                items.append((paths[where], place(cmd), *want))
                if a.twins and twin(cmd) != cmd:
                    twins.append((len(items) - 1, (paths[where], place(twin(cmd)))))

            def one(it):
                n = next(ctr)
                return {"cwd": it[0], "cmd": it[1], "want": it[2] if len(it) > 2 else "",
                        **{k: dict(zip(("v", "kind"), verdict(b, env, "%s/s/%s%d" % (root, k, n), it[0], it[1], n)))
                           for k, b in boards.items()}}

            with ThreadPoolExecutor(a.jobs) as ex:
                res = list(ex.map(one, items))
                tw = list(ex.map(one, [t for _, t in twins]))
            # a twin's expected verdict is main's on its board form; main's own verdict on the twin is shown, not judged
            for (i, _), r in zip(twins, tw):
                r.update(want=res[i]["main"]["v"].split("!")[0], board=res[i]["cmd"])
            loose = [r for r in res if r["main"]["v"] == "DENY" and not r["br"]["v"].startswith("DENY")]
            tight = [r for r in res if r["br"]["v"] == "DENY" and not r["main"]["v"].startswith("DENY")]
            crash = [r for r in res + tw if "CRASH" in r["main"]["v"] + r["br"]["v"]]
            miss = [r for r in res if r["want"] and r["br"]["v"] != r["want"]]
            differ = [r for r in tw if r["br"]["v"] != r["want"]]
            bad += len(loose) + len(crash) + len(miss) + len(differ)
            ntwins[0] += len(tw); ntwins[1] += len(differ); ntwins[2] += sum(r["main"]["v"] != r["want"] for r in tw)
            print("%-18s %4d commands  main refuses %4d  branch refuses %4d  looser %d  stricter %d  crashes %d%s%s" % (
                name, len(res), sum(r["main"]["v"] == "DENY" for r in res), sum(r["br"]["v"] == "DENY" for r in res),
                len(loose), len(tight), len(crash), "  expectation misses %d" % len(miss) if any(r["want"] for r in res) else "",
                "  twins %d differ %d (main %d)" % (len(tw), len(differ), sum(r["main"]["v"] != r["want"] for r in tw))
                if tw else ""))
            short = lambda r: "    [%s] %s" % (os.path.relpath(r["cwd"], root + "/h"), r["cmd"].replace(root, "@T@")[:160])
            for label, rows in (("LOOSER (branch allows, main refuses)", loose), ("stricter (review)", tight), ("CRASH", crash),
                                ("EXPECTATION MISS (branch verdict differs from the corpus's)", miss),
                                ("TWIN DIFFERS (branch verdict on switchboard differs from main's on board)", differ)):
                if rows:
                    print("  " + label)
                    for r in rows:
                        print(short(r) + ("  " + r["main"]["v"] + " / " + r["br"]["v"] if label == "CRASH" else
                                          "  want " + r["want"] if label.startswith(("EXP", "TWIN")) else ""))
            if a.out:
                os.makedirs(a.out, exist_ok=True)
                json.dump(res, open(os.path.join(a.out, name + ".json"), "w"), indent=1)
                if tw:
                    json.dump(tw, open(os.path.join(a.out, name + ".twins.json"), "w"), indent=1)
        if a.twins:
            print("twins: %d, branch differs from main's board verdict on %d; main itself on %d" % tuple(ntwins))
        print("FAIL: %d looser, crashing, missing an expectation or a twin" % bad if bad else
              "ok: nothing main refuses is allowed, no crashes, every expectation met, every twin as main's board form")
        return 1 if bad else 0
    finally:
        shutil.rmtree(root, ignore_errors=True)


if __name__ == "__main__":
    sys.exit(main())
