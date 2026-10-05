# Bakes the hand-card owner ribbon: ribbon/N_ribbon.png (and mob/ribbon/ for
# is_mob pilots). The ribbon is a right triangle covering the card's top-right
# corner, with the pilot's eyes placed inside it.
#
# Why baked and not a runtime mask: a mask shader adds a ShaderMaterial per
# hand card (extra pipeline variant / first-use compile hitch on mobile) and an
# SDF pass for the anti-aliased diagonal + rounded corner. Baking costs nothing
# at runtime — Card.gd shows it with a plain TextureRect.
#
# Face location uses the same multi-scale template match as make_eye_crops.py /
# make_mob_silhouettes.py, so the face scale is uniform across pilots.
#
# Geometry is in CARD units (Card.gd: CARD_W 160, CARD_RADIUS 10) and must match
# Card.gd's RIBBON_* constants:
#   canvas  = LEG x (LEG + SHADOW_PAD), placed at card (CARD_W - LEG, 0)
#   triangle = (0,0) (LEG,0) (LEG,LEG), top-right corner rounded by CARD_RADIUS
#   drop shadow falls straight down from the diagonal into the SHADOW_PAD strip
#
#   python resources/images/pilot/make_ribbon_crops.py     (from the project root)
import csv, io, os
import cv2
import numpy as np
from PIL import Image, ImageDraw, ImageFilter

ROOT = os.path.dirname(os.path.abspath(__file__))
PLAYERS = os.path.join(ROOT, "..", "..", "..", "data", "csv", "players.csv")

LEG = 60            # triangle leg (card units) — Card.RIBBON_LEG
SHADOW_PAD = 8      # canvas strip below the triangle for the shadow — Card.RIBBON_SHADOW_PAD
CARD_RADIUS = 10    # Card.CARD_RADIUS
SCALE = 2           # baked px per card unit (hand 1.2 x hover 1.2 stays near 1:1)
SS = 4              # supersampling for the mask edges

# Eye placement inside the triangle (card units, canvas origin top-left).
# At height EYE_Y the triangle spans x in [EYE_Y, LEG]; EYE_X sits a bit right
# of that span's middle so both eyes clear the diagonal.
EYE_Y = 18.0
EYE_X = 40.0
FACE_H = 46.0       # face rect height in card units (sets the zoom)
FACE_EYE_Y = 0.38   # eye line inside the face rect (make_eye_crops.py)

SHADOW_DY = 3.0     # card units, straight down
SHADOW_BLUR = 2.5   # gaussian radius, card units
SHADOW_ALPHA = 0.65
BACKING = (108, 114, 132, 255)   # behind transparent art (same as mob circle bg)

# File number -> (eye cx, eye cy, face h): faces/16_rect.png is a different
# illustration from full/16_full.png, so the template match misfires.
OVERRIDE = {16: (300.0, 274.0, 118.0)}


def locate_face(full_bgr, face_bgr):
    """(x, y, w, h, corr) of the face template inside full."""
    best = None
    for lo, hi, step in ((0.12, 0.98, 0.01), (None, None, 0.002)):
        if lo is None:
            lo = max(0.05, best[5] - 0.02)
            hi = min(1.20, best[5] + 0.02)
            step = 0.002
        s = lo
        while s <= hi:
            w = int(round(face_bgr.shape[1] * s))
            h = int(round(face_bgr.shape[0] * s))
            if 8 <= w <= full_bgr.shape[1] and 8 <= h <= full_bgr.shape[0]:
                t = cv2.resize(face_bgr, (w, h), interpolation=cv2.INTER_AREA)
                res = cv2.matchTemplate(full_bgr, t, cv2.TM_CCOEFF_NORMED)
                _, mx, _, mxl = cv2.minMaxLoc(res)
                if best is None or mx > best[0]:
                    best = (mx, mxl[0], mxl[1], w, h, s)
            s += step
    corr, x, y, w, h, _ = best
    return x, y, w, h, corr


