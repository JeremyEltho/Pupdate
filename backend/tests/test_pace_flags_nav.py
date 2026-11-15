"""Pace watch (with and without Gemini), flagged areas, flag-aware routing, turn-by-turn."""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
import pytest
from fastapi.testclient import TestClient

from app import demo, flags, nav, pace, route_ai, walks
from app.engine import ESCALATION_TOTAL
from app.geo import offset
from app.main import app

c = TestClient(app)
START = [33.41860, -111.93900]  # open ground west of campus, away from the seeded flags
HOME = offset(START, 0, 1500)


@pytest.fixture(autouse=True)
def clean(monkeypatch):
    monkeypatch.delenv("GEMINI_API_KEY", raising=False)
    monkeypatch.setattr(pace, "ASYNC", False)
    monkeypatch.setattr(pace, "_judge_override", None)
    c.post("/demo/reset")
    yield


def real_walk():
    w = walks.start_walk("jordan", dest=HOME, every=None)
    return w


def walk_track(w, legs, t0=1000.0, pos=None):
    """legs: [(seconds, m/s, heading 'e'|'w')]. Feeds a sample every 5 s. Returns all events."""
    pos = list(pos or START)
    t = t0
    out = []
    with walks.LOCK:
        w["engine"].last_tick = t0
        out += walks.handle(w, walks.on_position(w, t, pos))
        for secs, mps, head in legs:
            for _ in range(int(secs // 5)):
                t += 5
                pos = offset(pos, 0, mps * 5 * (1 if head == "e" else -1))
                w["engine"].last_tick = t
                out += walks.handle(w, walks.on_position(w, t, pos))
    return out, t, pos


def types(evs):
    return [e["type"] for e in evs]


# -- pace: rules -------------------------------------------------------------

@pytest.mark.parametrize("legs,expect", [
    ([(90, 1.4, "e")], None),                                   # steady walk
    ([(60, 1.4, "e"), (40, 0.0, "e"), (40, 1.4, "e")], None),   # waiting at a crosswalk
    ([(60, 1.4, "e"), (30, 1.2, "e")], None),                   # slowing down a bit
    ([(60, 1.4, "e"), (25, 3.6, "e")], "running"),
    ([(60, 1.4, "e"), (10, 0, "e"), (10, 1.6, "e"), (10, 0, "e"), (10, 1.6, "e"), (10, 0, "e"), (10, 1.6, "e")], "stop_and_go"),
    ([(60, 1.4, "e"), (45, 1.4, "w")], "backtracking"),
    ([(90, 1.5, "e"), (90, 0.0, "e")], "sudden_stop"),
])
def test_pace_patterns_without_gemini(legs, expect):
    w = real_walk()
    evs, _, _ = walk_track(w, legs)
    irregular = [e for e in evs if e["type"] == "pace_irregular"]
    if expect is None:
        assert not irregular and w["engine"].state == "calm"
    else:
        assert irregular[0]["pattern"] == expect
        # No Gemini key: the buddy checks in straight away.
        assert w["engine"].state == "checkin" and w["engine"].reason == "irregular_pace"
        assert w["pace"]["source"] == "rule" and w["pace"]["note"]
        assert walks.walk_view(w)["buddy_line"]


def test_car_speed_is_not_running():
    w = real_walk()
    evs, _, _ = walk_track(w, [(60, 1.4, "e"), (30, 12.0, "e")])
    pats = [e["pattern"] for e in evs if e["type"] == "pace_irregular"]
    assert pats == ["vehicle"]  # a car, never "running"


# -- pace: Gemini decides -----------------------------------------------------

def test_gemini_says_check_in_writes_the_line(monkeypatch):
    seen = {}

    def judge(prompt):
        seen["prompt"] = prompt
        return {"check_in": True, "pattern": "running", "buddy_line": "Why the sprint, Jordan? You OK?",
                "friend_note": "Jordan broke into a run at 3.6 m/s near Orange Mall.", "why": "sudden run at night"}
    monkeypatch.setattr(pace, "_judge_override", judge)
    w = real_walk()
    walk_track(w, [(60, 1.4, "e"), (25, 3.6, "e")])
    assert "m/s" in seen["prompt"] and "started running" in seen["prompt"]
    v = walks.walk_view(w)
    assert v["engine"]["state"] == "checkin"
    assert v["buddy_line"] == "Why the sprint, Jordan? You OK?" and v["buddy_line_source"] == "gemini"
    assert v["pace"]["source"] == "gemini" and "run" in v["pace"]["note"]
    judged = [e for e in w["events"] if e["type"] == "pace_judged"]
    assert judged and judged[0]["check_in"] is True


def test_gemini_says_normal_no_checkin(monkeypatch):
    monkeypatch.setattr(pace, "_judge_override", lambda p: {"check_in": False, "pattern": "normal",
                                                            "why": "Jogging across a crosswalk"})
    w = real_walk()
    walk_track(w, [(60, 1.4, "e"), (25, 3.6, "e")])
    assert w["engine"].state == "calm"
    judged = [e for e in w["events"] if e["type"] == "pace_judged"]
    assert judged[0]["check_in"] is False and "crosswalk" in judged[0]["why"]


def test_gemini_failure_still_checks_in(monkeypatch):
    def boom(prompt):
        raise TimeoutError("gemini slow")
    monkeypatch.setattr(pace, "_judge_override", boom)
    w = real_walk()
    walk_track(w, [(60, 1.4, "e"), (25, 3.6, "e")])
    assert w["engine"].state == "checkin" and w["pace"]["source"] == "rule"


def test_pace_checkin_escalates_to_friends_with_pace_context():
    w = real_walk()
    _, t, _ = walk_track(w, [(60, 1.4, "e"), (25, 3.6, "e")])
    assert w["engine"].state == "checkin"
    with walks.LOCK:
        w["engine"].last_tick = t + ESCALATION_TOTAL  # phone still ticking, walker not petting
        walks.handle(w, w["engine"].advance(t + ESCALATION_TOTAL + 1))
    feed = c.get("/friends/maya/feed").json()
    a = feed["open_alerts"][0]
    assert a["kind"] == "no_answer" and "Pace:" in a["summary"] and "running" in a["summary"]


def test_pet_answers_pace_checkin_and_cooldown_blocks_repeat():
    w = real_walk()
    _, t, pos = walk_track(w, [(60, 1.4, "e"), (25, 3.6, "e")])
    with walks.LOCK:
        evs = walks.handle(w, w["engine"].pet(t + 5))
    assert any(e["type"] == "pet_ok" and e["xp"] == 10 for e in evs)
    # Running again within the 2-minute cooldown: no second check-in.
    evs, _, _ = walk_track(w, [(10, 1.4, "e"), (40, 3.6, "e")], t0=t + 6, pos=pos)
    assert w["engine"].state == "calm"


def test_watch_speed_off_disables_pace_checkins():
    w = real_walk()
    w["watch_speed"] = False
    walk_track(w, [(60, 1.4, "e"), (25, 3.6, "e")])
    assert w["engine"].state == "calm"


def test_demo_pace_controls_trigger_checkin():
    v = c.post("/demo/start", json={}).json()
    w = walks.STATE["walks"][v["id"]]
    w["engine"].next_checkin = None  # no scripted first check-in for this test
    assert c.post("/demo/pace", json={"mode": "run"}).json()["ok"]
    assert c.post("/demo/pace", json={"mode": "fly"}).status_code == 400
    with walks.LOCK:
        w["clock"].base_sim += 40  # 40 sim seconds of running
        demo.step(w)
    v = c.get(f"/walks/{v['id']}").json()
    assert v["engine"]["state"] == "checkin" and v["engine"]["reason"] == "irregular_pace"
    assert v["pace"]["pattern"] == "running" and v["pace"]["mps"] > 3


def test_demo_bounce_does_not_trigger_pace():
    v = c.post("/demo/start", json={}).json()
    w = walks.STATE["walks"][v["id"]]
    w["engine"].next_checkin = None
    with walks.LOCK:
        w["clock"].base_sim += 900  # long enough to bounce off the route end
        demo.step(w)
    assert w["engine"].state == "calm"


# -- flags ----------------------------------------------------------------------

def test_flag_crud_and_visibility():
    seeds = c.get("/flags?viewer=jordan").json()
    assert {f["id"] for f in seeds} >= {"seed-lot", "seed-construction"}
    f = c.post("/flags", json={"by": "maya", "lat": 33.418, "lng": -111.93, "reason": "Felt unsafe",
                               "status": "caution", "radius_m": 40}).json()
    assert f["by_name"] == "Maya" and f["status"] == "caution"
    assert any(x["id"] == f["id"] for x in c.get("/flags?viewer=jordan").json())  # Maya is in Jordan's circle
    walks.STATE["users"]["zed"] = {"id": "zed", "name": "Zed", "phone": "", "friends": [], "streak": 0,
                                   "buddy": {"name": "Z", "xp": 0, "form": "sprout", "species": "cat"}}
    assert not any(x["id"] == f["id"] for x in c.get("/flags?viewer=zed").json())
    assert c.post(f"/flags/{f['id']}", json={"by": "zed", "status": "ok"}).status_code == 403
    assert c.post(f"/flags/{f['id']}", json={"by": "jordan", "status": "avoid"}).json()["status"] == "avoid"
    assert c.post(f"/flags/{f['id']}", json={"by": "jordan", "status": "maybe"}).status_code == 400
    assert c.delete(f"/flags/{f['id']}?by=jordan").status_code == 403  # only the author deletes
    assert c.delete(f"/flags/{f['id']}?by=maya").json()["ok"]
    assert c.post("/flags", json={"by": "nobody", "lat": 1, "lng": 1}).status_code == 404
    del walks.STATE["users"]["zed"]


def test_flags_expire_and_reset_keeps_user_flags():
    f = c.post("/flags", json={"by": "jordan", "lat": 33.41, "lng": -111.93}).json()
    c.post("/demo/reset")
    assert any(x["id"] == f["id"] for x in c.get("/flags").json())
    walks.STATE["flags"][f["id"]]["expires_at"] = 0
    assert not any(x["id"] == f["id"] for x in c.get("/flags").json())


def test_walking_into_avoid_flag_checks_in_once():
    lot = walks.STATE["flags"]["seed-lot"]
    w = real_walk()
    near = offset([lot["lat"], lot["lng"]], 0, -(lot["radius_m"] + 30))
    with walks.LOCK:
        w["engine"].last_pos = near
        evs = walks.handle(w, walks.on_position(w, 1000, near))
        assert "flag_nearby" in types(evs) and w["engine"].state == "calm"
        assert walks.walk_view(w)["flag_ahead"]["reason"] == "Poorly lit"
        evs = walks.handle(w, walks.on_position(w, 1006, [lot["lat"], lot["lng"]]))
    assert "flag_entered" in types(evs)
    assert w["engine"].state == "checkin" and w["engine"].reason == "flagged_area"
    with walks.LOCK:
        walks.handle(w, w["engine"].pet(1010))
        evs = walks.handle(w, walks.on_position(w, 1016, [lot["lat"], lot["lng"]]))
    assert w["engine"].state == "calm" and "flag_entered" not in types(evs)


def test_cleared_flag_is_ignored():
    c.post("/flags/seed-lot", json={"by": "jordan", "status": "ok"})
    lot = walks.STATE["flags"]["seed-lot"]
    w = real_walk()
    with walks.LOCK:
        walks.handle(w, walks.on_position(w, 1000, [lot["lat"], lot["lng"]]))
    assert w["engine"].state == "calm"


# -- flag-aware routing ------------------------------------------------------------

def _routes():
    lot = walks.STATE["flags"]["seed-lot"]
    through = [offset([lot["lat"], lot["lng"]], 0, -300), [lot["lat"], lot["lng"]], offset([lot["lat"], lot["lng"]], 0, 300)]
    around = [through[0], offset(through[0], -400, 0), offset(through[2], -400, 0), through[2]]
    return [{"id": "r0", "distance_m": 600, "minutes": 7, "steps": ["Head east on Apache Blvd"], "points": through},
            {"id": "r1", "distance_m": 1400, "minutes": 17, "steps": ["Head north on Rural Rd"], "points": around}]


def test_assess_avoids_flagged_route_without_gemini():
    out = c.post("/routes/assess", json={"routes": _routes(), "hour": 22}).json()
    assert out["safer_id"] == "r1" and out["source"] == "rule"
    assert out["flags"]["r0"][0]["reason"] == "Poorly lit" and out["flags"]["r1"] == []
    assert "Sam" in out["reasons"]["r0"]


def test_assess_overrides_gemini_pick_through_avoid_flag(monkeypatch):
    seen = {}

    def fake(routes, hour, hits=None):
        seen["hits"] = hits
        return {"safer_id": "r0", "reasons": {"r0": "Shorter on Apache Blvd."}, "source": "gemini"}
    monkeypatch.setattr(route_ai, "_gemini", fake)
    out = c.post("/routes/assess", json={"routes": _routes()}).json()
    assert seen["hits"]["r0"] and out["safer_id"] == "r1" and out["source"] == "gemini"


def test_gemini_prompt_mentions_flags(monkeypatch):
    captured = {}

    class R:
        def raise_for_status(self): pass
        def json(self):
            return {"candidates": [{"content": {"parts": [{"text": '{"safer_id": "r1", "reasons": {"r1": "Avoids Sam\'s dark lot."}}'}]}}]}

    def post(url, headers=None, json=None, timeout=None):
        captured["prompt"] = json["contents"][0]["parts"][0]["text"]
        return R()
    monkeypatch.setenv("GEMINI_API_KEY", "test")
    monkeypatch.setattr(route_ai.httpx, "post", post)
    out = c.post("/routes/assess", json={"routes": _routes()}).json()
    assert "AVOID flag by Sam: Poorly lit" in captured["prompt"]
    assert out["safer_id"] == "r1" and out["reasons"]["r1"] == "Avoids Sam's dark lot."


# -- turn-by-turn ------------------------------------------------------------------

def test_maneuvers():
    assert nav.maneuver("Turn left onto E University Dr") == "left"
    assert nav.maneuver("Turn right onto Rural Rd") == "right"
    assert nav.maneuver("Bear right toward Rural Rd") == "slight_right"
    assert nav.maneuver("Arrive at Tooker House") == "arrive"
    assert nav.maneuver("Continue onto Cady Mall") == "straight"


def test_demo_route_next_turn_advances():
    v = c.post("/demo/start", json={}).json()
    t = v["next_turn"]
    assert t["text"] == "Turn left onto Orange Mall" and t["maneuver"] == "left" and 40 < t["in_m"] < 70
    w = walks.STATE["walks"][v["id"]]
    w["sim"]["dist_m"] = 100
    t = c.get(f"/walks/{v['id']}").json()["next_turn"]
    assert t["text"] == "Bear right toward Rural Rd"
    w["sim"]["dist_m"] = 1150
    t = c.get(f"/walks/{v['id']}").json()["next_turn"]
    assert t["maneuver"] == "arrive" and "Tooker House" in t["text"]


def test_planned_route_keeps_apple_steps():
    pts = [START, offset(START, 0, 200), offset(START, 150, 200)]
    steps = [{"text": "", "lat": pts[0][0], "lng": pts[0][1]},
             {"text": "Turn left onto E University Dr", "lat": pts[1][0], "lng": pts[1][1], "distance_m": 150},
             {"text": "Arrive at the destination", "lat": pts[2][0], "lng": pts[2][1]}]
    v = c.post("/walks", json={"walker_id": "jordan", "points": pts, "steps": steps, "to_name": "Home"}).json()
    w = walks.STATE["walks"][v["id"]]
    with walks.LOCK:
        w["engine"].last_pos = offset(START, 0, 120)
    t = c.get(f"/walks/{v['id']}").json()["next_turn"]
    assert t["text"] == "Turn left onto E University Dr" and 70 <= t["in_m"] <= 90 and not t["near"]
    with walks.LOCK:
        w["engine"].last_pos = offset(START, 0, 190)
    t = c.get(f"/walks/{v['id']}").json()["next_turn"]
    assert t["near"] is True


# -- persistence -------------------------------------------------------------------

def test_dump_restore_keeps_flags_and_pace():
    f = c.post("/flags", json={"by": "jordan", "lat": 33.41, "lng": -111.93, "reason": "Construction"}).json()
    w = real_walk()
    walk_track(w, [(30, 1.4, "e")])
    import json
    snap = json.loads(json.dumps(walks.dump()))
    walks.restore(snap)
    assert f["id"] in walks.STATE["flags"]
    w2 = walks.STATE["walks"][w["id"]]
    assert len(w2["pace"]["samples"]) >= 5 and walks.walk_view(w2)["pace"]["mps"] > 1


# -- alert timing, long gaps, check-ins off, vehicles ---------------------------------

def test_custom_stage_timings_escalate_on_schedule():
    v = c.post("/walks", json={"walker_id": "jordan", "route_id": "library-to-tooker", "checkin_s": 60,
                               "nudge_s": 20, "final_s": 15, "countdown_s": 5}).json()
    assert v["stages"] == {"checkin": 60, "nudge": 20, "final": 15, "countdown": 10}  # clamped to 10 s min
    assert v["escalation_s"] == 105
    w = walks.STATE["walks"][v["id"]]
    e = w["engine"]
    t0 = e.last_tick
    with walks.LOCK:
        e.request_checkin(t0, "scheduled")
        e.last_tick = t0 + 100
        assert e.advance(t0 + 59) == [] and e.state == "checkin"
        e.advance(t0 + 61)
        assert e.state == "nudge"
        walks.handle(w, e.advance(t0 + 106))
    assert e.state == "alert" and walks.open_alerts(w["id"])


def test_long_checkin_gap_warns_walker_and_friends():
    r = c.post("/settings/check", json={"checkin_every_s": 1800}).json()
    assert r["warnings"][0]["kind"] == "long_checkins" and "30 min" in r["warnings"][0]["text"]
    assert c.post("/settings/check", json={"checkin_every_s": 600}).json()["warnings"] == []
    v = c.post("/walks", json={"walker_id": "jordan", "route_id": "library-to-tooker", "checkin_every_s": 1800}).json()
    assert v["notices"][0]["kind"] == "long_checkins"
    fw = c.get("/friends/maya/feed").json()["walks"][0]
    assert "every 30 min" in fw["notices"][0]["text"]


def test_slow_alert_ladder_warns():
    r = c.post("/settings/check", json={"checkin_s": 300, "nudge_s": 120}).json()
    assert r["escalation_s"] == 470 and r["warnings"][0]["kind"] == "slow_alerts"


def test_checkins_off_keeps_duress_and_tells_friends():
    v = c.post("/walks", json={"walker_id": "jordan", "route_id": "library-to-tooker", "checkins_off": True,
                               "checkin_every_s": 300}).json()
    assert v["checkins_off"] and v["checkin_every_s"] is None and v["notices"][0]["kind"] == "checkins_off"
    w = walks.STATE["walks"][v["id"]]
    with walks.LOCK:
        assert walks.handle(w, w["engine"].request_checkin(w["clock"].now(), "off_route")) == []
    assert w["engine"].state == "calm"
    c.post(f"/walks/{v['id']}/duress")
    assert c.get("/friends/maya/feed").json()["open_alerts"][0]["kind"] == "duress"


def test_vehicle_speed_detected_and_friends_told():
    w = real_walk()
    evs, _, _ = walk_track(w, [(60, 1.4, "e"), (30, 9.0, "e")])
    assert any(e.get("pattern") == "vehicle" for e in evs)
    assert w["engine"].state == "checkin" and w["engine"].reason == "moving_fast"
    v = walks.walk_view(w)
    assert v["pace"]["mode"] == "vehicle" and v["pace"]["kmh"] > 30
    assert v["notices"][-1]["kind"] == "in_vehicle" and "km/h" in v["notices"][-1]["text"]


def test_pace_modes():
    assert pace.mode_of(0.1) == "still" and pace.mode_of(1.4) == "walking"
    assert pace.mode_of(3.5) == "running" and pace.mode_of(9) == "vehicle"


def test_demo_car_mode():
    v = c.post("/demo/start", json={}).json()
    w = walks.STATE["walks"][v["id"]]
    w["engine"].next_checkin = None
    c.post("/demo/pace", json={"mode": "car"})
    with walks.LOCK:
        w["clock"].base_sim += 35
        demo.step(w)
    v = c.get(f"/walks/{v['id']}").json()
    assert v["engine"]["reason"] == "moving_fast" and v["pace"]["mode"] == "vehicle"
