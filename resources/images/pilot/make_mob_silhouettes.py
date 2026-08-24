# players.csv 의 `is_mob = 1` 인 파일럿의 다섯 컷을 실루엣으로 만들어
# pilot/mob/{faces,circle,eye,tall,full}/ 에 같은 파일명으로 저장한다.
#
# **얼굴이 보이면 안 된다.** 그래서 다섯 컷 모두 알파를 그대로 둔 채 RGB 를
# 단색으로 덮는다 — 밝기를 눌러 어둡게만 하던 예전 방식(dim)은 색만 빠진
# 초상화라 이목구비가 그대로 읽혔다.
#
# 문제는 `faces` / `circle` / `eye` 다. 셋은 **얼굴이 프레임을 꽉 채운 크롭**이라
# 알파가 사실상 통짜 사각형이고(실측: eye 밴드의 97.7% 가 불투명), 그 자리에서
# 단색으로 칠하면 검은 원 하나 · 검은 막대 하나가 된다 — 얼굴은 가려지지만
# 사람인지도 알 수 없다. 그래서 셋은 **전신 아트(full)에서 머리~어깨를 다시
# 잘라** 만든다: full 의 알파가 곧 인물 윤곽이라 배경이 투명하게 남아 머리
# 모양과 어깨선이 실루엣으로 읽힌다. 얼굴 사각형은 make_eye_crops.py /
# make_tall_crops.py 와 **같은 템플릿 매칭**으로 찾으므로 세 스크립트의 인물
# 배율이 서로 어긋나지 않는다.
#
# `tall` / `full` 은 이미 알파가 인물 윤곽이라 제자리에서 칠하기만 하면 된다.
#
# `circle` 만 **불투명한 원 바탕을 깔아** 내보낸다. 전장 마커는 초상 뒤에 흰
# 원을 깔고(`BattleRenderer._draw_pilot_circle`) 교전 아레나는 아무것도 안 까는데
# (`EngageArena._draw_unit`), 투명한 채로 두면 같은 그림이 한쪽에선 흰 배지,
# 다른 쪽에선 배경이 비치는 구멍이 된다. 바탕을 구우면 두 곳이 같아진다.
#
#   python resources/images/pilot/make_mob_silhouettes.py     (프로젝트 루트에서)
import csv, io, os
import cv2
import numpy as np
from PIL import Image, ImageDraw

ROOT = os.path.dirname(os.path.abspath(__file__))
PLAYERS = os.path.join(ROOT, "..", "..", "..", "data", "csv", "players.csv")

TINT = np.array([38, 42, 60], dtype=np.float32)     # 실루엣 단색 (어두운 청회색)
CIRCLE_BG = (108, 114, 132, 255)                    # circle 컷에만 까는 원 바탕

# 얼굴 사각형 기준 버스트 창. 값이 클수록 인물이 작게(= 여백이 넓게) 잡힌다.
#   BUST_H = 창 높이 / 얼굴 높이,  TOP = 얼굴 사각형 위로 남기는 여백 / 얼굴 높이
BUST = {
    "faces":  (3.3, 0.62),
    "circle": (3.3, 0.62),
    "eye":    (3.0, 0.55),
}
FLAT = ("tall", "full")     # 제자리에서 칠하기만 하는 컷
NAME = {"faces": "%d_rect.png", "circle": "%d_circle.png", "eye": "%d_eye.png",
        "tall": "%d_tall.png", "full": "%d_full.png"}

# make_eye_crops.py 와 같은 예외: pid 16 은 faces 와 full 이 다른 일러스트라
# 템플릿 매칭이 무기 부품에 오매칭된다. (눈 중심 x, 눈 중심 y, 얼굴 높이).
EYE_Y = 0.38
OVERRIDE = {16: (300.0, 274.0, 118.0)}


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


