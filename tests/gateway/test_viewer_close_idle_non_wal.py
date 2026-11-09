"""Boot's orphan-close sweep must not nest read contexts on a DB without WAL.

Without WAL (a WAL-reset-vulnerable SQLite such as 3.45.3, where Hermes keeps journal_mode=DELETE)
every ``_read_ctx`` holds the writer's non-reentrant ``_lock``. ``_idle_s`` resolved the physical
target inside its own read context, so the nested ``local_receipt`` read waited on the lock its
caller held: the gateway's event loop froze at startup, ``gateway ensure`` answered
``starting (deadline)`` and the watchdog killed the owner every two minutes.
"""
import threading
from types import SimpleNamespace


class _BoundedLock:
    """The writer lock, except that a re-entry fails fast instead of hanging the test run."""

    def __init__(self):
        self._lock = threading.Lock()

    def __enter__(self):
        if not self._lock.acquire(timeout=5):
            raise AssertionError('nested SessionDB read context: the non-reentrant writer lock deadlocks')
        return self

    def __exit__(self, *exc):
        self._lock.release()

    def acquire(self, *args, **kwargs):
        return self._lock.acquire(*args, **kwargs)

    def release(self):
        self._lock.release()

    def locked(self):
        return self._lock.locked()


def test_idle_s_without_wal_does_not_nest_read_contexts(tmp_path, monkeypatch):
    from gateway.session_viewer_close import _idle_s
    from hermes_state import SessionDB

    monkeypatch.setenv('HERMES_HOME', str(tmp_path))
    db = SessionDB(tmp_path / 'state.db')
    try:
        db.create_session('chat', source='cli', model='fake-model', cwd=str(tmp_path))
        db.append_message('chat', 'user', 'q')
        db._wal_active = False  # the vulnerable-SQLite path: reads go through the writer lock
        db._lock = _BoundedLock()

        assert _idle_s(SimpleNamespace(db=db), 'chat') >= 0.0
    finally:
        db.close()
