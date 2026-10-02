# Loaded by every Python process the self-test starts (tests/lib.sh puts this dir on PYTHONPATH). Records each
# uncaught exception in $SWITCHBOARD_CRASHLOG so a section fails on a crash even where a check expects no output.
import os
import sys
import traceback

_log = os.environ.get("SWITCHBOARD_CRASHLOG")
if _log:
    _prev = sys.excepthook

    def _record(t, v, tb):
        try:
            with open(_log, "a") as f:
                f.write("%s: %s\n" % (" ".join(sys.argv[:3]), "".join(traceback.format_exception(t, v, tb))[-800:]))
        except Exception:
            pass
        _prev(t, v, tb)

    sys.excepthook = _record

# SWITCHBOARD_TEST_FAULT=<dir>: Path.glob on that dir raises OSError, as a failing disk or mount would; with
# SWITCHBOARD_TEST_FAULT_GLOB=<pattern>, only a glob for that pattern. For checks that a reader fails closed, or a
# hook step fails alone, on a real error now that bad record files read as no record.
_fault = os.environ.get("SWITCHBOARD_TEST_FAULT")
if _fault:
    import pathlib
    _glob, _only = pathlib.Path.glob, os.environ.get("SWITCHBOARD_TEST_FAULT_GLOB")

    def _faulty_glob(self, *a, **k):
        if os.path.abspath(str(self)) == os.path.abspath(_fault) and (not _only or a[:1] == (_only,)):
            raise OSError(5, "test fault", str(self))
        return _glob(self, *a, **k)

    pathlib.Path.glob = _faulty_glob

# SWITCHBOARD_TEST_PLATFORM=Linux|Darwin: platform.system() says that, so one machine checks what init --always-on
# writes for systemd and for launchd (38-init.sh, with systemctl and launchctl stubbed on PATH)
_platform = os.environ.get("SWITCHBOARD_TEST_PLATFORM")
if _platform:
    import platform

    platform.system = lambda: _platform
