"""Cloud mode: state lives in (fake) Redis and survives cold starts on any instance."""
import json

import pytest
from fastapi.testclient import TestClient

from app import store, walks
from app.main import app


class FakeRedis:
    def __init__(self):
        self.kv = {}

    def __call__(self, *args):
        op = args[0]
        if op == "GET":
            return self.kv.get(args[1])
        if op == "SET":
            if "NX" in args and args[1] in self.kv:
                return None
            self.kv[args[1]] = args[2]
            return "OK"
        if op == "EVAL":
            key, token = args[3], args[4]
            if self.kv.get(key) == token:
                del self.kv[key]
                return 1
            return 0
        raise AssertionError(op)


@pytest.fixture
def cloud(monkeypatch):
    fake = FakeRedis()
    monkeypatch.setenv("KV_REST_API_URL", "https://fake.upstash.io")
    monkeypatch.setenv("KV_REST_API_TOKEN", "t")
    monkeypatch.setattr(store, "_cmd", fake)
    yield fake
    walks.reset()


def cold_start():
    """Simulate a fresh serverless instance: wipe in-memory state."""
    walks.STATE.clear()
    walks.STATE.update({"users": {}, "walks": {}, "alerts": {}, "seq": 0})


def shift_clock(fake, seconds):
    """Move every walk's sim clock forward in the stored snapshot."""
    data = json.loads(fake.kv[store.KEY])
    for w in data["walks"].values():
        w["clock"]["base_sim"] += seconds
    fake.kv[store.KEY] = json.dumps(data)


def test_state_survives_cold_starts_and_escalates(cloud):
    c = TestClient(app)
    assert c.get("/health").json()["store"] == "redis"
    c.post("/demo/reset")
    wid = c.post("/demo/start", json={}).json()["id"]
    assert store.LOCK not in cloud.kv  # lock released

    cold_start()
    assert c.get("/users/jordan/active").json()["id"] == wid

    cold_start()
    c.post("/demo/checkin")
    cold_start()
    r = c.post(f"/walks/{wid}/pet").json()
    assert [e for e in r["events"] if e["type"] == "pet_ok"][0]["xp"] == 10
    cold_start()
    assert c.get("/users/jordan").json()["buddy"]["xp"] == 100

    c.post("/demo/stop-answering")
    shift_clock(cloud, 200)  # well past the 110 s escalation
    cold_start()
    feed = c.get("/friends/maya/feed").json()
    assert [a["kind"] for a in feed["open_alerts"]] == ["no_answer"]
    aid = feed["open_alerts"][0]["id"]
    cold_start()
    assert c.post(f"/alerts/{aid}/close", json={"friend_id": "maya"}).json()["status"] == "closed"
    cold_start()
    assert c.get("/friends/maya/feed").json()["open_alerts"] == []


def test_planned_route_persists(cloud):
    c = TestClient(app)
    c.post("/demo/reset")
    pts = [[33.4196, -111.9346], [33.4186, -111.9330], [33.4180, -111.9300]]
    w = c.post("/walks", json={"walker_id": "jordan", "demo": True, "points": pts, "to_name": "Tooker House"}).json()
    cold_start()
    from app import routes
    routes.CUSTOM.clear()
    ids = [r["id"] for r in c.get("/routes").json()]
    assert w["route_id"] in ids


def test_mongo_snapshot_roundtrip(monkeypatch):
    """Snapshot mode: a POST saves, and a restart restores from the snapshot."""
    saved = {}
    monkeypatch.setenv("MONGODB_URI", "mongodb://fake")
    monkeypatch.delenv("KV_REST_API_URL", raising=False)
    monkeypatch.setattr(store, "mongo_save", lambda data: saved.update(json.loads(json.dumps(data))))
    monkeypatch.setattr(store, "mongo_load", lambda: json.loads(json.dumps(saved)) if saved else None)
    c = TestClient(app)
    assert c.get("/health").json()["store"] == "mongodb"
    c.post("/demo/reset")
    wid = c.post("/demo/start", json={}).json()["id"]
    c.post("/users/jordan/buddy", json={"name": "Biscuit", "species": "dog"})
    cold_start()
    walks.restore(store.mongo_load())
    assert walks.active_walk("jordan")["id"] == wid
    assert walks.user("jordan")["buddy"]["name"] == "Biscuit"
    walks.reset()
