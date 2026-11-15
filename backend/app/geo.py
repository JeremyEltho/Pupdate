"""Small geodesy helpers (meters, lat/lng degrees). Good enough at campus scale."""
import math

R = 6371000.0


def dist_m(a, b):
    lat1, lng1, lat2, lng2 = map(math.radians, (a[0], a[1], b[0], b[1]))
    x = (lng2 - lng1) * math.cos((lat1 + lat2) / 2)
    y = lat2 - lat1
    return math.hypot(x, y) * R


def path_length(points):
    return sum(dist_m(points[i], points[i + 1]) for i in range(len(points) - 1))


def point_along(points, meters):
    """Position at a distance along a polyline (clamped to the ends)."""
    if meters <= 0:
        return list(points[0])
    for i in range(len(points) - 1):
        seg = dist_m(points[i], points[i + 1])
        if meters <= seg and seg > 0:
            t = meters / seg
            return [points[i][0] + (points[i + 1][0] - points[i][0]) * t,
                    points[i][1] + (points[i + 1][1] - points[i][1]) * t]
        meters -= seg
    return list(points[-1])


def dist_to_path_m(p, points):
    """Shortest distance from p to a polyline, using a local flat projection."""
    lat0 = math.radians(p[0])

    def xy(q):
        return (math.radians(q[1]) * math.cos(lat0) * R, math.radians(q[0]) * R)

    px, py = xy(p)
    best = float("inf")
    for i in range(len(points) - 1):
        ax, ay = xy(points[i])
        bx, by = xy(points[i + 1])
        dx, dy = bx - ax, by - ay
        L = dx * dx + dy * dy
        t = 0.0 if L == 0 else max(0.0, min(1.0, ((px - ax) * dx + (py - ay) * dy) / L))
        best = min(best, math.hypot(px - (ax + t * dx), py - (ay + t * dy)))
    return best


def offset(p, north_m, east_m):
    dlat = north_m / R
    dlng = east_m / (R * math.cos(math.radians(p[0])))
    return [p[0] + math.degrees(dlat), p[1] + math.degrees(dlng)]


def along_of(p, points):
    """Distance along a polyline (meters from its start) of the point nearest to p."""
    lat0 = math.radians(p[0])

    def xy(q):
        return (math.radians(q[1]) * math.cos(lat0) * R, math.radians(q[0]) * R)

    px, py = xy(p)
    best, best_along, done = float("inf"), 0.0, 0.0
    for i in range(len(points) - 1):
        ax, ay = xy(points[i])
        bx, by = xy(points[i + 1])
        dx, dy = bx - ax, by - ay
        L = dx * dx + dy * dy
        t = 0.0 if L == 0 else max(0.0, min(1.0, ((px - ax) * dx + (py - ay) * dy) / L))
        d = math.hypot(px - (ax + t * dx), py - (ay + t * dy))
        seg = math.sqrt(L)
        if d < best:
            best, best_along = d, done + t * seg
        done += seg
    return best_along


def bearing(a, b):
    lat1, lat2 = math.radians(a[0]), math.radians(b[0])
    dl = math.radians(b[1] - a[1])
    x = math.sin(dl) * math.cos(lat2)
    y = math.cos(lat1) * math.sin(lat2) - math.sin(lat1) * math.cos(lat2) * math.cos(dl)
    return (math.degrees(math.atan2(x, y)) + 360) % 360
