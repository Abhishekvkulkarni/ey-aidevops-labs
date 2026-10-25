"""Ready-made tests for the Shipwave API. Copy to api/tests/ (Block 2 solo challenge)."""
import pytest
from fastapi.testclient import TestClient

from app.main import app
from app.pagination import paginate

KEY = "test-key"
HEADERS = {"X-API-Key": KEY}


@pytest.fixture(autouse=True)
def api_key(monkeypatch):
    monkeypatch.setenv("API_KEY", KEY)


@pytest.fixture
def client():
    return TestClient(app)


def test_health_is_ok(client):
    r = client.get("/health")
    assert r.status_code == 200
    assert r.json() == {"status": "ok"}


def test_list_requires_key(client):
    assert client.get("/shipments").status_code == 401


def test_list_rejects_wrong_key(client):
    assert client.get("/shipments", headers={"X-API-Key": "nope"}).status_code == 401


def test_list_with_key_returns_first_page(client):
    r = client.get("/shipments", headers=HEADERS)
    assert r.status_code == 200
    assert [s["id"] for s in r.json()] == list(range(1, 11))


def test_second_page(client):
    r = client.get("/shipments?page=2&size=10", headers=HEADERS)
    assert [s["id"] for s in r.json()] == list(range(11, 21))


def test_page_size_is_respected(client):
    r = client.get("/shipments?page=1&size=5", headers=HEADERS)
    assert len(r.json()) == 5


def test_page_zero_is_bad_request(client):
    assert client.get("/shipments?page=0", headers=HEADERS).status_code == 400


def test_read_one(client):
    r = client.get("/shipments/3", headers=HEADERS)
    assert r.status_code == 200
    assert r.json()["ref"] == "SW-1003"


def test_read_missing_is_404(client):
    assert client.get("/shipments/9999", headers=HEADERS).status_code == 404


def test_paginate_is_one_based():
    assert paginate(list(range(30)), 1, 10) == list(range(10))
    assert paginate(list(range(30)), 3, 10) == list(range(20, 30))


def test_paginate_rejects_zero():
    with pytest.raises(ValueError):
        paginate([1, 2, 3], 0, 10)
