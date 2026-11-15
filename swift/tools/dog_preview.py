"""SVG renderer for the dog, mirroring DogView.swift (same parts, same pose and face rules).
  python3 dog_preview.py out.html
"""
import json, math, sys
from pathlib import Path

ART = json.loads((Path(__file__).resolve().parent / "dog_art.json").read_text())
MOODS = ["calm", "asking", "worried", "alarmed", "happy", "petting"]
_id = [0]


def pose(mood, petting=0.0, t=0.0):
    """Returns tilt, earL, earR, tail, headDY (degrees / grid units). Same numbers as DogPose in Swift."""
    p = {"calm": (0, 0, 0, 0, 0), "asking": (-9, 24, -2, -8, -1), "worried": (4, -10, 10, 30, 1),
         "alarmed": (0, 16, -16, 55, 0), "happy": (6, 12, -12, -14, -2), "petting": (0, -12, 12, -6, 3)}[mood]
    tilt, el, er, tail, dy = p
    if petting > 0:
        el, er, dy = el - 12 * petting, er + 12 * petting, dy + 3 * petting
    return tilt, el, er, tail, dy


def fill_attr(fill, defs):
    if isinstance(fill, list):
        _id[0] += 1
        gid = f"g{_id[0]}"
        defs.append(f'<radialGradient id="{gid}" cx="35%" cy="28%" r="80%"><stop offset="0" stop-color="{fill[0]}"/><stop offset="1" stop-color="{fill[1]}"/></radialGradient>')
        return f"url(#{gid})"
    return fill


def part(p, defs):
    f = fill_attr(p["fill"], defs)
    op = f' opacity="{p["op"]}"' if p.get("op", 1) != 1 else ""
    if p["t"] == "e":
        rot = f' transform="rotate({p["rot"]} {p["cx"]} {p["cy"]})"' if p.get("rot") else ""
        return f'<ellipse cx="{p["cx"]}" cy="{p["cy"]}" rx="{p["w"]/2}" ry="{p["h"]/2}" fill="{f}"{op}{rot}/>'
    st = f' stroke="{p["stroke"]}" stroke-width="{p["sw"]}" stroke-linecap="round"' if p.get("stroke") else ""
    return f'<path d="{p["d"]}" fill="{f}"{op}{st}/>'


def layer(name, form, defs):
    return "".join(part(p, defs) for p in ART["parts"] if p["layer"] == name and (not p.get("forms") or form in p["forms"]))


def face(mood, petting=0.0, look=(0, 0)):
    f = ART["face"]
    ey, dx, ew, ln, my = f["eyeY"], f["eyeDX"], f["eyeW"], f["line"], f["mouthY"]
    o = []
    happy = mood in ("happy", "petting") or petting > 0.3
    for s in (-1, 1):
        o.append(f'<ellipse cx="{50 + s*f["cheekDX"]}" cy="{f["cheekY"]}" rx="4.6" ry="2.6" fill="#FF8FA3" opacity="{0.85 if happy else 0.5}"/>')
    eyes = "content" if (mood == "petting" or petting > 0.3) else "happy" if mood == "happy" else "wide" if mood == "alarmed" else "open"
    for s in (-1, 1):
        x = 50 + s * dx
        if eyes == "content":
            o.append(f'<path d="M{x-4.5} {ey} Q{x} {ey+4.2} {x+4.5} {ey}" stroke="{ln}" stroke-width="2.2" fill="none" stroke-linecap="round"/>')
        elif eyes == "happy":
            o.append(f'<path d="M{x-4.5} {ey+1.5} Q{x} {ey-4.5} {x+4.5} {ey+1.5}" stroke="{ln}" stroke-width="2.2" fill="none" stroke-linecap="round"/>')
        elif eyes == "wide":
            o.append(f'<ellipse cx="{x}" cy="{ey}" rx="6" ry="6.4" fill="#FFFFFF" stroke="{ln}" stroke-width="1"/>')
            o.append(f'<circle cx="{x+look[0]}" cy="{ey+look[1]}" r="2.6" fill="{f["iris"]}"/><circle cx="{x+look[0]+0.9}" cy="{ey+look[1]-1}" r="0.9" fill="#fff"/>')
        else:
            lx, ly = look[0] * 1.2, look[1] * 1.0
            o.append(f'<ellipse cx="{x}" cy="{ey}" rx="{ew/2}" ry="{ew/2*1.1}" fill="{f["iris"]}"/>')
            o.append(f'<ellipse cx="{x+lx+1.8}" cy="{ey+ly-2.2}" rx="2.2" ry="2.4" fill="#fff"/><circle cx="{x+lx-1.8}" cy="{ey+ly+2.2}" r="1" fill="#fff" opacity=".85"/>')
    if mood in ("asking", "worried", "alarmed"):
        ang = {"asking": 14, "worried": -20, "alarmed": -14}[mood]
        for s in (-1, 1):
            x = 50 + s * dx
            by = ey - 9 - (1.5 if mood == "asking" and s == -1 else 0)
            o.append(f'<path d="M{x-3.5} {by} L{x+3.5} {by}" stroke="#8C4E22" stroke-width="2" stroke-linecap="round" transform="rotate({ang * -s} {x} {by})"/>')
    # mouth
    if mood == "alarmed":
        o.append(f'<ellipse cx="50" cy="{my+1.5}" rx="2.8" ry="3.4" fill="#5A2230"/>')
    elif mood == "happy":
        o.append(f'<path d="M43.5 {my-1.5} Q50 {my+9} 56.5 {my-1.5} Q50 {my+0.5} 43.5 {my-1.5} Z" fill="#5A2230"/>')
        o.append(f'<path d="M47 {my+2.5} Q47 {my+9.5} 50 {my+9.5} Q53 {my+9.5} 53 {my+2.5} Q50 {my+4} 47 {my+2.5} Z" fill="#FF7E99"/>')
        o.append(f'<path d="M50 {my+4} L50 {my+8}" stroke="#E25A79" stroke-width=".8" stroke-linecap="round"/>')
    elif mood == "worried":
        o.append(f'<path d="M50 {my-3.5} L50 {my-1.5} M45.5 {my+0.8} Q47.7 {my-1.2} 50 {my+0.5} Q52.3 {my+2} 54.5 {my+0.2}" stroke="{ln}" stroke-width="1.5" fill="none" stroke-linecap="round"/>')
    else:
        o.append(f'<path d="M50 {my-3.5} L50 {my-1} M45.5 {my-1.5} Q47.75 {my+1.6} 50 {my-1} Q52.25 {my+1.6} 54.5 {my-1.5}" stroke="{ln}" stroke-width="1.5" fill="none" stroke-linecap="round"/>')
    return "".join(o)


