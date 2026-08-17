"""메크 전신 아트(N_full.png ×30)를 처음부터 다시 만든다.

    python build_mech_art.py          # 내려받기 + 가공 (raw/ 캐시 재사용)
    python build_mech_art.py --sheet  # + 확인용 대조 시트 _sheet.png

출처는 Gundam Evolution(반다이남코, 2022-09 ~ 2023-11 서비스 종료)의 기체 렌더
24종이고, Gundam Wiki 문서의 "Mobile Suits" 갤러리에서 받는다. 원본이 이미
**배경 없는 투명 PNG** 라 배경 제거 단계는 없다. 개인 프로젝트용 임시 에셋이며
배포용이 아니다(파일럿 초상화가 젠레스 존 제로 아트인 것과 같은 성격).

크기 정규화가 파일럿 아트와 다른 점이 이 스크립트의 요점이다. 파일럿은 알파
크롭 후 **높이 1024** 로 맞추고 폭은 비율대로 두지만(572~756), 기체 렌더는
검·날개·라이플이 옆으로 뻗어 바운딩 박스 비율이 0.62~1.51 로 흩어진다. 그래서

  1) 크기는 바운딩 박스가 아니라 **불투명 픽셀 면적의 제곱근**으로 맞춘다 —
     얇은 칼끝은 면적에 거의 기여하지 않으므로 본체 겉보기 크기가 고르게 맞는다.
     높이로 맞추면 넓은 포즈일수록 본체가 쪼그라든다.
  2) 캔버스는 **1024×1024 고정**이다(가로 중앙 · 세로 바닥 정렬). 폭을 제각각
     두면 `PilotDetailPanel` 이 높이(ART_H)로 정규화할 때 비율 1.5 짜리 기체가
     화면 폭의 두 배로 벌어진다.

이 규격에서 캔버스 밖으로 잘리는 것은 Exia / Mahiroo / Marasai 세 장의 무기 끝
44~64px 뿐이다(대칭으로 잘린다).

id 배치는 `mechs.csv` 의 **스탯 아키타입**을 따른다 — `name` 열(Bulwark-A1 등)은
자체 명명이라 기체와 무관하고, 맞춰야 할 것은 hp/atk/presence 구간이다.
24종으로 30칸을 채우므로 6칸이 중복이며, 중복은 언제나 같은 아키타입 안에서
원본과 떨어뜨려 둔다(밴픽 화면에 같은 그림이 나란히 서지 않게).

필요: Pillow, curl.
"""

import json
import math
import os
import re
import statistics
import subprocess
import sys
import tempfile
import urllib.parse

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
# 원본 캐시와 대조 시트는 **프로젝트 밖**에 둔다 — `res://` 아래에 두면 Godot 이
# 그 24장까지 텍스처로 임포트해 버린다(결과물은 30장이어야 한다).
WORK = os.path.join(tempfile.gettempdir(), "gunevo_mech_art")
RAW = os.path.join(WORK, "raw")
API = "https://gundam.fandom.com/api.php"
UA = "Mozilla/5.0"

CANVAS_W = 1024
CANVAS_H = 1024
# 드롭섀도(옅은 알파)를 본체 면적으로 세지 않기 위한 문턱.
ALPHA_SOLID = 40

# mech id -> Gundam Wiki 파일명. 주석은 실제 기체 이름.
MAPPING = {
    # --- 탱커 (hp 195-240 / atk 6-10, presence 4) ---
    0: "GE Sazabi.png",                       # MSN-04 Sazabi
    1: "GE DOM Trooper.png",                  # ZGMF-XX09T DOM Trooper
    2: "GE Guntank.png",                      # RX-75 Guntank (최고 HP 슬롯)
    3: "GE Pale Rider.png",                   # RX-80PR Pale Rider
    4: "GE Mahiroo.png",                      # G-838 Mahiroo
    5: "GE Dozle Zaku.png",                   # MS-06 Zaku II [Melee Loadout]
    # --- 격투가 (hp 135-170 / atk 13-18, presence 4) ---
    6: "GE Gundam.png",                       # RX-78-2 Gundam
    7: "Gundam Evolution Kaempfer.png",       # MS-18E Kaempfer
    8: "GE GM.png",                           # RGM-79 GM
    9: "GE Marasai Unicorn.png",              # RMS-108 Marasai (UC)
    10: "GE Barbatos.png",                    # ASW-G-08 Gundam Barbatos
    11: "Gundam Evolution Kaempfer.png",      # (중복) Kaempfer
    # --- 암살자 (hp 80-110 / atk 22-30, presence 4) ---
    12: "GE Exia.png",                        # GN-001 Gundam Exia
    13: "GE Susanowo.png",                    # GNX-Y901TW Susanowo
    14: "Zeta Gundam Gundam Evolution.png",   # MSZ-006 Zeta Gundam
    15: "GE Unicorn.png",                     # RX-0 Unicorn Gundam
    16: "GE Asshimar.png",                    # NRX-044 Asshimar
    17: "GE Exia.png",                        # (중복) Exia
    # --- 서포터 (atk 8-11, presence 2) ---
    18: "GE Methuss.png",                     # MSA-005 Methuss (힐러)
    19: "GE ∀ Gundam.png",               # WD-M01 ∀ Gundam
    20: "Hyperion Gundam GunEvo.png",         # CAT1-X1/3 Hyperion Gundam (실드)
    21: "Nu Gundam GunEvo.png",               # RX-93 ν Gundam
    22: "GE Methuss.png",                     # (중복) Methuss
    23: "Hyperion Gundam GunEvo.png",         # (중복) Hyperion
    # --- 스나이퍼 (atk 19-25, presence 2) ---
    24: "GE GM Sniper II.png",                # RGM-79SP GM Sniper II
    25: "GE Dynames.png",                     # GN-002 Gundam Dynames
    26: "Gundam Evolution Heavyarms EW.png",  # XXXG-01H2 Heavyarms Custom EW
    27: "GE Zaku II.png",                     # MS-06 Zaku II [Shooting Equipment]
    28: "GE GM Sniper II.png",                # (중복) GM Sniper II
    29: "GE Dynames.png",                     # (중복) Dynames
}


