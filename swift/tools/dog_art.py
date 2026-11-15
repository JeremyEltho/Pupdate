"""The dog buddy, as data. One source for the SwiftUI view (generated DogArt.swift) and the SVG preview.

Grid is 100 x 100, dog sitting, facing the viewer. Parts are ellipses or SVG paths.
fill is "#hex" (flat) or ["#light", "#dark"] (soft radial shading, light at the top-left, like the
Fluent 3D emoji the rest of the app uses).
Layers (back to front): tail, body, earL, earR, head, gear. The face is drawn in code (moods).
Pivots: tail wags around (70, 82); ears swing around their top attach points.
Forms: sprout = puppy, strider = gold bandana, guardian = navy collar + glowing shield tag + reflective vest.
"""
import json
from pathlib import Path

FUR = ["#F6C27A", "#D9893B"]       # golden
FUR_DARK = ["#B9692C", "#7E3F17"]  # ears, patch
CREAM = ["#FFF6E6", "#F1D6B0"]
NOSE = ["#4A3A36", "#15100F"]
PAW = ["#FFF2DC", "#E9C99D"]


def E(layer, cx, cy, w, h, fill, rot=0, op=1, forms=None):
    return {"t": "e", "layer": layer, "cx": cx, "cy": cy, "w": w, "h": h, "fill": fill, "rot": rot, "op": op, "forms": forms}


def P(layer, d, fill, op=1, forms=None, stroke=None, sw=0):
    return {"t": "p", "layer": layer, "d": d, "fill": fill, "op": op, "forms": forms, "stroke": stroke, "sw": sw}


PARTS = [
    # tail (curly, wags)
    P("tail", "M68 84 C78 84 86 76 85 66 C84.5 61 80 60 79 64 C79.5 70 76 77 67 79 Z", FUR),
    P("tail", "M83.5 63 C82 59.5 79 60 79 63.5 C80.5 63 82 63 83.5 63 Z", CREAM),
    # body
    E("body", 50, 78, 46, 34, FUR),
    P("body", "M38 70 C40 64 60 64 62 70 C63 80 58 92 50 92 C42 92 37 80 38 70 Z", CREAM),
    E("body", 31, 88, 14, 12, FUR),  # haunches
    E("body", 69, 88, 14, 12, FUR),
    E("body", 42, 93, 12, 8, PAW),   # front paws
    E("body", 58, 93, 12, 8, PAW),
    P("body", "M39.5 94 L39.5 96.2 M42 94.6 L42 96.8 M44.5 94 L44.5 96.2 M55.5 94 L55.5 96.2 M58 94.6 L58 96.8 M60.5 94 L60.5 96.2", "none", stroke="#C9A06A", sw=0.9),
    # gear on the body
    P("body", "M35 70.5 Q50 77 65 70.5 L62 79 Q50 86 38 79 Z", ["#FFD45E", "#E59A10"], forms=["strider"]),
    P("body", "M50 80 L44.5 89 L55.5 89 Z", ["#FFD45E", "#E59A10"], forms=["strider"]),
    E("body", 44, 74, 2.2, 2.2, "#FFF4C2", forms=["strider"]), E("body", 52, 77, 2.2, 2.2, "#FFF4C2", forms=["strider"]), E("body", 58, 74, 2.2, 2.2, "#FFF4C2", forms=["strider"]),
    P("body", "M31 76 C33 70 40 69 42 71 L42 92 C36 92 30 88 31 76 Z", ["#3E5BD8", "#22328A"], forms=["guardian"]),
    P("body", "M69 76 C67 70 60 69 58 71 L58 92 C64 92 70 88 69 76 Z", ["#3E5BD8", "#22328A"], forms=["guardian"]),
    P("body", "M32.5 80 L41.5 80 L41.5 83 L32.4 83.6 Z M58.5 80 L67.5 80 L67.6 83.6 L58.5 83 Z", "#E6F2FF", op=0.95, forms=["guardian"]),
    P("body", "M36 69.5 Q50 75 64 69.5 L63 73.5 Q50 79 37 73.5 Z", ["#3E5BD8", "#1C2A75"], forms=["guardian"]),
    P("body", "M50 74.5 L55 76.5 L55 81 Q55 85 50 87.5 Q45 85 45 81 L45 76.5 Z", ["#FFE07A", "#F0A81A"], forms=["guardian"]),
    P("body", "M50 77.5 L51.2 80 L54 80.2 L51.9 82 L52.6 84.8 L50 83.3 L47.4 84.8 L48.1 82 L46 80.2 L48.8 80 Z", "#FFFFFF", op=0.9, forms=["guardian"]),
    # floppy ears
    P("earL", "M30 30 C20 31 12 42 13 55 C14 64 22 66 27 60 C31 54 33 44 36 36 Z", FUR_DARK),
    P("earL", "M28 36 C22 40 18 47 19 55 C20 60 24 60 26 56 C28 51 29 45 31 39 Z", ["#D88A55", "#A85A2C"], op=0.55),
    P("earR", "M70 30 C80 31 88 42 87 55 C86 64 78 66 73 60 C69 54 67 44 64 36 Z", FUR_DARK),
    P("earR", "M72 36 C78 40 82 47 81 55 C80 60 76 60 74 56 C72 51 71 45 69 39 Z", ["#D88A55", "#A85A2C"], op=0.55),
    # head
    P("head", "M50 20 C68 20 79 31 79 46 C79 62 67 71 50 71 C33 71 21 62 21 46 C21 31 32 20 50 20 Z", FUR),
    E("head", 63.5, 44, 17, 15, FUR_DARK, rot=-12, op=0.9),        # eye patch
    P("head", "M50 22 C46 30 44 38 45 46 L55 46 C56 38 54 30 50 22 Z", CREAM, op=0.9),  # blaze
    E("head", 50, 59, 30, 21, CREAM),                               # muzzle
    E("head", 42, 28, 16, 6, "#FFFFFF", rot=-18, op=0.28),          # highlight
    P("head", "M44.5 52.5 C44.5 49.5 55.5 49.5 55.5 52.5 C55.5 55.5 52.5 58 50 58 C47.5 58 44.5 55.5 44.5 52.5 Z", NOSE),
    E("head", 48, 51.6, 3.4, 1.8, "#FFFFFF", rot=-10, op=0.6),
    P("gear", "M36 21 C38 16 46 14 50 14.5 C54 14 62 16 64 21 C58 19 54 19.5 50 20 C46 19.5 42 19 36 21 Z", ["#3E5BD8", "#22328A"], forms=["guardian"]),
    E("gear", 50, 16.5, 7, 5, ["#FFF7C2", "#FFC93C"], forms=["guardian"]),   # headlamp
]

FACE = {"eyeY": 45, "eyeDX": 11.5, "eyeW": 11, "iris": "#3B2314", "line": "#3A2416", "mouthY": 61.5, "cheekY": 55, "cheekDX": 19}

if __name__ == "__main__":
    out = Path(__file__).resolve().parent / "dog_art.json"
    out.write_text(json.dumps({"parts": PARTS, "face": FACE}, indent=1))
    print("parts:", len(PARTS))
