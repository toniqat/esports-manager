class_name TeamDraftView
extends Control

# 초기 팀 드래프트 화면 — **우마무스메식 인물 고르기**로 다시 세웠다.
#
#   상: 선택한 5인의 **상체 일러스트**가 가로로 나란히 (탑 · 정글 · 미드 · 원딜 · 서폿)
#       이름을 누르면 `DraftDetailPanel` 이 열린다
#   중: 전체 / 탑 / 정글 / 미드 / 원딜 / 서폿 필터 버튼 한 줄
#   하: 캐릭터 썸네일 격자 (세로 스크롤, 화면 아래 절반)
#   맨 아래: 좌 = 선택 5인의 파일럿 스킬 구성 / 우 = 큰 "드래프트 확정"
#
# 예전에는 5열(역할) × 5행(순위) 고정 격자에 `PilotCard` 200×175 칸이 스탯 막대
# 다섯 줄을 세우고 있었다. 그 배치의 문제는 둘이다 — (1) 얼굴이 48px 라 "누구를
# 뽑는가"가 이름표로만 읽혔고, (2) 25명이 한 화면에 다 들어가느라 칸을 키울
# 여지가 없었다. 지금은 **격자가 스크롤되므로 칸 크기가 인원 수에서 풀려났고**,
# 뽑은 사람은 위쪽에 큰 일러스트로 따로 선다.
#
# **다섯 칸은 역할 고정**이다(`TeamDraft.SLOT_ROLES`). `TeamDraft.validate_draft`
# 가 "역할당 정확히 1명"을 강제하므로 자유 순서로 두면 화면에서만 가능한 조합이
# 생겨 확정 버튼에서 처음 거절당한다 — 규칙은 고를 때 보여야 한다.

const ROLE_NAMES: Array = ["TANK", "FIGHTER", "ASSASSIN", "SUPPORT", "SNIPER"]
const ROLE_COLORS: Array = [
	Color(0.30, 0.55, 1.00),   # TANK     blue
	Color(1.00, 0.55, 0.20),   # FIGHTER  orange
	Color(0.75, 0.40, 1.00),   # ASSASSIN purple
	Color(0.30, 0.85, 0.45),   # SUPPORT  green
	Color(1.00, 0.35, 0.35),   # SNIPER   red
]

const BG_COLOR := Color(0.07, 0.08, 0.14, 1.0)

# ─── 상: 선택 5인 ────────────────────────────────────────────────────────────
const SLOT_COUNT: int = 5
const SLOT_W: float = 204.0
const SLOT_GAP: float = 12.0
const SLOT_X0: float = 6.0          # (1080 − 5×204 − 4×12) / 2
const SLOT_TAG_Y: float = 112.0
const SLOT_TAG_H: float = 28.0
const SLOT_ART_Y: float = 144.0
const SLOT_ART_H: float = 412.0
const SLOT_NAME_Y: float = 560.0
const SLOT_NAME_H: float = 54.0
const SLOT_SUB_Y: float = 616.0
const SLOT_SUB_H: float = 24.0

## 상체 크롭 — `tall/N_tall.png`(210×700, 머리~허벅지)의 **윗부분**을 잘라 쓴다.
## 어깨~얼굴만 필요한데 `full` 아트에서 직접 자르면 파일럿마다 인물 배율이
## 달라 다섯 칸의 얼굴 크기가 들쭉날쭉해진다 — `tall` 은 이미 얼굴 사각형을
## 템플릿 매칭으로 찾아 배율을 통일해 둔 컷이라, 그 위에서 자르면 다섯 얼굴이
## 같은 크기로 선다. 영역 비율은 칸 비율(204 : 412)과 같게 잡아 늘어남이 없다.
const BUST_REGION := Rect2(18.0, 0.0, 174.0, 351.0)

const SLOT_FRAME_BG := Color(0.10, 0.12, 0.18, 1.0)
const SLOT_FRAME_BG_EMPTY := Color(0.09, 0.10, 0.15, 1.0)
const SLOT_FRAME_BORDER_EMPTY := Color(0.24, 0.26, 0.34, 1.0)

