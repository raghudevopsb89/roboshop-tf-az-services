import newrelic.agent
newrelic.agent.initialize()

import os
import sys
import json
import uuid
import time
import signal
import logging
import contextvars
from azure.servicebus import ServiceBusClient, ServiceBusMessage
from azure.servicebus.exceptions import ServiceBusError
import httpx
from fastapi import FastAPI, HTTPException, Request
from pydantic import BaseModel
from prometheus_fastapi_instrumentator import Instrumentator

SERVICE = "payment"
_req_id_ctx: contextvars.ContextVar = contextvars.ContextVar("req_id", default="-")


class JsonLogFormatter(logging.Formatter):
    _RESERVED = {
        "name", "msg", "args", "levelname", "levelno", "pathname", "filename",
        "module", "exc_info", "exc_text", "stack_info", "lineno", "funcName",
        "created", "msecs", "relativeCreated", "thread", "threadName",
        "processName", "process", "message", "asctime", "extra_fields",
        "taskName",
    }

    def format(self, record):
        payload = {
            "ts": time.strftime("%Y-%m-%dT%H:%M:%S", time.gmtime(record.created)) + f".{int(record.msecs):03d}Z",
            "level": record.levelname.lower(),
            "service": SERVICE,
            "logger": record.name,
            "reqId": _req_id_ctx.get(),
            "msg": record.getMessage(),
        }
        if record.exc_info:
            payload["exc"] = self.formatException(record.exc_info)
        if hasattr(record, "extra_fields") and isinstance(record.extra_fields, dict):
            payload.update(record.extra_fields)
        for k, v in record.__dict__.items():
            if k not in self._RESERVED and k not in payload:
                payload[k] = v
        return json.dumps(payload, default=str)


def _install_json_logging():
    handler = logging.StreamHandler(stream=sys.stdout)
    handler.setFormatter(JsonLogFormatter())
    root = logging.getLogger()
    for h in list(root.handlers):
        root.removeHandler(h)
    root.addHandler(handler)
    root.setLevel(logging.INFO)
    for name in ("uvicorn", "uvicorn.error", "uvicorn.access", "fastapi", "asyncio", "httpx", "pika"):
        lg = logging.getLogger(name)
        for h in list(lg.handlers):
            lg.removeHandler(h)
        lg.addHandler(handler)
        lg.propagate = False
        lg.setLevel(logging.INFO)


_install_json_logging()
logger = logging.getLogger("payment")


def jlog(level, msg, **extra):
    rec = logger.makeRecord(logger.name, getattr(logging, level.upper()), "", 0, msg, None, None)
    rec.extra_fields = extra
    logger.handle(rec)


app = FastAPI(title="RoboShop Payment Service")
Instrumentator().instrument(app).expose(app, include_in_schema=False, should_gzip=True)

_req_seq = 0


@app.middleware("http")
async def request_logger(request: Request, call_next):
    global _req_seq
    if request.url.path in ("/metrics", "/health"):
        return await call_next(request)
    _req_seq += 1
    req_id = request.headers.get("x-request-id") or f"{os.getpid()}-{_req_seq}"
    token = _req_id_ctx.set(req_id)
    request.state.req_id = req_id
    start = time.monotonic()
    jlog("info", "req.start", method=request.method, path=request.url.path,
         remote=request.client.host if request.client else None)
    status = 0
    event = "finish"
    try:
        response = await call_next(request)
        status = response.status_code
        response.headers["x-request-id"] = req_id
        return response
    except Exception as e:
        event = "error"
        jlog("error", "req.error", path=request.url.path, error=str(e))
        raise
    finally:
        dur_ms = round((time.monotonic() - start) * 1000, 1)
        jlog("info", f"req.{event}", method=request.method, path=request.url.path,
             status=status, durMs=dur_ms)
        _req_id_ctx.reset(token)


SERVICEBUS_CONNECTION_STRING = os.getenv("SERVICEBUS_CONNECTION_STRING", "")
SERVICEBUS_QUEUE = os.getenv("SERVICEBUS_QUEUE", "orders")
CART_URL = os.getenv("CART_URL", "http://cart:8003")
USER_URL = os.getenv("USER_URL", "http://user:8001")
HTTP_CONNECT_TIMEOUT = float(os.getenv("HTTP_CONNECT_TIMEOUT", "5"))
HTTP_READ_TIMEOUT = float(os.getenv("HTTP_READ_TIMEOUT", "60"))
HTTP_KEEPALIVE_EXPIRY = float(os.getenv("HTTP_KEEPALIVE_EXPIRY", "120"))

servicebus_client: ServiceBusClient | None = None
http_client: httpx.AsyncClient | None = None


