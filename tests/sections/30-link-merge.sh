#!/usr/bin/env bash
# one record written on two machines in one sync window: the board-link and board-record merge drivers
source "$(dirname "$0")/../lib.sh"
ln -s "$B" "$HOME/.claude/board"   # the driver runs "$HOME/.claude/board", as on a real machine
mkrepo "$T/alpha"; mkrepo "$T/beta"   # a remote gives each the same repo id on both machines
git -C "$T/alpha" remote add origin https://example.com/t/alpha.git; git -C "$T/beta" remote add origin https://example.com/t/beta.git
P1=$(fake S1 "$T/alpha" road); seat S2 "$T/beta" impl; seat S3 "$T/alpha" other; seat S4 "$T/beta" impl2
# the checks run in Python: each case is a bare remote, a clone per machine and several syncs on each
binit "$T/files"
# shellcheck disable=SC2034  # FAILED is read by lib.sh's finish
python3 - "$B" "$T" "$T/files/.gitattributes" "$T/sock.$P1" <<'PY' || FAILED=1
import fcntl, json, os, re, shlex, shutil, subprocess, sys, time
B, T, ATTR, SOCK1 = sys.argv[1:5]
DRV = ("sh -c 'c=$1; shift; if [ -L \"$c\" ] && [ -x \"$c\" ]; then exec \"$c\" %s \"$@\"; fi; "
       "if [ -x \"$HOME/.claude/board\" ]; then exec \"$HOME/.claude/board\" %s \"$@\"; fi; "
       "exec git merge-file \"$2\" \"$1\" \"$3\"' switchboard %s %s")
drv_of = lambda sub, marks, st: DRV % (sub, sub, shlex.quote(st + "/cli"), marks)  # st: the syncing machine's state dir
# no cli link in this state dir: the driver runs "$HOME/.claude/board"
DRIVER = drv_of("merge-link", "%O %A %B", os.environ["SWITCHBOARD_STATE"])
NOW, failed, P = int(time.time()), [], [""]


def ok(cond, what, why=""):
    print("  ok   " + what if cond else "  FAIL %s%s" % (what, ": " + why if why else ""))
    failed.extend([] if cond else [what])


def setup(cond, what):  # as die "setup: ...": the section ends
    if not cond:
        print("  FAIL setup: " + what)
        sys.exit(1)


def run(args, cwd=None, inp=None, **env):
    r = subprocess.run(args, cwd=cwd, input=inp, env=dict(os.environ, **env), capture_output=True, text=True)
    return r.returncode, r.stdout


def git(d, *a):
    return run(["git", "-C", d, "-c", "user.email=t@t", "-c", "user.name=t"] + list(a))


def write(f, text):
    with open(f, "w") as fh:
        fh.write(text)


def read(f):
    try:
        return open(f).read()
    except OSError:
        return ""


def js(text):
    try:
        return json.loads(text)
    except ValueError:
        return None


# ---- merge-link on its own, given the temp file names git gives a driver
U = T + "/unit"
os.makedirs(U)


def ml(o, a, t, **env):
    for n, v in (("o", o), (".merge_file_a", a), ("t", t)):
        write(U + "/" + n, v)
    return run([B, "merge-link", "o", ".merge_file_a", "t"], cwd=U, **env)[0]


merged = lambda: js(read(U + "/.merge_file_a")) or dict()
rc = ml('{"id":"l1","scope":"a","x":1}', '{"id":"l1","scope":"b","x":1}', '{"id":"l1","scope":"a","x":2}')
ok(rc == 0 and merged() == dict(id="l1", scope="b", x=2), "a field changed on one side only is kept, from either side", read(U + "/.merge_file_a"))
rc = ml('{"id":"l1","cap":5}', '{"id":"l1","cap":3,"scope":"s"}', '{"id":"l1","cap":3,"scope":"s"}')
ok(rc == 0 and merged() == dict(id="l1", cap=3, scope="s"), "the same change on both sides is taken once", read(U + "/.merge_file_a"))
caps = [(ml('{"cap":5}', '{"cap":%d}' % a, '{"cap":%d}' % b), merged().get("cap")) for a, b in ((4, 2), (2, 4), (0, 3))]
ok(caps == [(0, 2), (0, 2), (0, 3)], "a cap both sides changed takes the lower, and 0 (no cap) is not lower", str(caps))
rc = ml('{"x":1}', '{"x":2,"revoked":200,"closed_reason":"late","closed_by":"board"}',
        '{"x":3,"revoked":100,"closed_reason":"early","closed_by":"terminal"}')
