# full/N_full.png 에서 "양 눈이 보이는 가로로 긴" 밴드를 잘라 eye/N_eye.png 로 저장.
#
# 얼굴 위치는 추측하지 않는다 — faces/N_rect.png 가 같은 원본 아트의 얼굴 크롭이라
# (실측 상관계수 0.84~0.99) 다중 스케일 템플릿 매칭으로 full 안의 얼굴 사각형을
# 정확히 되찾을 수 있다. 눈은 그 사각형 높이의 약 0.38 지점에 있다(40장 육안 확인).
import os, glob, sys
import cv2
import numpy as np

ROOT = r"D:\Projects\Godot Project\esports-manager\resources\images\pilot"
FULL = os.path.join(ROOT, "full")
FACES = os.path.join(ROOT, "faces")
OUT = os.path.join(ROOT, "eye")

# 얼굴 사각형 기준 눈 밴드. EYE_Y 는 눈 중심의 세로 위치(얼굴 높이 비율).
EYE_Y = 0.38
BAND_H = 0.46          # 밴드 높이 = 얼굴 높이 × 이 값
BAND_ASPECT = 2.4      # 밴드 가로:세로
OUT_W, OUT_H = 480, 200

# 템플릿 매칭이 통하지 않는 파일럿의 수동 지정: pid → (눈 중심 x, 눈 중심 y, 얼굴 높이).
# pid 16 은 faces/16_rect.png 가 full/16_full.png 와 **다른 일러스트**(다른 코스튬 ·
# 다른 포즈)라 상관계수가 0.554 까지 떨어지고 무기 부품에 오매칭된다. 나머지 39장은
# 0.84~0.99 로 안정적이다.
OVERRIDE = {16: (300.0, 274.0, 118.0)}

os.makedirs(OUT, exist_ok=True)


def locate_face(full_bgr, face_bgr):
    """full 안에서 face 템플릿의 (x, y, w, h, corr) 을 찾는다."""
    best = None
    for lo, hi, step in ((0.12, 0.98, 0.01), (None, None, 0.002)):
        if lo is None:
            lo = max(0.05, best[4] - 0.02)
            hi = min(1.20, best[4] + 0.02)
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
        cx, cy, fh = OVERRIDE[pid]
        corr = -1.0
    else:
        fx, fy, fw, fh, corr = locate_face(full[:, :, :3], face[:, :, :3])
        cx = fx + fw * 0.5
        cy = fy + fh * EYE_Y

    band_h = fh * BAND_H
    band_w = band_h * BAND_ASPECT

    H, W = full.shape[:2]
    # 밴드가 이미지보다 크면 그때만 줄이고, 아니면 안쪽으로 밀어 넣는다 —
    # 줄이면 파일럿마다 배율이 달라져 스트립에서 얼굴 크기가 들쭉날쭉해진다.
    band_w = min(band_w, W)
    band_h = min(band_h, H)
    x0 = int(round(min(max(0.0, cx - band_w * 0.5), W - band_w)))
    y0 = int(round(min(max(0.0, cy - band_h * 0.5), H - band_h)))
    crop = full[y0:y0 + int(round(band_h)), x0:x0 + int(round(band_w))]
    out = cv2.resize(crop, (OUT_W, OUT_H), interpolation=cv2.INTER_AREA)
    cv2.imwrite(os.path.join(OUT, "%d_eye.png" % pid), out)
    rows.append((pid, corr, x0, y0, int(band_w), int(band_h)))

rows.sort(key=lambda r: r[1])
print("corr 최저 8건:")
for r in rows[:8]:
    print("  pid %2d corr=%.3f band=(%d,%d %dx%d)" % r)
print("총 %d장, corr 평균 %.3f / 최저 %.3f" % (
    len(rows), np.mean([r[1] for r in rows]), rows[0][1]))
