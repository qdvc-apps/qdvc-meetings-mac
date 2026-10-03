#!/usr/bin/env python3
"""Generate the app icon: Resources/AppIcon.svg (vector master) and
Resources/AppIcon.icns (every macOS size, rendered natively from the vector).

The design is a frosted-glass calendar card (a header band, binder rings and
a grid of days, one of them marked), sealed with a blue badge showing two
people: a meeting, recorded. It is drawn in the macOS 26 Liquid Glass style,
in the "Lagoon" palette (pale aqua to deep blue), and follows the icons of
QDVC Nice Mail, Bibliotheca and GTD EML for macOS, so the apps look like a
family.

Geometry follows Apple's macOS icon template: a 1024x1024 canvas holding an
824x824 tile (100 px transparent margin) with a 185.4 px continuous-curvature
("squircle") corner, plus a soft drop shadow. The corner is the curve UIKit
draws for continuous corners, as reverse-engineered and published by PaintCode
(https://www.paintcodeapp.com/blogpost/code-for-ios-7-rounded-rectangles).

Usage:

    python3 tools/make_icon.py            # writes Resources/AppIcon.{svg,icns}
    python3 tools/make_icon.py --preview  # also writes build/icon-preview.png

Requires rsvg-convert (macOS: `brew install librsvg`; Debian/Ubuntu:
`apt install librsvg2-bin`). No other dependencies; the .icns is written
directly, so Apple's iconutil is not needed.
"""

import argparse
import struct
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
RESOURCES = ROOT / "Resources"

# ---------------------------------------------------------------------------
# Palette ("Lagoon"). The deep tone also tints the card's shadows, so the
# white glass stays distinct from the pale background.

BG_TOP = "#EAF6FB"
BG_DEEP = "#5C9FD0"

# The seal: a blue sphere with two white people.
FACE_LIGHT, FACE_MID, FACE_DARK = "#B9E0FF", "#2F8BE6", "#1A5FB0"
FEATURES = "#FFFFFF"
ACCENT = "#2F8BE6"

# ---------------------------------------------------------------------------
# Apple's template geometry.

TILE_ORIGIN, TILE_SIZE, CORNER_RADIUS = 100, 824, 185.4
SHADOW_BLUR_RADIUS, SHADOW_OFFSET_Y, SHADOW_OPACITY = 28, 12, 0.5

# Continuous-corner segments around the top-right corner, in units of the
# radius: (distance from the right edge, distance from the top edge).
_CORNER = [
    ("L", (1.52866471, 0.0)),
    ("C", (1.08849323, 0.0), (0.86840689, 0.0), (0.66993427, 0.06549600)),
    ("L", (0.63149399, 0.07491100)),
    ("C", (0.37282392, 0.16905899), (0.16906013, 0.37282401), (0.07491176, 0.63149399)),
    ("C", (0.0, 0.86840701), (0.0, 1.08849299), (0.0, 1.52866483)),
]


def continuous_rounded_rect(x, y, w, h, r):
    """SVG path of a rounded rectangle with Apple's continuous corners."""
    r = min(r, min(w, h) / 2 / 1.52866483)
    corners = [
        lambda u, v: (x + w - u * r, y + v * r),        # top-right
        lambda u, v: (x + w - v * r, y + h - u * r),    # bottom-right
        lambda u, v: (x + u * r, y + h - v * r),        # bottom-left
        lambda u, v: (x + v * r, y + u * r),            # top-left
    ]

    def fmt(p):
        return f"{p[0]:.2f},{p[1]:.2f}"

    d = [f"M{fmt((x + 1.52866483 * r, y))}"]
    for corner in corners:
        for seg in _CORNER:
            if seg[0] == "L":
                d.append("L" + fmt(corner(*seg[1])))
            else:
                d.append("C" + " ".join(fmt(corner(*p)) for p in seg[1:]))
    d.append("Z")
    return " ".join(d)


TILE = continuous_rounded_rect(TILE_ORIGIN, TILE_ORIGIN, TILE_SIZE, TILE_SIZE, CORNER_RADIUS)

# The card (x, y, width, height) and the seal's radius. The seal sits on the
# card's lower right corner.
CARD = (232, 250, 520, 500)
SEAL_RADIUS = 132


def _hex2rgb(h):
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


def _mix(a, b, t):
    ra, rb = _hex2rgb(a), _hex2rgb(b)
    return "#%02X%02X%02X" % tuple(round(x + (y - x) * t) for x, y in zip(ra, rb))