ok(rc == 0 and merged() == dict(x=2, revoked=100, closed_reason="early", closed_by="terminal"),
   "two closes keep the earlier with its reason and closer; another field both changed goes to the newer side", read(U + "/.merge_file_a"))
sides = ('{"a":1}', '{"a":3}', '{"a":2}')
rcs = [ml(*[bad if i == j else good for j, good in enumerate(sides)]) for bad in ("nope", "[1,2]", '"s"', "") for i in range(3) if bad or i]
rc = ml('{"a":1}', '{"a":3}', "nope")
ok(rcs == [1] * 11 and rc == 1 and read(U + "/.merge_file_a").startswith("<<<<<<< ours"),
   "a side that is not a JSON object (base, ours or theirs; an empty base is a file both sides added) exits 1 and leaves conflict markers", "%s %s" % (rcs, read(U + "/.merge_file_a")))
write(U + "/l1.json", '{"id":"l1","until":1}\n'); write(U + "/forged.json", '{"id":"l1","until":9999999999}\n')
os.symlink("l1.json", U + "/.merge_file_s"); os.link(U + "/l1.json", U + "/.merge_file_h")
rcs = [run([B, "merge-link", "l1.json", x, "forged.json"], cwd=U)[0] for x in ("l1.json", ".merge_file_s", ".merge_file_h")]
ok(rcs == [1, 1, 1] and read(U + "/l1.json") == '{"id":"l1","until":1}\n',
   "run by hand on a record, or on a link to one named like the temp file from git, it exits 1 and writes nothing",
   "%s %s" % (rcs, read(U + "/l1.json")))
nob = dict(os.environ, HOME=T + "/nohome"); nob.pop("SWITCHBOARD_DIR")
write(U + "/o", '{"a":1}'); write(U + "/.merge_file_a", '{"a":3}'); write(U + "/t", "nope")
rc = subprocess.run([B, "merge-link", "o", ".merge_file_a", "t"], cwd=U, env=nob, capture_output=True).returncode
ok(rc == 1, "on a machine with no board a bad merge still exits 1, never 0", "rc %d" % rc)

# git with the driver: a link conflict it cannot merge stops the rebase as it does with no driver
for side in ("ours", "theirs"):  # in a rebase, ours is the upstream and theirs the commit replayed onto it
    R = "%s/r-%s" % (T, side)
    os.makedirs(R + "/links"); git(R, "init", "-q", "-b", "main"); shutil.copy(ATTR, R)
    write(R + "/links/l1.json", '{"id":"l1","cap":5}\n'); git(R, "config", "merge.board-link.driver", DRIVER)
    git(R, "add", "-A"); git(R, "commit", "-qm", "base"); git(R, "checkout", "-qb", "side")
    write(R + "/links/l1.json", "nope\n" if side == "theirs" else '{"id":"l1","cap":3}\n'); git(R, "commit", "-qam", "side")
    git(R, "checkout", "-q", "main")
    write(R + "/links/l1.json", "nope\n" if side == "ours" else '{"id":"l1","cap":4}\n'); git(R, "commit", "-qam", "main")
    git(R, "checkout", "-q", "side")
    rc, un = git(R, "rebase", "main")[0], git(R, "diff", "--name-only", "--diff-filter=U")[1].split()
    ok(rc != 0 and un == ["links/l1.json"] and "<<<<<<< " in read(R + "/links/l1.json"),
       "bad JSON on the %s side: the rebase stops on links/l1.json with conflict markers, as with no driver" % side,
       "rc %d %s %s" % (rc, un, read(R + "/links/l1.json")))

# ---- merge-record on its own


def mr(o, a, t, path):
    for n, v in (("o", o), (".merge_file_a", a), ("t", t)):
        write(U + "/" + n, v)
    return run([B, "merge-record", "o", ".merge_file_a", "t", path], cwd=U)[0]


rc = mr('{"id":"h1","until":100,"reason":"r","ts":1}', '{"id":"h1","until":100,"reason":"r","ts":1,"released":50}',
        '{"id":"h1","until":200,"reason":"x","ts":1}', "holds/h1.json")
ok(rc == 0 and merged() == js('{"id":"h1","until":200,"reason":"x","ts":1,"released":50}'),
   "merge-record: a hold released on one side and extended with a new reason on the other keeps all three changes", read(U + "/.merge_file_a"))
rcs = [mr('{"id":"h1","ts":1}', '{"id":"h1","ts":1,"released":%d}' % x, '{"id":"h1","ts":1,"released":%d}' % y, "holds/h1.json")
       for x, y in ((70, 50), (50, 70))]
