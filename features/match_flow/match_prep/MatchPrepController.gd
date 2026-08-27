extends Node

# MatchFlow PREP step. Shown before BAN_PICK so the player can review their
# own roster's stats and the opposing team's stats before committing to the
# match. Pressing "경기 시작" emits phase_finished.

signal phase_finished(result: Dictionary)

@onready var _mf: MatchFlow = get_parent() as MatchFlow

const ROLE_NAMES: Array = ["TANK", "FIGHTER", "ASSASSIN", "SUPPORT", "SNIPER"]
const ROLE_COLORS: Array = [
	Color(0.30, 0.55, 1.00),
	Color(1.00, 0.55, 0.20),
	Color(0.75, 0.40, 1.00),
	Color(0.30, 0.85, 0.45),
	Color(1.00, 0.35, 0.35),
]
const STAT_KEYS: Array   = ["laning", "mechanics", "gamesense", "teamfight", "mental"]
const STAT_LABELS: Array = ["라", "메", "겜", "한", "멘"]

var _panel: Panel


# Called by MatchFlow with the resolved player + enemy rosters and the
# enemy team display name.
func enter(player_roster: Array, enemy_roster: Array, player_team_name: String, enemy_team_name: String) -> void:
	_build_ui(player_roster, enemy_roster, player_team_name, enemy_team_name)


func _build_ui(player_roster: Array, enemy_roster: Array, player_team_name: String, enemy_team_name: String) -> void:
	_panel = Panel.new()
	_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.04, 0.06, 0.12, 1.0)
	_panel.add_theme_stylebox_override("panel", bg)
	_mf.canvas.add_child(_panel)
	# 화면 전체를 안전 영역 위끝까지 내린다 — 노치 / 다이나믹 아일랜드 밑에
	# 제목이 깔리지 않게. 제목만 따로 내리면 본문과 겹친다.
	ScreenMetrics.indent_to_safe_top(_panel)
	# 판을 내리면 위쪽 띠가 비므로 같은 색으로 메운다 — 노치 자리는
	# 비워 둘 곳이 아니라 쓰지 않을 곳이다.
	ScreenMetrics.backfill_top(_panel, Color(0.04, 0.06, 0.12, 1.0))

	UiHelpers.mk_label(_panel, "경기 준비", 48, Color(1.0, 0.85, 0.20),
			Vector2(0, 30), Vector2(1080, 60), HORIZONTAL_ALIGNMENT_CENTER)
	UiHelpers.mk_label(_panel, "%s  vs  %s" % [player_team_name, enemy_team_name],
			28, Color(0.85, 0.92, 1.0),
			Vector2(0, 100), Vector2(1080, 36), HORIZONTAL_ALIGNMENT_CENTER)

	# Two rosters stacked vertically. Player on top, enemy below.
	_build_team_block(_panel, player_roster, "내 팀", Color(0.55, 0.85, 1.0), 160.0)
	_build_team_block(_panel, enemy_roster,  "상대 팀", Color(1.00, 0.55, 0.55), 920.0)

	var btn := Button.new()
	btn.text = "경기 시작"
	btn.size     = Vector2(480, 110)
	# 하단 안전선에 매단다 — 이 자리는 아이폰 홈 인디케이터 / 안드로이드
	# 제스처 바가 터치를 가져가는 구간과 맞닿아 있다.
	btn.position = Vector2((ScreenMetrics.vp_w() - btn.size.x) * 0.5,
			ScreenMetrics.safe_h() - 70.0 - btn.size.y)
	btn.add_theme_font_size_override("font_size", 36)
	btn.pressed.connect(_on_start_pressed)
	_panel.add_child(btn)