# ─── 중: 필터 ────────────────────────────────────────────────────────────────
const FILTER_Y: float = 660.0
const FILTER_H: float = 64.0
const FILTER_X0: float = 24.0
const FILTER_TOTAL_W: float = 1032.0
const FILTER_GAP: float = 8.0
const FILTER_LABELS: Array = ["전체", "탑", "정글", "미드", "원딜", "서폿"]
const FILTER_BG_ON  := Color(0.20, 0.32, 0.55, 1.0)
const FILTER_BG_OFF := Color(0.11, 0.13, 0.19, 1.0)
const FILTER_BORDER_ON  := Color(1.00, 0.85, 0.20, 1.0)
const FILTER_BORDER_OFF := Color(0.28, 0.31, 0.40, 1.0)

# ─── 하: 썸네일 격자 ─────────────────────────────────────────────────────────
const GRID_Y: float = 740.0
const GRID_H: float = 950.0
const GRID_X0: float = 24.0
const GRID_W: float = 1032.0
const GRID_COLS: int = 5
const GRID_GAP: float = 8.0

# ─── 맨 아래: 스킬 구성 + 확정 ───────────────────────────────────────────────
const BAR_Y: float = 1702.0
const BAR_H: float = 198.0
const SKILL_PANEL_X: float = 24.0
const SKILL_PANEL_W: float = 640.0
const CONFIRM_X: float = 680.0
const CONFIRM_W: float = 376.0

@onready var _draft: TeamDraft = get_parent() as TeamDraft
@onready var _gm: Node = get_node("/root/GameManager")

var _picks: Array = [-1, -1, -1, -1, -1]   # 슬롯 인덱스 → pilot id (-1 = 빈 칸)
var _thumbs_by_id: Dictionary = {}         # pilot_id(int) → PilotThumb
var _entries: Array = []                   # Array[PlayerData], 화면 정렬 순서
var _filter_role: int = -1                 # -1 = 전체

var _slot_art: Array = []                  # 5 × TextureRect
var _slot_frame: Array = []                # 5 × Panel
var _slot_name_btn: Array = []             # 5 × Button
var _slot_sub_lbl: Array = []              # 5 × Label
var _filter_btns: Array = []               # 6 × Button
var _skill_rows: Array = []                # 5 × Label
var _grid_body: Control
var _count_lbl: Label
var _confirm_btn: Button
var _detail: DraftDetailPanel


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_PASS
	_build_ui()
	_reflow_grid()
	_refresh_slots()
	_refresh_skill_panel()
	_refresh_confirm_btn()


# ── Build ────────────────────────────────────────────────────────────────────
func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = BG_COLOR
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	UiHelpers.mk_label(self, "TEAM DRAFT", 42, Color(1.0, 0.85, 0.2),
			Vector2(0, 18), Vector2(1080, 50), HORIZONTAL_ALIGNMENT_CENTER)
	_count_lbl = UiHelpers.mk_label(self, "내 팀 (0/5)", 22,
			Color(0.9, 0.95, 1.0),
			Vector2(0, 74), Vector2(1080, 28), HORIZONTAL_ALIGNMENT_CENTER)

	_build_slot_row()
	_build_filter_row()
	_build_grid()
	_build_bottom_bar()

	_detail = DraftDetailPanel.new()
	add_child(_detail)


func _slot_x(i: int) -> float:
	return SLOT_X0 + float(i) * (SLOT_W + SLOT_GAP)


