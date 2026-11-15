"""Users, walks, alerts. In-memory store guarded by one lock; reseeded by /demo/reset.

Alert rules:
- Alerts open when the engine raises them and stay open until a FRIEND closes them.
- A late pet after an alert calms the engine but does not close the alert; the
  friend sees "petted after the alert" instead.
- Duress alerts are silent: the walker's own view never shows them.
"""
import copy
import itertools
import threading
import time
from datetime import datetime, timezone

from . import buddy as buddy_mod
from .engine import ESCALATING, Engine
from .routes import load_routes

LOCK = threading.RLock()
_ids = itertools.count(1)

SEED_USERS = {
    "jordan": {"id": "jordan", "name": "Jordan", "phone": "+15555550100", "friends": ["maya", "sam"], "streak": 6,
               "buddy": {"name": "Levin", "xp": 90, "form": "sprout"}},
    "maya": {"id": "maya", "name": "Maya", "phone": "+15555550101", "friends": ["jordan"], "streak": 2,
             "buddy": {"name": "Pip", "xp": 40, "form": "sprout"}},
    "sam": {"id": "sam", "name": "Sam", "phone": "+15555550102", "friends": ["jordan"], "streak": 11,
            "buddy": {"name": "Moss", "xp": 130, "form": "strider"}},
}

STATE = {"users": {}, "walks": {}, "alerts": {}}


def iso(ts=None):
    return datetime.fromtimestamp(ts if ts is not None else time.time(), timezone.utc).isoformat()


class Clock:
    """Engine time. Real walks: wall clock. Demo walks: a sim clock with a speed factor."""

    def __init__(self, demo, speed=1.0):
        self.demo = demo
        self.base_real = time.time()
        self.base_sim = 0.0 if demo else self.base_real
        self.speed = speed if demo else 1.0

    def now(self):
        return self.base_sim + (time.time() - self.base_real) * self.speed

    def set_speed(self, speed):
        if not self.demo or speed == self.speed:
            return
        self.base_sim = self.now()
        self.base_real = time.time()
        self.speed = speed


def reset():
    with LOCK:
        STATE["users"] = copy.deepcopy(SEED_USERS)
        STATE["walks"] = {}
        STATE["alerts"] = {}


reset()


def user(uid):
    u = STATE["users"].get(uid)
    if not u:
        raise KeyError(uid)
    return u


def friends_watching(walker_id):
    """Users who list the walker as a friend (they get the walker's alerts)."""
    return [u["id"] for u in STATE["users"].values() if walker_id in u["friends"]]


def start_walk(walker_id, route_id=None, dest=None, demo=False):
    with LOCK:
        user(walker_id)
        for w in STATE["walks"].values():
            if w["walker_id"] == walker_id and w["status"] == "active":
                w["status"] = "ended"
                w["ended_at"] = iso()
        routes = load_routes()
        route = routes.get(route_id) if route_id else None
        clock = Clock(demo, speed=2.0)
        wid = "w%d" % next(_ids)
        w = {
            "id": wid, "walker_id": walker_id, "demo": demo, "status": "active",
            "route_id": route["id"] if route else None, "dest": dest or (route["points"][-1] if route else None),
            "started_at": iso(), "clock": clock, "engine": Engine(clock.now(), demo=demo),
            "events": [], "trail": [], "sim": {"dist_m": 0.0, "dir": 1, "deviate_until": None,
                                                "speed_override": None, "last_now": clock.now()},
        }
        STATE["walks"][wid] = w
        return w


def active_walk(walker_id):
    for w in STATE["walks"].values():
        if w["walker_id"] == walker_id and w["status"] == "active":
            return w
    return None


def _log(w, ev):
    ev = dict(ev, real_at=iso())
    w["events"].append(ev)
    del w["events"][:-60]
    return ev