def connect_servicebus():
    """Open the Service Bus client once at startup (retried)."""
    global servicebus_client
    for i in range(30):
        try:
            servicebus_client = ServiceBusClient.from_connection_string(SERVICEBUS_CONNECTION_STRING)
            jlog("info", "servicebus.connected", queue=SERVICEBUS_QUEUE)
            return
        except Exception as e:
            jlog("warn", "servicebus.connect.retry", attempt=i + 1, error=str(e))
            time.sleep(2)
    raise Exception("Failed to connect to Service Bus")


def publish_order(order_event: dict):
    """Send one order event to the Service Bus queue."""
    with servicebus_client.get_queue_sender(queue_name=SERVICEBUS_QUEUE) as sender:
        sender.send_messages(ServiceBusMessage(json.dumps(order_event)))


class PaymentRequest(BaseModel):
    userId: str
    cityId: int


@app.on_event("startup")
async def startup():
    global http_client
    connect_servicebus()
    http_client = httpx.AsyncClient(
        timeout=httpx.Timeout(connect=HTTP_CONNECT_TIMEOUT, read=HTTP_READ_TIMEOUT,
                              write=HTTP_READ_TIMEOUT, pool=HTTP_READ_TIMEOUT),
        limits=httpx.Limits(max_connections=None,
                            max_keepalive_connections=None,
                            keepalive_expiry=HTTP_KEEPALIVE_EXPIRY),
    )
    jlog("info", "server.listen", pid=os.getpid(), keepaliveExpiry=HTTP_KEEPALIVE_EXPIRY)


@app.on_event("shutdown")
async def shutdown_event():
    global http_client, servicebus_client
    if http_client is not None:
        try:
            await http_client.aclose()
        except Exception as e:
            jlog("warn", "http_client.close.failed", error=str(e))
        http_client = None
    if servicebus_client is not None:
        try:
            servicebus_client.close()
        except Exception as e:
            jlog("warn", "servicebus.close.failed", error=str(e))
        servicebus_client = None
    jlog("warn", "server.shutdown.done", pid=os.getpid())
    try:
        sys.stdout.flush()
    except Exception:
        pass


def _sig_handler(signum, _frame):
    jlog("warn", "server.shutdown.start", signal=signal.Signals(signum).name)
    try:
        sys.stdout.flush()
    except Exception:
        pass


signal.signal(signal.SIGTERM, _sig_handler)
signal.signal(signal.SIGINT, _sig_handler)


@app.get("/health")
def health():
    return {"status": "OK", "service": "payment"}


def _trace_headers(req_id: str):
    return {"x-request-id": req_id}


@app.post("/payment/process")
async def process_payment(req: Request, payment: PaymentRequest):
    req_id = getattr(req.state, "req_id", "-")
    headers = _trace_headers(req_id)
    try:
        user_resp = await http_client.get(f"{USER_URL}/validate/{payment.userId}", headers=headers)
        if user_resp.status_code != 200:
            jlog("warn", "user.validate.bad_status", status=user_resp.status_code, userId=payment.userId)
            raise HTTPException(status_code=400, detail="Invalid user")
        user = user_resp.json()
    except httpx.RequestError as e:
        jlog("error", "user.unreachable", error=str(e), userId=payment.userId)
        raise HTTPException(status_code=503, detail="User service unavailable")

    try:
        cart_resp = await http_client.get(f"{CART_URL}/cart/{payment.userId}", headers=headers)
        if cart_resp.status_code != 200:
            jlog("warn", "cart.get.bad_status", status=cart_resp.status_code, userId=payment.userId)
            raise HTTPException(status_code=400, detail="Failed to get cart")
        cart = cart_resp.json()
    except httpx.RequestError as e:
        jlog("error", "cart.unreachable", error=str(e), userId=payment.userId)
        raise HTTPException(status_code=503, detail="Cart service unavailable")

    if not cart.get("items"):
        jlog("warn", "cart.empty", userId=payment.userId)
        raise HTTPException(status_code=400, detail="Cart is empty")

    total = sum(item["price"] * item["quantity"] for item in cart["items"])
    transaction_id = f"TXN-{uuid.uuid4().hex[:8].upper()}"

    order_event = {
        "userId": payment.userId,
        "userEmail": user.get("email", ""),
        "userName": user.get("firstName", "Customer"),
        "items": cart["items"],
        "total": total,
        "cityId": payment.cityId,
        "transactionId": transaction_id,
        "status": "PAID",
    }

    try:
        publish_order(order_event)
        jlog("info", "payment.processed", transactionId=transaction_id, userId=payment.userId, total=total)
    except ServiceBusError as e:
        jlog("error", "servicebus.publish.failed", error=str(e), transactionId=transaction_id)
        connect_servicebus()
        publish_order(order_event)
        jlog("info", "payment.processed.retry", transactionId=transaction_id, userId=payment.userId)

    try:
        await http_client.delete(f"{CART_URL}/cart/{payment.userId}", headers=headers)
    except Exception as e:
        jlog("warn", "cart.clear.failed", error=str(e), userId=payment.userId)

    return {
        "status": "SUCCESS",
        "transactionId": transaction_id,
        "total": total,
    }

#
