"""Component integration tests for the ratings service against a REAL MySQL.

Unlike the unit tests (tests/test_ratings.py) which mock ``app.get_db`` with an
in-memory fake, these tests stand up an actual MySQL 8 server in a container via
Testcontainers, provision the real schema from ``db/schema.sql`` (which carries the
UNIQUE KEY that drives ``INSERT ... ON DUPLICATE KEY UPDATE``), and exercise the app
end-to-end through Flask's test client. Nothing about the database layer is mocked, so
these tests prove real persistence, real upsert semantics, and real SQL aggregation.

Run with:   pytest -m integration
They are excluded from the default (unit) run by the ``-m "not integration"`` addopts.
"""
import os
import re

import pymysql
import pytest
from testcontainers.mysql import MySqlContainer

import app as ratings_app

# Credentials/database match the app's production defaults (app.py MYSQL_* env). The
# mysql image auto-creates this database + user (with ALL privileges on it) from the
# MYSQL_DATABASE / MYSQL_USER / MYSQL_PASSWORD env that MySqlContainer injects.
DB_USER = "ratings"
DB_PASSWORD = "RoboShop@1"
DB_NAME = "ratings"

# Image is overridable so offline/air-gapped runners can point at a locally cached tag;
# CI uses the default mysql:8 image.
MYSQL_IMAGE = os.getenv("TC_MYSQL_IMAGE", "mysql:8")

_SCHEMA_PATH = os.path.join(os.path.dirname(__file__), "..", "..", "db", "schema.sql")


def _table_ddl_from_schema(sql_text: str) -> str:
    """Extract the CREATE TABLE statement from db/schema.sql.

    We connect straight to the container's ``ratings`` database as the ``ratings``
    user, so the CREATE DATABASE / USE statements in the file are neither needed nor
    permitted for a non-root user -- we run only the table DDL, which the ratings user
    is privileged to execute on its own database.
    """
    match = re.search(r"CREATE TABLE.*?\);", sql_text, re.IGNORECASE | re.DOTALL)
    if not match:  # pragma: no cover - guards against schema.sql drifting
        raise AssertionError("Could not find CREATE TABLE in db/schema.sql")
    return match.group(0)


@pytest.fixture(scope="session")
def mysql_container():
    with MySqlContainer(
        MYSQL_IMAGE,
        username=DB_USER,
        password=DB_PASSWORD,
        dbname=DB_NAME,
    ) as mysql:
        host = mysql.get_container_host_ip()
        port = int(mysql.get_exposed_port(3306))

        with open(_SCHEMA_PATH, "r", encoding="utf-8") as fh:
            ddl = _table_ddl_from_schema(fh.read())

        # Provision the real schema against the running container.
        conn = pymysql.connect(
            host=host, port=port, user=DB_USER, password=DB_PASSWORD,
            database=DB_NAME, autocommit=True,
        )
        try:
            with conn.cursor() as cur:
                cur.execute(ddl)
        finally:
            conn.close()

        yield {"host": host, "port": port}


@pytest.fixture
def client(mysql_container, monkeypatch):
    """Flask test client wired to the REAL container.

    app.get_db() hardcodes params from env but omits the port; the container maps 3306
    to a random host port, so we override get_db to connect (with the port) to the
    container. Each test starts from a clean ``ratings`` table.
    """
    host = mysql_container["host"]
    port = mysql_container["port"]

    def real_get_db():
        return pymysql.connect(
            host=host,
            port=port,
            user=DB_USER,
            password=DB_PASSWORD,
            database=DB_NAME,
            cursorclass=pymysql.cursors.DictCursor,
            autocommit=True,
        )

    monkeypatch.setattr(ratings_app, "get_db", real_get_db)

    # Clean slate so counts/averages are deterministic across tests.
    conn = real_get_db()
    try:
        with conn.cursor() as cur:
            cur.execute("TRUNCATE TABLE ratings")
    finally:
        conn.close()

    ratings_app.app.config["TESTING"] = True
    return ratings_app.app.test_client()


@pytest.mark.integration
def test_post_persists_and_is_readable(client):
    """POST /ratings really writes a row that GET /ratings/product/<id> reads back."""
    resp = client.post(
        "/ratings",
        json={"productId": 101, "userId": "alice", "score": 5, "review": "excellent"},
    )
    assert resp.status_code == 200
    assert resp.get_json() == {"status": "ok"}

    read = client.get("/ratings/product/101")
    assert read.status_code == 200
    rows = read.get_json()
    assert len(rows) == 1
    assert rows[0]["product_id"] == 101
    assert rows[0]["user_id"] == "alice"
    assert rows[0]["score"] == 5
    assert rows[0]["review"] == "excellent"


@pytest.mark.integration
def test_second_rating_same_user_product_upserts(client):
    """A second rating for the SAME (product,user) UPDATES rather than duplicates.

    This exercises the real UNIQUE KEY (user_id, product_id) + ON DUPLICATE KEY UPDATE
    that unit tests mock away.
    """
    first = client.post(
        "/ratings",
        json={"productId": 202, "userId": "bob", "score": 2, "review": "meh"},
    )
    assert first.status_code == 200

    second = client.post(
        "/ratings",
        json={"productId": 202, "userId": "bob", "score": 4, "review": "changed my mind"},
    )
    assert second.status_code == 200

    rows = client.get("/ratings/product/202").get_json()
    assert len(rows) == 1, "duplicate (product,user) must upsert, not insert a new row"
    assert rows[0]["score"] == 4
    assert rows[0]["review"] == "changed my mind"

    avg = client.get("/ratings/product/202/average").get_json()
    assert avg["count"] == 1
    assert avg["average"] == 4.0


@pytest.mark.integration
def test_average_computed_by_real_sql_across_users(client):
    """/average returns AVG(score) computed by real SQL over multiple distinct users."""
    for user, score in [("u1", 5), ("u2", 3), ("u3", 4)]:
        r = client.post(
            "/ratings",
            json={"productId": 303, "userId": user, "score": score},
        )
        assert r.status_code == 200

    avg = client.get("/ratings/product/303/average").get_json()
    assert avg["productId"] == 303
    assert avg["count"] == 3
    assert avg["average"] == pytest.approx((5 + 3 + 4) / 3)  # 4.0
    assert isinstance(avg["average"], float)


@pytest.mark.integration
def test_score_validation_still_returns_400(client):
    """Score validation rejects out-of-range values before touching the DB (still 400)."""
    resp = client.post(
        "/ratings",
        json={"productId": 404, "userId": "carol", "score": 6},
    )
    assert resp.status_code == 400
    assert resp.get_json() == {"error": "Score must be between 1 and 5"}

    # Nothing was persisted.
    rows = client.get("/ratings/product/404").get_json()
    assert rows == []
