class_name PilotImages
extends RefCounted

# Pilot 초상화 텍스처 조회. 40인 풀은 id 0..39 를 쓰지만 디스크의 파일명은
# 1..40 이다 (1_rect.png, 1_circle.png, 1_eye.png, 1_full.png). INTL 파일럿
# (id ≥ 100) 과 범위 밖 id 는 null 을 돌려주므로 호출자가 플레이스홀더로
# 폴백하면 된다.
#
# 네 가지 컷:
#   faces/N_rect.png   — 정사각 얼굴 크롭 (256²)
#   circle/N_circle.png — 원형 마스크 (256²) — 전장 마커 · 교전 무대
#   eye/N_eye.png      — **양 눈이 보이는 가로로 긴 밴드** (480×200) — 파일럿
#                        스트립. `make_eye_crops.py` 가 full 아트에서 자동 생성한다
#                        (얼굴 위치는 faces 크롭을 full 안에서 템플릿 매칭해 찾고,
#                        눈은 그 사각형 높이의 0.38 지점). 다시 만들 때는 그
#                        스크립트를 돌릴 것 — 수동으로 자르면 파일럿마다 얼굴
#                        배율이 어긋나 스트립이 들쭉날쭉해진다.
#   tall/N_tall.png    — **세로로 긴 전신 크롭** (210×700, 머리~허벅지) — 교전
#                        아레나 하단 스트립. `make_tall_crops.py` 가 full 아트에서
#                        자동 생성한다(얼굴 위치는 eye 크롭과 **같은** 템플릿 매칭).
#                        밴드 폭이 얼굴 높이 ×1.32 로 고정이라 **길이를 늘려도
#                        화면에서의 얼굴 크기는 그대로**다 — 몸이 더 보일 뿐.
#   full/N_full.png    — 전신 아트 (가변 폭 × 1024) — 파일럿 상세 패널
#
# `prime_into(parent)`는 모든 circle/face 텍스처를 화면 밖 Sprite2D 자식으로
# 한 번 add_child한다. `load()`로 받은 CompressedTexture2D는 SceneTree에 붙은
# CanvasItem에 할당되기 전까지 GPU에 업로드되지 않아 `draw_texture_rect`에서
# fallback 흰 사각형으로 그려지는 현상이 있어, 사용 직전 prime이 필요하다.
# **eye / full 은 prime 대상이 아니다** — 둘 다 `TextureRect` 노드에만 쓰이고,
# 노드에 할당하는 경로는 업로드가 보장된다. **tall 은 prime 대상이다** — 교전
# 아레나가 `draw_texture_rect` 로 그리므로, prime 하지 않으면 초상화 열 칸이
# 통째로 흰 사각형으로 나온다(실측 확인).

const POOL_SIZE: int = 40
const FACE_DIR: String   = "res://resources/images/pilot/faces/"
const CIRCLE_DIR: String = "res://resources/images/pilot/circle/"
const EYE_DIR: String    = "res://resources/images/pilot/eye/"
const TALL_DIR: String   = "res://resources/images/pilot/tall/"
const FULL_DIR: String   = "res://resources/images/pilot/full/"

# ─── 모브 파일럿 ─────────────────────────────────────────────────────────────
# 스킬을 받지 못한 15명은 **실루엣 컷**으로 나온다 — 같은 파일명이 `mob/` 아래에
# 한 벌 더 있고(`resources/images/pilot/mob/{faces,circle,eye,tall,full}/`),
# 아래 조회 함수가 id 를 보고 그쪽으로 갈아탄다. 이름표가 아니라 그림이
# "이 선수는 이름 없는 선수다"를 말하게 하려는 것이다.
#
# 실루엣 방식은 컷마다 다르다(`make_mob_silhouettes.py`). `full` / `tall` 은
# 알파가 곧 인물 윤곽이라 납작한 단색으로 칠하면 그림자 인간이 되지만,
# `circle` / `faces` / `eye` 는 원형 마스크·타이트 얼굴 크롭이라 같은 처리를
# 하면 **특징 없는 덩어리**가 된다 — 그쪽은 밝기를 어두운 띠로 눌러 얼굴
# 형태만 남긴다.
#
# 목록은 `GameManager` 가 players.csv 의 `is_mob` 을 읽어 `set_mob_ids()` 로
# 심는다. 비어 있으면(BattleSim 단독 실행 등) 전원이 평소 컷으로 나온다 —
# 폴백이 원본이라 심는 것을 잊어도 흰 사각형이 뜨지는 않는다.
const MOB_DIR: String = "res://resources/images/pilot/mob/"

