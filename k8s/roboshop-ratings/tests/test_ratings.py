"""Unit tests for the ratings Flask service.

External systems mocked:
  * New Relic is neutralised in conftest.py before import.
  * MySQL (pymysql) is never dialled - app.get_db is patched to return a fake
    connection whose cursor supports the context-manager + execute/fetchall/
    fetchone interface that app.py relies on.
"""
import pytest

import app as ratings_app


class FakeCursor:
    """Stand-in for a pymysql DictCursor used as a context manager."""

    def __init__(self, fetchall=None, fetchone=None):
        self._fetchall = fetchall if fetchall is not None else []
        self._fetchone = fetchone if fetchone is not None else {}
        self.executed = []

    def __enter__(self):
        return self

    def __exit__(self, *exc):
        return False

    def execute(self, sql, params=None):
        self.executed.append((sql, params))

    def fetchall(self):
        return self._fetchall

    def fetchone(self):
        return self._fetchone


class FakeConn:
    def __init__(self, cursor):
        self._cursor = cursor
        self.closed = False

    def cursor(self):
        return self._cursor

    def close(self):
        self.closed = True


@pytest.fixture
def client():
    ratings_app.app.config["TESTING"] = True
    return ratings_app.app.test_client()


def _patch_db(monkeypatch, cursor):
    conn = FakeConn(cursor)
    monkeypatch.setattr(ratings_app, "get_db", lambda: conn)
    return conn


def test_health(client):
    resp = client.get("/health")
    assert resp.status_code == 200
    assert resp.get_json() == {"status": "OK", "service": "ratings"}


def test_missing_fields_returns_400(client, monkeypatch):
    # get_db must NOT be reached for a validation failure.
    monkeypatch.setattr(ratings_app, "get_db",
                        lambda: (_ for _ in ()).throw(AssertionError("db hit")))
    resp = client.post("/ratings", json={"productId": 1, "userId": 2})  # no score

    assert resp.status_code == 400
    assert resp.get_json() == {"error": "productId, userId, and score are required"}


def test_score_out_of_range_returns_400(client, monkeypatch):
    monkeypatch.setattr(ratings_app, "get_db",
                        lambda: (_ for _ in ()).throw(AssertionError("db hit")))
    resp = client.post("/ratings", json={"productId": 1, "userId": 2, "score": 6})

    assert resp.status_code == 400
    assert resp.get_json() == {"error": "Score must be between 1 and 5"}


def test_add_rating_ok(client, monkeypatch):
    cursor = FakeCursor()
    conn = _patch_db(monkeypatch, cursor)

    resp = client.post("/ratings",
                       json={"productId": 10, "userId": 20, "score": 4, "review": "nice"})

    assert resp.status_code == 200
    assert resp.get_json() == {"status": "ok"}
    # Insert was executed and the connection closed.
    assert len(cursor.executed) == 1
    assert "INSERT INTO ratings" in cursor.executed[0][0]
    assert cursor.executed[0][1] == (10, 20, 4, "nice", 4, "nice")
    assert conn.closed is True


def test_get_ratings_returns_list(client, monkeypatch):
    rows = [
        {"id": 1, "product_id": 10, "user_id": 20, "score": 5,
         "review": "great", "created_at": "2026-07-08T00:00:00"},
        {"id": 2, "product_id": 10, "user_id": 21, "score": 3,
         "review": "ok", "created_at": "2026-07-07T00:00:00"},
    ]
    _patch_db(monkeypatch, FakeCursor(fetchall=rows))

    resp = client.get("/ratings/product/10")

    assert resp.status_code == 200
    data = resp.get_json()
    assert isinstance(data, list)
    assert len(data) == 2
    assert data[0]["score"] == 5


def test_average_computes_float_and_count(client, monkeypatch):
    _patch_db(monkeypatch, FakeCursor(fetchone={"average": 4.5, "count": 2}))

    resp = client.get("/ratings/product/10/average")

    assert resp.status_code == 200
    data = resp.get_json()
    assert data == {"productId": 10, "average": 4.5, "count": 2}
    assert isinstance(data["average"], float)


def test_average_no_ratings_returns_zero(client, monkeypatch):
    _patch_db(monkeypatch, FakeCursor(fetchone={"average": None, "count": 0}))

    resp = client.get("/ratings/product/99/average")

    assert resp.status_code == 200
    assert resp.get_json() == {"productId": 99, "average": 0, "count": 0}
