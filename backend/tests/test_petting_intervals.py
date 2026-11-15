"""Petting at many points in time. Each case: (seconds after the check-in starts, expected outcome)."""
import pytest

from app.engine import Engine

ON_TIME, LATE, AFTER_ALERT = "on_time", "late", "after_alert"

CASES = [
    (0.0, ON_TIME, "checkin"), (0.5, ON_TIME, "checkin"), (15.0, ON_TIME, "checkin"), (29.9, ON_TIME, "checkin"),
    (30.0, LATE, "nudge"), (45.0, LATE, "nudge"), (59.9, LATE, "nudge"),
    (60.0, LATE, "final"), (89.9, LATE, "final"),
    (90.0, LATE, "countdown"), (109.9, LATE, "countdown"),
    (110.0, AFTER_ALERT, "alert"), (300.0, AFTER_ALERT, "alert"),
]


@pytest.mark.parametrize("delay,expected,stage", CASES)
def test_pet_at_each_moment(delay, expected, stage):
    e = Engine(0, demo=True)
    e.request_checkin(10, "test")
    # keep contact alive so only the escalation matters
    t = 10
    while t + 20 < 10 + delay:
        t += 20
        e.tick(t)
    e.advance(10 + delay)
    assert e.state == stage, (delay, e.state)
    ev = e.pet(10 + delay)[-1]
    assert ev["type"] == "pet_ok"
    if expected == ON_TIME:
        assert ev["xp"] == 10
    elif expected == LATE:
        assert ev["xp"] == 0 and ev.get("late")
    else:
        assert ev["xp"] == 0 and ev.get("after_alert")
    assert e.state == "calm"


def test_double_pet_only_counts_once():
    e = Engine(0, demo=True)
    e.request_checkin(0, "test")
    assert e.pet(5)[-1]["xp"] == 10
    second = e.pet(6)[-1]
    assert second["xp"] == 0 and second.get("unprompted")


def test_unprompted_pet_while_calm_gives_nothing():
    e = Engine(0, demo=True)
    ev = e.pet(3)[-1]
    assert ev["xp"] == 0 and ev.get("unprompted") and e.state == "calm"


@pytest.mark.parametrize("every", [300, 600, 900])
def test_repeated_scheduled_checkins_each_reward(every):
    """Pet each scheduled check-in a few seconds in, three times in a row."""
    e = Engine(0, demo=False, every=every)
    t, xp = 0.0, 0
    for _ in range(3):
        target = e.next_checkin
        while t + 30 < target:
            t += 30
            e.tick(t)
        e.tick(target)
        assert e.state == "checkin"
        xp += e.pet(target + 4)[-1]["xp"]
        t = target + 4
        assert e.next_checkin == pytest.approx(target + 4 + every)
    assert xp == 30


def test_pets_ignored_while_demo_stops_answering_then_count_after_alert():
    e = Engine(0, demo=True)
    e.request_checkin(0, "stop_answering", ignore_pets=True)
    for t in (5, 40, 70, 100):
        e.tick(t)
        assert e.pet(t)[-1]["type"] == "pet_ignored"
    e.tick(111)
    assert e.state == "alert"
    assert e.pet(112)[-1].get("after_alert")
