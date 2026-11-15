"""Rebuild the demo routes on real sidewalks, footpaths and crosswalks from OpenStreetMap.

Offline tool, run once on a laptop with network access (the server never imports osmnx):
    python3.11 -m venv .venv-tools && .venv-tools/bin/pip install osmnx
    .venv-tools/bin/python tools/build_routes.py
Writes data/routes_graph.json. routes.py loads it over routes_precomputed.json (same ids), so
deleting the file brings the hand-drawn routes back.

Routing prefers mapped sidewalks, footpaths and pedestrian malls. Walking along a car road
costs 4x unless OSM says it has a sidewalk, so the walker only uses roads where nothing else
connects. Turn-by-turn text comes from the OSM way names along the path.
"""
import json
import math
import sys
import time
from pathlib import Path

import osmnx as ox

DATA = Path(__file__).resolve().parents[1] / "data"
CENTER, DIST = (33.4165, -111.9300), 1100
MIRRORS = ["https://overpass-api.de/api", "https://overpass.private.coffee/api", "https://maps.mail.ru/osm/tools/overpass/api"]
# Same ids, names and endpoints as the hand-drawn demo routes.
ROUTES = [
    {"id": "library-to-tooker", "name": "Hayden Library to Tooker House", "from": "Hayden Library", "to": "Tooker House",
     "start": (33.41955, -111.93455), "end": (33.4157, -111.9261)},
    {"id": "mu-to-vista", "name": "Memorial Union to Vista del Sol", "from": "Memorial Union", "to": "Vista del Sol",
     "start": (33.4175, -111.9346), "end": (33.4132, -111.9291)},  # Vista del Sol community center
]
FOOT = {"footway", "pedestrian", "path", "cycleway", "living_street", "corridor", "track", "bridleway"}
ROADS = {"residential", "tertiary", "secondary", "primary", "trunk", "unclassified", "tertiary_link", "secondary_link",
         "primary_link", "road"}


def first(v):
    return v[0] if isinstance(v, list) else v


def kind(d):
    """foot, crossing, steps, service, road (no sidewalk) or road_sw (road with a mapped sidewalk)."""
    hw, fw = first(d.get("highway")), first(d.get("footway"))
    if fw == "crossing" or first(d.get("crossing")):
        return "crossing"
    if hw == "steps":
        return "steps"
    if hw in FOOT:
        return "foot"
    if hw == "service":
        return "service"
    if first(d.get("sidewalk")) in ("both", "left", "right", "yes", "separate"):
        return "road_sw"
    return "road"


COST = {"foot": 1.0, "crossing": 1.0, "road_sw": 1.2, "service": 1.6, "steps": 2.0, "road": 4.0}


STREETS = []  # (name, [points]) of named car roads, for naming the sidewalks and crosswalks beside them


def seg_dist(p, a, b):
    ax, ay = (a[1] - p[1]) * 92900, (a[0] - p[0]) * 111320
    bx, by = (b[1] - p[1]) * 92900, (b[0] - p[0]) * 111320
    dx, dy = bx - ax, by - ay
    t = 0.0 if dx == dy == 0 else max(0.0, min(1.0, -(ax * dx + ay * dy) / (dx * dx + dy * dy)))
    return math.hypot(ax + t * dx, ay + t * dy)


def street_near(p, within=30.0):
    best = (within, None)
    for name, pts in STREETS:
        for a, b in zip(pts, pts[1:]):
            d = seg_dist(p, a, b)
            if d < best[0]:
                best = (d, name)
    return best[1]


def label(d, mid=None):
    name = first(d.get("name"))
    if name:
        return name
    k = kind(d)
    street = street_near(mid) if mid else None
    if k == "crossing":
        return f"the {street} crosswalk" if street else "the crosswalk"
    if k == "steps":
        return "the steps"
    if first(d.get("footway")) == "sidewalk" or street:
        return f"the {street} sidewalk" if street else "the sidewalk"
    return "the path"


def bearing(a, b):
    y = math.sin(math.radians(b[1] - a[1])) * math.cos(math.radians(b[0]))
    x = math.cos(math.radians(a[0])) * math.sin(math.radians(b[0])) - \
        math.sin(math.radians(a[0])) * math.cos(math.radians(b[0])) * math.cos(math.radians(b[1] - a[1]))
    return (math.degrees(math.atan2(y, x)) + 360) % 360


def dist(a, b):
    dy = (b[0] - a[0]) * 111320
    dx = (b[1] - a[1]) * 111320 * math.cos(math.radians(a[0]))
    return math.hypot(dx, dy)