ok(rcs == [0, 0] and merged().get("released") == 50 and mr('{"s":"a","ended":0}', '{"s":"a","ended":9}', '{"s":"b","ended":12}',
                                                          "sessions/east-s.json") == 0 and merged() == js('{"s":"b","ended":9}'),
   "merge-record: released (and a session ended) once set wins, and the earlier time stands", read(U + "/.merge_file_a"))
base, ours, theirs = '{"name":"a","seen":1,"role":"x"}', '{"name":"b","seen":5,"role":"x"}', '{"name":"c","seen":3,"role":""}'
r1 = (mr(base, ours, theirs, "sessions/east-s.json"), merged())
r2 = (mr(base, theirs, ours, "sessions/east-s.json"), merged())
ok(r1 == r2 == (0, js('{"name":"b","seen":5,"role":""}')),
   "merge-record: a field both changed goes to the side with the newer time, the same from either side", "%s %s" % (r1, r2))
bound = '{"repo":"r","role":"x","session_id":"%s","since":%d,"machine":"east"}'
opened = '{"repo":"r","role":"x","open":%d,"was":"%s","why":"w"}'
r1 = (mr(opened % (5, "S0"), bound % ("S1", 10), opened % (20, "S1"), "roles/r--x.json"), merged())
r2 = (mr(opened % (5, "S0"), opened % (30, "S3"), bound % ("S1", 20), "roles/r--x.json"), merged())
r3 = (mr(opened % (5, "S0"), bound % ("S1", 20), opened % (30, "S3"), "roles/r--x.json"), merged())
ok(r1 == (0, js(opened % (20, "S1"))) and r2 == r3 == (0, js(bound % ("S1", 20))),
   "merge-record: a role file is taken whole; a release beats the binding it released, and loses to a binding of another session",
   "%s %s %s" % (r1, r2, r3))
rc = mr("", '{"repo":"r","role":"x","session_id":"S1","since":10}', '{"repo":"r","role":"x","session_id":"S2","since":12}', "roles/r--x.json")
ok(rc == 0 and merged().get("session_id") == "S2", "merge-record: a file both sides added (an empty base) merges", read(U + "/.merge_file_a"))
w = ['{"kind":"path","target":"repo:%s"}' % n for n in "1234"]
rc = mr('{"repo":"r","watches":[%s,%s]}' % (w[0], w[1]), '{"repo":"r","watches":[%s,%s,%s]}' % (w[0], w[1], w[2]),
        '{"repo":"r","watches":[%s,%s]}' % (w[1], w[3]), "subs/r.manual.json")
ok(rc == 0 and sorted(_["target"] for _ in merged().get("watches", [])) == ["repo:2", "repo:3", "repo:4"],
   "merge-record: a list both changed keeps what either side added and drops what either removed", read(U + "/.merge_file_a"))
rcs = [mr('{"a":1}', bad, '{"a":2}', "holds/h.json") for bad in ("nope", "[1]")] + [mr('{"a":1}', '{"a":3}', "nope", "holds/h.json")]
rcs.append(run([B, "merge-record", "l1.json", "l1.json", "forged.json", "holds/h.json"], cwd=U)[0])
ok(rcs == [1, 1, 1, 1] and read(U + "/.merge_file_a").startswith("<<<<<<< ours") and read(U + "/l1.json") == '{"id":"l1","until":1}\n',
   "merge-record: not a JSON object exits 1 with conflict markers, and run by hand on a record it writes nothing", "%s" % rcs)
rc = ml('{"id":"l1"}', '{"id":"l1","revoked":"yesterday"}', '{"id":"l1","revoked":100}')
ok(rc == 1 and read(U + "/.merge_file_a").startswith("<<<<<<< ours"),
   "a merge that raises (a close time that is not a number) exits 1 and leaves conflict markers, as bad JSON does", read(U + "/.merge_file_a"))
pairs = [('{"x":1}', '{"x":1.0}', '{"x":1}'), ('{"a":1,"c":null}', '{"a":1}', '{"a":1,"c":null}'),
         ('{"x":1}', '{"x":2,"revoked":5,"closed_by":null}', '{"x":3,"revoked":5}')]
sym = [(ml(o, a, b), read(U + "/.merge_file_a"), ml(o, b, a), read(U + "/.merge_file_a")) for o, a, b in pairs]
ok(all(r[0] == r[2] == 0 and r[1] == r[3] for r in sym),
   "values compare as JSON text (1 and 1.0 differ, null and missing agree): either side order gives the same record", str(sym))
