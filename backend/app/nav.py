"""Turn-by-turn: the next maneuver ahead of the walker on their route.

Steps come from Apple Maps on the phone (instruction text + maneuver point) or from the
hand-drawn demo routes. The server works out the next one from the walker's position, so the
walker's screen, the Lock Screen card and the friend's view all agree.
"""
from .geo import along_of

TURN_NEAR_M = 25.0  # "turn here" range: the buddy reacts and the phone speaks


def maneuver(text):
    t = text.lower()
    if "arrive" in t or "destination" in t:
        return "arrive"
    if "u-turn" in t or "turn around" in t:
        return "uturn"
    if "slight left" in t or "bear left" in t or "keep left" in t:
        return "slight_left"
    if "slight right" in t or "bear right" in t or "keep right" in t:
        return "slight_right"
    if "left" in t:
        return "left"
    if "right" in t:
        return "right"
    return "straight"


def walked_m(w, route):
    """How far along the route the walker is."""
    sim = w.get("sim") or {}
    if w.get("demo") and sim.get("dir", 1) == 1 and not sim.get("deviate_until"):
        return float(sim.get("dist_m", 0.0))
    pos = w["engine"].last_pos
    return along_of(pos, route["points"]) if pos else 0.0


def next_turn(w, route):
    if not route:
        return None
    along = walked_m(w, route)
    steps = route.get("steps") or []
    for i, s in enumerate(steps):
        if s["along_m"] > along + 3 and s["along_m"] > 1:
            d = max(0, round(s["along_m"] - along))
            return {"index": i, "text": s["text"], "in_m": d, "maneuver": maneuver(s["text"]),
                    "near": d <= TURN_NEAR_M, "step_count": len(steps)}
    left = max(0, round(route.get("length_m", 0) - along))
    return {"index": len(steps), "text": f"Arrive at {route.get('to', 'your destination')}", "in_m": left,
            "maneuver": "arrive", "near": left <= TURN_NEAR_M, "step_count": len(steps)}