func _build_team_block(parent: Node, roster: Array, header: String, header_color: Color, y0: float) -> void:
	UiHelpers.mk_label(parent, header, 26, header_color,
			Vector2(40, y0), Vector2(420, 32), HORIZONTAL_ALIGNMENT_LEFT)

	var x0: float = 30.0
	var row_h: float = 130.0
	var row_gap: float = 8.0
	var width: float = 1020.0

	# Sort by role 0..4 so the rendering order is stable.
	var by_role: Array = [null, null, null, null, null]
	for raw in roster:
		var p := raw as PlayerData
		if p != null and p.role >= 0 and p.role < 5:
			by_role[int(p.role)] = p

	# 줄 순서는 **역할 열거값 순서가 아니라 화면 순서**다(탑 · 정글 · 미드 ·
	# 원딜 · 서폿). `by_role` 은 역할로 색인하므로 자리(seat)를 역할로 한 번
	# 바꿔 읽는다 — `GameEnums.ROLE_DISPLAY_ORDER` 가 그 표다.
	for seat in 5:
		var r: int = int(GameEnums.ROLE_DISPLAY_ORDER[seat])
		var y: float = y0 + 44.0 + seat * (row_h + row_gap)
		var role_col: Color = ROLE_COLORS[r]
		var p: PlayerData = by_role[r]

		var row := Panel.new()
		var sty := StyleBoxFlat.new()
		sty.bg_color = Color(0.10, 0.12, 0.18, 1.0)
		sty.border_color = role_col
		sty.border_width_left = 2; sty.border_width_right = 2
		sty.border_width_top  = 2; sty.border_width_bottom = 2
		sty.corner_radius_top_left = 6; sty.corner_radius_top_right = 6
		sty.corner_radius_bottom_left = 6; sty.corner_radius_bottom_right = 6
		row.add_theme_stylebox_override("panel", sty)
		row.position = Vector2(x0, y)
		row.size     = Vector2(width, row_h)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		parent.add_child(row)

		var face_rect := TextureRect.new()
		face_rect.position     = Vector2(12, 12)
		face_rect.size         = Vector2(106, 106)
		face_rect.expand_mode  = TextureRect.EXPAND_IGNORE_SIZE
		face_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		face_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if p != null:
			face_rect.texture = PilotImages.face_for(p.id)
		row.add_child(face_rect)

		UiHelpers.mk_label(row, ROLE_NAMES[r], 18, role_col,
				Vector2(132, 12), Vector2(140, 22), HORIZONTAL_ALIGNMENT_LEFT)
		var name_text: String = "—"
		if p != null:
			name_text = p.name
		UiHelpers.mk_label(row, name_text, 24, Color(1, 1, 1),
				Vector2(132, 38), Vector2(360, 30), HORIZONTAL_ALIGNMENT_LEFT)
		var total: int = 0
		if p != null:
			total = p.laning + p.mechanics + p.gamesense + p.teamfight + p.mental
		UiHelpers.mk_label(row, "TOTAL %d" % total, 22, Color(1.0, 0.85, 0.40),
				Vector2(132, 76), Vector2(200, 30), HORIZONTAL_ALIGNMENT_LEFT)

		# Stat strip: 5 stats each "라 25" style
		var stat_x0: float = 480.0
		var stat_w: float = (width - stat_x0 - 20) / 5.0
		for s in STAT_KEYS.size():
			var sx: float = stat_x0 + s * stat_w
			var key: String = STAT_KEYS[s]
			var val: int = 0
			if p != null:
				val = int(p.get(key))
			UiHelpers.mk_label(row, STAT_LABELS[s], 16, Color(0.65, 0.75, 0.90),
					Vector2(sx, 14), Vector2(stat_w, 22),
					HORIZONTAL_ALIGNMENT_CENTER)
			UiHelpers.mk_label(row, "%d" % val, 30, Color(1, 1, 1),
					Vector2(sx, 40), Vector2(stat_w, 38),
					HORIZONTAL_ALIGNMENT_CENTER)


func _on_start_pressed() -> void:
	if _panel != null:
		_panel.queue_free()
		_panel = null
	phase_finished.emit({})