func _build_slot_row() -> void:
	for i in SLOT_COUNT:
		var role: int = int(TeamDraft.SLOT_ROLES[i])
		var col: Color = ROLE_COLORS[role]
		var x: float = _slot_x(i)

		UiHelpers.mk_label(self, String(TeamDraft.SLOT_NAMES[i]), 24, col,
				Vector2(x, SLOT_TAG_Y), Vector2(SLOT_W, SLOT_TAG_H),
				HORIZONTAL_ALIGNMENT_CENTER)

		var frame := Panel.new()
		frame.position = Vector2(x, SLOT_ART_Y)
		frame.size = Vector2(SLOT_W, SLOT_ART_H)
		frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
		frame.clip_contents = true
		add_child(frame)
		_slot_frame.append(frame)

		var art := TextureRect.new()
		art.position = Vector2.ZERO
		art.size = Vector2(SLOT_W, SLOT_ART_H)
		art.expand_mode  = TextureRect.EXPAND_IGNORE_SIZE
		art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		art.mouse_filter = Control.MOUSE_FILTER_IGNORE
		frame.add_child(art)
		_slot_art.append(art)

		var empty := UiHelpers.mk_label(frame, "선택 없음", 26,
				Color(0.42, 0.46, 0.58), Vector2(0, SLOT_ART_H * 0.5 - 20.0),
				Vector2(SLOT_W, 40), HORIZONTAL_ALIGNMENT_CENTER)
		empty.name = "EmptyMark"
		empty.mouse_filter = Control.MOUSE_FILTER_IGNORE

		# 이름 칸이 곧 상세 팝업 버튼이다 — 요구는 "이름을 누르면 상세정보"이고,
		# 일러스트 전체를 버튼으로 두면 슬롯을 비우려는 탭과 구분되지 않는다.
		var name_btn := Button.new()
		name_btn.text = "—"
		name_btn.focus_mode = Control.FOCUS_NONE
		name_btn.clip_text = true
		name_btn.add_theme_font_size_override("font_size", 26)
		name_btn.position = Vector2(x, SLOT_NAME_Y)
		name_btn.size = Vector2(SLOT_W, SLOT_NAME_H)
		name_btn.disabled = true
		name_btn.pressed.connect(_on_slot_name_pressed.bind(i))
		add_child(name_btn)
		_slot_name_btn.append(name_btn)

		var sub := UiHelpers.mk_label(self, "", 16, Color(0.70, 0.75, 0.85),
				Vector2(x, SLOT_SUB_Y), Vector2(SLOT_W, SLOT_SUB_H),
				HORIZONTAL_ALIGNMENT_CENTER)
		sub.clip_text = true
		_slot_sub_lbl.append(sub)


func _build_filter_row() -> void:
	var n: int = FILTER_LABELS.size()
	var w: float = (FILTER_TOTAL_W - FILTER_GAP * float(n - 1)) / float(n)
	for i in n:
		var btn := Button.new()
		btn.text = String(FILTER_LABELS[i])
		btn.focus_mode = Control.FOCUS_NONE
		btn.add_theme_font_size_override("font_size", 26)
		btn.position = Vector2(FILTER_X0 + float(i) * (w + FILTER_GAP), FILTER_Y)
		btn.size = Vector2(w, FILTER_H)
		# i == 0 이 "전체"(-1), 그 뒤는 `SLOT_ROLES` 와 같은 순서다 — 필터 버튼과
		# 위쪽 다섯 칸이 같은 표를 읽으므로 순서가 갈릴 수 없다.
		var role: int = -1 if i == 0 else int(TeamDraft.SLOT_ROLES[i - 1])
		btn.pressed.connect(_on_filter_pressed.bind(role))
		add_child(btn)
		_filter_btns.append(btn)
	_apply_filter_styles()


