class_name SceneFade
extends RefCounted

# 암전 → 가짜 로딩 → 밝아짐. 한 장면이 **넘어갔다**는 것을 말하는 전환 연출.
#
# 덮개는 **SceneTree 의 root 에 붙인 `CanvasLayer`** 다 — 현재 씬의 자식이 아니라
# `change_scene_to_file` 이 씬을 통째로 갈아 끼워도 살아남는다. 그래서 같은 함수가
# 씬 안의 화면 전환(드래프트 → 허브)과 씬 사이의 전환(밴픽 → 전장) 둘 다를 덮는다.
#
# `on_covered` 는 **화면이 다 가려진 순간**에 한 번 돈다 — 바뀌는 순간이 보이지
# 않아야 한 장면이 넘어간 것으로 읽힌다. 로딩 막대는 실제 작업과 무관한 연출이다
# (다만 씬 전환이면 새 씬의 `_ready` 가 그 막대 뒤에서 실제로 돈다).

const FADE_OUT_SEC: float = 0.30
const LOAD_SEC: float = 0.50
const FADE_IN_SEC: float = 0.35
const BAR_W: float = 420.0
const LAYER: int = 100


static func play(tree: SceneTree, on_covered: Callable) -> void:
	var layer := CanvasLayer.new()
	layer.layer = LAYER
	tree.root.add_child(layer)

	var vp: Vector2 = ScreenMetrics.viewport_size()
	var cover := ColorRect.new()
	cover.color = Color(0, 0, 0, 1)
	cover.position = Vector2.ZERO
	cover.size = vp
	cover.mouse_filter = Control.MOUSE_FILTER_STOP   # 전환 중의 탭을 삼킨다
	cover.modulate.a = 0.0
	layer.add_child(cover)

	var load_lbl := UiHelpers.mk_label(cover, "LOADING", 28,
			Color(1, 1, 1, 0.80), Vector2(0, vp.y * 0.5 - 56.0),
			Vector2(vp.x, 36), HORIZONTAL_ALIGNMENT_CENTER)
	load_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var track := ColorRect.new()
	track.color = Color(1, 1, 1, 0.18)
	track.position = Vector2((vp.x - BAR_W) * 0.5, vp.y * 0.5)
	track.size = Vector2(BAR_W, 6)
	track.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cover.add_child(track)
	var fill := ColorRect.new()
	fill.color = OutgameTheme.ACCENT
	fill.size = Vector2(0, 6)
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	track.add_child(fill)

	# 트윈은 레이어가 쥔다 — 씬이 바뀌어도 레이어와 함께 살아남는다.
	var tw := layer.create_tween()
	tw.tween_property(cover, "modulate:a", 1.0, FADE_OUT_SEC)
	tw.tween_callback(on_covered)
	tw.tween_property(fill, "size:x", BAR_W, LOAD_SEC) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(cover, "modulate:a", 0.0, FADE_IN_SEC)
	tw.tween_callback(layer.queue_free)


## 덮개 뒤에서 씬을 갈아 끼운다.
static func change_scene(tree: SceneTree, path: String) -> void:
	play(tree, func() -> void: tree.change_scene_to_file(path))
