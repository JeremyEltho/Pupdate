"""WalkBuddy API."""
import logging
from contextlib import asynccontextmanager
from pathlib import Path
from typing import List, Optional

from dotenv import load_dotenv

ROOT = Path(__file__).resolve().parent.parent
load_dotenv(ROOT.parent / ".env")
load_dotenv(ROOT / ".env")

from fastapi import FastAPI, HTTPException  # noqa: E402
from fastapi.middleware.cors import CORSMiddleware  # noqa: E402
from fastapi.responses import FileResponse, RedirectResponse  # noqa: E402
from pydantic import BaseModel  # noqa: E402

from . import demo, walks  # noqa: E402
from .routes import load_routes  # noqa: E402

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(name)s %(levelname)s %(message)s")
log = logging.getLogger("walkbuddy")


@asynccontextmanager
async def lifespan(app):
    demo.start_loop()
    yield
    demo.stop_loop()


app = FastAPI(title="WalkBuddy", lifespan=lifespan)
app.add_middleware(CORSMiddleware, allow_origins=["*"], allow_methods=["*"], allow_headers=["*"])


class StartWalk(BaseModel):
    walker_id: str
    route_id: Optional[str] = None
    dest: Optional[List[float]] = None
    demo: bool = False
    # A route planned on the phone: list of [lat, lng] plus labels.
    points: Optional[List[List[float]]] = None
    from_name: Optional[str] = None
    to_name: Optional[str] = None


def _register_custom(req):
    if not req.points or len(req.points) < 2:
        return req.route_id
    import uuid
    rid = "planned-" + uuid.uuid4().hex[:8]
    to = req.to_name or "Destination"
    frm = req.from_name or "Current location"
    from .routes import register
    register(rid, f"{frm} to {to}", frm, to, req.points)
    return rid


class Tick(BaseModel):
    lat: Optional[float] = None
    lng: Optional[float] = None
    accuracy: Optional[float] = None
    ts: Optional[float] = None  # phone timestamp (seconds); defaults to server time


class CloseAlert(BaseModel):
    friend_id: str


class DemoStart(BaseModel):
    route_id: str = "library-to-tooker"
    walker_id: str = "jordan"


class DemoSpeed(BaseModel):
    x: Optional[float] = None  # None returns to automatic 2x / 4x


def _walk(wid):
    w = walks.STATE["walks"].get(wid)
    if not w:
        raise HTTPException(404, "unknown walk")
    return w


def _demo_walk():
    w = walks.active_walk("jordan")
    if not w or not w["demo"]:
        raise HTTPException(409, "no demo walk running; tap Start walk first")
    return w


@app.get("/health")
def health():
    return {"ok": True}


@app.get("/routes")
def routes():
    return list(load_routes().values())


@app.get("/users/{uid}")
def get_user(uid: str):
    try:
        u = walks.user(uid)
    except KeyError:
        raise HTTPException(404, "unknown user")
    w = walks.active_walk(uid)
    return dict(u, active_walk_id=w["id"] if w else None)


@app.get("/users/{uid}/active")
def active(uid: str):
    w = walks.active_walk(uid)
    return walks.walk_view(w, "walker") if w else None


@app.post("/walks")
def start_walk(req: StartWalk):
    route_id = _register_custom(req)
    try:
        if req.demo:
            w = demo.start(route_id, req.walker_id)
        else:
            w = walks.start_walk(req.walker_id, route_id, req.dest, False)
    except KeyError:
        raise HTTPException(404, "unknown walker")
    with walks.LOCK:
        return walks.walk_view(w)


@app.get("/walks/{wid}")
def get_walk(wid: str, viewer: str = "walker"):
    with walks.LOCK:
        return walks.walk_view(_walk(wid), "friend" if viewer == "friend" else "walker")


@app.post("/walks/{wid}/tick")
def tick(wid: str, t: Tick):
    w = _walk(wid)
    from . import speed
    return speed.ingest(w, t.lat, t.lng, t.accuracy, t.ts)


@app.post("/walks/{wid}/pet")
def pet(wid: str):
    w = _walk(wid)
    ev = walks.apply(w, w["engine"].pet)
    with walks.LOCK:
        return {"events": ev, "walk": walks.walk_view(w)}


@app.post("/walks/{wid}/duress")
def duress(wid: str):
    w = _walk(wid)
    walks.apply(w, w["engine"].duress)
    # Silent: answer exactly like a normal pet would, so nothing on screen changes.
    with walks.LOCK:
        return {"ok": True, "walk": walks.walk_view(w)}


@app.post("/walks/{wid}/end")
def end(wid: str):
    w = _walk(wid)
    with walks.LOCK:
        walks.finish_walk(w)
        return walks.walk_view(w)


@app.get("/friends/{fid}/feed")
def feed(fid: str):
    try:
        return walks.feed(fid)
    except KeyError:
        raise HTTPException(404, "unknown user")


@app.post("/alerts/{aid}/close")
def close_alert(aid: str, req: CloseAlert):
    try:
        return walks.close_alert(aid, req.friend_id)
    except KeyError:
        raise HTTPException(404, "unknown alert")
    except PermissionError as e:
        raise HTTPException(403, str(e))


@app.post("/demo/reset")
def demo_reset():
    walks.reset()
    return {"ok": True, "users": walks.STATE["users"]}


@app.post("/demo/start")
def demo_start(req: DemoStart):
    w = demo.start(req.route_id, req.walker_id)
    with walks.LOCK:
        return walks.walk_view(w)


@app.post("/demo/stop-answering")
def demo_stop_answering():
    w = _demo_walk()
    demo.stop_answering(w)
    with walks.LOCK:
        return walks.walk_view(w, "friend")


@app.post("/demo/checkin")
def demo_checkin():
    w = _demo_walk()
    demo.checkin_now(w)
    with walks.LOCK:
        return walks.walk_view(w, "friend")


@app.post("/demo/deviate")
def demo_deviate():
    w = _demo_walk()
    demo.deviate(w)
    return {"ok": True}


@app.post("/demo/speed")
def demo_speed(req: DemoSpeed):
    w = _demo_walk()
    demo.set_speed(w, req.x)
    return {"ok": True, "speed": w["clock"].speed}


WEB = ROOT.parent / "app" / "dist"


@app.get("/app/{path:path}")
def web_app(path: str = ""):
    """Serve the exported Expo web build; unknown paths fall back to index.html (SPA routes)."""
    if not WEB.exists():
        raise HTTPException(404, "web build missing: run `npx expo export -p web --output-dir dist` in app/")
    target = (WEB / path).resolve()
    if path and target.is_file() and WEB.resolve() in target.parents:
        return FileResponse(target)
    return FileResponse(WEB / "index.html")


@app.get("/")
def root():
    return RedirectResponse("/app/") if WEB.exists() else {"ok": True, "app": "WalkBuddy API"}
