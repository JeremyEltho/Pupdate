"""Walking routes: hand drawn precomputed routes, optionally replaced by an OSM graph build,
plus routes planned on the phone (Apple Maps walking directions, with their turn-by-turn steps)."""
import json
from pathlib import Path

from .geo import along_of, dist_to_path_m, path_length

DATA = Path(__file__).resolve().parent.parent / "data"
OFF_ROUTE_M = 60.0  # farther than this from the route counts as off route
CUSTOM = {}  # routes planned on the phone, kept in memory (and in the persisted snapshot)
_FILE_CACHE = {}


def make_steps(points, raw):
    """raw: [{"text", "lat", "lng"} or {"text", "at_index"}] -> [{"text", "at", "along_m"}] sorted by along."""
    out = []
    for s in raw or []:
        text = (s.get("text") or "").strip()
        if not text:
            continue
        if s.get("at_index") is not None:
            at = points[max(0, min(len(points) - 1, int(s["at_index"])))]
        elif s.get("lat") is not None and s.get("lng") is not None:
            at = [float(s["lat"]), float(s["lng"])]
        else:
            continue
        out.append({"text": text[:90], "at": [round(at[0], 6), round(at[1], 6)], "along_m": round(along_of(at, points), 1)})
    out.sort(key=lambda s: s["along_m"])
    return out


def register(route_id, name, frm, to, points, steps=None):
    pts = [[float(a), float(b)] for a, b in points]
    CUSTOM[route_id] = {"id": route_id, "name": name, "from": frm, "to": to, "points": pts,
                        "steps": make_steps(pts, steps), "source": "phone"}
    return CUSTOM[route_id]


def _file_routes():
    out = {}
    for path, source in ((DATA / "routes_precomputed.json", "hand drawn"), (DATA / "routes_graph.json", "osm")):
        if not path.exists():
            continue
        mtime = path.stat().st_mtime
        cached = _FILE_CACHE.get(path)
        if not cached or cached[0] != mtime:
            routes = {}
            for r in json.loads(path.read_text())["routes"]:
                r = dict(r, source=source)
                r["steps"] = make_steps(r["points"], r.get("steps"))
                routes[r["id"]] = r
            _FILE_CACHE[path] = cached = (mtime, routes)
        out.update(cached[1])
    return out


def load_routes():
    routes = dict(_file_routes())
    routes.update(CUSTOM)
    for r in routes.values():
        r.setdefault("source", "hand drawn")
        r.setdefault("steps", [])
        if "length_m" not in r:
            r["length_m"] = round(path_length(r["points"]))
    return routes


def off_route_m(pos, route):
    return dist_to_path_m(pos, route["points"])
