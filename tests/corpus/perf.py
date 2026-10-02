#!/usr/bin/env python3
"""Median PreToolUse time of main's and the branch's hook on a few commands, with and without holds.

    tests/corpus/perf.py [--main X] [--branch Y] [--n 10]
"""
import argparse, json, os, shutil, statistics, subprocess, sys, tempfile, time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from run import REPO, env_for, fixture, main_copy  # noqa: E402


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--main")
    ap.add_argument("--branch", default=REPO + "/bin/switchboard")
    ap.add_argument("--n", type=int, default=10)
    a = ap.parse_args()
    root = tempfile.mkdtemp(prefix="ab-perf-")
    try:
        mb = a.main or main_copy(root)
        boards = {"main": os.path.abspath(mb), "br": os.path.abspath(a.branch)}
        p = fixture(root, boards["main"])
        nohold = root + "/h/board-nohold"
        shutil.copytree(p["BD"], nohold)
        shutil.rmtree(nohold + "/holds", ignore_errors=True)
        big = "python3 - <<'EOF'\n" + "\n".join("x%d = open('%s/o%d', 'w').write('line %d with some words')  # ./src/f%d ../held/x"
                                                % (i, root, i, i, i) for i in range(1000)) + "\nEOF"
        bigsh = "\n".join("echo line %d >> %s/log.txt && cp src/a%d.txt %s/b%d.txt" % (i, root, i, root, i) for i in range(1000))
        cmds = {"git status": "git status", "python3 x > f": "python3 src/x.py > %s/out.txt" % root,
                "find|xargs grep": "find . -type f | xargs grep -l n",
                "cd src && sort -o && rm": "cd src && sort -o %s/s.txt x.py && rm %s/s.txt" % (root, root),
                "heredoc 1000 lines": big, "shell 1000 lines": bigsh}
        env = env_for(root)
        for label, bd in (("no hold", nohold), ("3 holds", p["BD"])):
            for name, cmd in cmds.items():
                t, v = {"main": [], "br": []}, {}
                for i in range(a.n):
                    for b in boards:
                        d = {"hook_event_name": "PreToolUse", "cwd": p["G"], "session_id": "P", "tool_name": "Bash",
                             "tool_input": {"command": cmd}}
                        e = dict(env, AGENT_BOARD_DIR=bd, AGENT_BOARD_STATE="%s/sp-%s" % (root, b))
                        s = time.perf_counter()
                        r = subprocess.run([boards[b], "hook"], input=json.dumps(d), capture_output=True, text=True, env=e)
                        t[b].append((time.perf_counter() - s) * 1000)
                        v[b] = "deny" if "deny" in r.stdout else "allow"
                print("%-8s %-24s main %6.0f ms  branch %6.0f ms   verdict main %s branch %s" % (
                    label, name, statistics.median(t["main"]), statistics.median(t["br"]), v["main"], v["br"]))
    finally:
        shutil.rmtree(root, ignore_errors=True)


if __name__ == "__main__":
    main()
