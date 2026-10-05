class_name PilotStrip
extends Control

# 파일럿 5인 스트립 — **원형 초상 5개를 가로로 나란히** 놓고, 원 아래로
# 늘어진 둥근 탭에 성장치 숫자를 찍는다(Deadlock 중계 HUD 의 초상 줄).
# 스트립 뒤판(배경)과 초상 원의 테두리는 없다.
#
# 한 칸의 초상은 **팀색 원 + 그 위의 머리~어깨 흉상**이다. 흉상은
# `shaders/pilot_bust_mask.gdshader` 가 잘라 낸다 — 원 중심 아래는 원 모양으로,
# 그 위는 원 **폭**으로만 잘라 머리가 원 위로 튀어나온다. 흉상 칸의 위쪽
# 1/5 이 그 돌출부 몫이다(`PilotImages.STRIP_ASPECT` = 0.8).
#
# 화면에 두 벌이 있다:
#   • 적 팀 — 화면 **최상단**. (`HudBuilder._build_top_panel`)
#   • 아군  — **핸드 행보다 아래**. (`HudBuilder._build_player_strip`)
# 둘 다 누르면 파일럿 상세 패널이 열린다(작전 단계 + 자동 진행 —
# `PilotDetailPanel.can_open`, `set_interactive_enabled` 로 게이트).
#
# **체력 바는 삭제됐다** — 원형 초상으로 바뀌며 원 아래에는 성장치 배지만
# 남겼다. 체력은 전장 마커와 상세 패널이 보여 준다.
#
# **성장치는 게이지가 아니라 숫자다** — 상한이 없어서 채울 바탕이 없다.
# 개시 1.00k 에서 시작해 처치 / 피해 / 오브젝트로 오른다(`BattleSim` 의
# `SCORE_*` 절 참고).

## 한 파일럿이 눌렸을 때. `interactive` 인 스트립만 쏜다.
signal pilot_pressed(pilot: PilotData)

const SLOT_COUNT: int = 5

const BUST_SHADER: Shader = preload("res://resources/shaders/pilot_bust_mask.gdshader")

## 원 바탕색 — 팀색. [아군, 적]. 성장치 탭도 같은 색이라 원에서 이어져 내려온
## 한 덩어리로 읽힌다.
const DISC_COLOR := [Color(0.17, 0.32, 0.58), Color(0.58, 0.21, 0.18)]
## 스킬 숫자 원의 테두리색. (초상 원 자체의 테두리는 삭제됐다 — 셰이더에
## `rim_width = 0` 을 넘긴다.)
const TEAM_RIM := [Color(0.32, 0.62, 0.95), Color(0.95, 0.40, 0.32)]
## 원과 칸 가장자리 사이 최소 여백(좌우 합). **축소 전** 레이아웃을 정할 때만
## 쓴다 — 그때 생긴 원 사이 간격이 축소 뒤에도 그대로 유지된다.
const CELL_GAP: float = 12.0
## 초상 크기 배율 — 칸에서 유도한 원 지름을 이만큼 줄인다(30% 축소). 원 사이
## 간격은 축소 전 그대로이므로 줄 전체가 좁아지고 스트립 가로 가운데에 모인다.
## 세로는 축소 전 원 중심을 지킨다(적 스트립 양옆 오브젝트 시계가 거기 맞춰져 있다).
const PORTRAIT_SCALE: float = 0.7