static var _mob_ids: Dictionary = {}


## players.csv 의 `is_mob = 1` 인 파일럿 id 들. GameManager 가 한 번 심는다.
static func set_mob_ids(ids: Array) -> void:
	_mob_ids.clear()
	for raw in ids:
		_mob_ids[int(raw)] = true


static func is_mob(pilot_id: int) -> bool:
	return _mob_ids.has(pilot_id)


## `sub` 컷의 디렉터리. 모브면 같은 이름의 실루엣 폴더를 돌려준다.
static func _dir_for(pilot_id: int, sub: String, normal_dir: String) -> String:
	return (MOB_DIR + sub + "/") if is_mob(pilot_id) else normal_dir


static func has_image(pilot_id: int) -> bool:
	return pilot_id >= 0 and pilot_id < POOL_SIZE


static func face_for(pilot_id: int) -> Texture2D:
	if not has_image(pilot_id):
		return null
	return load(_dir_for(pilot_id, "faces", FACE_DIR) + "%d_rect.png" % (pilot_id + 1)) as Texture2D


static func circle_for(pilot_id: int) -> Texture2D:
	if not has_image(pilot_id):
		return null
	return load(_dir_for(pilot_id, "circle", CIRCLE_DIR) + "%d_circle.png" % (pilot_id + 1)) as Texture2D


## 눈높이 밴드 (480×200). 파일럿 스트립이 쓴다 — 세로로 잘라 쓰지 말 것.
static func eye_for(pilot_id: int) -> Texture2D:
	if not has_image(pilot_id):
		return null
	return load(_dir_for(pilot_id, "eye", EYE_DIR) + "%d_eye.png" % (pilot_id + 1)) as Texture2D


## 세로로 긴 전신 크롭 (210×700, 머리~허벅지). 교전 아레나 하단 스트립이 쓴다 —
## 열 명이 한 줄에 서면 한 칸이 90px 뿐이라, 그 폭에서 얼굴이 읽히려면 세로로
## 길어야 한다. 가로로 잘라 쓰지 말 것(그건 eye 밴드의 몫이다).
static func tall_for(pilot_id: int) -> Texture2D:
	if not has_image(pilot_id):
		return null
	return load(_dir_for(pilot_id, "tall", TALL_DIR) + "%d_tall.png" % (pilot_id + 1)) as Texture2D


## 전신 아트 (가변 폭 × 1024). 파일럿 상세 패널이 쓴다.
static func full_for(pilot_id: int) -> Texture2D:
	if not has_image(pilot_id):
		return null
	return load(_dir_for(pilot_id, "full", FULL_DIR) + "%d_full.png" % (pilot_id + 1)) as Texture2D


# 모든 PilotImages 텍스처를 parent의 자식 Sprite2D로 등록해 GPU 업로드를 트리거.
# Sprite2D는 화면 밖에 배치하고 visible 유지 (visible=false면 GPU 업로드가
# 보장되지 않음). 호출자는 BattleSim._ready() 같은 진입 시점에 한 번만 호출.
static func prime_into(parent: Node) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	for pid in range(POOL_SIZE):
		var ctex: Texture2D = circle_for(pid)
		if ctex != null:
			var csp := Sprite2D.new()
			csp.name = "_PrimeCircle_%d" % pid
			csp.texture = ctex
			csp.position = Vector2(-9999.0, -9999.0)
			parent.add_child(csp)
		var ftex: Texture2D = face_for(pid)
		if ftex != null:
			var fsp := Sprite2D.new()
			fsp.name = "_PrimeFace_%d" % pid
			fsp.texture = ftex
			fsp.position = Vector2(-9999.0, -9999.0)
			parent.add_child(fsp)
		var ttex: Texture2D = tall_for(pid)
		if ttex != null:
			var tsp := Sprite2D.new()
			tsp.name = "_PrimeTall_%d" % pid
			tsp.texture = ttex
			tsp.position = Vector2(-9999.0, -9999.0)
			parent.add_child(tsp)