func _build_grid() -> void:
	# 격자 뒤판 — 필터를 좁히면 칸이 다섯 개만 남아 아래가 통째로 비는데,
	# 받침이 없으면 그 여백이 "화면이 끝났다"로 읽힌다. 스크롤 영역의 경계를
	# 색으로 못 박아 두면 빈 목록도 빈 목록으로 보인다.
	var back := Panel.new()
	back.position = Vector2(GRID_X0 - 8.0, GRID_Y - 8.0)
	back.size = Vector2(GRID_W + 16.0, GRID_H + 16.0)
	back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var back_sty := StyleBoxFlat.new()
	back_sty.bg_color = Color(0.05, 0.06, 0.10, 1.0)
	back_sty.border_color = Color(0.22, 0.25, 0.33, 1.0)
	back_sty.border_width_left = 2
	back_sty.border_width_right = 2
	back_sty.border_width_top = 2
	back_sty.border_width_bottom = 2
	back_sty.corner_radius_top_left     = 12
	back_sty.corner_radius_top_right    = 12
	back_sty.corner_radius_bottom_left  = 12
	back_sty.corner_radius_bottom_right = 12
	back.add_theme_stylebox_override("panel", back_sty)
	add_child(back)

	var scroll := ScrollContainer.new()
	scroll.position = Vector2(GRID_X0, GRID_Y)
	scroll.size = Vector2(GRID_W, GRID_H)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)

	# 스크롤 범위는 이 Control 의 `custom_minimum_size` 가 정한다 — 칸을
	# 좌표로 놓으므로 컨테이너가 아니라 빈 Control 이 몸통이다.
	_grid_body = Control.new()
	_grid_body.mouse_filter = Control.MOUSE_FILTER_PASS
	scroll.add_child(_grid_body)

	# 격자 순서는 **슬롯 순서(탑 → 정글 → 미드 → 원딜 → 서폿) 안에서 종합
	# 스탯 내림차순**이다. `TeamDraft.get_pool_grid()` 는 역할 열거값 순서로
	# 돌려주므로 여기서 슬롯 순서로 다시 묶는다 — 필터 버튼의 순서와 격자의
	# 순서가 어긋나면 "정글 다음이 미드"라는 읽기 기준이 깨진다.
	var by_role: Dictionary = {}
	for entry_raw in _draft.get_pool_grid():
		var entry: Dictionary = entry_raw
		var r: int = int(entry["role"])
		if not by_role.has(r):
			by_role[r] = []
		(by_role[r] as Array).append(entry["pilot"])
	for role_raw in TeamDraft.SLOT_ROLES:
		var role: int = int(role_raw)
		for p_raw in by_role.get(role, []):
			var p := p_raw as PlayerData
			_entries.append(p)
			var thumb := PilotThumb.new()
			_grid_body.add_child(thumb)
			thumb.setup(p, false)
			thumb.thumb_tapped.connect(_on_thumb_tapped)
			_thumbs_by_id[p.id] = thumb


func _build_bottom_bar() -> void:
	var panel := Panel.new()
	panel.position = Vector2(SKILL_PANEL_X, BAR_Y)
	panel.size = Vector2(SKILL_PANEL_W, BAR_H)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sty := StyleBoxFlat.new()
	sty.bg_color = Color(0.10, 0.12, 0.18, 1.0)
	sty.border_color = Color(0.28, 0.31, 0.40, 1.0)
	sty.border_width_left = 2
	sty.border_width_right = 2
	sty.border_width_top = 2
	sty.border_width_bottom = 2
	sty.corner_radius_top_left     = 10
	sty.corner_radius_top_right    = 10
	sty.corner_radius_bottom_left  = 10
	sty.corner_radius_bottom_right = 10
	panel.add_theme_stylebox_override("panel", sty)
	add_child(panel)

	UiHelpers.mk_label(panel, "파일럿 스킬 구성", 20, Color(0.58, 0.78, 1.0),
			Vector2(14, 6), Vector2(SKILL_PANEL_W - 28, 26))
	for i in SLOT_COUNT:
		var row := UiHelpers.mk_label(panel, "", 20, Color(0.86, 0.89, 0.95),
				Vector2(14, 34.0 + float(i) * 31.0),
				Vector2(SKILL_PANEL_W - 28, 30))
		row.clip_text = true
		_skill_rows.append(row)

	_confirm_btn = Button.new()
	_confirm_btn.text = "드래프트 확정"
	_confirm_btn.focus_mode = Control.FOCUS_NONE
	_confirm_btn.position = Vector2(CONFIRM_X, BAR_Y)
	_confirm_btn.size     = Vector2(CONFIRM_W, BAR_H)
	_confirm_btn.add_theme_font_size_override("font_size", 38)
	_confirm_btn.disabled = true
	_confirm_btn.pressed.connect(_on_confirm_pressed)
	add_child(_confirm_btn)


# ── Interaction ──────────────────────────────────────────────────────────────
func _on_filter_pressed(role: int) -> void:
	if _filter_role == role:
		return
	_filter_role = role
	_apply_filter_styles()
	_reflow_grid()


