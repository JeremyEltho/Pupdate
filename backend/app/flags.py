"""Flagged areas shared with your circle.

A flag is a circle on the map with a reason and a status:
- avoid:   planned routes steer around it, and walking into it starts a check-in
- caution: routes may pass; the buddy warns you as you get close
- ok:      cleared (kept for the record, ignored by routing)
Anyone connected to the flag's author (their circle, either direction) sees it and can change
its status; only the author can delete it. Flags expire after 7 days so they don't go stale.
"""
import time

from .geo import dist_m, dist_to_path_m

STATUSES = ("avoid", "caution", "ok")
EXPIRE_S = 7 * 86400
NEAR_EXTRA_M = 50.0  # "flag ahead" warning range beyond the flag's radius

SEEDS = [
    {"id": "seed-construction", "lat": 33.41862, "lng": -111.93105, "radius_m": 45, "status": "caution",
     "reason": "Construction", "note": "Fenced path, narrow sidewalk", "by": "maya"},
    {"id": "seed-lot", "lat": 33.41470, "lng": -111.93320, "radius_m": 70, "status": "avoid",
     "reason": "Poorly lit", "note": "Dark parking lot, lights out", "by": "sam"},
    {"id": "seed-lights", "lat": 33.42060, "lng": -111.93000, "radius_m": 50, "status": "ok",
     "reason": "Poorly lit", "note": "Lights fixed this week", "by": "maya"},
]


def _state():
    from . import walks
    return walks.STATE.setdefault("flags", {})


def seed(now=None):
    now = now or time.time()
    st = _state()
    for s in SEEDS:
        st[s["id"]] = _make(s["id"], s["by"], s["lat"], s["lng"], s["reason"], s["status"], s["radius_m"], s["note"], now)


def _make(fid, by, lat, lng, reason, status, radius_m, note, now):
    from . import walks
    by_name = walks.STATE["users"].get(by, {}).get("name", by)
    return {"id": fid, "lat": round(float(lat), 6), "lng": round(float(lng), 6), "radius_m": float(radius_m),
            "reason": reason, "note": note or "", "status": status, "by": by, "by_name": by_name,
            "created_at": now, "updated_at": now, "updated_by": by, "expires_at": now + EXPIRE_S}


def connected(uid):
    from . import walks
    users = walks.STATE["users"]
    me = users.get(uid, {})
    out = {uid} | set(me.get("friends", []))
    out |= {u for u, x in users.items() if uid in x.get("friends", [])}
    return out


def purge(now=None):
    now = now or time.time()
    st = _state()
    for fid in [f for f, x in st.items() if x["expires_at"] < now]:
        del st[fid]


def visible(uid=None):
    """Flags this user can see (all flags when uid is None)."""
    purge()
    flags = list(_state().values())
    if uid is not None:
        who = connected(uid)
        flags = [f for f in flags if f["by"] in who]
    return sorted(flags, key=lambda f: -f["updated_at"])


def add(uid, lat, lng, reason, status="avoid", radius_m=60, note=""):
    from . import walks
    walks.user(uid)
    if status not in STATUSES:
        raise ValueError("status must be avoid, caution or ok")
    reason = (reason or "").strip()[:40] or "Flagged"
    radius_m = max(15.0, min(300.0, float(radius_m)))
    fid = walks.new_id("f")
    f = _make(fid, uid, lat, lng, reason, status, radius_m, (note or "").strip()[:120], time.time())
    _state()[fid] = f
    return f


def update(fid, uid, status=None, note=None):
    f = _state().get(fid)
    if not f:
        raise KeyError(fid)
    if f["by"] not in connected(uid):
        raise PermissionError("not in this flag's circle")
    if status is not None:
        if status not in STATUSES:
            raise ValueError("status must be avoid, caution or ok")
        f["status"] = status
    if note is not None:
        f["note"] = note.strip()[:120]
    now = time.time()
    f["updated_at"], f["updated_by"], f["expires_at"] = now, uid, now + EXPIRE_S
    return f


def remove(fid, uid):
    f = _state().get(fid)
    if not f:
        raise KeyError(fid)
    if f["by"] != uid:
        raise PermissionError("only the person who flagged it can delete it")
    del _state()[fid]
    return {"ok": True}


def inside(pos, f, extra=0.0):
    return dist_m(pos, [f["lat"], f["lng"]]) <= f["radius_m"] + extra


def on_path(points, flags, pad=15.0):
    """Flags (avoid/caution) that a route passes through."""
    if not points or len(points) < 2:
        return []
    return [f for f in flags if f["status"] != "ok"
            and dist_to_path_m([f["lat"], f["lng"]], points) <= f["radius_m"] + pad]


def brief(f):
    return {"id": f["id"], "reason": f["reason"], "status": f["status"], "by_name": f["by_name"], "note": f.get("note", "")}
