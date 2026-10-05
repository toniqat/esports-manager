class_name PilotStrip
extends Control

# 파일럿 5인 스트립 — **원형 초상 5개를 가로로 나란히** 놓고, 원 아래끝에
# 걸친 알약 배지에 성장치 숫자를 찍는다(Deadlock 중계 HUD 의 초상 줄).
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

## 원 바탕색 / 테두리색 — 팀색. [아군, 적].
const DISC_COLOR := [Color(0.17, 0.32, 0.58), Color(0.58, 0.21, 0.18)]
const TEAM_RIM := [Color(0.32, 0.62, 0.95), Color(0.95, 0.40, 0.32)]
const RIM_WIDTH: float = 3.0
## 원과 칸 가장자리 사이 최소 여백(좌우 합).
const CELL_GAP: float = 12.0

const SCORE_COLOR      := Color(1.0, 0.94, 0.62)
const SCORE_PILL_BG    := Color(0.05, 0.05, 0.09, 0.95)
## 성장치 배지 폭 = 원 지름 × 이 값.
const SCORE_PILL_W_RATIO: float = 0.58
# ─── 파일럿 스킬 표시 ────────────────────────────────────────────────────────
# **초상화는 기본적으로 어둡게 덮여 있고, 스킬이 준비되는 만큼 왼쪽부터 밝아진다.**
# 채움은 `PilotSkillSystem.progress()` 가 답한다 — 쿨타임은 경과 비율, 충전식은
# 활성화에 필요한 충전 대비 비율, **패시브는 언제나 1.0**(누를 수 없는 대신 상시
# 적용이라 "아직 안 됐다"가 성립하지 않는다).
#
# 딤은 셰이더의 `fill` / `dim` 이다 — 사각형을 겹쳐 얹으면 원 바깥의 빈
# 모서리까지 어두운 상자가 그려진다. 채움이 100% 면 딤이 사라져 원래 색 그대로다.
const SKILL_DIM: float = 0.55
## 지금 누를 수 있는 스킬의 숫자 색 / 아직인 스킬의 숫자 색.
const SKILL_BADGE_READY := Color(1.0, 0.86, 0.35)
const SKILL_BADGE_WAIT  := Color(0.78, 0.82, 0.92)
const SKILL_BADGE_OUTLINE := Color(0, 0, 0, 0.9)
## 숫자 원 — 초상 원의 오른쪽 위 테두리에 걸친다. 지름 = 원 지름 × 이 값.
const SKILL_BADGE_RATIO: float = 0.30
const SKILL_BADGE_FONT_RATIO: float = 0.62
## 쓰러진 파일럿의 초상화에 씌우는 틴트.
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

	_cell_w = rect.size.x / float(SLOT_COUNT)
	var avail_h: float = rect.size.y - _pill_h() * 0.5 - 2.0
	_disc_d = minf(_cell_w - CELL_GAP, avail_h * PilotImages.STRIP_ASPECT)
	_bust_h = _disc_d / PilotImages.STRIP_ASPECT
	_bust_y = avail_h - _bust_h
	for i in SLOT_COUNT:
		_cells.append(_build_cell(i))


func _pill_h() -> float:
	return float(_score_font) + 10.0


func _build_cell(idx: int) -> Dictionary:
	var cx: float = _cell_w * (float(idx) + 0.5)
	var px: float = cx - _disc_d * 0.5
	var r: float = _disc_d * 0.5
	var disc_c := Vector2(cx, _bust_y + _bust_h - r)

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
	mat.set_shader_parameter("rim_color", TEAM_RIM[_team])
	mat.set_shader_parameter("rim_width", RIM_WIDTH)
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

	# 성장치 배지 — 원 아래끝에 반쯤 걸친 알약. 테두리는 팀색.
	var pill_h: float = _pill_h()
	var pill_w: float = _disc_d * SCORE_PILL_W_RATIO
	var pill := Panel.new()
	pill.position = Vector2(cx - pill_w * 0.5, _bust_y + _bust_h - pill_h * 0.5)
	pill.size = Vector2(pill_w, pill_h)
	pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var pill_sb := StyleBoxFlat.new()
	pill_sb.bg_color = SCORE_PILL_BG
	pill_sb.border_color = TEAM_RIM[_team]
	pill_sb.set_border_width_all(2)
	pill_sb.set_corner_radius_all(int(pill_h * 0.5))
	pill_sb.anti_aliasing = true
	pill.add_theme_stylebox_override("panel", pill_sb)
	add_child(pill)

	var score_lbl := Label.new()
	score_lbl.add_theme_font_size_override("font_size", _score_font)
	score_lbl.add_theme_color_override("font_color", SCORE_COLOR)
	score_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	score_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	score_lbl.position = pill.position
	score_lbl.size = pill.size
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
		btn.position = Vector2(_cell_w * float(idx), 0.0)
		btn.size = Vector2(_cell_w, size.y)
		btn.pressed.connect(func() -> void: _on_cell_pressed(idx))
		add_child(btn)

	return {
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

	(cell["score"] as Label).text = BattleSim.fmt_score(p.score)
	_apply_skill_state(cell, p)


## 스킬 준비도 딤과 숫자. **아군 스트립에만** 뜬다 — 스킬은 아군만 누를 수 있고,
## 적 칸까지 어둡게 덮으면 상대 얼굴이 스킬과 무관하게 흐려 보인다.
func _apply_skill_state(cell: Dictionary, p: PilotData) -> void:
	var mat := cell["mat"] as ShaderMaterial
	var badge_bg := cell["badge_bg"] as Panel
	var badge := cell["badge"] as Label
	var sk: PilotSkillSystem = _bs.skill if _bs != null else null
	if _team != 0 or sk == null or not sk.has_skill(p):
		mat.set_shader_parameter("dim", 0.0)
		badge_bg.visible = false
		badge.visible = false
		return
	# 채움만큼 왼쪽이 밝아진다 — 셰이더가 UV.x > fill 인 쪽만 어둡게 한다.
	var filled: float = clampf(sk.progress(p), 0.0, 1.0)
	mat.set_shader_parameter("fill", filled)
	mat.set_shader_parameter("dim", SKILL_DIM if filled < 1.0 else 0.0)

	var text: String = sk.badge_text(p)
	var show: bool = not text.is_empty()
	badge_bg.visible = show
	badge.visible = show
	if show:
		badge.text = text
		badge.add_theme_color_override("font_color",
				SKILL_BADGE_READY if sk.can_activate(p) else SKILL_BADGE_WAIT)
