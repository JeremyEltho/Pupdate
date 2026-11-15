"""WalkBuddy walk engine: a pure state machine with injected time.

Times are engine seconds. Real walks use wall clock seconds; demo walks use a
sim clock that runs faster (see demo.py). The engine never pets by itself.

States: calm -> checkin (30 s) -> nudge (30 s) -> final (30 s) -> countdown (20 s) -> alert
A separate lost_contact alert fires after 90 s without any tick.
"""
import random

STAGES = [("checkin", 30.0), ("nudge", 30.0), ("final", 30.0), ("countdown", 20.0)]
STAGE_LEN = dict(STAGES)
ESCALATION_TOTAL = sum(s for _, s in STAGES)  # 110 s
LOST_CONTACT_S = 90.0
CHECKIN_GAP = (120.0, 900.0)  # random gap between check-ins on real walks
PET_XP = 10
ESCALATING = {name for name, _ in STAGES}


class Engine:
    def __init__(self, now, demo=False, seed=None):
        self.demo = demo
        self.rng = random.Random(seed)
        self.state = "calm"
        self.stage_started = now
        self.last_tick = now
        self.last_pos = None
        self.lost_contact = False
        self.alert_kind = None  # "no_answer" | "duress" | "lost_contact"
        self.ignore_pets = False
        self.reason = None
        self.next_checkin = None if demo else now + self._gap()

    # -- helpers ---------------------------------------------------------
    def _gap(self):
        return self.rng.uniform(*CHECKIN_GAP)

    def _to_calm(self, now):
        self.state = "calm"
        self.stage_started = now
        self.reason = None
        self.ignore_pets = False
        self.next_checkin = None if self.demo else now + self._gap()

    def snapshot(self, now):
        left = None
        if self.state in ESCALATING:
            left = max(0.0, STAGE_LEN[self.state] - (now - self.stage_started))
        return {
            "state": self.state,
            "seconds_left": None if left is None else round(left, 1),
            "reason": self.reason,
            "alert_kind": self.alert_kind,
            "lost_contact": self.lost_contact,
            "ignore_pets": self.ignore_pets,
            "last_pos": self.last_pos,
        }

    # -- time ------------------------------------------------------------
    def advance(self, now):
        """Apply every timeout up to now. Returns the events that happened, in order."""
        ev = []
        if not self.lost_contact and now - self.last_tick >= LOST_CONTACT_S:
            self.lost_contact = True
            ev.append({"type": "alert_raised", "kind": "lost_contact", "at": self.last_tick + LOST_CONTACT_S})
        if self.state == "calm" and self.next_checkin is not None and now >= self.next_checkin:
            ev += self._start_checkin(self.next_checkin, "scheduled")
        # Walk stage timeouts forward, possibly several stages in one call.
        while self.state in ESCALATING:
            end = self.stage_started + STAGE_LEN[self.state]
            if now < end:
                break
            names = [n for n, _ in STAGES]
            i = names.index(self.state)
            if i + 1 < len(names):
                self.state = names[i + 1]
                self.stage_started = end
                ev.append({"type": "escalated", "state": self.state, "at": end})
            else:
                self.state = "alert"
                self.stage_started = end
                self.ignore_pets = False
                if self.alert_kind != "duress":
                    self.alert_kind = "no_answer"
                ev.append({"type": "alert_raised", "kind": "no_answer", "at": end})
        return ev

    def _start_checkin(self, now, reason):
        self.state = "checkin"
        self.stage_started = now
        self.reason = reason
        self.next_checkin = None
        return [{"type": "checkin_started", "reason": reason, "at": now}]

    # -- inputs ----------------------------------------------------------
    def tick(self, now, pos=None):
        """A heartbeat from the phone (or sim). pos may be None when the fix was too noisy;
        the tick still proves contact and keeps the last good position."""
        ev = self.advance(now)
        self.last_tick = now
        if pos is not None:
            self.last_pos = list(pos)
        if self.lost_contact:
            self.lost_contact = False
            ev.append({"type": "contact_restored", "at": now})
        return ev

    def request_checkin(self, now, reason, ignore_pets=False):
        ev = self.advance(now)
        if self.state == "calm":
            ev += self._start_checkin(now, reason)
        if ignore_pets and self.state in ESCALATING:
            self.ignore_pets = True
        return ev

    def pet(self, now):
        ev = self.advance(now)
        if self.ignore_pets:
            return ev + [{"type": "pet_ignored", "at": now}]
        if self.state == "checkin":
            ev.append({"type": "pet_ok", "xp": PET_XP, "at": now})
            self._to_calm(now)
        elif self.state in ("nudge", "final", "countdown"):
            ev.append({"type": "pet_ok", "xp": 0, "late": True, "at": now})
            self._to_calm(now)
        elif self.state == "alert":
            # Late pet after the alert: the engine calms down with no XP.
            # The alert itself stays open until a friend closes it (walks.py).
            ev.append({"type": "pet_ok", "xp": 0, "after_alert": True, "at": now})
            self._to_calm(now)
        else:
            ev.append({"type": "pet_ok", "xp": 0, "unprompted": True, "at": now})
        return ev

    def duress(self, now):
        ev = self.advance(now)
        self.alert_kind = "duress"
        # The walker's screen stays calm; the alert is silent on this phone.
        return ev + [{"type": "alert_raised", "kind": "duress", "silent": True, "at": now}]