def dog_svg(form="sprout", mood="calm", size=180, petting=0.0, look=(0, 0), tail_phase=0.0):
    defs = []
    tilt, el, er, tail, dy = pose(mood, petting)
    tail += tail_phase
    body = (f'<g transform="rotate({tail} 70 82)">{layer("tail", form, defs)}</g>' + layer("body", form, defs))
    head = (f'<g transform="translate(0 {dy}) rotate({tilt} 50 70)">'
            f'<g transform="rotate({el} 32 32)">{layer("earL", form, defs)}</g>'
            f'<g transform="rotate({er} 68 32)">{layer("earR", form, defs)}</g>'
            f'{layer("head", form, defs)}{face(mood, petting, look)}{layer("gear", form, defs)}</g>')
    shadow = '<ellipse cx="50" cy="98" rx="30" ry="3" fill="#000" opacity=".25"/>'
    hearts = ""
    if mood == "happy":
        hearts = ('<path d="M82 22 C76 17 75 10 80 9 C82 9 82 11 82 11 C82 11 82 9 84 9 C89 10 88 17 82 22 Z" fill="#FF5C86"/>'
                  '<path d="M15 30 C11.5 27 11 22.5 14 22 C15 22 15 23 15 23 C15 23 15 22 16 22 C19 22.5 18.5 27 15 30 Z" fill="#FF8FB0"/>')
    return f'<svg viewBox="0 0 100 100" width="{size}" height="{size}"><defs>{"".join(defs)}</defs>{shadow}{body}{head}{hearts}</svg>'


if __name__ == "__main__":
    rows = []
    for form, label in (("sprout", "Puppy"), ("strider", "Scout"), ("guardian", "Guardian")):
        cells = "".join(f'<div class="c">{dog_svg(form, m, 160, 0.9 if m == "petting" else 0)}<span>{m}</span></div>' for m in MOODS)
        rows.append(f'<div class="r"><b>{label}</b>{cells}</div>')
    css = "body{background:#0a0d1c;color:#9aa1c9;font-family:-apple-system,sans-serif;margin:20px}.r{display:flex;align-items:center;gap:6px}.r b{width:80px;color:#f3f4ff}.c{text-align:center;font-size:12px}.c span{display:block}"
    Path(sys.argv[1] if len(sys.argv) > 1 else "dog.html").write_text(f'<!doctype html><style>{css}</style><h3 style="color:#fff">Dog buddy: forms × moods</h3>{"".join(rows)}')
