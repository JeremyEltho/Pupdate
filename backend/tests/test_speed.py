import random

from app import speed, walks
from app.geo import offset

START = [33.4196, -111.9346]


def walk_fixes(mps, seconds, noise_m=0.0, seed=0, dt=1.0):
    rng = random.Random(seed)
    out = []
    for i in range(int(seconds / dt)):
        p = offset(START, 0, mps * i * dt)
        if noise_m:
            p = offset(p, rng.gauss(0, noise_m), rng.gauss(0, noise_m))
        out.append((i * dt, p))
    return out


def run(fixes):
    st = speed.new_state()
    flagged = []
    for t, p in fixes:
        flagged += speed.anomalies(st, t, p)
    return flagged


def test_noisy_walk_raises_nothing():
    # 10 minutes of walking with 6 m GPS jitter every second (bad but accepted fixes).
    assert run(walk_fixes(1.4, 600, noise_m=6.0, seed=3, dt=2.0)) == []


def test_car_speed_flags_once():
    flagged = run(walk_fixes(1.4, 60) + [(60 + t, p) for t, p in walk_fixes(15.0, 60)])
    assert flagged == ["moving_fast"]


def test_long_stop_flags():
    flagged = run([(t, START) for t in range(0, 400, 10)])
    assert flagged == ["stopped"]


def test_bad_fix_still_counts_as_contact():
    walks.reset()
    w = walks.start_walk("jordan", "library-to-tooker", demo=False)
    w["clock"].base_sim -= 0  # real clock
    r = speed.ingest(w, 33.4196, -111.9346, accuracy=80.0)
    assert r["accepted_fix"] is False
    assert w["engine"].last_tick > 0 and not w["engine"].lost_contact


def test_arrival_ends_real_walk_but_not_demo():
    walks.reset()
    w = walks.start_walk("jordan", "library-to-tooker", demo=False)
    dest = w["dest"]
    r = speed.ingest(w, dest[0], dest[1], accuracy=5.0)
    assert r["walk"]["status"] == "ended"
    d = walks.start_walk("jordan", "library-to-tooker", demo=True)
    r = speed.ingest(d, dest[0], dest[1], accuracy=5.0)
    assert r["walk"]["status"] == "active"
