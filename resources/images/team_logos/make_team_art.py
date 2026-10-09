"""Team art generator: the 12 team logos (team_<id>.svg, one emblem shape per team) and the
PREP banners (../team_banners/banner_<id>.svg), coloured from data/csv/teams.csv and
intl_teams.csv (color_main / color_sub).

    python resources/images/team_logos/make_team_art.py [repo root]

Rerun after changing a team colour, then `godot --headless --path . --import` for the .import files.
"""
import csv, os, sys, math
root = sys.argv[1] if len(sys.argv) > 1 else os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", ".."))
LOGO = os.path.join(root, "resources/images/team_logos")
BAN = os.path.join(root, "resources/images/team_banners")
os.makedirs(BAN, exist_ok=True)
COL = {}
for f in ("data/csv/teams.csv", "data/csv/intl_teams.csv"):
    for r in csv.DictReader(open(os.path.join(root, f), encoding="utf-8")):
        COL[int(r["id"])] = (r["color_main"], r["color_sub"])

# Glyphs (unchanged symbols). Single-colour glyphs as one path / group, holes via evenodd.
G_STAR = '<path d="M64 30 L72 54 L97 54 L77 69 L85 93 L64 78 L43 93 L51 69 L31 54 L56 54 Z"/>'
G_BOLT = '<path d="M72 26 L42 70 L62 70 L54 102 L86 56 L66 56 Z"/>'
G_RING = '<path fill-rule="evenodd" d="M64 32.5 A31.5 31.5 0 1 1 63.99 32.5 Z M64 43.5 A20.5 20.5 0 1 0 64.01 43.5 Z M64 56 A8 8 0 1 1 63.99 56 Z"/>'
G_CHEV = '<path d="M36 44 L64 66 L92 44 L92 60 L64 82 L36 60 Z M36 66 L64 88 L92 66 L92 80 L64 102 L36 80 Z"/>'
G_DIAM = '<path fill-rule="evenodd" d="M64 28 L92 64 L64 100 L36 64 Z M64 46 L50 64 L64 82 L78 64 Z"/>'
G_CROWN = '<path d="M34 86 L34 46 L50 62 L64 38 L78 62 L94 46 L94 86 Z"/>'
G_CLAW = '<path d="M30 74 C44 40 70 32 98 34 C82 44 76 54 74 64 C64 62 52 66 30 74 Z M44 92 C60 70 80 66 100 66 C88 76 82 84 80 94 Z"/>'
G_TRI = '<path fill-rule="evenodd" d="M64 30 L98 92 L30 92 Z M64 56 L48 84 L80 84 Z"/>'

def poly(n, r, rot=0.0, cx=64, cy=64):
    pts = []
    for i in range(n):
        a = math.radians(rot + 360.0 * i / n)
        pts.append("%.1f %.1f" % (cx + r * math.cos(a), cy + r * math.sin(a)))
    return "M" + " L".join(pts) + " Z"

def star_badge(points, ro, ri):
    pts = []
    for i in range(points * 2):
        r = ro if i % 2 == 0 else ri
        a = math.radians(-90 + 180.0 * i / points)
        pts.append("%.1f %.1f" % (64 + r * math.cos(a), 64 + r * math.sin(a)))
    return "M" + " L".join(pts) + " Z"

SHIELD = "M64 6 L116 22 L116 62 C116 92 94 112 64 124 C34 112 12 92 12 62 L12 22 Z"
# id -> (shape name, glyph, backdrop kind, backdrop data)
TEAMS = {
    0: ("circle", G_STAR, "path", "M64 6 A58 58 0 1 1 63.99 6 Z"),
    1: ("three horizontal bars", G_BOLT, "bars_h", None),
    2: ("hexagon", G_RING, "path", poly(6, 60, 30)),
    3: ("shield", G_CHEV, "path", SHIELD),
    4: ("octagon", G_DIAM, "path", poly(8, 60, 22.5)),
    5: ("rounded square", G_CROWN, "rect", None),
    6: ("diamond", G_CLAW, "path", "M64 2 L126 64 L64 126 L2 64 Z"),
    7: ("three vertical bars", G_TRI, "bars_v", None),
    100: ("star badge", G_STAR, "path", star_badge(12, 62, 52)),
    101: ("split diagonal", G_BOLT, "split", None),
    102: ("swallowtail pennant", G_RING, "path", "M14 6 L114 6 L114 124 L64 100 L14 124 Z"),
    103: ("chevron badge", G_CHEV, "path", "M10 10 L64 24 L118 10 L118 92 L64 122 L10 92 Z"),
}
H_BARS = [(6, 38), (47, 81), (90, 122)]   # y0, y1 (gaps 9)
V_BARS = [(6, 38), (47, 81), (90, 122)]   # x0, x1