def _card():
    """The frosted-glass calendar card. Returns (elements, seal centre)."""
    x, y, w, h = CARD
    band = 118
    parts = [
        f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="56" fill="url(#glass)"/>',
        # header band
        f'<path d="M{x},{y + band} L{x},{y + 56} Q{x},{y} {x + 56},{y} L{x + w - 56},{y} '
        f'Q{x + w},{y} {x + w},{y + 56} L{x + w},{y + band} Z" fill="{ACCENT}" fill-opacity="0.78"/>',
        f'<rect x="{x}" y="{y + band - 4}" width="{w}" height="8" fill="#FFFFFF" fill-opacity="0.35"/>',
    ]
    # binder rings
    for rx in (x + w * 0.30, x + w * 0.70):
        parts.append(f'<rect x="{rx - 15:.1f}" y="{y - 38}" width="30" height="86" rx="15" '
                     'fill="#FFFFFF" stroke="#FFFFFF" stroke-opacity="0.6" stroke-width="4"/>')
        parts.append(f'<rect x="{rx - 7:.1f}" y="{y - 26}" width="14" height="62" rx="7" '
                     f'fill="{BG_DEEP}" fill-opacity="0.35"/>')
    # day grid: 4 columns x 3 rows of dots, one marked
    gx0, gy0 = x + 78, y + band + 70
    dx, dy = (w - 156) / 3, 96
    for row in range(3):
        for col in range(4):
            cx, cy = gx0 + col * dx, gy0 + row * dy
            if (row, col) == (0, 2):
                parts.append(f'<circle cx="{cx:.1f}" cy="{cy:.1f}" r="30" fill="{ACCENT}" fill-opacity="0.85"/>')
            elif (row, col) not in ((2, 2), (2, 3), (1, 3)):
                parts.append(f'<circle cx="{cx:.1f}" cy="{cy:.1f}" r="15" fill="{BG_DEEP}" fill-opacity="0.32"/>')
    # glass rim
    parts.append(f'<rect x="{x + 2}" y="{y + 2}" width="{w - 4}" height="{h - 4}" rx="54" fill="none" '
                 'stroke="url(#rim)" stroke-width="4"/>')
    return parts, (x + w - 70, y + h - 70)


def _seal(cx, cy, r):
    """A glossy blue seal with two white people, in a white ring."""
    def person(px, py, s, opacity):
        head = f'<circle cx="{px:.1f}" cy="{py - s * 0.42:.1f}" r="{s * 0.27:.1f}" fill="{FEATURES}" opacity="{opacity}"/>'
        body = (f'<path d="M{px - s * 0.48:.1f},{py + s * 0.42:.1f} Q{px - s * 0.48:.1f},{py - s * 0.06:.1f} '
                f'{px:.1f},{py - s * 0.06:.1f} Q{px + s * 0.48:.1f},{py - s * 0.06:.1f} '
                f'{px + s * 0.48:.1f},{py + s * 0.42:.1f} Z" fill="{FEATURES}" opacity="{opacity}"/>')
        return [head, body]
    return [
        f'<circle cx="{cx}" cy="{cy}" r="{r + 10}" fill="#FFFFFF" opacity="0.9"/>',
        f'<circle cx="{cx}" cy="{cy}" r="{r}" fill="url(#face)"/>',
        *person(cx + r * 0.26, cy + r * 0.02, r * 0.70, 0.72),
        *person(cx - r * 0.18, cy + r * 0.10, r * 0.82, 1.0),
        # specular highlight
        f'<ellipse cx="{cx - r * 0.30:.1f}" cy="{cy - r * 0.55:.1f}" rx="{r * 0.38:.1f}" '
        f'ry="{r * 0.18:.1f}" fill="#FFFFFF" opacity="0.45"/>',
    ]


