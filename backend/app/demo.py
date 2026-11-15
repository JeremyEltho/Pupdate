"""Demo simulator: plays a walker along a route on the sim clock.

- Walk at 2x, escalation at 4x (about 27 s real for the full 110 s escalation).
- The sim NEVER pets. Every pet comes from the phone.
- Arrival is blocked: the sim walks back and forth along the route.
- "Deviate" walks the sim off the route so the off-route check-in can be shown.
"""
import logging
import math
import threading
import time

from . import walks
from .engine import ESCALATING
from .geo import offset, point_along
from .routes import OFF_ROUTE_M, load_routes, off_route_m

log = logging.getLogger("walkbuddy.demo")
WALK_SPEED = 1.4  # m/s, a brisk walk
WALK_X, ESCALATE_X = 2.0, 4.0
TICK_REAL_S = 0.25
DEVIATE_SIM_S = 70.0  # how long the sim stays off route
OFF_ROUTE_CHECKIN_S = 20.0  # off route this long (sim s) -> check-in

_thread = None
_stop = threading.Event()


def step(w):
    """Advance one demo walk to the current sim time. Caller holds walks.LOCK."""
    sim = w["sim"]
    clock = w["clock"]
    e = w["engine"]
    # 4x only once the walker is really not answering: after "Stop answering", or
    # past the first check-in stage. A normal check-in stays at 2x (15 s real to pet).
    escalating = e.ignore_pets or e.state in ESCALATING - {"checkin"}
    want = sim["speed_override"] or (ESCALATE_X if escalating else WALK_X)
    clock.set_speed(want)
    now = clock.now()
    dt = max(0.0, now - sim["last_now"])
    sim["last_now"] = now
    route = load_routes().get(w["route_id"]) if w["route_id"] else None
    if route is None:
        return walks.handle(w, e.tick(now, e.last_pos))
    # Move along the route, bouncing at the ends (arrival is blocked in demo mode).
    L = route["length_m"]
    sim["dist_m"] += sim["dir"] * WALK_SPEED * dt
    if sim["dist_m"] >= L:
        sim["dist_m"], sim["dir"] = L - (sim["dist_m"] - L), -1
    elif sim["dist_m"] <= 0:
        sim["dist_m"], sim["dir"] = -sim["dist_m"], 1
    pos = point_along(route["points"], sim["dist_m"])
    if sim["deviate_until"] is not None:
        if now < sim["deviate_until"]:
            # Drift sideways off the route, up to about 140 m.
            progress = 1 - (sim["deviate_until"] - now) / DEVIATE_SIM_S
            ahead = point_along(route["points"], min(L, sim["dist_m"] + 5))
            behind = point_along(route["points"], max(0.0, sim["dist_m"] - 5))
            dn = (ahead[0] - behind[0]) * 111320.0  # meters north along the route
            de = (ahead[1] - behind[1]) * 111320.0 * 0.834  # meters east (cos 33.4 deg)
            n = math.hypot(dn, de) or 1.0
            side = 140 * min(1.0, progress * 2)
            pos = offset(pos, -de / n * side, dn / n * side)  # perpendicular to the route
        else:
            sim["deviate_until"] = None
    events = e.tick(now, pos)
    off = w.get("watch_route", True) and off_route_m(pos, route) > OFF_ROUTE_M
    if off:
        sim.setdefault("off_since", now)
        if now - sim["off_since"] >= OFF_ROUTE_CHECKIN_S and not sim.get("off_checked"):
            sim["off_checked"] = True
            events += e.request_checkin(now, "off_route")
    else:
        sim.pop("off_since", None)
        sim["off_checked"] = False
    sim["off_route"] = off
    w["trail"].append([round(pos[0], 6), round(pos[1], 6)])
    del w["trail"][:-400]
    return walks.handle(w, events)


def loop():
    while not _stop.is_set():
        try:
            with walks.LOCK:
                for w in list(walks.STATE["walks"].values()):
                    if w["demo"] and w["status"] == "active":
                        step(w)
                    elif w["status"] == "active":
                        # Real walks: just run timeouts so alerts fire even if the phone goes quiet.
                        walks.handle(w, w["engine"].advance(w["clock"].now()))
        except Exception:
            log.exception("demo loop error")
        time.sleep(TICK_REAL_S)


def start_loop():
    global _thread
    if _thread and _thread.is_alive():
        return
    _stop.clear()
    _thread = threading.Thread(target=loop, daemon=True, name="walkbuddy-sim")
    _thread.start()


def stop_loop():
    _stop.set()


FIRST_CHECKIN_SIM_S = 30.0  # demo walks ask "Still good?" once, 15 s real after start


def start(route_id="library-to-tooker", walker_id="jordan", watch_route=True, watch_speed=True):
    w = walks.start_walk(walker_id, route_id=route_id, demo=True, watch_route=watch_route, watch_speed=watch_speed)
    with walks.LOCK:
        w["engine"].next_checkin = w["clock"].now() + FIRST_CHECKIN_SIM_S
        step(w)
    return w


def checkin_now(w):
    return walks.apply(w, lambda now: w["engine"].request_checkin(now, "demo"))


def stop_answering(w):
    """Start a check-in right now and drop phone pets until the alert fires."""
    return walks.apply(w, lambda now: w["engine"].request_checkin(now, "stop_answering", ignore_pets=True))


def deviate(w):
    with walks.LOCK:
        w["sim"]["deviate_until"] = w["clock"].now() + DEVIATE_SIM_S
        return True


def set_speed(w, x):
    with walks.LOCK:
        w["sim"]["speed_override"] = x
        w["clock"].set_speed(x or WALK_X)
