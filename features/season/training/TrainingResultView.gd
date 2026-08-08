class_name TrainingResultView
extends Control

# Post-week training-result dashboard. SeasonHub creates this view, populates
# `result_data` (the dict returned by TrainingScheduler.apply_week_training)
# and routes here. Player presses "다음 →" to continue into the match-prep
# step (if a match is scheduled) or directly to the standings (no match).

const ROLE_NAMES: Array = ["TANK", "FIGHTER", "ASSASSIN", "SUPPORT", "SNIPER"]
const ROLE_COLORS: Array = [
	Color(0.30, 0.55, 1.00),
	Color(1.00, 0.55, 0.20),
	Color(0.75, 0.40, 1.00),
	Color(0.30, 0.85, 0.45),
	Color(1.00, 0.35, 0.35),
]
const STAT_KEYS: Array   = ["laning", "mechanics", "gamesense", "teamfight", "mental"]
const STAT_LABELS: Array = ["라인전", "메카닉", "게임감각", "한타", "멘탈"]

@onready var _hub: SeasonHub = get_parent() as SeasonHub
@onready var _gm: Node = get_node("/root/GameManager")

# {pilot_id: {before:{stat:int}, after:{stat:int}, name:String, role:int}}.
# SeasonHub assigns this before routing to the screen; refresh() reads it.
var result_data: Dictionary = {}

var _row_widgets: Array = []      # 5 rows of {name_lbl, stat_cells}
var _next_btn: Button
var _next_label: String = "다음 →"
var _built: bool = false


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_PASS
	if not _built:
		_build()
		_built = true
	refresh()


func ensure_view() -> void:
	if not _built:
		_build()
		_built = true
	refresh()


# Set what the "다음 →" button shows. Defaults to "다음 →"; SeasonHub may
# override to "경기 준비 →" or "리그 순위 →" depending on what's next.
func set_next_label(lbl: String) -> void:
	_next_label = lbl
	if _next_btn != null:
		_next_btn.text = lbl


# ── Build ────────────────────────────────────────────────────────────────────
func _build() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.07, 0.08, 0.14, 1.0)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	UiHelpers.mk_label(self, "주간 훈련 결과", 40, Color(1.0, 0.85, 0.20),
			Vector2(0, 24), Vector2(1080, 50), HORIZONTAL_ALIGNMENT_CENTER)
	UiHelpers.mk_label(self, "이번 주 훈련을 통한 능력치 변화", 22, Color(0.85, 0.92, 1.0),
			Vector2(0, 84), Vector2(1080, 30), HORIZONTAL_ALIGNMENT_CENTER)

	_build_table()
	_build_button()