acc = '{"id":"l1","state":"active","accepted":%d,"accepted_by":{"session":"%s"},"until":%d}'
rcs = [ml('{"id":"l1","state":"proposed","until":1}', acc % (100, "S2", 900), acc % (200, "S4", 1000)),
       ml('{"id":"l1","state":"proposed","until":1}', acc % (200, "S4", 1000), acc % (100, "S2", 900))]
ok(rcs == [0, 0] and merged() == js(acc % (200, "S4", 1000)),
   "both sides accepted: the later accept stands whole, as the role file keeps the later binding", read(U + "/.merge_file_a"))


# ---- two clones of one bare remote, a pair for each case
def clone(m):
    return "%s/%s-%s" % (T, P[0], m)


def state(m):
    return "%s/%s-state-%s" % (T, P[0], m)


def on(m, args, inp=None, **env):  # a board command as that machine; no sync unless asked
    return run([B] + args, inp=inp, SWITCHBOARD_DIR=clone(m), SWITCHBOARD_STATE=state(m), SWITCHBOARD_MACHINE=m, **env)


def hook(m, event, cwd, sid, prompt="next", **env):
    d = dict(hook_event_name=event, cwd=cwd, session_id=sid)
    d.update(dict(prompt=prompt) if event == "UserPromptSubmit" else dict(source="startup"))
    return on(m, ["hook"], inp=json.dumps(d), **env)


def job_held(m):  # a sync job holds that machine's job lock (probed shared, never waiting)
    try:
        with open(state(m) + "/sync-job.lock", "a") as f:
            fcntl.flock(f, fcntl.LOCK_SH | fcntl.LOCK_NB)
        return False
    except BlockingIOError:
        return True
    except OSError:
        return False


def syncw(m, front=False):
    """One sync, finished when this returns. Plain: the job a CLI write starts (commit, fetch, rebase, push).
    front: board sync, whose own fetch and fast-forward run before that job."""
    for f in ("sync.ok", "sync.fail"):
        if os.path.exists(state(m) + "/" + f):
            os.remove(state(m) + "/" + f)
    on(m, ["sync" if front else "sync-job"], SWITCHBOARD_NOSYNC="")
    for _ in range(120 if front else 0):
        if not job_held(m) and any(os.path.exists(state(m) + "/" + f) for f in ("sync.ok", "sync.fail")):
            break
        time.sleep(0.25)


def round_(front=False):  # the first pushes, the second merges onto it and pushes, the first catches up
    for m in ("east", "west", "east"):
        syncw(m, front)


def pair(name):
    """A bare remote seeded with the .gitattributes init writes, and a clone per machine with alpha and beta
    registered, each synced once."""
    P[0] = name
    bare, seed = "%s/%s.git" % (T, name), "%s/%s-seed" % (T, name)
    run(["git", "init", "-q", "--bare", "-b", "main", bare]); run(["git", "clone", "-q", bare, seed])
    shutil.copy(ATTR, seed); os.makedirs(seed + "/links"); write(seed + "/links/seed.log.jsonl", '{"line":"seed"}\n')
    git(seed, "add", "-A"); git(seed, "commit", "-qm", "seed"); git(seed, "push", "-q", "origin", "HEAD:main")
    for m in ("east", "west"):
        run(["git", "clone", "-q", bare, clone(m)])
        run(["git", "-C", clone(m), "config", "user.email", "t@t"]); run(["git", "-C", clone(m), "config", "user.name", m])
        on(m, ["register", T + "/alpha"]); on(m, ["register", T + "/beta"])
    round_(front=True)


def link(m, lid):
    return js(read("%s/links/%s.json" % (clone(m), lid))) or dict()


def sync_line(m):
    return ([x for x in on(m, ["status"])[1].splitlines() if x.startswith("sync:")] or [""])[0]


def clean(m):  # its last sync pushed, nothing failed, no rebase or conflict is left
    return os.path.exists(state(m) + "/sync.ok") and not os.path.exists(state(m) + "/sync.fail") and \
        not os.path.exists(clone(m) + "/.git/rebase-merge") and not git(clone(m), "diff", "--name-only", "--diff-filter=U")[1].strip() \
        and "last failure" not in sync_line(m)


def same(lid):  # both clones at one commit, holding one record
    return read("%s/links/%s.json" % (clone("east"), lid)) == read("%s/links/%s.json" % (clone("west"), lid)) != "" and \
        git(clone("east"), "rev-parse", "HEAD")[1] == git(clone("west"), "rev-parse", "HEAD")[1]