def compass(deg):
    return ["north", "northeast", "east", "southeast", "south", "southwest", "west", "northwest"][int((deg + 22.5) % 360 // 45)]


def turn_word(delta):
    """delta: change of heading in degrees, -180..180, positive = right."""
    a = abs(delta)
    if a < 25:
        return "Continue"
    side = "right" if delta > 0 else "left"
    return f"Bear {side}" if a < 60 else f"Turn {side}" if a < 150 else "Make a U-turn"


def edge_points(G, u, v):
    d = min(G[u][v].values(), key=lambda e: e["length"])
    if "geometry" in d:
        pts = [(y, x) for x, y in d["geometry"].coords]
        if dist(pts[0], (G.nodes[u]["y"], G.nodes[u]["x"])) > dist(pts[-1], (G.nodes[u]["y"], G.nodes[u]["x"])):
            pts.reverse()
    else:
        pts = [(G.nodes[u]["y"], G.nodes[u]["x"]), (G.nodes[v]["y"], G.nodes[v]["x"])]
    return d, pts


def build(G, r):
    near = lambda p: min(G.nodes, key=lambda n: dist(p, (G.nodes[n]["y"], G.nodes[n]["x"])))
    src, dst = near(r["start"]), near(r["end"])
    path = ox.routing.shortest_path(G, src, dst, weight="cost")
    if not path:
        raise SystemExit("no path for " + r["id"])
    points, segs, by_kind = [], [], {}
    for u, v in zip(path, path[1:]):
        d, pts = edge_points(G, u, v)
        start_idx = max(0, len(points) - 1)
        points += pts if not points else pts[1:]
        k = kind(d)
        by_kind[k] = by_kind.get(k, 0.0) + d["length"]
        lab = label(d, pts[len(pts) // 2])
        if segs and segs[-1]["label"] == lab:
            segs[-1]["len"] += d["length"]
            segs[-1]["end_idx"] = len(points) - 1
        else:
            segs.append({"label": lab, "kind": k, "len": d["length"], "start_idx": start_idx, "end_idx": len(points) - 1})
    # Fold short unnamed bits into their neighbour so the steps stay readable (crosswalks always stay).
    merged = []
    for s in segs:
        if merged and s["kind"] != "crossing" and (s["len"] < 15 or (s["len"] < 30 and s["label"].startswith("the "))):
            merged[-1]["len"] += s["len"]
            merged[-1]["end_idx"] = s["end_idx"]
        elif merged and merged[-1]["label"] == s["label"]:
            merged[-1]["len"] += s["len"]
            merged[-1]["end_idx"] = s["end_idx"]
        else:
            merged.append(dict(s))
    steps = []
    for i, s in enumerate(merged):
        p = points[s["start_idx"]]
        # heading over the first 15 m of the segment, so a tiny jog at a corner doesn't set the direction
        nxt = next((q for q in points[s["start_idx"] + 1:s["end_idx"] + 1] if dist(p, q) >= 15), points[min(len(points) - 1, s["end_idx"])])
        if i == 0:
            steps.append({"text": f"Head {compass(bearing(p, nxt))} on {s['label']}", "at_index": 0})
            continue
        prev = points[max(0, s["start_idx"] - 1)]
        delta = (bearing(p, nxt) - bearing(prev, p) + 540) % 360 - 180
        word = turn_word(delta)
        if s["kind"] == "crossing":
            road = s["label"][4:-10].strip() if s["label"] != "the crosswalk" else ""
            what = f"cross {road}" if road else "cross at the crosswalk"
            text = what[0].upper() + what[1:] if word == "Continue" else f"{word} and {what}"
        elif word == "Continue" and s["label"].startswith("the ") and (not steps or "ross" in steps[-1]["text"]):
            continue  # "continue onto the sidewalk" after a crossing says nothing new
        else:
            text = f"{word} onto {s['label']}"
        if steps and steps[-1]["text"].endswith(text[1:]):
            continue  # back-to-back crosswalks over the same street (a median island) read as one crossing
        steps.append({"text": text, "at_index": s["start_idx"]})
    total = sum(by_kind.values())
    off_sidewalk = by_kind.get("road", 0.0)
    pts = [[round(a, 6), round(b, 6)] for a, b in points]
    return {"id": r["id"], "name": r["name"], "from": r["from"], "to": r["to"], "points": pts, "steps": steps}, total, by_kind, off_sidewalk


def main():
    ox.settings.useful_tags_way = list(ox.settings.useful_tags_way) + ["footway", "sidewalk", "crossing", "lit"]
    G = None
    for attempt in range(6):   # the public Overpass servers are often busy: back off and try the mirrors
        ox.settings.overpass_url = MIRRORS[attempt % len(MIRRORS)]
        try:
            G = ox.graph_from_point(CENTER, dist=DIST, network_type="walk", simplify=True, retain_all=False)
            break
        except Exception as e:
            print(f"{ox.settings.overpass_url} failed ({str(e).splitlines()[0][:80]}), retrying", file=sys.stderr)
            time.sleep(5 * 2 ** attempt)
    if G is None:
        raise SystemExit("no Overpass server answered; try again later")
    for u, v, k, d in G.edges(keys=True, data=True):
        d["cost"] = d["length"] * COST[kind(d)]
        if kind(d) in ("road", "road_sw", "service") and first(d.get("name")):
            STREETS.append((first(d["name"]), edge_points(G, u, v)[1]))
    out = []
    for r in ROUTES:
        route, total, by_kind, road = build(G, r)
        near = lambda p: min(G.nodes, key=lambda n: dist(p, (G.nodes[n]["y"], G.nodes[n]["x"])))
        plain = ox.routing.shortest_path(G, near(r["start"]), near(r["end"]), weight="length")
        plain_m = sum(min(G[u][v].values(), key=lambda e: e["length"])["length"] for u, v in zip(plain, plain[1:]))
        print(f"{r['id']}: plain shortest path {plain_m:.0f} m (any walkable way, roads included)")
        out.append(route)
        share = {k: f"{v / total:.0%}" for k, v in sorted(by_kind.items(), key=lambda x: -x[1])}
        print(f"{r['id']}: {total:.0f} m, {len(route['points'])} points, {len(route['steps'])} steps, by type {share}")
        print(f"  on a car road with no sidewalk: {road:.0f} m")
        for s in route["steps"]:
            print("  -", s["text"])
    (DATA / "routes_graph.json").write_text(json.dumps({
        "_note": "Demo routes on OpenStreetMap sidewalks, footpaths and crosswalks. Built by tools/build_routes.py. "
                 "Map data (c) OpenStreetMap contributors, ODbL.",
        "routes": out}, indent=1))
    print("wrote", DATA / "routes_graph.json")


if __name__ == "__main__":
    sys.exit(main())
