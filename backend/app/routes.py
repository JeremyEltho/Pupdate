"""Walking routes: hand drawn precomputed routes, optionally replaced by an OSM graph build."""
import json
from pathlib import Path

from .geo import dist_to_path_m, path_length

DATA = Path(__file__).resolve().parent.parent / "data"
OFF_ROUTE_M = 60.0  # farther than this from the route counts as off route
CUSTOM = {}  # routes planned on the phone (Apple Maps walking directions), kept in memory


def register(route_id, name, frm, to, points):
    CUSTOM[route_id] = {"id": route_id, "name": name, "from": frm, "to": to,
                        "points": [[float(a), float(b)] for a, b in points], "source": "phone"}
    return CUSTOM[route_id]


def load_routes():
    routes = {r["id"]: r for r in json.loads((DATA / "routes_precomputed.json").read_text())["routes"]}
    graph_routes = DATA / "routes_graph.json"
    if graph_routes.exists():  # written by scripts/build_graph.py when a teammate runs it
        for r in json.loads(graph_routes.read_text())["routes"]:
            routes[r["id"]] = dict(r, source="osm")
    routes.update(CUSTOM)
    for r in routes.values():
        r.setdefault("source", "hand drawn")
        r["length_m"] = round(path_length(r["points"]))
    return routes


def off_route_m(pos, route):
    return dist_to_path_m(pos, route["points"])
