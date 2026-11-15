"""GPS tick ingestion for real walks: filter noisy fixes, measure speed, flag anomalies.

- Fixes with accuracy worse than 50 m are dropped from speed math, but the tick
  is still sent to the engine with the last good position, so the 90 s watchdog
  never mistakes bad indoor GPS for lost contact.
- Speed is the median of recent segment speeds, which shrugs off single jumps.
- Anomalies start a check-in once per episode:
    moving_fast: median speed over 7 m/s for 20 s (a car, not a walk)
    stopped:     median speed under 0.3 m/s for 5 minutes
    off_route:   more than 60 m from the route for 60 s
- Arrival within 30 m of the destination ends the walk (never in demo mode).
"""
import statistics
import time

from . import walks
from .geo import dist_m
from .routes import OFF_ROUTE_M, load_routes, off_route_m

MAX_ACCURACY_M = 50.0
FAST_MPS, FAST_FOR_S = 7.0, 20.0
STOPPED_MPS, STOPPED_FOR_S = 0.3, 300.0
OFF_ROUTE_FOR_S = 60.0
ARRIVE_M = 30.0
WINDOW = 5


def new_state():
    return {"fixes": [], "fast_since": None, "slow_since": None, "off_since": None, "flagged": set()}


def median_speed(fixes):
    """fixes: list of (t, [lat, lng]) good fixes, oldest first."""
    speeds = []
    for (t0, p0), (t1, p1) in zip(fixes, fixes[1:]):
        if t1 - t0 > 0:
            speeds.append(dist_m(p0, p1) / (t1 - t0))
    return statistics.median(speeds) if speeds else None


def anomalies(st, t, pos, route=None):
    """Update the speed state with a good fix and return newly flagged anomaly names."""
    st["fixes"].append((t, pos))
    del st["fixes"][:-(WINDOW + 1)]
    v = median_speed(st["fixes"])
    out = []

    def episode(name, active, since_key, need_s):
        if active:
            if st[since_key] is None:
                st[since_key] = t
            if t - st[since_key] >= need_s and name not in st["flagged"]:
                st["flagged"].add(name)
                out.append(name)
        else:
            st[since_key] = None
            st["flagged"].discard(name)

    if v is not None and len(st["fixes"]) >= 3:
        episode("moving_fast", v > FAST_MPS, "fast_since", FAST_FOR_S)
        episode("stopped", v < STOPPED_MPS, "slow_since", STOPPED_FOR_S)
    if route is not None:
        episode("off_route", off_route_m(pos, route) > OFF_ROUTE_M, "off_since", OFF_ROUTE_FOR_S)
    st["speed_mps"] = v
    return out


def ingest(w, lat, lng, accuracy, ts=None):
    t = ts if ts is not None else time.time()
    with walks.LOCK:
        e = w["engine"]
        st = w.setdefault("speedstate", new_state())
        good = lat is not None and lng is not None and (accuracy is None or accuracy <= MAX_ACCURACY_M)
        now = w["clock"].now()
        events = e.tick(now, [lat, lng] if good else None)
        flagged = []
        if good:
            pos = [lat, lng]
            w["trail"].append([round(lat, 6), round(lng, 6)])
            del w["trail"][:-400]
            route = load_routes().get(w["route_id"]) if w["route_id"] else None
            flagged = anomalies(st, t, pos, route if w.get("watch_route", True) else None)
            if not w.get("watch_speed", True):
                flagged = [f for f in flagged if f not in ("moving_fast", "stopped")]
            for name in flagged:
                events += e.request_checkin(now, name)
            events += walks.on_position(w, now, pos)
            if not w["demo"] and w["dest"] and dist_m(pos, w["dest"]) <= ARRIVE_M:
                walks.finish_walk(w)
                events.append({"type": "arrived", "at": now})
        elif lat is None and e.last_pos:
            # A heartbeat with no new fix: iOS only reports movement, so the walker is standing still.
            events += walks.on_position(w, now, e.last_pos)
        logged = walks.handle(w, events)
        return {"accepted_fix": good, "speed_mps": st.get("speed_mps"), "flagged": flagged,
                "events": logged, "walk": walks.walk_view(w)}