def glyph(g, fill):
    return '<g fill="%s">%s</g>' % (fill, g)

def logo_svg(tid):
    name, g, kind, data = TEAMS[tid]
    main, sub = COL[tid]
    out = ['<svg xmlns="http://www.w3.org/2000/svg" width="128" height="128" viewBox="0 0 128 128">']
    if kind == "path":
        out.append('<path d="%s" fill="%s"/>' % (data, main))
        out.append(glyph(g, sub))
    elif kind == "rect":
        out.append('<rect x="8" y="8" width="112" height="112" rx="26" fill="%s"/>' % main)
        out.append(glyph(g, sub))
    elif kind == "split":
        out.append('<rect x="8" y="8" width="112" height="112" rx="10" fill="%s"/>' % main)
        out.append('<path d="M120 8 L120 110 A10 10 0 0 1 110 120 L8 120 Z" fill="#000" fill-opacity="0.28"/>')
        out.append(glyph(g, sub))
    else:  # bars: glyph in sub over the bars, in main over the gaps (colour inverts)
        rects = []
        for a, b in (H_BARS if kind == "bars_h" else V_BARS):
            if kind == "bars_h":
                rects.append('<rect x="6" y="%d" width="116" height="%d" rx="7"/>' % (a, b - a))
            else:
                rects.append('<rect x="%d" y="6" width="%d" height="116" rx="7"/>' % (a, b - a))
        out.append('<defs><clipPath id="bars">%s</clipPath></defs>' % "".join(rects))
        out.append('<g fill="%s">%s</g>' % (main, "".join(rects)))
        out.append(glyph(g, main))                       # gaps: main glyph on the page
        out.append('<g clip-path="url(#bars)">%s</g>' % glyph(g, sub))  # bars: sub glyph
    out.append("</svg>")
    return "".join(out)

for tid in TEAMS:
    open(os.path.join(LOGO, "team_%d.svg" % tid), "w", encoding="utf-8", newline="\n").write(logo_svg(tid) + "\n")

# Banners: main field, sub stripes / edge bands, faint logo watermark (logo with main / sub swapped).
for tid in TEAMS:
    main, sub = COL[tid]
    inner = logo_svg(tid)
    inner = inner[inner.index(">") + 1: inner.rindex("</svg>")]
    wm = inner.replace(main, "@M@").replace(sub, main).replace("@M@", sub).replace('id="bars"', 'id="wm%d"').replace("url(#bars)", "url(#wm%d)")
    W, H = 1000, 320
    p = ['<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d" viewBox="0 0 %d %d">' % (W, H, W, H),
         '<rect width="%d" height="%d" fill="%s"/>' % (W, H, main)]
    y = 26
    while y + 4 <= H - 26:
        p.append('<rect y="%d" width="%d" height="4" fill="%s" fill-opacity="0.16"/>' % (y, W, sub))
        y += 16
    p.append('<rect width="%d" height="12" fill="%s" fill-opacity="0.55"/>' % (W, sub))
    p.append('<rect y="16" width="%d" height="3" fill="%s" fill-opacity="0.35"/>' % (W, sub))
    p.append('<rect y="%d" width="%d" height="3" fill="%s" fill-opacity="0.35"/>' % (H - 19, W, sub))
    p.append('<rect y="%d" width="%d" height="12" fill="%s" fill-opacity="0.55"/>' % (H - 12, W, sub))
    p.append('<g opacity="0.2" transform="translate(%d %d) scale(2.7)">%s</g>' % (W - 330, -13, wm.replace("%d", "a")))
    p.append('<g opacity="0.12" transform="translate(%d %d) scale(2.7)">%s</g>' % (-16, -13, wm.replace("%d", "b")))
    p.append("</svg>")
    open(os.path.join(BAN, "banner_%d.svg" % tid), "w", encoding="utf-8", newline="\n").write("".join(p) + "\n")
for tid, t in TEAMS.items():
    print(tid, t[0], COL[tid])