def icon_svg():
    sigma = SHADOW_BLUR_RADIUS / 2
    defs = [
        f'<linearGradient id="bg" x1="0" y1="0" x2="0.35" y2="1">'
        f'<stop offset="0" stop-color="{BG_TOP}"/><stop offset="1" stop-color="{BG_DEEP}"/></linearGradient>',
        '<radialGradient id="glow" cx="0.30" cy="0.18" r="0.75">'
        '<stop offset="0" stop-color="#FFFFFF" stop-opacity="0.34"/>'
        '<stop offset="1" stop-color="#FFFFFF" stop-opacity="0"/></radialGradient>',
        '<linearGradient id="sheen" x1="0" y1="0" x2="0" y2="1">'
        '<stop offset="0" stop-color="#FFFFFF" stop-opacity="0.22"/>'
        '<stop offset="0.40" stop-color="#FFFFFF" stop-opacity="0.03"/>'
        '<stop offset="1" stop-color="#FFFFFF" stop-opacity="0"/></linearGradient>',
        '<linearGradient id="rim" x1="0" y1="0" x2="0" y2="1">'
        '<stop offset="0" stop-color="#FFFFFF" stop-opacity="0.9"/>'
        '<stop offset="0.5" stop-color="#FFFFFF" stop-opacity="0.3"/>'
        '<stop offset="1" stop-color="#FFFFFF" stop-opacity="0.6"/></linearGradient>',
        '<linearGradient id="edge" x1="0" y1="0" x2="0" y2="1">'
        '<stop offset="0" stop-color="#FFFFFF" stop-opacity="0.75"/>'
        '<stop offset="0.5" stop-color="#FFFFFF" stop-opacity="0.12"/>'
        '<stop offset="1" stop-color="#FFFFFF" stop-opacity="0.35"/></linearGradient>',
        '<linearGradient id="glass" x1="0" y1="0" x2="0" y2="1">'
        '<stop offset="0" stop-color="#FFFFFF" stop-opacity="0.78"/>'
        f'<stop offset="1" stop-color="{_mix("#FFFFFF", BG_DEEP, 0.25)}" stop-opacity="0.55"/></linearGradient>',
        '<linearGradient id="glassflap" x1="0" y1="0" x2="0" y2="1">'
        '<stop offset="0" stop-color="#FFFFFF" stop-opacity="0.95"/>'
        '<stop offset="1" stop-color="#FFFFFF" stop-opacity="0.62"/></linearGradient>',
        '<radialGradient id="face" cx="0.38" cy="0.30" r="0.8">'
        f'<stop offset="0" stop-color="{FACE_LIGHT}"/><stop offset="0.55" stop-color="{FACE_MID}"/>'
        f'<stop offset="1" stop-color="{FACE_DARK}"/></radialGradient>',
        f'<clipPath id="clip"><path d="{TILE}"/></clipPath>',
        # Apple template shadow: black, 28 px blur radius, 12 px down, 50 %.
        '<filter id="shadow" x="-20%" y="-20%" width="140%" height="140%">'
        f'<feGaussianBlur in="SourceAlpha" stdDeviation="{sigma}"/><feOffset dy="{SHADOW_OFFSET_Y}"/>'
        f'<feComponentTransfer><feFuncA type="linear" slope="{SHADOW_OPACITY}"/></feComponentTransfer>'
        '<feMerge><feMergeNode/><feMergeNode in="SourceGraphic"/></feMerge></filter>',
        # Tinted shadow under the card and seal.
        '<filter id="objshadow" x="-30%" y="-30%" width="160%" height="160%">'
        '<feGaussianBlur in="SourceAlpha" stdDeviation="14"/><feOffset dx="0" dy="16"/>'
        f'<feFlood flood-color="{BG_DEEP}" flood-opacity="0.55"/><feComposite operator="in" in2="SourceAlpha"/>'
        '<feMerge><feMergeNode/><feMergeNode in="SourceGraphic"/></feMerge></filter>',
    ]
    card, (cx, cy) = _card()
    objects = card + _seal(cx, cy, SEAL_RADIUS)
    parts = [
        f'<g filter="url(#shadow)"><path d="{TILE}" fill="url(#bg)"/></g>',
        '<g clip-path="url(#clip)">',
        '<rect x="100" y="100" width="824" height="824" fill="url(#glow)"/>',
        '<g filter="url(#objshadow)">', *objects, '</g>',
        '<rect x="100" y="100" width="824" height="824" fill="url(#sheen)"/>',
        '</g>',
        f'<path d="{TILE}" fill="none" stroke="url(#edge)" stroke-width="6"/>',
    ]
    return ('<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">'
            f'<defs>{"".join(defs)}</defs>{"".join(parts)}</svg>\n')


# ---------------------------------------------------------------------------
# .icns writing. These are the element types `iconutil` emits for a standard
# .iconset; all of them hold PNG data.

ICNS_ELEMENTS = [
    ("icp4", 16), ("ic11", 32), ("icp5", 32), ("ic12", 64),
    ("ic07", 128), ("ic13", 256), ("ic08", 256), ("ic14", 512),
    ("ic09", 512), ("ic10", 1024),
]


def render_png(svg_path, size, out_path):
    subprocess.run(["rsvg-convert", "-w", str(size), "-h", str(size), str(svg_path), "-o", str(out_path)],
                   check=True)


def write_icns(pngs_by_size, out_path):
    chunks = b""
    for code, size in ICNS_ELEMENTS:
        data = pngs_by_size[size]
        chunks += code.encode("ascii") + struct.pack(">I", len(data) + 8) + data
    out_path.write_bytes(b"icns" + struct.pack(">I", len(chunks) + 8) + chunks)


def main():
    parser = argparse.ArgumentParser(description="Generate Resources/AppIcon.svg and AppIcon.icns.")
    parser.add_argument("--preview", action="store_true",
                        help="also write build/icon-preview.png (1024 px)")
    args = parser.parse_args()

    try:
        subprocess.run(["rsvg-convert", "--version"], check=True, capture_output=True)
    except (OSError, subprocess.CalledProcessError):
        sys.exit("error: rsvg-convert not found (macOS: brew install librsvg)")

    RESOURCES.mkdir(exist_ok=True)
    svg_path = RESOURCES / "AppIcon.svg"
    svg_path.write_text(icon_svg())

    with tempfile.TemporaryDirectory() as tmp:
        pngs = {}
        for size in sorted({s for _, s in ICNS_ELEMENTS}):
            png = Path(tmp) / f"icon_{size}.png"
            render_png(svg_path, size, png)
            pngs[size] = png.read_bytes()
        write_icns(pngs, RESOURCES / "AppIcon.icns")

    if args.preview:
        (ROOT / "build").mkdir(exist_ok=True)
        render_png(svg_path, 1024, ROOT / "build" / "icon-preview.png")
    print(f"Wrote {svg_path.relative_to(ROOT)} and Resources/AppIcon.icns")


if __name__ == "__main__":
    main()