def lid_of(out):
    w = out.split()
    return w[1] if w[:1] == ["link"] and len(w) > 1 else ""


def both():
    return "east %s %s | west %s %s" % (sync_line("east"), read(state("east") + "/sync.fail").strip(),
                                         sync_line("west"), read(state("west") + "/sync.fail").strip())


# accept on west and the expiry of the proposal on east, in one window; synced by the job a CLI write starts
pair("acc")
drv = [git(clone(m), "config", "merge.board-%s.driver" % k)[1].strip() for m in ("east", "west") for k in ("link", "record")]
ok(drv == [drv_of(s, k, state(m)) for m in ("east", "west") for s, k in (("merge-link", "%O %A %B"),
                                                                            ("merge-record", "%O %A %B %P"))] and git(clone("west"), "config", "merge.board-record.name")[1].strip() != "",
   "board sync sets the board-link and board-record merge drivers in the .git/config of each clone, at the stable path", str(drv))
hook("east", "SessionStart", T + "/alpha", "S1"); on("east", ["role", "roadmap"], SWITCHBOARD_SESSION_ID="S1")
LA = lid_of(on("east", ["link", "--from", T + "/alpha:roadmap", "--to", T + "/beta:implementer", "--scope", "merge test", "--covers", "merge test"],
               SWITCHBOARD_SESSION_ID="S1", SWITCHBOARD_TEST_PROPOSE="1")[1])
hook("west", "SessionStart", T + "/beta", "S2"); on("west", ["role", "implementer"], SWITCHBOARD_SESSION_ID="S2")
round_()
rc = on("west", ["link", "accept", LA], SWITCHBOARD_SESSION_ID="S2", SWITCHBOARD_TEST_PROPOSE="1")[0]
hook("east", "UserPromptSubmit", T + "/alpha", "S1", SWITCHBOARD_NOW=str(NOW + 25 * 3600))
a, m = link("west", LA), link("east", LA)
setup(rc == 0 and a.get("state") == "active" and "proposal expired" in m.get("closed_reason", ""),
      "accept on west and expiry on east: %s / %s" % (a, m))
round_()
ok(clean("east") and clean("west"), "accept on one machine and expiry of the proposal on the other: both syncs succeed (passes on main too: git line merge already merges this case)", both())
x = link("east", LA)
listed = [l for mm in ("east", "west") for l in on(mm, ["links"])[1].splitlines() if l.startswith(LA + " ")]
ok(same(LA) and x.get("revoked") == m["revoked"] and "proposal expired" in x.get("closed_reason", "") and
   x.get("accepted") == a["accepted"] and (x.get("accepted_by") or dict()).get("session") == "S2" and not listed,
   "both clones end with one link: closed by the expiry, the acceptance kept, active on neither (passes on main too)",
   "%s vs %s %s" % (read(clone("east") + "/links/%s.json" % LA), read(clone("west") + "/links/%s.json" % LA), listed))

# unlink and a cap change on east, a cap change on west; synced by board sync, so its pull with autostash merges them
pair("cap")
hook("east", "SessionStart", T + "/alpha", "S1")
LC = lid_of(on("east", ["link", "--from", T + "/alpha:lead", "--to", T + "/beta:builder", "--scope", "cap test", "--covers", "cap test", "--cap", "5",
                       "--to-session", "open"], SWITCHBOARD_SESSION_ID="S1")[1])
setup(LC != "", "link on east")
round_(front=True)
rcs = [on("east", ["link-cap", LC, "2"])[0], on("east", ["unlink", LC, "--reason", "east is done"])[0], on("west", ["link-cap", LC, "4"])[0]]
setup(rcs == [0, 0, 0], "unlink and caps: %s" % rcs)
rev = link("east", LC).get("revoked")
round_(front=True)
x = link("west", LC)
ok(clean("east") and clean("west") and same(LC) and x.get("revoked") == rev and "east is done" in x.get("closed_reason", "") and x.get("cap") == 2,
   "unlink on one machine and a cap change on both: both syncs succeed, and both clones hold the closed link with the lower cap",
   "%s %s" % (both(), read(clone("west") + "/links/%s.json" % LC)))

# two different closes; the earlier is on the machine that syncs second, so the merge keeps its own side
pair("close")
hook("east", "SessionStart", T + "/alpha", "S1")
LD = lid_of(on("east", ["link", "--from", T + "/alpha:lead", "--to", T + "/beta:builder", "--scope", "close test", "--covers", "close test", "--to-session", "open"],
               SWITCHBOARD_SESSION_ID="S1")[1])
