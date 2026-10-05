# full/N_full.png 에서 "머리~어깨" 흉상을 잘라 strip/N_strip.png 로 저장한다 —
# 파일럿 스트립의 원형 초상(`ui/PilotStrip.gd`)이 쓴다.
#
# 얼굴 찾기는 make_eye_crops.py / make_tall_crops.py 와 **같은 템플릿 매칭**이라
# 다섯 칸의 얼굴 배율이 어긋나지 않는다. 배경은 full 의 알파 그대로 투명하게
# 남는다 — 원 마스킹은 PNG 에 굽지 않고 셰이더(`pilot_bust_mask.gdshader`)가
# 한다. 원 지름 · 돌출 비율을 바꿀 때 컷을 다시 굽지 않아도 되게 하려는 것이다.
#
# 구도 (단위: 얼굴 높이 fh):
#   창 폭  = WIN_W  (= 원 지름 — 셰이더가 원 폭만큼 좌우를 자른다)
#   창 높이 = WIN_W × OUT_H / OUT_W  (원 위로 머리가 튀어나올 여백 포함)
#   창 위끝 = 얼굴 사각형 위끝 − TOP_PAD
# 창이 full 밖으로 나가면 투명으로 채운다(잘라 붙이면 그 파일럿만 비율이 깨진다).
#
# 모브 파일럿은 mob/full 의 같은 자리를 잘라 mob/strip 에 저장한다 — 실루엣
# full 은 원본과 픽셀 좌표가 같으므로 얼굴 사각형을 원본에서 찾아 그대로 쓴다.
#
#   python resources/images/pilot/make_strip_crops.py     (프로젝트 루트에서)
import os, glob, sys
import cv2
import numpy as np

ROOT = os.path.dirname(os.path.abspath(__file__))
FULL = os.path.join(ROOT, "full")
FACES = os.path.join(ROOT, "faces")
OUT = os.path.join(ROOT, "strip")
MOB_FULL = os.path.join(ROOT, "mob", "full")
MOB_OUT = os.path.join(ROOT, "mob", "strip")

EYE_Y = 0.38
WIN_W = 1.75           # 창 폭(= 원 지름) / 얼굴 높이
TOP_PAD = 0.30         # 얼굴 사각형 위로 남기는 여백 / 얼굴 높이
OUT_W, OUT_H = 256, 320   # 가로:세로 = 0.8 — `PilotImages.STRIP_ASPECT` 와 같아야 한다

OVERRIDE = {16: (300.0, 274.0, 118.0)}

os.makedirs(OUT, exist_ok=True)
os.makedirs(MOB_OUT, exist_ok=True)


def locate_face(full_bgr, face_bgr):
    """full 안에서 face 템플릿의 (x, y, w, h, corr) 을 찾는다."""
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


def crop_window(img, x0, y0, w, h):
    """(x0, y0, w, h) 창을 잘라 낸다. 원본 밖은 투명 픽셀로 채운다."""
    H, W = img.shape[:2]
    out = np.zeros((h, w, 4), dtype=img.dtype)
    sx0, sy0 = max(0, x0), max(0, y0)
    sx1, sy1 = min(W, x0 + w), min(H, y0 + h)
    if sx1 > sx0 and sy1 > sy0:
        out[sy0 - y0:sy1 - y0, sx0 - x0:sx1 - x0] = img[sy0:sy1, sx0:sx1]
    return out


def to_bgra(img):
    return cv2.cvtColor(img, cv2.COLOR_BGR2BGRA) if img.shape[2] == 3 else img


rows = []
for path in sorted(glob.glob(os.path.join(FULL, "*_full.png"))):
    pid = int(os.path.basename(path).split("_")[0])
    full = cv2.imread(path, cv2.IMREAD_UNCHANGED)
    face = cv2.imread(os.path.join(FACES, "%d_rect.png" % pid), cv2.IMREAD_UNCHANGED)
    if full is None or face is None:
        print("MISSING", pid); sys.exit(1)
    full = to_bgra(full)

    if pid in OVERRIDE:
        ex, ey, fh = OVERRIDE[pid]
        cx = ex
        fy = ey - fh * EYE_Y
        corr = -1.0
    else:
        fx, fy, fw, fh, corr = locate_face(full[:, :, :3], face[:, :, :3])
        cx = fx + fw * 0.5

    win_w = int(round(fh * WIN_W))
    win_h = int(round(win_w * OUT_H / OUT_W))
    x0 = int(round(cx - win_w * 0.5))
    y0 = int(round(fy - fh * TOP_PAD))

    out = cv2.resize(crop_window(full, x0, y0, win_w, win_h), (OUT_W, OUT_H),
                     interpolation=cv2.INTER_AREA)
    cv2.imwrite(os.path.join(OUT, "%d_strip.png" % pid), out)

    mob_path = os.path.join(MOB_FULL, "%d_full.png" % pid)
    if os.path.exists(mob_path):
        mob = to_bgra(cv2.imread(mob_path, cv2.IMREAD_UNCHANGED))
        mout = cv2.resize(crop_window(mob, x0, y0, win_w, win_h), (OUT_W, OUT_H),
                          interpolation=cv2.INTER_AREA)
        cv2.imwrite(os.path.join(MOB_OUT, "%d_strip.png" % pid), mout)
    rows.append((pid, corr, x0, y0, win_w, win_h))

rows.sort(key=lambda r: r[1])
print("corr 최저 5건:")
for r in rows[:5]:
    print("  pid %2d corr=%.3f win=(%d,%d %dx%d)" % r)
print("총 %d장" % len(rows))
