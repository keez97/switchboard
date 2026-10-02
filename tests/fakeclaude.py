#!/usr/bin/env python3
"""A stand-in for a Claude Code process in the self-test. It stays up and runs every command it is sent as its own
child through /bin/sh -c, the way Claude Code runs a hook or a Bash tool call, so the board finds the session by
walking up from the hook or the CLI to this process, with no session file needed.

  fakeclaude.py serve <socket>                    run until sent "quit" or idle for 10 minutes
  fakeclaude.py run <socket> <cwd> <command>      stdin goes to the command; prints its stdout and stderr, exits with its code
"""
import json, os, socket, subprocess, sys


def serve(path):
    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    s.bind(path)
    s.listen(4)
    s.settimeout(600)
    while True:
        try:
            c, _ = s.accept()
        except socket.timeout:
            break
        with c:
            req = json.loads(c.makefile("rb").readline() or b"{}")
            if req.get("quit"):
                c.sendall(b"{}\n")
                break
            r = subprocess.run(["/bin/sh", "-c", req["cmd"]], cwd=req["cwd"], env=req["env"], input=req["stdin"],
                               capture_output=True, text=True)
            c.sendall((json.dumps({"rc": r.returncode, "out": r.stdout, "err": r.stderr}) + "\n").encode())
    os.unlink(path)


def run(path, cwd, cmd):
    c = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    c.connect(path)
    stdin = "" if sys.stdin.isatty() else sys.stdin.read()
    c.sendall((json.dumps({"cwd": cwd, "cmd": cmd, "env": dict(os.environ), "stdin": stdin}) + "\n").encode())
    r = json.loads(c.makefile("rb").readline())
    sys.stdout.write(r["out"])
    sys.stderr.write(r["err"])
    sys.exit(r["rc"])


if __name__ == "__main__":
    if sys.argv[1] == "serve":
        serve(sys.argv[2])
    elif sys.argv[1] == "quit":
        c = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        c.connect(sys.argv[2])
        c.sendall(b'{"quit": true}\n')
        c.recv(16)
    else:
        run(*sys.argv[2:5])