const SCORE_COLOR      := Color(1.0, 0.94, 0.62)
## 성장치 탭 폭 = 원 지름 × 이 값. 탭 위끝은 원 중심에 숨고 아래로
## `_pill_h()` 만큼 원 밖으로 늘어진다(Deadlock 초상 줄의 금색 탭 모양).
const SCORE_PILL_W_RATIO: float = 0.58
const SCORE_TAB_RADIUS: int = 8
# ─── 파일럿 스킬 표시 ────────────────────────────────────────────────────────
# 스킬 준비도는 **숫자 배지 하나**로만 보인다. 예전에는 준비도(충전 / 쿨타임
# 비율)만큼 초상화가 왼쪽부터 밝아지는 딤이 있었으나 삭제됐다 — 딤은 이제
# **전장을 이탈한(쓰러진) 파일럿**만의 표시이고, 그때도 흉상만 어두워지고 팀색
# 원은 그대로다(셰이더 `tint`).
## 지금 누를 수 있는 스킬의 숫자 색 / 아직인 스킬의 숫자 색.
const SKILL_BADGE_READY := Color(1.0, 0.86, 0.35)
const SKILL_BADGE_WAIT  := Color(0.78, 0.82, 0.92)
const SKILL_BADGE_OUTLINE := Color(0, 0, 0, 0.9)
## 숫자 원 — 초상 원의 오른쪽 위 테두리에 걸친다. 지름 = 원 지름 × 이 값.
const SKILL_BADGE_RATIO: float = 0.30
const SKILL_BADGE_FONT_RATIO: float = 0.62
## 쓰러진 파일럿의 **흉상**에 씌우는 틴트(원은 제외).
const DEAD_TINT        := Color(0.42, 0.42, 0.46, 1.0)
## **역할 태그는 삭제됐다.** 스트립의 자리 순서 자체가 이미 역할이다
## (`GameEnums.ROLE_DISPLAY_ORDER` — 탑 · 정글 · 미드 · 원딜 · 서폿).

# ─── 레이아웃 (setup 이 채운다) ──────────────────────────────────────────────
var _cell_w: float = 200.0
## 원 지름 = 흉상 칸 폭.
var _disc_d: float = 180.0
## 흉상 칸 높이 (= 원 지름 / STRIP_ASPECT).
var _bust_h: float = 225.0
## 흉상 칸 위끝 y (스트립 로컬).
var _bust_y: float = 0.0
## 줄 왼쪽 끝 x — 줄이 스트립보다 좁아 가로 가운데에 모인다.
var _row_x: float = 0.0
var _score_font: int = 16
var _team: int = 0
var _interactive: bool = false

var _cells: Array = []          # Array[Dictionary]
var _pilots: Array = []         # Array[PilotData]
var _bs: BattleSim = null


## `parent` 아래에 스트립을 만든다. `rect` 는 스트립 전체가 차지하는 화면 영역.
## 원 지름은 칸 폭과 높이 중 빡빡한 쪽에서 유도하고, 흉상 칸 높이는
## **`PilotImages.STRIP_ASPECT`(0.8)** 로 정한다 — 다른 비율이면 얼굴이 찌그러진다.
## 칸 맨 아래에는 원 밑에 걸친 성장치 배지의 아래 절반이 앉을 자리를 남긴다.
func setup(bs: BattleSim, team: int, rect: Rect2, interactive: bool,
		score_font: int) -> void:
	_bs = bs
	_team = team
	_interactive = interactive
	_score_font = score_font
	position = rect.position
	size = rect.size
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	# 축소 전 레이아웃 — 칸 폭과 높이에서 원 지름, 원 사이 간격, 원 중심을 정한다.
	var full_cell_w: float = rect.size.x / float(SLOT_COUNT)
	var avail_h: float = rect.size.y - _pill_h() * 0.5 - 2.0
	var full_d: float = minf(full_cell_w - CELL_GAP, avail_h * PilotImages.STRIP_ASPECT)
	var disc_cy: float = avail_h - full_d * 0.5
	var gap: float = full_cell_w - full_d

	# 축소 — 지름만 줄고 간격은 그대로, 원 중심 높이도 그대로.
	_disc_d = full_d * PORTRAIT_SCALE
	_bust_h = _disc_d / PilotImages.STRIP_ASPECT
	_bust_y = disc_cy + _disc_d * 0.5 - _bust_h
	_cell_w = _disc_d + gap
	_row_x = (rect.size.x - _cell_w * float(SLOT_COUNT)) * 0.5
	for i in SLOT_COUNT:
		_cells.append(_build_cell(i))


func _pill_h() -> float:
	return float(_score_font) + 10.0


