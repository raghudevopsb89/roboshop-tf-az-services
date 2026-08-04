"""Test bootstrap for the ratings service.

Runs before any test module is imported, so it neutralises New Relic (which
``app.py`` initialises at import time) before ``app`` is ever imported.
"""
import os
import sys
from unittest.mock import MagicMock

# Point MySQL at an obviously-fake host; get_db is patched in tests so this is
# only a belt-and-braces safety net.
os.environ.setdefault("MYSQL_HOST", "mysql.test")

try:
    import newrelic.agent  # noqa: E402

    newrelic.agent.initialize = lambda *a, **k: None
except Exception:  # pragma: no cover - full stub if newrelic is unavailable
    nr = MagicMock()
    sys.modules["newrelic"] = nr
    sys.modules["newrelic.agent"] = nr.agent
