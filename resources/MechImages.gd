class_name MechImages
extends RefCounted

# 메크(기체) 일러스트 조회. `PilotImages` 와 같은 역할이고 **에셋 30장이 모두
# 들어와 있다**(Gundam Evolution 기체 렌더 24종 + 아키타입별 중복 6칸).
#
#   N_full.png   — 전신 기체 아트. 파일럿 전신 아트와 달리 하위 폴더 없이
#                  `mech/` 바로 아래에 평평하게 놓인다.
#
# `N` 은 `mechs.csv` 의 `id` 그대로다(파일럿과 달리 +1 하지 않는다 — 파일럿
# 쪽의 오프셋은 40장을 1..40 으로 받아 온 역사적 사정이고, 여기는 그 사정이
# 없으므로 반복하지 않는다).
#
# 규격은 **1024×1024 고정 캔버스**다(가로 중앙 · 세로 바닥 정렬). 파일럿 아트처럼
# 폭을 제각각 두지 않는 이유는 상세 패널이 높이로 정규화하기 때문 — 검·날개가
# 옆으로 뻗은 기체는 바운딩 박스 비율이 1.5 까지 가서 화면 폭의 두 배로 벌어진다.
# 출처와 크기 정규화 방식(면적 기준), id ↔ 기체 대응표는 `resources/README.md`.
#
# **`load()` 를 그냥 부르지 않는다.** 파일이 없으면 Godot 이 에러를 뱉으며
# null 을 돌려주므로 `ResourceLoader.exists()` 로 먼저 물어보고 없으면 조용히
# null 을 준다 — 호출자(`PilotDetailPanel`)는 그때 실루엣 플레이스홀더를 그린다.
# 지금은 30칸이 다 차 있어 돌지 않는 길이지만 `mechs.csv` 에 행을 더하면 되살아난다.

const FULL_DIR: String = "res://resources/images/mech/"


## 이 메크의 전신 아트. 없으면 null — 호출자가 플레이스홀더로 폴백한다.
static func full_for(mech_id: int) -> Texture2D:
	var path: String = FULL_DIR + "%d_full.png" % mech_id
	if not ResourceLoader.exists(path):
		return null
	return load(path) as Texture2D


## 아트가 실제로 있는가. 플레이스홀더를 그릴지 판정할 때 쓴다.
static func has_image(mech_id: int) -> bool:
	return ResourceLoader.exists(FULL_DIR + "%d_full.png" % mech_id)