func _build_cell(idx: int) -> Dictionary:
	var cx: float = _row_x + _cell_w * (float(idx) + 0.5)
	var px: float = cx - _disc_d * 0.5
	var r: float = _disc_d * 0.5
	var disc_c := Vector2(cx, _bust_y + _bust_h - r)

	# 성장치 탭 — 원 **뒤에** 먼저 붙인다. 위끝은 원 중심에서 시작해 원에 덮이고,
	# 원 아래끝 밖으로 `pill_h` 만큼만 드러난다. 끝이 둥근 사각형이 원에서 밑으로
	# 늘어진 모양(별도 알약이 아니다).
	var pill_h: float = _pill_h()
	var pill_w: float = _disc_d * SCORE_PILL_W_RATIO
	var disc_bottom: float = disc_c.y + r
	var pill := Panel.new()
	pill.position = Vector2(cx - pill_w * 0.5, disc_c.y)
	pill.size = Vector2(pill_w, disc_bottom + pill_h - disc_c.y)
	pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var pill_sb := StyleBoxFlat.new()
	pill_sb.bg_color = DISC_COLOR[_team]
	pill_sb.set_corner_radius_all(SCORE_TAB_RADIUS)
	pill_sb.anti_aliasing = true
	pill.add_theme_stylebox_override("panel", pill_sb)
	add_child(pill)

	# 원 + 흉상 — ColorRect 한 장에 셰이더. 이미지가 없을 때(단독 실행 / INTL)도
	# 팀색 원은 그대로 그려진다(`has_portrait = false`).
	var bust := ColorRect.new()
	bust.position = Vector2(px, _bust_y)
	bust.size = Vector2(_disc_d, _bust_h)
	bust.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = BUST_SHADER
	mat.set_shader_parameter("rect_size", bust.size)
	mat.set_shader_parameter("disc_color", DISC_COLOR[_team])
	mat.set_shader_parameter("rim_width", 0.0)
	bust.material = mat
	add_child(bust)

	# 부활까지 남은 턴 — 쓰러져 있는 동안 원 한가운데에 크게.
	var dead_lbl := Label.new()
	dead_lbl.add_theme_font_size_override("font_size", int(_disc_d * 0.42))
	dead_lbl.add_theme_color_override("font_color", Color(1.0, 0.55, 0.5))
	dead_lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	dead_lbl.add_theme_constant_override("outline_size", 6)
	dead_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	dead_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	dead_lbl.position = disc_c - Vector2(r, r)
	dead_lbl.size = Vector2(_disc_d, _disc_d)
	dead_lbl.visible = false
	dead_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dead_lbl)

	# 성장치 숫자 — 탭 중 원 밖으로 드러난 부분에만 앉는다.
	var score_lbl := Label.new()
	score_lbl.add_theme_font_size_override("font_size", _score_font)
	score_lbl.add_theme_color_override("font_color", SCORE_COLOR)
	score_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	score_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	score_lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.6))
	score_lbl.add_theme_constant_override("outline_size", 3)
	score_lbl.position = Vector2(pill.position.x, disc_bottom)
	score_lbl.size = Vector2(pill_w, pill_h)
	score_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(score_lbl)

	# 스킬 숫자 — 원 오른쪽 위 테두리에 걸친 작은 원. 쿨타임이면 남은 턴,
	# 충전식/충전 패시브면 충전 수다. 빈 문자열이면 숨는다(준비된 쿨타임 스킬 ·
	# 충전 없는 패시브).
	var badge_d: float = _disc_d * SKILL_BADGE_RATIO
	var badge_c: Vector2 = disc_c + Vector2(0.72, -0.62) * r
	var badge_bg := Panel.new()
	badge_bg.position = badge_c - Vector2(badge_d, badge_d) * 0.5
	badge_bg.size = Vector2(badge_d, badge_d)
	badge_bg.visible = false
	badge_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var badge_sb := StyleBoxFlat.new()
	badge_sb.bg_color = Color(0.0, 0.0, 0.0, 0.75)
	badge_sb.border_color = TEAM_RIM[_team]
	badge_sb.set_border_width_all(2)
	badge_sb.set_corner_radius_all(int(badge_d * 0.5))
	badge_sb.anti_aliasing = true
	badge_bg.add_theme_stylebox_override("panel", badge_sb)
	add_child(badge_bg)

	var badge := Label.new()
	badge.add_theme_font_size_override("font_size",
			maxi(9, int(round(badge_d * SKILL_BADGE_FONT_RATIO))))
	badge.add_theme_color_override("font_outline_color", SKILL_BADGE_OUTLINE)
	badge.add_theme_constant_override("outline_size", 4)
	badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	badge.position = badge_bg.position
	badge.size = badge_bg.size
	badge.visible = false
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(badge)

	# 히트 버튼 — 칸 전체를 덮는 투명 버튼. 나머지 노드는 전부 IGNORE 라
	# 입력은 여기서만 가져간다.
	var btn: Button = null
	if _interactive:
		btn = Button.new()
		btn.flat = true
		btn.focus_mode = Control.FOCUS_NONE
		btn.modulate = Color(1, 1, 1, 0)
		btn.position = Vector2(_row_x + _cell_w * float(idx), 0.0)
		btn.size = Vector2(_cell_w, size.y)
		btn.pressed.connect(func() -> void: _on_cell_pressed(idx))
		add_child(btn)

	return {
		"center": disc_c,
		"bust": bust, "mat": mat, "dead": dead_lbl,
		"pill": pill, "score": score_lbl, "btn": btn,
		"badge_bg": badge_bg, "badge": badge,
	}


