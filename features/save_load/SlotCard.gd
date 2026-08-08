class_name SlotCard
extends Control

# One save-slot card on the title screen. Builds its own UI procedurally;
# parent (TitleScreen) wires the per-slot callbacks and feeds meta data.
#
# Empty slot:    "새 게임" button only.
# Filled slot:   "이어하기" + "삭제" buttons (delete double-taps to confirm).

const PHASE_NAMES: Dictionary = {
	0: "프리시즌",
	1: "프리시즌 국제대회",
	2: "미드시즌",
	3: "미드시즌 국제대회",
	4: "정규시즌",
	5: "정규시즌 국제대회",
}
const WEEKDAY_NAMES: Array = ["월", "화", "수", "목", "금", "토", "일"]

var slot_index: int = 0
var on_new_game: Callable = Callable()
var on_continue: Callable = Callable()
var on_delete: Callable = Callable()

var _meta: Dictionary = {}
var _delete_armed: bool = false

var _bg: ColorRect
var _title_lbl: Label
var _saved_lbl: Label
var _phase_lbl: Label
var _team_lbl: Label
var _record_lbl: Label
var _new_btn: Button
var _continue_btn: Button
var _delete_btn: Button
var _built: bool = false


func _ready() -> void:
	if not _built:
		_build()
		_built = true
	_refresh()


func set_meta_data(meta: Dictionary) -> void:
	_meta = meta
	_delete_armed = false
	if _built:
		_refresh()


# ── Build ────────────────────────────────────────────────────────────────────
func _build() -> void:
	_bg = ColorRect.new()
	_bg.color = Color(0.10, 0.12, 0.20, 1.0)
	_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_bg)

	_title_lbl = UiHelpers.mk_label(self, "", 32, Color(1.0, 0.85, 0.20),
			Vector2(28, 18), Vector2(400, 40))
	_saved_lbl = UiHelpers.mk_label(self, "", 18, Color(0.65, 0.70, 0.80),
			Vector2(0, 26), Vector2(size.x - 28.0, 26),
			HORIZONTAL_ALIGNMENT_RIGHT)

	_phase_lbl = UiHelpers.mk_label(self, "", 24, Color(0.85, 0.92, 1.0),
			Vector2(28, 80), Vector2(820, 32))
	_team_lbl = UiHelpers.mk_label(self, "", 22, Color(0.95, 0.95, 1.0),
			Vector2(28, 122), Vector2(820, 30))
	_record_lbl = UiHelpers.mk_label(self, "", 22, Color(0.85, 0.85, 0.92),
			Vector2(28, 162), Vector2(820, 30))

	_new_btn = _make_btn("새 게임")
	_new_btn.position = Vector2(28, 240)
	_new_btn.size = Vector2(size.x - 56.0, 100)
	_new_btn.pressed.connect(_on_new)
	add_child(_new_btn)

	_continue_btn = _make_btn("이어하기")
	_continue_btn.position = Vector2(28, 240)
	_continue_btn.size = Vector2((size.x - 80.0) * 0.6, 100)
	_continue_btn.pressed.connect(_on_continue)
	add_child(_continue_btn)

	_delete_btn = _make_btn("삭제")
	_delete_btn.position = Vector2(28 + (size.x - 80.0) * 0.6 + 24, 240)
	_delete_btn.size = Vector2((size.x - 80.0) * 0.4, 100)
	_delete_btn.pressed.connect(_on_delete)
	add_child(_delete_btn)


func _make_btn(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", 28)
	return b


# ── Refresh ──────────────────────────────────────────────────────────────────
func _refresh() -> void:
	_title_lbl.text = "슬롯 %d" % (slot_index + 1)
	if _meta.is_empty():
		_phase_lbl.text = "비어 있음"
		_team_lbl.text = ""
		_record_lbl.text = ""
		_saved_lbl.text = ""
		_new_btn.visible = true
		_continue_btn.visible = false
		_delete_btn.visible = false
		return

	_phase_lbl.text = "%s · %d년 %d월 %d일 (%s)" % [
		_phase_name(int(_meta.get("phase", 0))),
		int(_meta.get("year", 1)),
		int(_meta.get("month", 12)),
		int(_meta.get("day", 1)),
		_weekday_name(int(_meta.get("weekday", 0))),
	]
	_team_lbl.text = "%s · 우승 트로피 %d개" % [
		String(_meta.get("team_name", "—")),
		int(_meta.get("trophies", 0)),
	]
	var rank: int = int(_meta.get("rank", 0))
	if rank > 0:
		_record_lbl.text = "현재 리그 %d위 (%d승 %d패)" % [
			rank, int(_meta.get("wins", 0)), int(_meta.get("losses", 0)),
		]
	else:
		_record_lbl.text = "리그 미시작"
	if bool(_meta.get("match_in_progress", false)):
		_record_lbl.text += "  ·  경기 진행 중"
		_record_lbl.add_theme_color_override("font_color", Color(1.0, 0.85, 0.40))
	else:
		_record_lbl.add_theme_color_override("font_color", Color(0.85, 0.85, 0.92))
	_saved_lbl.text = "마지막 세이브: " + String(_meta.get("saved_at", ""))
	_new_btn.visible = false
	_continue_btn.visible = true
	_delete_btn.visible = true
	_delete_btn.text = "삭제 다시 누르기" if _delete_armed else "삭제"


func _phase_name(phase: int) -> String:
	return String(PHASE_NAMES.get(phase, "—"))


func _weekday_name(wd: int) -> String:
	if wd >= 0 and wd < WEEKDAY_NAMES.size():
		return String(WEEKDAY_NAMES[wd])
	return "?"


# ── Button handlers ──────────────────────────────────────────────────────────
func _on_new() -> void:
	if on_new_game.is_valid():
		on_new_game.call(slot_index)


func _on_continue() -> void:
	if on_continue.is_valid():
		on_continue.call(slot_index)


func _on_delete() -> void:
	if not _delete_armed:
		_delete_armed = true
		_delete_btn.text = "삭제 다시 누르기"
		return
	if on_delete.is_valid():
		on_delete.call(slot_index)