## 필터가 바뀌면 **보이는 칸만** 좌표를 다시 받는다. 숨긴 칸을 격자에 그대로
## 두고 `visible` 만 끄면 빈 구멍이 남아 5열 배치가 무너진다.
func _reflow_grid() -> void:
	var shown: int = 0
	var cell_w: float = PilotThumb.CELL_W
	var cell_h: float = PilotThumb.CELL_H
	for p_raw in _entries:
		var p := p_raw as PlayerData
		var thumb: PilotThumb = _thumbs_by_id[p.id]
		if _filter_role != -1 and int(p.role) != _filter_role:
			thumb.visible = false
			continue
		thumb.visible = true
		var col: int = shown % GRID_COLS
		@warning_ignore("integer_division")
		var row: int = shown / GRID_COLS
		thumb.position = Vector2(float(col) * (cell_w + GRID_GAP),
				float(row) * (cell_h + GRID_GAP))
		shown += 1
	var rows: int = int(ceil(float(shown) / float(GRID_COLS)))
	var body_h: float = float(rows) * cell_h + float(maxi(0, rows - 1)) * GRID_GAP
	_grid_body.custom_minimum_size = Vector2(GRID_W, body_h)
	_grid_body.size = Vector2(GRID_W, body_h)


func _on_thumb_tapped(pilot_id: int) -> void:
	if not _thumbs_by_id.has(pilot_id):
		return
	var thumb: PilotThumb = _thumbs_by_id[pilot_id]
	var slot: int = TeamDraft.slot_of_role(int(thumb.pilot.role))
	if slot < 0:
		return

	if int(_picks[slot]) == pilot_id:
		_picks[slot] = -1
		thumb.set_selected(false)
	else:
		var prev_id: int = int(_picks[slot])
		if prev_id != -1 and _thumbs_by_id.has(prev_id):
			(_thumbs_by_id[prev_id] as PilotThumb).set_selected(false)
		_picks[slot] = pilot_id
		thumb.set_selected(true)

	_refresh_slots()
	_refresh_skill_panel()
	_refresh_confirm_btn()


func _on_slot_name_pressed(slot: int) -> void:
	var p: PlayerData = _pilot_in_slot(slot)
	if p == null:
		return
	_detail.open(_draft, p)


# ── Refresh ──────────────────────────────────────────────────────────────────
func _pilot_in_slot(slot: int) -> PlayerData:
	var pid: int = int(_picks[slot])
	if pid == -1 or not _thumbs_by_id.has(pid):
		return null
	return (_thumbs_by_id[pid] as PilotThumb).pilot


func _refresh_slots() -> void:
	var count: int = 0
	for i in SLOT_COUNT:
		var p: PlayerData = _pilot_in_slot(i)
		var role: int = int(TeamDraft.SLOT_ROLES[i])
		var frame: Panel = _slot_frame[i]
		var art: TextureRect = _slot_art[i]
		var empty_mark: Label = frame.get_node("EmptyMark") as Label
		var sty := StyleBoxFlat.new()
		sty.corner_radius_top_left     = 10
		sty.corner_radius_top_right    = 10
		sty.corner_radius_bottom_left  = 10
		sty.corner_radius_bottom_right = 10
		sty.border_width_left = 3
		sty.border_width_right = 3
		sty.border_width_top = 3
		sty.border_width_bottom = 3

		if p == null:
			art.texture = null
			empty_mark.visible = true
			sty.bg_color = SLOT_FRAME_BG_EMPTY
			sty.border_color = SLOT_FRAME_BORDER_EMPTY
			_slot_name_btn[i].text = "—"
			_slot_name_btn[i].disabled = true
			_slot_sub_lbl[i].text = ""
		else:
			count += 1
			art.texture = _bust_texture(p.id)
			empty_mark.visible = false
			sty.bg_color = SLOT_FRAME_BG
			sty.border_color = ROLE_COLORS[role]
			_slot_name_btn[i].text = p.name
			_slot_name_btn[i].disabled = false
			_slot_sub_lbl[i].text = "%s · 원소속 %s" % [
					String(ROLE_NAMES[role]), _team_short(p.team_id)]
		frame.add_theme_stylebox_override("panel", sty)
	_count_lbl.text = "내 팀 (%d/5)" % count