def handle(w, events):
    """Apply engine events to the store (XP, alerts). Caller holds LOCK."""
    out = []
    for ev in events:
        t = ev["type"]
        if t == "pet_ok":
            if ev.get("xp"):
                u = user(w["walker_id"])
                u["buddy"], evolved = buddy_mod.add_xp(u["buddy"], ev["xp"])
                if evolved:
                    ev = dict(ev, evolved=evolved)
            if ev.get("after_alert"):
                for a in open_alerts(w["id"]):
                    a["petted_after"] = iso()
        elif t == "alert_raised":
            open_alert(w, ev["kind"])
        elif t == "contact_restored":
            for a in open_alerts(w["id"]):
                if a["kind"] == "lost_contact":
                    a["contact_restored"] = iso()
        out.append(_log(w, ev))
    return out


def finish_walk(w):
    """End a walk. A walk with no alerts at all extends the safe-walk streak."""
    if w["status"] != "active":
        return
    w["status"] = "ended"
    w["ended_at"] = iso()
    had_alert = any(a["walk_id"] == w["id"] for a in STATE["alerts"].values())
    u = user(w["walker_id"])
    u["streak"] = 0 if had_alert else u.get("streak", 0) + 1


def open_alerts(walk_id=None):
    return [a for a in STATE["alerts"].values()
            if a["status"] == "open" and (walk_id is None or a["walk_id"] == walk_id)]


def open_alert(w, kind):
    for a in open_alerts(w["id"]):
        if a["kind"] == kind:
            return a
    aid = "a%d" % next(_ids)
    walker = user(w["walker_id"])
    a = {
        "id": aid, "walk_id": w["id"], "walker_id": walker["id"], "walker_name": walker["name"],
        "walker_phone": walker["phone"], "kind": kind, "status": "open", "opened_at": iso(),
        "pos": w["engine"].last_pos, "route_id": w["route_id"], "closed_by": None,
        "petted_after": None, "contact_restored": None, "notify": friends_watching(walker["id"]),
    }
    STATE["alerts"][aid] = a
    return a


def close_alert(alert_id, friend_id):
    with LOCK:
        a = STATE["alerts"].get(alert_id)
        if not a:
            raise KeyError(alert_id)
        if friend_id == a["walker_id"] or friend_id not in a["notify"]:
            raise PermissionError("only a friend of %s can close this alert" % a["walker_name"])
        a["status"] = "closed"
        a["closed_by"] = friend_id
        a["closed_at"] = iso()
        return a


def apply(w, fn, *args):
    """Run an engine input at the walk's current engine time and handle its events."""
    with LOCK:
        now = w["clock"].now()
        events = fn(now, *args)
        return handle(w, events)


def walk_view(w, viewer="walker"):
    """Public JSON for a walk. The walker never sees duress state."""
    e = w["engine"]
    now = w["clock"].now()
    snap = e.snapshot(now)
    alerts = open_alerts(w["id"])
    if viewer == "walker":
        alerts = [a for a in alerts if a["kind"] != "duress"]
        if snap["alert_kind"] == "duress":
            snap["alert_kind"] = None
    u = user(w["walker_id"])
    return {
        "id": w["id"], "walker_id": w["walker_id"], "walker_name": u["name"], "demo": w["demo"], "streak": u.get("streak", 0),
        "status": w["status"], "route_id": w["route_id"], "dest": w["dest"], "started_at": w["started_at"],
        "engine": snap, "escalating": snap["state"] in ESCALATING, "speed": w["clock"].speed,
        "pos": e.last_pos, "trail": w["trail"][-200:], "buddy": u["buddy"],
        "next_form_at": buddy_mod.next_form_at(u["buddy"]["xp"]),
        "alerts": alerts, "events": w["events"][-12:],
        "off_route": w["sim"].get("off_route", False),
    }


def feed(friend_id):
    """What a friend's phone polls: walks of people they watch, and open alerts for them."""
    with LOCK:
        user(friend_id)
        watched = [uid for uid, u in STATE["users"].items() if friend_id in friends_watching(uid)]
        walks = [walk_view(w, viewer="friend") for w in STATE["walks"].values()
                 if w["status"] == "active" and w["walker_id"] in watched]
        alerts = [a for a in STATE["alerts"].values() if friend_id in a["notify"]]
        alerts.sort(key=lambda a: a["opened_at"], reverse=True)
        return {"walks": walks, "open_alerts": [a for a in alerts if a["status"] == "open"],
                "recent_alerts": alerts[:10]}
