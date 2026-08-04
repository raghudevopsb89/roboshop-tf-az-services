"""Component integration test for the payment service against a FAKE Service Bus.

The unit tests (tests/test_payment.py) patch ``publish_order`` outright. Here we
go one layer deeper: we replace ``ServiceBusClient`` with an in-process fake so
the app's own ``connect_servicebus()`` and ``publish_order()`` run for real
(building a real ``ServiceBusMessage``) and we then assert the message that
would have gone on the wire — the right queue and payload, exactly what the
orders service's Service Bus consumer will read.

No Docker and no Azure account required, so this runs anywhere.
"""
import json

import pytest
from fastapi.testclient import TestClient
from unittest.mock import AsyncMock, MagicMock

import main

pytestmark = pytest.mark.integration


class FakeSender:
    def __init__(self, sink, queue_name):
        self.sink = sink
        self.queue_name = queue_name

    def __enter__(self):
        return self

    def __exit__(self, *a):
        return False

    def send_messages(self, message):
        # ServiceBusMessage stringifies to its body.
        self.sink.append({"queue": self.queue_name, "body": str(message)})


class FakeServiceBusClient:
    last = None

    def __init__(self):
        self.sent = []
        FakeServiceBusClient.last = self

    @classmethod
    def from_connection_string(cls, _conn):
        return cls()

    def get_queue_sender(self, queue_name):
        return FakeSender(self.sent, queue_name)

    def close(self):
        pass


def _resp(status_code=200, payload=None):
    r = MagicMock()
    r.status_code = status_code
    r.json = MagicMock(return_value=payload if payload is not None else {})
    return r


@pytest.fixture
def wired(monkeypatch):
    monkeypatch.setattr(main, "ServiceBusClient", FakeServiceBusClient)
    monkeypatch.setattr(main, "SERVICEBUS_QUEUE", "orders")
    # Real connect using the fake client.
    main.connect_servicebus()

    http = AsyncMock()
    monkeypatch.setattr(main, "http_client", http)
    tc = TestClient(main.app)
    tc.mock_http = http
    return tc


def test_order_event_is_published_to_orders_queue(wired):
    user_resp = _resp(200, {"email": "ann@example.com", "firstName": "Ann"})
    cart_resp = _resp(200, {"items": [{"productId": 1, "price": 100, "quantity": 2}]})
    wired.mock_http.get = AsyncMock(side_effect=[user_resp, cart_resp])
    wired.mock_http.delete = AsyncMock(return_value=_resp(200, {}))

    resp = wired.post("/payment/process", json={"userId": "u42", "cityId": 7})
    assert resp.status_code == 200

    sent = FakeServiceBusClient.last.sent
    assert len(sent) == 1
    assert sent[0]["queue"] == "orders"
    event = json.loads(sent[0]["body"])
    assert event["userId"] == "u42"
    assert event["total"] == 200
    assert event["cityId"] == 7