func _on_cell_pressed(idx: int) -> void:
	if idx >= _pilots.size():
		return
	pilot_pressed.emit(_pilots[idx] as PilotData)


## 이 스트립이 보여 줄 파일럿 5인. `HudBuilder` 가 역할 순으로 정렬해 넘긴다.
func set_pilots(list: Array) -> void:
	_pilots = list
	refresh()


## 입력 게이트. 자기 작전 단계가 아닐 때는 눌러도 아무 일이 없어야 한다.
func set_interactive_enabled(on: bool) -> void:
	for raw in _cells:
		var btn: Button = (raw as Dictionary)["btn"]
		if btn != null:
			btn.disabled = not on


func refresh() -> void:
	for i in _cells.size():
		var cell: Dictionary = _cells[i]
		if i >= _pilots.size():
			_set_cell_visible(cell, false)
			continue
		_set_cell_visible(cell, true)
		_apply_cell(cell, _pilots[i] as PilotData)


static func _set_cell_visible(cell: Dictionary, on: bool) -> void:
	(cell["bust"] as ColorRect).visible = on
	(cell["pill"] as Panel).visible = on
	(cell["score"] as Label).visible = on
	if not on:
		(cell["dead"] as Label).visible = false
		(cell["badge_bg"] as Panel).visible = false
		(cell["badge"] as Label).visible = false


func _apply_cell(cell: Dictionary, p: PilotData) -> void:
	var mat := cell["mat"] as ShaderMaterial
	var tex: Texture2D = PilotImages.strip_for(p.pilot_id)
	mat.set_shader_parameter("has_portrait", tex != null)
	mat.set_shader_parameter("portrait", tex)
	mat.set_shader_parameter("tint", Color.WHITE if p.alive else DEAD_TINT)

	var dead_lbl := cell["dead"] as Label
	dead_lbl.visible = not p.alive
	if not p.alive:
		dead_lbl.text = str(_bs.turns_until_return(p))

	(cell["score"] as Label).text = fmt_strip_score(p.score)
	_apply_skill_state(cell, p)


## 스트립 탭의 성장치 표기 — 소수 한 자리(`9.9k`), **10k 이상은 정수**(`12k`).
## 상세 패널은 여전히 `BattleSim.fmt_score`(소수 두 자리)를 쓴다 — 탭은 원
## 지름의 58% 폭이라 자릿수가 적어야 한다. 9.95 이상은 `%.1f` 가 `10.0` 으로
## 올라가므로 그 자리부터 정수 표기로 넘긴다.
static func fmt_strip_score(v: float) -> String:
	if absf(v) >= 9.95:
		return "%.0fk" % v
	return "%.1fk" % v


## 스킬 숫자 배지. **아군 스트립에만** 뜬다 — 스킬은 아군만 누를 수 있다.
func _apply_skill_state(cell: Dictionary, p: PilotData) -> void:
	var badge_bg := cell["badge_bg"] as Panel
	var badge := cell["badge"] as Label
	var sk: PilotSkillSystem = _bs.skill if _bs != null else null
	if _team != 0 or sk == null or not sk.has_skill(p):
		badge_bg.visible = false
		badge.visible = false
		return
	var text: String = sk.badge_text(p)
	var show: bool = not text.is_empty()
	badge_bg.visible = show
	badge.visible = show
	if show:
		badge.text = text
		badge.add_theme_color_override("font_color",
				SKILL_BADGE_READY if sk.can_activate(p) else SKILL_BADGE_WAIT)