func _build_table() -> void:
	var x0: float = 30.0
	var y0: float = 156.0
	var row_h: float = 280.0
	var row_gap: float = 16.0
	var width: float = 1020.0

	for r in 5:
		var y: float = y0 + r * (row_h + row_gap)
		var role_col: Color = ROLE_COLORS[r]

		var panel := Panel.new()
		var sty := StyleBoxFlat.new()
		sty.bg_color = Color(0.10, 0.12, 0.18, 1.0)
		sty.border_color = role_col
		sty.border_width_left = 3; sty.border_width_right = 3
		sty.border_width_top  = 3; sty.border_width_bottom = 3
		sty.corner_radius_top_left = 8; sty.corner_radius_top_right = 8
		sty.corner_radius_bottom_left = 8; sty.corner_radius_bottom_right = 8
		panel.add_theme_stylebox_override("panel", sty)
		panel.position = Vector2(x0, y)
		panel.size     = Vector2(width, row_h)
		panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(panel)

		var face_rect := TextureRect.new()
		face_rect.position     = Vector2(16, 12)
		face_rect.size         = Vector2(40, 40)
		face_rect.expand_mode  = TextureRect.EXPAND_IGNORE_SIZE
		face_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		face_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		panel.add_child(face_rect)

		UiHelpers.mk_label(panel, ROLE_NAMES[r], 22, role_col,
				Vector2(64, 14), Vector2(140, 28), HORIZONTAL_ALIGNMENT_LEFT)
		var name_lbl := UiHelpers.mk_label(panel, "—", 28, Color(1, 1, 1),
				Vector2(210, 12), Vector2(600, 32), HORIZONTAL_ALIGNMENT_LEFT)

		var stats_y: float = 60.0
		var stat_w: float = (width - 40.0) / 5.0
		var stat_cells: Array = []
		for s in STAT_KEYS.size():
			var sx: float = 20 + s * stat_w
			UiHelpers.mk_label(panel, STAT_LABELS[s], 18, Color(0.65, 0.75, 0.90),
					Vector2(sx, stats_y), Vector2(stat_w, 22),
					HORIZONTAL_ALIGNMENT_CENTER)
			# Before / arrow / after on one row
			var line_y: float = stats_y + 28
			var before_lbl := UiHelpers.mk_label(panel, "", 28, Color(0.85, 0.85, 0.92),
					Vector2(sx, line_y), Vector2(stat_w * 0.45, 36),
					HORIZONTAL_ALIGNMENT_CENTER)
			UiHelpers.mk_label(panel, "→", 22, Color(0.70, 0.75, 0.85),
					Vector2(sx + stat_w * 0.45, line_y + 4), Vector2(stat_w * 0.10, 32),
					HORIZONTAL_ALIGNMENT_CENTER)
			var after_lbl := UiHelpers.mk_label(panel, "", 28, Color(1, 1, 1),
					Vector2(sx + stat_w * 0.55, line_y), Vector2(stat_w * 0.45, 36),
					HORIZONTAL_ALIGNMENT_CENTER)
			# Delta on the next line
			var delta_lbl := UiHelpers.mk_label(panel, "", 22, Color(0.55, 0.95, 0.55),
					Vector2(sx, line_y + 44), Vector2(stat_w, 28),
					HORIZONTAL_ALIGNMENT_CENTER)
			stat_cells.append({
				"before": before_lbl,
				"after":  after_lbl,
				"delta":  delta_lbl,
			})
		_row_widgets.append({"name": name_lbl, "stats": stat_cells, "face": face_rect})


func _build_button() -> void:
	_next_btn = Button.new()
	_next_btn.text = _next_label
	_next_btn.position = Vector2((1080.0 - 480.0) / 2.0, 1740.0)
	_next_btn.size     = Vector2(480, 110)
	_next_btn.add_theme_font_size_override("font_size", 36)
	_next_btn.pressed.connect(_on_next_pressed)
	add_child(_next_btn)


# ── Refresh ──────────────────────────────────────────────────────────────────
func refresh() -> void:
	if not _built:
		return
	if _next_btn != null:
		_next_btn.text = _next_label
	# Build a role-keyed lookup so empty roles render as "—".
	var by_role: Dictionary = {}
	for pid in result_data.keys():
		var entry: Dictionary = result_data[pid]
		by_role[int(entry["role"])] = entry

	for r in 5:
		var w: Dictionary = _row_widgets[r]
		if not by_role.has(r):
			w["name"].text = "—"
			(w["face"] as TextureRect).texture = null
			for s in STAT_KEYS.size():
				w["stats"][s]["before"].text = ""
				w["stats"][s]["after"].text  = ""
				w["stats"][s]["delta"].text  = ""
			continue
		var entry: Dictionary = by_role[r]
		w["name"].text = String(entry["name"])
		(w["face"] as TextureRect).texture = PilotImages.face_for(int(entry.get("pilot_id", -1)))
		var before: Dictionary = entry["before"]
		var after: Dictionary  = entry["after"]
		for s in STAT_KEYS.size():
			var key: String = STAT_KEYS[s]
			var b: int = int(before.get(key, 0))
			var a: int = int(after.get(key, 0))
			var diff: int = a - b
			w["stats"][s]["before"].text = "%d" % b
			w["stats"][s]["after"].text  = "%d" % a
			var delta_lbl: Label = w["stats"][s]["delta"]
			if diff > 0:
				delta_lbl.text = "+%d" % diff
				delta_lbl.add_theme_color_override("font_color", Color(0.55, 0.95, 0.55))
			elif diff < 0:
				delta_lbl.text = "%d" % diff
				delta_lbl.add_theme_color_override("font_color", Color(1.00, 0.55, 0.55))
			else:
				delta_lbl.text = "—"
				delta_lbl.add_theme_color_override("font_color", Color(0.55, 0.60, 0.70))


# ── Button handler ──────────────────────────────────────────────────────────
func _on_next_pressed() -> void:
	if _hub != null and _hub.has_method("on_training_result_continue"):
		_hub.on_training_result_continue()