setup(LD != "", "link on east")
round_()
rcs = [on("west", ["unlink", LD, "--reason", "west first"], SWITCHBOARD_NOW=str(NOW + 60))[0],
       on("east", ["unlink", LD, "--reason", "east later"], SWITCHBOARD_NOW=str(NOW + 600))[0]]
setup(rcs == [0, 0], "two closes: %s" % rcs)
round_()
x = link("east", LD)
ok(clean("east") and clean("west") and same(LD) and x.get("revoked") == NOW + 60 and "west first" in x.get("closed_reason", ""),
   "two different closes: both syncs succeed and both clones keep the earlier close with its reason",
   "%s %s" % (both(), read(clone("east") + "/links/%s.json" % LD)))



def edit(m, rel, **changes):  # a record rewritten in one clone as a writer would, with save()'s format
    r = js(read("%s/%s" % (clone(m), rel))) or dict()
    r.update(changes)
    write("%s/%s" % (clone(m), rel), json.dumps(r, indent=1, sort_keys=True) + "\n")


def same_file(rel):  # both clones at one commit, holding one copy of rel
    return read("%s/%s" % (clone("east"), rel)) == read("%s/%s" % (clone("west"), rel)) != "" and \
        git(clone("east"), "rev-parse", "HEAD")[1] == git(clone("west"), "rev-parse", "HEAD")[1]


# a hold released on east while west extends its until and changes its reason (no command does that yet: the record
# is rewritten as one would)
pair("hold")
w = on("east", ["hold", T + "/alpha", "--until", "2d", "--reason", "hold test"])[1].split()
H = w[1] if len(w) > 1 else ""
setup(H.startswith("h"), "hold on east")
round_()
until = (js(read("%s/holds/%s.json" % (clone("west"), H))) or dict()).get("until", 0) + 86400
setup(on("east", ["release", H], SWITCHBOARD_NOW=str(NOW + 60))[0] == 0, "release on east")
edit("west", "holds/%s.json" % H, until=until, reason="hold test, extended")
round_()
x = js(read("%s/holds/%s.json" % (clone("east"), H))) or dict()
ok(clean("east") and clean("west") and same_file("holds/%s.json" % H) and x.get("released") == NOW + 60 and
   x.get("until") == until and x.get("reason") == "hold test, extended",
   "a hold released on one machine and extended with a new reason on the other: both syncs succeed and both clones keep all three",
   "%s %s" % (both(), x))

# one role taken on both machines, by a session on each; the later binding stands on both
pair("role")
hook("east", "SessionStart", T + "/alpha", "S1"); hook("west", "SessionStart", T + "/alpha", "S3")
round_()
r1 = on("east", ["role", "lead"], SWITCHBOARD_SESSION_ID="S1")[0]
r3 = on("west", ["role", "lead"], SWITCHBOARD_SESSION_ID="S3", SWITCHBOARD_NOW=str(NOW + 60))[0]
rp = [f for f in os.listdir(clone("east") + "/roles") if f.endswith("--lead.json")]
setup(r1 == r3 == 0 and len(rp) == 1, "lead taken on both: %s %s %s" % (r1, r3, rp))
round_()
x = js(read("%s/roles/%s" % (clone("west"), rp[0]))) or dict()
ok(clean("east") and clean("west") and same_file("roles/" + rp[0]) and x.get("session_id") == "S3" and x.get("machine") == "west",
   "a role taken on both machines: both syncs succeed and both clones hold the later binding whole", "%s %s" % (both(), x))

# a session record changed on both machines: bind clearing the role of a holder on the other machine (the known
# two-writer case) while its own machine refreshes it
pair("sess")
hook("east", "SessionStart", T + "/alpha", "S1"); on("east", ["role", "lead"], SWITCHBOARD_SESSION_ID="S1")
round_()
sp = [f for f in os.listdir(clone("east") + "/sessions") if f.startswith("east-") and f.endswith("S1.json")]
setup(len(sp) == 1 and (js(read("%s/sessions/%s" % (clone("west"), sp[0]))) or dict()).get("role") == "lead", "session record of S1: %s" % sp)
seen = (js(read("%s/sessions/%s" % (clone("east"), sp[0]))) or dict()).get("seen", 0) + 3600
edit("east", "sessions/" + sp[0], seen=seen, name="road again")
edit("west", "sessions/" + sp[0], role="")
round_()
x = js(read("%s/sessions/%s" % (clone("east"), sp[0]))) or dict()
ok(clean("east") and clean("west") and same_file("sessions/" + sp[0]) and x.get("role") == "" and x.get("seen") == seen and
   x.get("name") == "road again", "a session record changed on both machines: both syncs succeed and both clones keep both changes",
   "%s %s" % (both(), x))