## `tall` 컷의 윗부분(어깨~얼굴)만 잘라 낸 텍스처. `AtlasTexture` 라 원본을
## 한 벌 더 만들지 않는다.
func _bust_texture(pilot_id: int) -> Texture2D:
	var src: Texture2D = PilotImages.tall_for(pilot_id)
	if src == null:
		return null
	var atlas := AtlasTexture.new()
	atlas.atlas = src
	atlas.region = BUST_REGION
	return atlas


func _refresh_skill_panel() -> void:
	for i in SLOT_COUNT:
		var p: PlayerData = _pilot_in_slot(i)
		var slot_name: String = String(TeamDraft.SLOT_NAMES[i])
		if p == null:
			_skill_rows[i].text = "%s   —" % slot_name
			_skill_rows[i].add_theme_color_override("font_color",
					Color(0.48, 0.51, 0.60))
			continue
		var sk: Dictionary = _draft.skill_def_for(p)
		if sk.is_empty():
			_skill_rows[i].text = "%s   %s — 스킬 없음" % [slot_name, p.name]
			_skill_rows[i].add_theme_color_override("font_color",
					Color(0.62, 0.65, 0.74))
		else:
			_skill_rows[i].text = "%s   %s — %s (%s)" % [
					slot_name, p.name, String(sk.get("name", "?")),
					TeamDraft.skill_type_label(String(sk.get("type", "")))]
			_skill_rows[i].add_theme_color_override("font_color",
					Color(0.92, 0.94, 0.98))


func _refresh_confirm_btn() -> void:
	for i in SLOT_COUNT:
		if int(_picks[i]) == -1:
			_confirm_btn.disabled = true
			return
	_confirm_btn.disabled = false


func _apply_filter_styles() -> void:
	for i in _filter_btns.size():
		var role: int = -1 if i == 0 else int(TeamDraft.SLOT_ROLES[i - 1])
		var on: bool = role == _filter_role
		var sty := StyleBoxFlat.new()
		sty.bg_color     = FILTER_BG_ON if on else FILTER_BG_OFF
		sty.border_color = FILTER_BORDER_ON if on else FILTER_BORDER_OFF
		var w: int = 3 if on else 2
		sty.border_width_left = w
		sty.border_width_right = w
		sty.border_width_top = w
		sty.border_width_bottom = w
		sty.corner_radius_top_left     = 8
		sty.corner_radius_top_right    = 8
		sty.corner_radius_bottom_left  = 8
		sty.corner_radius_bottom_right = 8
		var btn: Button = _filter_btns[i]
		btn.add_theme_stylebox_override("normal",  sty)
		btn.add_theme_stylebox_override("hover",   sty)
		btn.add_theme_stylebox_override("pressed", sty)
		btn.add_theme_stylebox_override("focus",   sty)


func _team_short(team_id: int) -> String:
	var meta: Array = _gm.season_state.get("team_meta", [])
	if team_id < 0 or team_id >= meta.size():
		return "TEAM %d" % team_id
	return String(meta[team_id]["short_name"])


func _on_confirm_pressed() -> void:
	# 확정은 **역할 순서(GameEnums.Role)** 로 넘긴다 — `validate_draft` 는 순서를
	# 보지 않지만, 화면의 슬롯 순서(탑 · 정글 · 미드 · 원딜 · 서폿)를 그대로
	# 흘려보내면 이 목록이 무엇의 순서인지가 호출부마다 달라진다.
	var ids: Array = []
	for role in 5:
		var slot: int = TeamDraft.slot_of_role(role)
		ids.append(int(_picks[slot]))
	var err: String = _draft.apply_draft(ids)
	if err != "":
		push_error("TeamDraftView: confirm failed — " + err)
		return
	# 팝업은 CanvasLayer 라 부모 Control 의 `visible` 을 따르지 않는다 — 열어 둔
	# 채 허브로 넘어가면 딤이 화면에 그대로 남는다.
	_detail.close()
	var hub: SeasonHub = _draft.get_parent() as SeasonHub
	if hub:
		hub.goto(SeasonHub.Screen.HUB)
