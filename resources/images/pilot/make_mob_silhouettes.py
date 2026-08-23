# players.csv 의 `is_mob = 1` 인 파일럿의 다섯 컷을 실루엣으로 만들어
# pilot/mob/{faces,circle,eye,tall,full}/ 에 같은 파일명으로 저장한다.
#
# 방식이 컷마다 다른 것이 요점이다. `full` / `tall` 은 알파가 곧 인물 윤곽이라
# 납작한 단색으로 칠하면 그림자 인간이 되지만, `circle` / `faces` / `eye` 는
# 원형 마스크·타이트 얼굴 크롭이라 같은 처리를 하면 특징 없는 덩어리가 된다
# (실측: circle 을 단색으로 칠하면 그냥 검은 원 하나다). 그쪽은 밝기를 어두운
# 띠로 눌러 얼굴 형태만 남긴다.
#
#   python resources/images/pilot/make_mob_silhouettes.py     (프로젝트 루트에서)
import csv, io, os
import numpy as np
from PIL import Image

ROOT = os.path.dirname(os.path.abspath(__file__))
PLAYERS = os.path.join(ROOT, "..", "..", "..", "data", "csv", "players.csv")

SETS = {
    "faces":  ("%d_rect.png",   "dim"),
    "circle": ("%d_circle.png", "dim"),
    "eye":    ("%d_eye.png",    "dim"),
    "tall":   ("%d_tall.png",   "flat"),
    "full":   ("%d_full.png",   "flat"),
}
TINT = np.array([38, 42, 60], dtype=np.float32)   # 어두운 청회색
LO, HI = 0.10, 0.46                               # dim 모드의 밝기 압축 구간


def main():
    with io.open(os.path.normpath(PLAYERS), encoding="utf-8") as f:
        pids = [int(r["id"]) for r in csv.DictReader(f) if int(r["is_mob"]) == 1]
    print("mob pilot ids:", pids)

    for sub, (pat, mode) in SETS.items():
        out = os.path.join(ROOT, "mob", sub)
        os.makedirs(out, exist_ok=True)
        for pid in pids:
            name = pat % (pid + 1)
            arr = np.asarray(Image.open(os.path.join(ROOT, sub, name))
                             .convert("RGBA")).astype(np.float32)
            if mode == "flat":
                rgb = np.broadcast_to(TINT, arr[..., :3].shape).copy()
            else:
                lum = (0.299 * arr[..., 0] + 0.587 * arr[..., 1]
                       + 0.114 * arr[..., 2]) / 255.0
                rgb = np.clip(TINT[None, None, :]
                              * ((LO + (HI - LO) * lum) / HI)[..., None] * 2.0, 0, 255)
            Image.fromarray(
                np.concatenate([rgb, arr[..., 3:4]], axis=-1).astype(np.uint8),
                "RGBA").save(os.path.join(out, name))
    print("wrote %d silhouettes" % (len(pids) * len(SETS)))


if __name__ == "__main__":
    main()