# a release beats only the binding it released: west binds S3 to alpha:lead and releases it; between the two, east
# binds S1. lead is open in the base
pair("release")
hook("east", "SessionStart", T + "/alpha", "S1"); hook("west", "SessionStart", T + "/alpha", "S3")
on("east", ["role", "lead"], SWITCHBOARD_SESSION_ID="S1"); on("east", ["role", "spare"], SWITCHBOARD_SESSION_ID="S1")
round_()
rp = [f for f in os.listdir(clone("east") + "/roles") if f.endswith("--lead.json")]
setup(len(rp) == 1 and (js(read("%s/roles/%s" % (clone("west"), rp[0]))) or dict()).get("open"), "alpha:lead open in the base: %s" % rp)
rcs = [on("west", ["role", "lead"], SWITCHBOARD_SESSION_ID="S3", SWITCHBOARD_NOW=str(NOW + 10))[0],
       on("west", ["role", "other"], SWITCHBOARD_SESSION_ID="S3", SWITCHBOARD_NOW=str(NOW + 30))[0],
       on("east", ["role", "lead"], SWITCHBOARD_SESSION_ID="S1", SWITCHBOARD_NOW=str(NOW + 20))[0]]
x = js(read("%s/roles/%s" % (clone("west"), rp[0]))) or dict()
setup(rcs == [0, 0, 0] and x.get("open") == NOW + 30 and x.get("was") == "S3", "bind and release on west: %s %s" % (rcs, x))
round_()
x = js(read("%s/roles/%s" % (clone("east"), rp[0]))) or dict()
ok(clean("east") and clean("west") and same_file("roles/" + rp[0]) and x.get("session_id") == "S1" and not x.get("open"),
   "a binding on one machine is kept against a release, on the other, of a different session that held the role",
   "%s %s" % (both(), x))

# both machines accept one proposal, whose beta end is open: the link and the role file name the same, later session,
# and that session gets messages over the link
pair("accept2")
hook("east", "SessionStart", T + "/alpha", "S1"); on("east", ["role", "roadmap"], SWITCHBOARD_SESSION_ID="S1")
LB = lid_of(on("east", ["link", "--from", T + "/alpha:roadmap", "--to", T + "/beta:implementer", "--scope", "two accepts", "--covers", "two accepts"],
               SWITCHBOARD_SESSION_ID="S1", SWITCHBOARD_TEST_PROPOSE="1")[1])
hook("west", "SessionStart", T + "/beta", "S2"); hook("east", "SessionStart", T + "/beta", "S4")
round_()
rcs = [on("west", ["link", "accept", LB], SWITCHBOARD_SESSION_ID="S2", SWITCHBOARD_TEST_PROPOSE="1", SWITCHBOARD_NOW=str(NOW + 100))[0],
       on("east", ["link", "accept", LB], SWITCHBOARD_SESSION_ID="S4", SWITCHBOARD_TEST_PROPOSE="1", SWITCHBOARD_NOW=str(NOW + 200))[0]]
setup(LB != "" and rcs == [0, 0], "two accepts: %s %s" % (LB, rcs))
round_()
rp = [f for f in os.listdir(clone("east") + "/roles") if f.endswith("--implementer.json")]
x, r = link("east", LB), js(read("%s/roles/%s" % (clone("west"), rp[0] if rp else "none"))) or dict()
msg = '<cross-session-message from="uds:%s" from-name="road" from-mode="prompting">\nnext: build Y\n</cross-session-message>' % SOCK1
note = hook("east", "UserPromptSubmit", T + "/beta", "S4", prompt=msg)[1]
ok(clean("east") and clean("west") and same(LB) and same_file("roles/" + rp[0]) and
   (x.get("accepted_by") or dict()).get("session") == "S4" and r.get("session_id") == "S4" and "This message arrives over link %s" % LB in note,
   "both machines accept one proposal: link and role file name the later session, and it gets messages over the link",
   "%s link %s role %s note %s" % (both(), x.get("accepted_by"), r, note[:300]))