def flatten(im):
    """알파는 그대로, RGB 만 TINT 로 덮는다."""
    a = np.asarray(im.convert("RGBA")).astype(np.float32)
    rgb = np.broadcast_to(TINT, a[..., :3].shape).copy()
    return Image.fromarray(
        np.concatenate([rgb, a[..., 3:4]], axis=-1).astype(np.uint8), "RGBA")


def face_rect(pid):
    """full 안에서의 (얼굴 중심 x, 얼굴 위끝 y, 얼굴 높이)."""
    if pid in OVERRIDE:
        cx, cy, fh = OVERRIDE[pid]
        return cx, cy - EYE_Y * fh, fh
    full = cv2.imread(os.path.join(ROOT, "full", "%d_full.png" % (pid + 1)),
                      cv2.IMREAD_UNCHANGED)
    face = cv2.imread(os.path.join(ROOT, "faces", "%d_rect.png" % (pid + 1)),
                      cv2.IMREAD_UNCHANGED)
    fx, fy, fw, fh, corr = locate_face(full[:, :, :3], face[:, :, :3])
    print("  face corr %.3f" % corr, end="")
    return fx + fw * 0.5, float(fy), float(fh)


def bust(sil, cx, fy, fh, out_w, out_h, bust_h, top):
    """전신 실루엣에서 머리~어깨 창을 잘라 (out_w, out_h) 로 맞춘다.

    창이 아트 밖으로 나가도 자르지 않고 **투명하게 채운다** — 안쪽으로 밀어
    넣으면 파일럿마다 인물이 프레임 안에서 다른 자리에 앉는다.
    """
    bh = fh * bust_h
    bw = bh * out_w / out_h
    canvas = Image.new("RGBA", (int(round(bw)), int(round(bh))), (0, 0, 0, 0))
    canvas.paste(sil, (int(round(bw * 0.5 - cx)), int(round(fh * top - fy))), sil)
    return canvas.resize((out_w, out_h), Image.LANCZOS)


def circle_backdrop(im):
    """내접원을 CIRCLE_BG 로 채우고 그 위에 실루엣을 얹는다."""
    ss = 4
    mask = Image.new("L", (im.width * ss, im.height * ss), 0)
    ImageDraw.Draw(mask).ellipse((0, 0, im.width * ss - 1, im.height * ss - 1),
                                 fill=255)
    disc = Image.new("RGBA", im.size, CIRCLE_BG)
    disc.putalpha(mask.resize(im.size, Image.LANCZOS))
    out = Image.alpha_composite(disc, im)
    # 실루엣이 원 밖으로 삐져나오지 않게 원 마스크로 한 번 더 자른다.
    out.putalpha(Image.fromarray(np.minimum(
        np.asarray(out.split()[3]), np.asarray(disc.split()[3]))))
    return out


def main():
    with io.open(os.path.normpath(PLAYERS), encoding="utf-8") as f:
        pids = [int(r["id"]) for r in csv.DictReader(f) if int(r["is_mob"]) == 1]
    print("mob pilot ids:", pids)

    for sub in list(BUST) + list(FLAT):
        os.makedirs(os.path.join(ROOT, "mob", sub), exist_ok=True)

    for pid in pids:
        print("pid %2d:" % pid, end="")
        sil = flatten(Image.open(os.path.join(ROOT, "full",
                                              "%d_full.png" % (pid + 1))))
        cx, fy, fh = face_rect(pid)
        for sub, (bust_h, top) in BUST.items():
            name = NAME[sub] % (pid + 1)
            src = Image.open(os.path.join(ROOT, sub, name))
            out = bust(sil, cx, fy, fh, src.width, src.height, bust_h, top)
            if sub == "circle":
                out = circle_backdrop(out)
            out.save(os.path.join(ROOT, "mob", sub, name))
        for sub in FLAT:
            name = NAME[sub] % (pid + 1)
            flatten(Image.open(os.path.join(ROOT, sub, name))).save(
                os.path.join(ROOT, "mob", sub, name))
        print(" ok")
    print("wrote %d silhouettes" % (len(pids) * (len(BUST) + len(FLAT))))


if __name__ == "__main__":
    main()
