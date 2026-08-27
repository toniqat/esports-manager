#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""메크 전신 아트에서 **정사각 초상화**를 굽는다.

    resources/images/mech/{id}_full.png  →  resources/images/mech/portrait/{id}_portrait.png

전신 아트는 1024² 캔버스에 기체가 온몸으로 서 있는 그림이라, 밴픽 격자처럼
칸이 200px 도 안 되는 자리에 그대로 넣으면 기체가 콩알만 하게 들어가고 어느
기체인지가 안 읽힌다. 그래서 챔피언 아이콘처럼 **머리~상반신만** 잘라 정사각
한 장으로 굽는다. 쓰는 곳은 밴픽 격자 · 밴 칩 · 팀 블록의 메크 칸이고, 상세
시트만 여전히 원본 전신 아트를 쓴다(거기서는 한 번에 한 대뿐이다).

── 머리를 찾는 법 ──────────────────────────────────────────────────────────
알파 바운딩 박스의 위끝을 머리로 치면 안 된다 — 21대 중 열 대 넘게 라이플 ·
안테나 · 날개가 머리 위로 뻗어 있어서, 그 자리에서 자르면 프레임이 무기로
가득 차고 얼굴은 아래로 밀려난다. 그래서 알파를 **침식**(MinFilter)해 폭이
얇은 구조물을 통째로 지운 뒤, 남은 덩어리의 위끝을 머리로 삼는다. 가로
중심도 같은 침식 마스크로 잡는다 — 옆으로 뻗은 칼·총을 세면 중심이 그쪽으로
끌려간다.

크기는 **기체 전체 높이의 비율**로 잡는다(`SIDE_FRAC`). 절대 픽셀로 잡으면
아트마다 기체 크기가 달라 어떤 기체는 얼굴만, 어떤 기체는 무릎까지 들어온다.

── 손으로 잡아 주는 자리 ───────────────────────────────────────────────────
자동 판정이 어긋나는 기체만 `OVERRIDES` 에 적는다. 값은 자동 판정에 **더하는**
보정이고(비율 단위), 표에 없는 기체는 전부 자동값 그대로다.

실행: `python resources/images/mech/make_mech_portraits.py` (프로젝트 루트에서)
"""

import os
import re
import glob

from PIL import Image, ImageFilter
import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
OUT_DIR = os.path.join(HERE, "portrait")

OUT_PX = 256
## 자를 정사각형의 한 변 = 기체 전체 높이 × 이 값.
SIDE_FRAC = 0.58
## 머리 위로 남기는 여백 = 정사각형 한 변 × 이 값.
HEADROOM = 0.10
## 침식 반경(px). 이보다 얇은 구조물(총열 · 안테나 · 날개 끝)은 머리 판정에서
## 빠진다. 31 은 1024² 아트에서 기체 팔뚝은 남고 라이플은 지워지는 값이다.
ERODE = 31

# id → 보정. 두 가지 형식이 있다.
#   {"box": (left, top, side)}  — 1024² 원본 좌표의 **절대** 정사각형. 자동
#                                 판정이 머리를 아예 못 찾는 기체만 이걸 쓴다.
#   {"side"/"head"/"dx"/"dy"}   — 자동값에 **더하는** 비율 보정.
# 표에 없는 기체는 전부 자동값 그대로다.
OVERRIDES = {
	# Bulwark-A1 — 거대한 방패가 몸통 앞을 가로질러서 침식 덩어리의 위끝이
	# 방패 모서리다. 머리는 그 뒤 왼쪽 위에 따로 있어 자동 판정이 닿지 않는다.
	0:  {"box": (110, 240, 520)},
	# Cleric-P1 — 왼쪽으로 뻗은 라이플과 백팩이 무게중심을 통째로 끌어가
	# 프레임에서 기체가 오른쪽 아래로 밀려난다.
	20: {"box": (283, 373, 470)},
	# Oracle-L1 — 오른쪽으로 뻗은 팔이 중심을 그쪽으로 당긴다.
	22: {"dx": -0.13},
	# Sniper-Q1 / Longbow-F1 — 라이플을 어깨에 걸친 자세라 머리가 프레임 위끝에
	# 아슬아슬하게 붙는다. 여백을 조금 더 준다.
	24: {"head": 0.06},
	28: {"head": 0.06},
}


def portrait(path):
	im = Image.open(path).convert("RGBA")
	alpha = np.array(im)[:, :, 3]
	solid = alpha > 8
	ys, xs = np.where(solid)
	if len(ys) == 0:
		return None
	body_h = ys.max() - ys.min() + 1

	eroded = np.array(
		Image.fromarray((solid.astype(np.uint8) * 255)).filter(ImageFilter.MinFilter(ERODE))
	) > 0
	if not eroded.any():
		eroded = solid

	mid = int(re.match(r"(\d+)", os.path.basename(path)).group(1))
	ov = OVERRIDES.get(mid, {})
	if "box" in ov:
		bl, bt, bs = ov["box"]
		return im.crop((bl, bt, bl + bs, bt + bs)).resize((OUT_PX, OUT_PX), Image.LANCZOS)

	side = int((SIDE_FRAC + ov.get("side", 0.0)) * body_h)
	head = np.where(eroded)[0].min()
	top = int(head - (HEADROOM + ov.get("head", 0.0)) * side)

	# 가로 중심 — 자를 띠 안의 침식 덩어리 무게중심(중앙값). 평균이 아니라
	# 중앙값인 것은 한쪽으로 뻗은 팔 하나가 평균을 통째로 끌고 가기 때문이다.
	band = eroded[max(top, 0):top + side, :]
	col = band.sum(axis=0).astype(np.float64)
	if col.sum() == 0:
		col = eroded.sum(axis=0).astype(np.float64)
	cum = np.cumsum(col)
	cx = int(np.searchsorted(cum, cum[-1] * 0.5))

	left = cx - side // 2 + int(ov.get("dx", 0.0) * side)
	top += int(ov.get("dy", 0.0) * side)
	return im.crop((left, top, left + side, top + side)).resize((OUT_PX, OUT_PX), Image.LANCZOS)


def main():
	os.makedirs(OUT_DIR, exist_ok=True)
	paths = sorted(
		glob.glob(os.path.join(HERE, "*_full.png")),
		key=lambda p: int(re.match(r"(\d+)", os.path.basename(p)).group(1)),
	)
	for p in paths:
		mid = int(re.match(r"(\d+)", os.path.basename(p)).group(1))
		out = portrait(p)
		if out is None:
			print("skip (empty alpha):", p)
			continue
		dst = os.path.join(OUT_DIR, "%d_portrait.png" % mid)
		out.save(dst)
		print("wrote", dst)


if __name__ == "__main__":
	main()
