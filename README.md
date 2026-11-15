# WalkBuddy

Raise a little buddy by walking home safe. Pick your pet (pup, kitty, bunny, otter, sloth and more), name it, and while you walk it checks in now and then. You answer by petting it: rub your finger across it, because a tap doesn't count. If you stop answering, it escalates, and then your friends get a full-screen alert with your last location.

Built at SunHacks 2026.

## How it works

- **Check-ins.** By default the buddy only checks in when something looks off: you leave your route, move at car speed, or stop for a long time. You can add a schedule in Settings (every 5, 10 or 15 minutes). Pet it within 30 s.
- **Escalation.** If you don't answer: check-in (30 s), nudge (30 s), final warning (30 s), countdown (20 s), then an alert to your friends.
- **Duress.** A 2 second long-press on the buddy sends a silent alert. Your own screen stays calm. Your friends' screens say "Do not call first" and hide the call button.
- **Lost contact.** If your phone stops checking in for 90 s, your friends get a lost-contact alert.
- **XP and evolution.** Answering on time earns XP. The chick grows from egg to chick to night owl; every other pet earns a star at 100 XP and a crown at 250 XP. A safe-walk streak grows too.
- **Closing alerts.** Only a friend can close an alert. If you pet the buddy late, the friend sees "petted after the alert", and the alert stays open until they confirm.

The safety logic lives in one small, deterministic state machine (`backend/app/engine.py`) with injected time, and it is fully unit-tested.

## Repo layout

```
backend/   FastAPI server: walk engine, alerts, demo simulator, GPS speed filter (pytest)
swift/     Native SwiftUI iPhone app + Live Activity widget (Lock Screen and Dynamic Island)
app/       Earlier Expo prototype of the same app (kept for reference)
```

## Run the backend

```bash
cd backend
python3.11 -m venv .venv
.venv/bin/pip install -r requirements.txt
.venv/bin/pytest -q                                   # 21 tests
.venv/bin/uvicorn app.main:app --host 0.0.0.0 --port 8100
```

Phones need a public URL to reach it. A Cloudflare quick tunnel needs no account:

```bash
cloudflared tunnel --url http://localhost:8100
```

Quick-tunnel URLs change on every restart. Enter the new one on the app's first screen under **Server**.

## Run the iPhone app

The Xcode project is generated from `swift/project.yml` with [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```bash
cd swift
xcodegen generate
open WalkBuddy.xcodeproj
```

1. Set your own Team in Signing & Capabilities for both targets, WalkBuddy and WalkBuddyWidgets.
2. Change the bundle ID if needed.
3. Run on an iPhone.

Each phone chooses a role on first launch: **walker (Jordan)** or **friend (Maya)**.

### Screens

- **Home:** the buddy on its pedestal, XP, streak, level, and the evolution track.
- **Where to tonight?:** Apple Maps destination search and real walking directions. Then "Walk with Levin", as a demo walk or with real GPS.
- **Walk:** a live 3D map, the buddy's speech bubble with a countdown ring, and mood badges. The walk is mirrored to a Live Activity on the Lock Screen and in the Dynamic Island.
- **Friend:** a live map of the walk, demo controls, and full-screen alerts.

## Demo script (about 2 min, two phones)

1. On the friend phone, tap **Reset**, then **Start walk**. Or on the walker phone, pick a destination and start a demo walk. The sim walks the route at 2x.
2. About 15 s in, Levin asks "Still good?". Pet him: +10 XP, and he evolves into a Chick.
3. Tap **Stop answering**. Escalation runs at 4x, about 28 s. The friend phone shows the red alert with **Call Jordan** and the last location.
4. The friend closes the alert. Then long-press Levin for 2 s: a silent duress alert reaches the friend with "Do not call first", and there's no call button.
5. Tap **Off route**. The sim drifts off the route, and a check-in fires.
6. Tap **Reset** before the next judge. Every judge sees the same evolution.

The simulator never pets the buddy. Every pet comes from the phone.

## API (short)

| Route | Purpose |
|---|---|
| `POST /walks` | Start a walk: `route_id`, or phone-planned `points`, plus `demo` |
| `POST /walks/{id}/tick` | GPS fix or heartbeat. Bad fixes (over 50 m accuracy) still count as contact |
| `POST /walks/{id}/pet` | Answer a check-in |
| `POST /walks/{id}/duress` | Silent alert |
| `GET /friends/{id}/feed` | A friend's view: active walks and open alerts |
| `POST /alerts/{id}/close` | A friend closes an alert (the walker can't) |
| `POST /demo/reset`, `/demo/start`, `/demo/stop-answering`, `/demo/checkin`, `/demo/deviate`, `/demo/speed` | Demo controls |

## Known limits

- **Friend alerts only arrive while the app is open.** They come by polling, with no push notifications.
- **State is in memory.** A server restart resets users, walks and alerts.
- **The demo routes are hand-drawn.** They're approximate ASU Tempe paths. Routes planned in the app use Apple walking directions.
- **The Live Activity needs the app running.** It updates locally, so the app has to stay alive, which it does during a walk via background location.
- **Quick tunnels drop.** For a stable address, use a named Cloudflare tunnel or an ngrok reserved domain.

## Credits

- **3D sprites:** [Microsoft Fluent Emoji](https://github.com/microsoft/fluentui-emoji), MIT License. See `swift/WalkBuddy/Resources/Sprites/FLUENT_EMOJI_LICENSE.txt`.
- **Fonts:** Bricolage Grotesque and Figtree, SIL Open Font License. See `swift/WalkBuddy/Resources/Fonts/OFL-*.txt`.
- **Maps, search and walking directions:** Apple MapKit.
