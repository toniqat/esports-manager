class_name PilotImages
extends RefCounted

# Pilot face / circle texture lookup. The 40-pilot pool stores ids 0..39, while
# the on-disk image filenames are 1..40 (1_rect.png, 1_circle.png, …). INTL
# pilots (ids ≥ 100) and any other out-of-range id return null so callers can
# fall back to a placeholder.
#
# `prime_into(parent)`는 모든 circle/face 텍스처를 화면 밖 Sprite2D 자식으로
# 한 번 add_child한다. `load()`로 받은 CompressedTexture2D는 SceneTree에 붙은
# CanvasItem에 할당되기 전까지 GPU에 업로드되지 않아 `draw_texture_rect`에서
# fallback 흰 사각형으로 그려지는 현상이 있어, 사용 직전 prime이 필요하다.

const POOL_SIZE: int = 40
const FACE_DIR: String   = "res://resources/images/pilot/faces/"
const CIRCLE_DIR: String = "res://resources/images/pilot/circle/"


static func has_image(pilot_id: int) -> bool:
	return pilot_id >= 0 and pilot_id < POOL_SIZE


static func face_for(pilot_id: int) -> Texture2D:
	if not has_image(pilot_id):
		return null
	return load(FACE_DIR + "%d_rect.png" % (pilot_id + 1)) as Texture2D


static func circle_for(pilot_id: int) -> Texture2D:
	if not has_image(pilot_id):
		return null
	return load(CIRCLE_DIR + "%d_circle.png" % (pilot_id + 1)) as Texture2D


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
