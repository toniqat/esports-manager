# full/N_full.png 에서 "머리~가슴"의 세로로 긴 버스트를 잘라 tall/N_tall.png 로 저장.
#
# 얼굴 찾기는 make_eye_crops.py 와 **같은 방식**이다 — faces/N_rect.png 를 full 안에서
# 다중 스케일 템플릿 매칭으로 되찾는다(실측 상관계수 0.84~0.99). 두 크롭이 같은 얼굴
# 사각형에서 나오므로 스트립마다 얼굴 배율이 어긋나지 않는다.
#
# 구도: 얼굴 사각형 위로 TOP_PAD(머리 여백), 아래로 BUST_H 만큼 내려간 세로 밴드.
# 폭은 높이 × ASPECT 로 정해 **출력 비율(1 : 3.33)을 파일럿마다 고정**한다 —
# 폭을 어깨에 맞춰 재면 파일럿마다 인물 크기가 들쭉날쭉해진다.
#
# **밴드 폭은 얼굴 높이의 1.32배로 고정이다** (`BAND_W_FACES` = 예전 2.40×0.55).
# 스트립 칸 폭이 90px 로 고정이므로 이 값이 곧 화면에서의 얼굴 크기다 — BUST_H 를
# 늘릴 때 ASPECT 를 같은 비율로 줄여 폭을 유지해야 "세로만 길어지고 얼굴 크기는
# 그대로"가 된다. 폭까지 같이 늘리면 얼굴이 작아져 스트립에서 안 읽힌다.
import os, glob, sys
import cv2
import numpy as np

ROOT = os.path.dirname(os.path.abspath(__file__))
FULL = os.path.join(ROOT, "full")
FACES = os.path.join(ROOT, "faces")
OUT = os.path.join(ROOT, "tall")

EYE_Y = 0.38           # make_eye_crops.py 와 같은 눈 높이(얼굴 높이 비율)
TOP_PAD = 0.30         # 얼굴 사각형 위로 남기는 머리 여백 (얼굴 높이 비율)
BUST_H = 4.40          # 밴드 높이 = 얼굴 높이 × 이 값 (머리 ~ 허벅지)
BAND_W_FACES = 1.32    # 밴드 폭 = 얼굴 높이 × 이 값 (고정 — 위 주석 참조)
ASPECT = BAND_W_FACES / BUST_H   # 밴드 가로:세로 = 0.30
OUT_W, OUT_H = 210, 700

# make_eye_crops.py 와 같은 예외: pid 16 은 faces 와 full 이 다른 일러스트라
# 템플릿 매칭이 무기 부품에 오매칭된다. (눈 중심 x, 눈 중심 y, 얼굴 높이).
OVERRIDE = {16: (300.0, 274.0, 118.0)}

os.makedirs(OUT, exist_ok=True)


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


rows = []
for path in sorted(glob.glob(os.path.join(FULL, "*_full.png"))):
    pid = int(os.path.basename(path).split("_")[0])
    full = cv2.imread(path, cv2.IMREAD_UNCHANGED)
    face = cv2.imread(os.path.join(FACES, "%d_rect.png" % pid), cv2.IMREAD_UNCHANGED)
    if full is None or face is None:
        print("MISSING", pid); sys.exit(1)
    if full.shape[2] == 3:
        full = cv2.cvtColor(full, cv2.COLOR_BGR2BGRA)

    if pid in OVERRIDE:
        ex, ey, fh = OVERRIDE[pid]
        cx = ex
        fy = ey - fh * EYE_Y
        corr = -1.0
    else:
        fx, fy, fw, fh, corr = locate_face(full[:, :, :3], face[:, :, :3])
        cx = fx + fw * 0.5

    band_h = fh * BUST_H
    band_w = band_h * ASPECT

    H, W = full.shape[:2]
    # 잘려서 비율이 깨지면 그 파일럿만 세로로 눌린다 — 조용히 넘기지 않는다.
    if band_h > H or band_w > W:
        print("  !! pid %d 밴드가 원본(%dx%d)보다 큼 → %dx%d 로 잘림(비율 깨짐)"
              % (pid, W, H, min(band_w, W), min(band_h, H)))
    band_w = min(band_w, W)
    band_h = min(band_h, H)
    x0 = int(round(min(max(0.0, cx - band_w * 0.5), W - band_w)))
    y0 = int(round(min(max(0.0, fy - fh * TOP_PAD), H - band_h)))
    crop = full[y0:y0 + int(round(band_h)), x0:x0 + int(round(band_w))]
    out = cv2.resize(crop, (OUT_W, OUT_H), interpolation=cv2.INTER_AREA)
    cv2.imwrite(os.path.join(OUT, "%d_tall.png" % pid), out)
    rows.append((pid, corr, x0, y0, int(band_w), int(band_h)))

rows.sort(key=lambda r: r[1])
print("corr 최저 8건:")
for r in rows[:8]:
    print("  pid %2d corr=%.3f band=(%d,%d %dx%d)" % r)
print("총 %d장, corr 평균 %.3f / 최저 %.3f" % (
    len(rows), np.mean([r[1] for r in rows]), rows[0][1]))
