"""App icon: Pupdate's guardian pup inside a map pin, at the end of a lit walking route
(the pup walks you to where you're going). Renders with headless Chrome.
  python3 gen_app_icon.py     (writes Pupdate/Resources/Assets.xcassets/AppIcon.appiconset/icon-1024.png)
"""
import subprocess
import tempfile
from pathlib import Path

from dog_preview import dog_svg

CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
OUT = Path(__file__).resolve().parents[1] / "Pupdate/Resources/Assets.xcassets/AppIcon.appiconset/icon-1024.png"
AMBER, GROUND = "#f2b134", "#121318"  # the app's accent and background
CX, CY, R = 560, 400, 280  # pin head
r = R - 46                  # dark window the pup sits in
s = int(r * 1.88)           # pup size, so the guardian's cap and vest fill the window

route = (f'<path d="M70 1080 C 150 900, 360 960, {CX - 6} {CY + R + 175}" fill="none" stroke="{AMBER}" '
         f'stroke-width="38" stroke-linecap="round" stroke-dasharray="1 76"/>')
pin = (f'<path d="M{CX} {CY + R + 190} C {CX - 58} {CY + R + 90} {CX - R} {CY + R - 50} {CX - R} {CY} '
       f'A {R} {R} 0 1 1 {CX + R} {CY} C {CX + R} {CY + R - 50} {CX + 58} {CY + R + 90} {CX} {CY + R + 190} Z" fill="{AMBER}"/>')
html = f"""<!doctype html><body style="margin:0;width:1024px;height:1024px;overflow:hidden;background:{GROUND}">
<svg width="1024" height="1024" style="position:absolute">{route}{pin}<circle cx="{CX}" cy="{CY}" r="{r}" fill="{GROUND}"/></svg>
<div style="position:absolute;left:{CX - s // 2}px;top:{CY - r}px;width:{s}px;height:{s}px;clip-path:circle({r}px at {s // 2}px {r}px)">
{dog_svg(form="guardian", mood="calm", size=s)}</div></body>"""

with tempfile.TemporaryDirectory() as d:
    page = Path(d) / "icon.html"
    page.write_text(html)
    subprocess.run([CHROME, "--headless", "--hide-scrollbars", "--force-device-scale-factor=1", "--window-size=1024,1024",
                    f"--screenshot={OUT}", page.as_uri()], check=True, capture_output=True)
print("wrote", OUT)