def curl(url: str, out_path: str | None = None) -> bytes:
    cmd = ["curl", "-s", "-m", "90", "-L", "-A", UA]
    if out_path:
        cmd += ["-o", out_path]
    cmd.append(url)
    res = subprocess.run(cmd, capture_output=True, check=True)
    return res.stdout


def download_raw(names: list[str]) -> None:
    """빠진 원본만 받는다. `raw/` 는 캐시라 지워도 무방하다."""
    os.makedirs(RAW, exist_ok=True)
    todo = [n for n in names if not _cached(os.path.join(RAW, n))]
    if not todo:
        return

    # imageinfo 로 원본 URL 을 한 번에 받아 온다.
    titles = "|".join("File:" + n for n in todo)
    url = (
        f"{API}?action=query&prop=imageinfo&iiprop=url&format=json"
        f"&titles={urllib.parse.quote(titles)}"
    )
    pages = json.loads(curl(url).decode("utf-8"))["query"]["pages"]
    urls = {
        p["title"][len("File:"):]: p["imageinfo"][0]["url"]
        for p in pages.values()
        if "imageinfo" in p
    }

    for name in todo:
        if name not in urls:
            raise SystemExit(f"위키에서 찾지 못함: {name}")
        # /revision/latest?cb=... 를 떼면 축소본이 아닌 원본이 온다.
        src = re.sub(r"/revision/latest.*$", "", urls[name])
        dest = os.path.join(RAW, name)
        curl(src, dest)
        if not _cached(dest):
            raise SystemExit(f"내려받기 실패: {name}")
        print(f"  받음  {name}")


def _cached(path: str) -> bool:
    return os.path.exists(path) and os.path.getsize(path) > 1024


def solid_area(im: Image.Image) -> int:
    a = im.getchannel("A").point(lambda v: 255 if v > ALPHA_SOLID else 0)
    return sum(a.histogram()[255:])


def build() -> None:
    names = sorted(set(MAPPING.values()))
    download_raw(names)

    cropped = {}
    for n in names:
        im = Image.open(os.path.join(RAW, n)).convert("RGBA")
        cropped[n] = im.crop(im.getbbox())

    # (1) 겉보기 크기 기준 = 불투명 면적 제곱근의 중앙값.
    roots = {n: math.sqrt(solid_area(im)) for n, im in cropped.items()}
    target = statistics.median(roots.values())
    # (2) 그 기준으로 키운 뒤 가장 높은 기체가 캔버스 세로에 딱 맞도록 전역 배율.
    tallest = max(im.height * (target / roots[n]) for n, im in cropped.items())
    global_k = CANVAS_H / tallest

    for mech_id in sorted(MAPPING):
        name = MAPPING[mech_id]
        src = cropped[name]
        k = (target / roots[name]) * global_k
        w, h = max(1, round(src.width * k)), max(1, round(src.height * k))
        scaled = src.resize((w, h), Image.LANCZOS)

        canvas = Image.new("RGBA", (CANVAS_W, CANVAS_H), (0, 0, 0, 0))
        ox = (CANVAS_W - w) // 2       # 가로 중앙 (음수면 양쪽 대칭으로 잘린다)
        oy = CANVAS_H - h              # 세로 바닥 정렬 — 파일럿 아트와 같은 바닥선
        if ox >= 0:
            canvas.paste(scaled, (ox, oy), scaled)
            clipped = 0
        else:
            part = scaled.crop((-ox, 0, -ox + CANVAS_W, h))
            canvas.paste(part, (0, oy), part)
            clipped = -ox

        canvas.save(os.path.join(HERE, "%d_full.png" % mech_id), optimize=True)
        note = f"  잘림 {clipped}px/측" if clipped else ""
        print("%2d  %-38s %4dx%4d%s" % (mech_id, name, w, h, note))

    print("기준 sqrt(면적)=%.0f  전역 배율=%.3f" % (target, global_k))


def sheet() -> None:
    """30칸 대조 시트. 배치가 아키타입과 맞는지 눈으로 확인할 때만 쓴다."""
    from PIL import ImageDraw

    cell, cols = 170, 6
    rows = (len(MAPPING) + cols - 1) // cols
    out = Image.new("RGB", (cols * cell, rows * cell), (235, 235, 238))
    draw = ImageDraw.Draw(out)
    for i in sorted(MAPPING):
        im = Image.open(os.path.join(HERE, "%d_full.png" % i)).convert("RGBA")
        tile = Image.new("RGBA", (cell, cell), (255, 255, 255, 255))
        tile.alpha_composite(im.resize((cell, cell), Image.LANCZOS))
        x, y = (i % cols) * cell, (i // cols) * cell
        out.paste(tile.convert("RGB"), (x, y))
        draw.rectangle([x, y, x + cell - 1, y + cell - 1], outline=(150, 150, 160))
        draw.text((x + 5, y + 4), str(i), fill=(200, 30, 30))
    os.makedirs(WORK, exist_ok=True)
    path = os.path.join(WORK, "sheet.png")
    out.save(path)
    print("시트:", path)


if __name__ == "__main__":
    build()
    if "--sheet" in sys.argv:
        sheet()
