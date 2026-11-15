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

from fastapi import Request  # noqa: E402
from starlette.concurrency import run_in_threadpool  # noqa: E402

from . import demo, store, walks  # noqa: E402
from .routes import load_routes  # noqa: E402

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(name)s %(levelname)s %(message)s")
log = logging.getLogger("walkbuddy")


@asynccontextmanager
async def lifespan(app):
    # Local: a background loop advances demo walks. Cloud: each request catches up instead.
    if store.mongo_enabled():
        data = await run_in_threadpool(store.mongo_load)
        if data:
            with walks.LOCK:
                walks.restore(data)
            log.info("restored state from MongoDB")
    if not store.enabled():
        demo.start_loop()
    yield
    demo.stop_loop()


app = FastAPI(title="WalkBuddy", lifespan=lifespan)
app.add_middleware(CORSMiddleware, allow_origins=["*"], allow_methods=["*"], allow_headers=["*"])


def _load_and_catch_up():
    data = store.load()
    with walks.LOCK:
        if data:
            walks.restore(data)
        else:
            walks.reset()  # first boot: seed the demo users
        demo.catch_up()


def _save():
    with walks.LOCK:
        snapshot = walks.dump()
    store.save(snapshot)


@app.middleware("http")
async def persisted_state(request: Request, call_next):
    """In the cloud, wrap every request in lock -> load -> catch up -> handle -> save -> unlock."""
    if store.mongo_enabled() and not store.enabled():
        response = await call_next(request)
        if request.method in ("POST", "DELETE"):  # every change is saved; reads are free
            await run_in_threadpool(lambda: store.mongo_save(walks.dump()))
        return response
    if not store.enabled() or request.url.path.startswith("/app") or request.url.path == "/health":
        return await call_next(request)
    token = await run_in_threadpool(store.acquire)
    try:
        await run_in_threadpool(_load_and_catch_up)
        response = await call_next(request)
        await run_in_threadpool(_save)
        return response
    finally:
        await run_in_threadpool(store.release, token)


class StartWalk(BaseModel):
    walker_id: str
    route_id: Optional[str] = None
    dest: Optional[List[float]] = None
    demo: bool = False
    # A route planned on the phone: list of [lat, lng] plus labels.
    points: Optional[List[List[float]]] = None
    from_name: Optional[str] = None
    to_name: Optional[str] = None
    # Walker settings: seconds between scheduled check-ins (None = only when something is off),
    # and whether leaving the route or odd speed should trigger a check-in.
    checkin_every_s: Optional[float] = None  # default: only check in when something looks off
    watch_route: bool = True
    watch_speed: bool = True


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


class RouteCandidate(BaseModel):
    id: str
    distance_m: float = 0
    minutes: float = 0
    steps: List[str] = []


class AssessRoutes(BaseModel):
    routes: List[RouteCandidate]
    hour: int = 21


class FriendAdd(BaseModel):
    name: str
    phone: str = ""


class BuddyEdit(BaseModel):
    name: Optional[str] = None
    species: Optional[str] = None


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
    return {"ok": True, "store": "redis" if store.enabled() else "mongodb" if store.mongo_enabled() else "memory"}


@app.get("/routes")
def routes():
    return list(load_routes().values())


@app.post("/routes/assess")
def assess_routes(req: AssessRoutes):
    """Which walking route is safer at night, and why (Gemini, with a street-based fallback)."""
    from .route_ai import assess
    return assess([r.model_dump() for r in req.routes][:4], req.hour)


@app.get("/users/{uid}")
def get_user(uid: str):
    try:
        u = walks.user(uid)
    except KeyError:
        raise HTTPException(404, "unknown user")
    w = walks.active_walk(uid)
    return dict(u, active_walk_id=w["id"] if w else None)


@app.post("/users/{uid}/buddy")
def edit_buddy(uid: str, req: BuddyEdit):
    try:
        return walks.customize_buddy(uid, req.name, req.species)
    except KeyError:
        raise HTTPException(404, "unknown user")
    except ValueError as e:
        raise HTTPException(400, str(e))


@app.get("/users/{uid}/circle")
def get_circle(uid: str):
    try:
        return walks.circle(uid)
    except KeyError:
        raise HTTPException(404, "unknown user")


@app.post("/users/{uid}/circle")
def add_to_circle(uid: str, req: FriendAdd):
    try:
        return walks.add_friend(uid, req.name, req.phone)
    except KeyError:
        raise HTTPException(404, "unknown user")
    except ValueError as e:
        raise HTTPException(400, str(e))


@app.delete("/users/{uid}/circle/{fid}")
def remove_from_circle(uid: str, fid: str):
    try:
        return walks.remove_friend(uid, fid)
    except KeyError:
        raise HTTPException(404, "not in the circle")


@app.get("/users/{uid}/active")
def active(uid: str):
    w = walks.active_walk(uid)
    return walks.walk_view(w, "walker") if w else None


@app.post("/walks")
def start_walk(req: StartWalk):
    route_id = _register_custom(req)
    try:
        if req.demo:
            w = demo.start(route_id, req.walker_id, req.watch_route, req.watch_speed)
        else:
            w = walks.start_walk(req.walker_id, route_id, req.dest, False, req.checkin_every_s,
                                 req.watch_route, req.watch_speed)
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
