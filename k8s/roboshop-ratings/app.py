import newrelic.agent
newrelic.agent.initialize()

import os
import json
import time
import signal
import logging
import pymysql
from flask import Flask, request, jsonify, g
from flask_cors import CORS
from prometheus_flask_exporter import PrometheusMetrics

class JsonLogFormatter(logging.Formatter):
    def format(self, record):
        payload = {
            "ts": time.strftime("%Y-%m-%dT%H:%M:%S", time.gmtime(record.created)) + f".{int(record.msecs):03d}Z",
            "level": record.levelname.lower(),
            "service": "ratings",
            "msg": record.getMessage(),
        }
        if hasattr(record, "extra_fields"):
            payload.update(record.extra_fields)
        return json.dumps(payload)

_handler = logging.StreamHandler()
_handler.setFormatter(JsonLogFormatter())
logging.basicConfig(level=logging.INFO, handlers=[_handler], force=True)
logger = logging.getLogger("ratings")

def jlog(level, msg, **extra):
    rec = logger.makeRecord(logger.name, getattr(logging, level.upper()), "", 0, msg, None, None)
    rec.extra_fields = extra
    logger.handle(rec)

app = Flask(__name__)
CORS(app)
PrometheusMetrics(app, group_by="endpoint")

_req_seq = 0

@app.before_request
def _log_request_start():
    global _req_seq
    if request.path in ("/metrics", "/health"):
        return
    _req_seq += 1
    g.req_id = request.headers.get("X-Request-ID") or f"{os.getpid()}-{_req_seq}"
    g.req_start = time.monotonic()
    jlog("info", "req.start", reqId=g.req_id, method=request.method, path=request.path,
         remote=request.remote_addr)

@app.after_request
def _log_request_finish(response):
    if request.path in ("/metrics", "/health"):
        return response
    dur_ms = round((time.monotonic() - g.req_start) * 1000, 1) if hasattr(g, "req_start") else None
    jlog("info", "req.finish", reqId=getattr(g, "req_id", None), method=request.method, path=request.path,
         status=response.status_code, durMs=dur_ms)
    if hasattr(g, "req_id"):
        response.headers["X-Request-ID"] = g.req_id
    return response

@app.teardown_request
def _log_request_teardown(exc):
    if exc is not None:
        jlog("error", "req.error", reqId=getattr(g, "req_id", None), path=request.path, error=str(exc))

def _sig_handler(signum, _frame):
    jlog("warn", "server.shutdown.start", signal=signal.Signals(signum).name)

signal.signal(signal.SIGTERM, _sig_handler)
signal.signal(signal.SIGINT, _sig_handler)

MYSQL_HOST = os.getenv("MYSQL_HOST", "mysql")
MYSQL_USER = os.getenv("MYSQL_USER", "ratings")
MYSQL_PASSWORD = os.getenv("MYSQL_PASSWORD", "RoboShop@1")
MYSQL_DATABASE = os.getenv("MYSQL_DATABASE", "ratings")
# Azure Database for MySQL requires TLS. Set MYSQL_SSL=true to connect over SSL,
# verifying against the system CA bundle (overridable via MYSQL_SSL_CA).
MYSQL_SSL = os.getenv("MYSQL_SSL", "false").lower() == "true"
MYSQL_SSL_CA = os.getenv("MYSQL_SSL_CA", "/etc/ssl/certs/ca-certificates.crt")


def get_db():
    for i in range(30):
        try:
            connect_args = dict(
                host=MYSQL_HOST,
                user=MYSQL_USER,
                password=MYSQL_PASSWORD,
                database=MYSQL_DATABASE,
                cursorclass=pymysql.cursors.DictCursor,
                autocommit=True,
            )
            if MYSQL_SSL:
                connect_args["ssl"] = {"ca": MYSQL_SSL_CA}
            conn = pymysql.connect(**connect_args)
            return conn
        except Exception as e:
            logger.warning(f"MySQL connection attempt {i+1}/30 failed: {e}")
            time.sleep(2)
    raise Exception("Failed to connect to MySQL")


@app.route("/health")
def health():
    return jsonify({"status": "OK", "service": "ratings"})


@app.route("/ratings", methods=["POST"])
def add_rating():
    data = request.json
    product_id = data.get("productId")
    user_id = data.get("userId")
    score = data.get("score")
    review = data.get("review", "")

    if not all([product_id, user_id, score]):
        return jsonify({"error": "productId, userId, and score are required"}), 400

    if not (1 <= int(score) <= 5):
        return jsonify({"error": "Score must be between 1 and 5"}), 400

    conn = get_db()
    try:
        with conn.cursor() as cursor:
            cursor.execute(
                """INSERT INTO ratings (product_id, user_id, score, review)
                   VALUES (%s, %s, %s, %s)
                   ON DUPLICATE KEY UPDATE score = %s, review = %s""",
                (product_id, user_id, score, review, score, review),
            )
        logger.info(f"Rating added: product={product_id}, user={user_id}, score={score}")
        return jsonify({"status": "ok"})
    finally:
        conn.close()


@app.route("/ratings/product/<int:product_id>")
def get_ratings(product_id):
    conn = get_db()
    try:
        with conn.cursor() as cursor:
            cursor.execute(
                "SELECT id, product_id, user_id, score, review, created_at FROM ratings WHERE product_id = %s ORDER BY created_at DESC",
                (product_id,),
            )
            ratings = cursor.fetchall()
        return jsonify(ratings)
    finally:
        conn.close()


@app.route("/ratings/product/<int:product_id>/average")
def get_average(product_id):
    conn = get_db()
    try:
        with conn.cursor() as cursor:
            cursor.execute(
                "SELECT AVG(score) as average, COUNT(*) as count FROM ratings WHERE product_id = %s",
                (product_id,),
            )
            result = cursor.fetchone()
        return jsonify({
            "productId": product_id,
            "average": float(result["average"]) if result["average"] else 0,
            "count": result["count"],
        })
    finally:
        conn.close()


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=int(os.getenv("PORT", "8006")))