def eye_point(num):
    """(eye cx, eye cy, face h) in full/<num>_full.png pixels."""
    if num in OVERRIDE:
        return OVERRIDE[num]
    full = cv2.imread(os.path.join(ROOT, "full", "%d_full.png" % num), cv2.IMREAD_UNCHANGED)
    face = cv2.imread(os.path.join(ROOT, "faces", "%d_rect.png" % num), cv2.IMREAD_UNCHANGED)
    fx, fy, fw, fh, corr = locate_face(full[:, :, :3], face[:, :, :3])
    print("  #%2d corr %.3f" % (num, corr))
    return fx + fw * 0.5, fy + fh * FACE_EYE_Y, float(fh)


def masks():
    """(ribbon alpha, shadow alpha) as L images at the baked size."""
    w, h = LEG * SCALE * SS, (LEG + SHADOW_PAD) * SCALE * SS
    u = SCALE * SS
    tri = Image.new("L", (w, h), 0)
    ImageDraw.Draw(tri).polygon([(0, 0), (LEG * u, 0), (LEG * u, LEG * u)], fill=255)
    # Card corner rounding — only the top-right corner of this rect is on canvas.
    corner = Image.new("L", (w, h), 0)
    ImageDraw.Draw(corner).rounded_rectangle(
        (-w, 0, w - 1, h * 2), radius=CARD_RADIUS * u, fill=255)
    rib = Image.fromarray(np.minimum(np.asarray(tri), np.asarray(corner)))

    shadow = Image.new("L", (w, h), 0)
    shadow.paste(rib, (0, int(round(SHADOW_DY * u))))
    shadow = shadow.filter(ImageFilter.GaussianBlur(SHADOW_BLUR * u))
    shadow = Image.fromarray(np.minimum(np.asarray(shadow), np.asarray(corner)))
    out = (LEG * SCALE, (LEG + SHADOW_PAD) * SCALE)
    return rib.resize(out, Image.LANCZOS), shadow.resize(out, Image.LANCZOS)


def bake(full_path, ex, ey, fh, rib_a, shadow_a):
    size = rib_a.size
    k = FACE_H * SCALE / fh                     # baked px per source px
    full = Image.open(full_path).convert("RGBA")
    full = full.resize((max(1, int(round(full.width * k))),
                        max(1, int(round(full.height * k)))), Image.LANCZOS)
    layer = Image.new("RGBA", size, (0, 0, 0, 0))
    layer.paste(full, (int(round(EYE_X * SCALE - ex * k)),
                       int(round(EYE_Y * SCALE - ey * k))))
    art = Image.alpha_composite(Image.new("RGBA", size, BACKING), layer)
    art.putalpha(rib_a)

    sh = Image.new("RGBA", size, (0, 0, 0, 0))
    sh.putalpha(shadow_a.point(lambda v: int(v * SHADOW_ALPHA)))
    return Image.alpha_composite(sh, art)


def main():
    with io.open(os.path.normpath(PLAYERS), encoding="utf-8") as f:
        mob = {int(r["id"]) + 1 for r in csv.DictReader(f) if int(r["is_mob"]) == 1}
    rib_a, shadow_a = masks()
    os.makedirs(os.path.join(ROOT, "ribbon"), exist_ok=True)
    os.makedirs(os.path.join(ROOT, "mob", "ribbon"), exist_ok=True)
    n = 0
    for num in range(1, 41):
        ex, ey, fh = eye_point(num)
        name = "%d_ribbon.png" % num
        bake(os.path.join(ROOT, "full", "%d_full.png" % num), ex, ey, fh,
             rib_a, shadow_a).save(os.path.join(ROOT, "ribbon", name))
        n += 1
        if num in mob:
            bake(os.path.join(ROOT, "mob", "full", "%d_full.png" % num), ex, ey, fh,
                 rib_a, shadow_a).save(os.path.join(ROOT, "mob", "ribbon", name))
            n += 1
    print("wrote %d ribbons" % n)


if __name__ == "__main__":
    main()