# a driver value an earlier version wrote, twice, is replaced by the one current value
pair("stale")
for v in ('"$HOME/.claude/board" merge-link %O %A %B', "old", "sh -c 'b=\"$HOME/.claude/board\"; if [ -x \"$b\" ]; then exec "
          "\"$b\" merge-link \"$@\"; fi; exec git merge-file \"$2\" \"$1\" \"$3\"' board %O %A %B"):  # the last, the live machines'
    git(clone("east"), "config", "--add", "merge.board-link.driver", v)
syncw("east", front=True)
vals = git(clone("east"), "config", "--get-all", "merge.board-link.driver")[1].splitlines()
ok(vals == [drv_of("merge-link", "%O %A %B", state("east"))] and clean("east"), "board sync replaces older driver values with the one current value", str(vals))
# what no driver can merge (a record that is not JSON) still stops the sync, and status names its path: in the rebase
# of the job, and in the autostash of board sync, where git leaves the markers in the file
for name, front in (("bad", False), ("stash", True)):
    pair(name)
    w = on("east", ["hold", T + "/alpha", "--until", "2d", "--reason", name + " test"])[1].split()
    H = w[1] if len(w) > 1 else ""
    setup(H.startswith("h"), "hold on east")
    round_(front)
    on("east", ["release", H], SWITCHBOARD_NOW=str(NOW + 60)); write("%s/holds/%s.json" % (clone("west"), H), "nope\n")
    round_(front)
    named = re.search(r"last failure .*NOT RECOVERED.*conflict in holds/%s\.json" % H, sync_line("west"))
    if not front:
        ok(named and not os.path.exists(clone("west") + "/.git/rebase-merge"),
           "a record no driver can merge fails the sync, with no rebase left, and status names its path", both())
    else:
        remote = js(run(["git", "-C", "%s/%s.git" % (T, name), "show", "main:holds/%s.json" % H])[1]) or dict()
        ok(named and remote.get("released") == NOW + 60,
           "an autostash that did not apply is not committed: no conflict markers reach the remote, and status names the path",
           "%s remote: %s" % (both(), remote))

# no board at the stable path: the drivers fall back to the three-way merge of git, so what git merges with no driver
# still merges and a real conflict stops the sync as it does with no driver (both as on main)
os.rename(os.environ["HOME"] + "/.claude/board", T + "/board.away")
pair("noboard")
hook("east", "SessionStart", T + "/alpha", "S1"); on("east", ["role", "roadmap"], SWITCHBOARD_SESSION_ID="S1")
LN = lid_of(on("east", ["link", "--from", T + "/alpha:roadmap", "--to", T + "/beta:implementer", "--scope", "no board", "--covers", "no board"],
               SWITCHBOARD_SESSION_ID="S1", SWITCHBOARD_TEST_PROPOSE="1")[1])
hook("west", "SessionStart", T + "/beta", "S2"); on("west", ["role", "implementer"], SWITCHBOARD_SESSION_ID="S2")
for m in ("east", "west"):  # nor the state dir's cli link: with no ~/.claude/board leading to this CLI and no
    setup(not os.path.lexists(state(m) + "/cli"), "no cli link on %s" % m)  # CLAUDE_PLUGIN_ROOT, a session start makes none
round_()
rc = on("west", ["link", "accept", LN], SWITCHBOARD_SESSION_ID="S2", SWITCHBOARD_TEST_PROPOSE="1")[0]
hook("east", "UserPromptSubmit", T + "/alpha", "S1", SWITCHBOARD_NOW=str(NOW + 25 * 3600))
setup(rc == 0 and "proposal expired" in link("east", LN).get("closed_reason", ""), "accept and expiry with no board: %s %s" % (rc, link("east", LN)))
round_()
x = link("east", LN)
ok(clean("east") and clean("west") and same(LN) and x.get("revoked") and (x.get("accepted_by") or dict()).get("session") == "S2",
   "with no board at the stable path, accept against expiry still merges, through the fallback to git merge-file (as on main)", both())
on("west", ["unlink", LN, "--reason", "west"], SWITCHBOARD_NOW=str(NOW + 26 * 3600))
on("east", ["unlink", LN, "--reason", "east"], SWITCHBOARD_NOW=str(NOW + 27 * 3600))
round_()
ok(re.search(r"last failure .*NOT RECOVERED.*conflict in links/%s\.json" % LN, sync_line("west")) and clean("east"),
   "with no board, two closes of one link stop the sync of the second machine, and status names the file", both())
os.rename(T + "/board.away", os.environ["HOME"] + "/.claude/board")
sys.exit(1 if failed else 0)
PY
finish
