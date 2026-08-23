class_name PilotStrip
extends Control

# 파일럿 5인 스트립 — **눈높이 초상화 5개를 가로로 나란히** 놓고, 그 아래에
# 체력 바, 다시 그 아래에 성장치 숫자를 찍는다.
#
# 화면에 두 벌이 있다:
#   • 적 팀 — 화면 **최상단**, 시간·팀 점수 줄 바로 아래. 표시 전용.
#            (`HudBuilder._build_top_panel` 이 상단 패널의 자식으로 만든다)
#   • 아군  — **핸드 행보다 아래**. 누르면 파일럿 상세 패널이 열린다
#            (자기 작전 단계에 한함 — `set_interactive_enabled` 로 게이트).
#            (`HudBuilder._build_player_strip`)
#
# 예전에는 열 명이 전부 상단 점수 패널 양옆에 84px 슬롯으로 몰려 있었다.
# 얼굴이 76px 정사각이라 누가 누구인지 읽히지 않았고, 아군과 적이 같은 줄에
# 붙어 있어 어느 쪽이 내 팀인지도 한눈에 안 들어왔다.
#
# **성장치는 게이지가 아니라 숫자다** — 상한이 없어서 채울 바탕이 없다.
# 개시 1.00k 에서 시작해 처치 / 피해 / 오브젝트로 오른다(`BattleSim` 의
# `SCORE_*` 절 참고).

## 한 파일럿이 눌렸을 때. `interactive` 인 스트립만 쏜다.
signal pilot_pressed(pilot: PilotData)

const SLOT_COUNT: int = 5

const ROLE_TAG_COLOR   := Color(1, 1, 1)
const ROLE_TAG_OUTLINE := Color(0, 0, 0, 0.85)
const HP_FILL_HI       := Color(0.30, 0.85, 0.45)
const HP_FILL_LOW      := Color(0.90, 0.55, 0.25)
const HP_BG            := Color(0.08, 0.09, 0.13)
const SHIELD_FILL      := Color(0.85, 0.85, 0.30)
## 체력 바가 경고색으로 바뀌는 비율.
const HP_LOW_RATIO: float = 0.30
const SCORE_COLOR      := Color(1.0, 0.94, 0.62)
# ─── 파일럿 스킬 표시 ────────────────────────────────────────────────────────
# **초상화는 기본적으로 어둡게 덮여 있고, 스킬이 준비되는 만큼 왼쪽부터 밝아진다.**
# 채움은 `PilotSkillSystem.progress()` 가 답한다 — 쿨타임은 경과 비율, 충전식은
# 활성화에 필요한 충전 대비 비율, **패시브는 언제나 1.0**(누를 수 없는 대신 상시
# 적용이라 "아직 안 됐다"가 성립하지 않는다).
#
# 구현은 딤 한 장의 **왼쪽 끝을 밀어내는** 것이다: 밝은 쪽에 사각형을 얹는 대신
# 어두운 쪽을 좁히면, 채움이 100% 일 때 딤이 폭 0 이 되어 초상화가 원래 색
# 그대로가 된다(얹는 방식은 100% 에서도 한 겹이 남는다).
const SKILL_DIM        := Color(0.0, 0.0, 0.05, 0.55)
## 지금 누를 수 있는 스킬의 숫자 색 / 아직인 스킬의 숫자 색.
const SKILL_BADGE_READY := Color(1.0, 0.86, 0.35)
const SKILL_BADGE_WAIT  := Color(0.78, 0.82, 0.92)
const SKILL_BADGE_OUTLINE := Color(0, 0, 0, 0.9)
## 숫자 칸 — 초상화 오른쪽 위. 폭은 초상화 폭 비율로 잡아 두 스트립이 같이 준다.
const SKILL_BADGE_W_RATIO: float = 0.28
const SKILL_BADGE_H_RATIO: float = 0.42
const SKILL_BADGE_FONT_RATIO: float = 0.80
## 쓰러진 파일럿의 초상화에 씌우는 틴트.
const DEAD_TINT        := Color(0.42, 0.42, 0.46, 1.0)
## 초상화 테두리 — 팀색.
const TEAM_RIM := [Color(0.32, 0.62, 0.95), Color(0.95, 0.40, 0.32)]
## 역할 태그 받침 — **초상화 높이에서 유도한다**. 두 스트립의 초상화 크기가
## 달라졌으므로(아군 190×79 / 적 118×49) 고정 픽셀로 두면 작은 쪽에서 태그가
## 얼굴 절반을 덮는다. 비율은 큰 쪽의 원래 값(30×19, 폰트 14)에서 그대로 딴
## 것이라 아군 스트립의 그림은 한 픽셀도 달라지지 않는다.
const ROLE_TAG_H_RATIO: float = 0.24     # 79 × 0.24 ≈ 19
const ROLE_TAG_ASPECT: float = 30.0 / 19.0
const ROLE_TAG_FONT_RATIO: float = 0.74  # 19 × 0.74 ≈ 14

# ─── 레이아웃 (setup 이 채운다) ──────────────────────────────────────────────
var _cell_w: float = 200.0
var _portrait_w: float = 184.0
var _portrait_h: float = 77.0
var _hp_h: float = 8.0
var _tag_h: float = 19.0
var _tag_w: float = 30.0
var _tag_font: int = 14
var _score_font: int = 16
var _team: int = 0
var _interactive: bool = false

var _cells: Array = []          # Array[Dictionary]
var _pilots: Array = []         # Array[PilotData]
var _bs: BattleSim = null


## `parent` 아래에 스트립을 만든다. `rect` 는 스트립 전체가 차지하는 화면 영역.
## 초상화 폭은 칸 폭에서 유도하고, 높이는 **eye 이미지의 가로:세로 비(2.4:1)**
## 로 결정한다 — 임의 높이로 늘리면 얼굴이 찌그러진다.
func setup(bs: BattleSim, team: int, rect: Rect2, interactive: bool,
		score_font: int, hp_h: float) -> void:
	_bs = bs
	_team = team
	_interactive = interactive
	_score_font = score_font
	_hp_h = hp_h
	position = rect.position
	size = rect.size
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	_cell_w = rect.size.x / float(SLOT_COUNT)
	_portrait_w = _cell_w - 16.0
	_portrait_h = _portrait_w / EYE_ASPECT
	_tag_h = _portrait_h * ROLE_TAG_H_RATIO
	_tag_w = _tag_h * ROLE_TAG_ASPECT
	_tag_font = maxi(9, int(round(_tag_h * ROLE_TAG_FONT_RATIO)))
	for i in SLOT_COUNT:
		_cells.append(_build_cell(i))


## eye 크롭의 가로:세로 비. `make_eye_crops.py` 가 480×200 으로 내보낸다.
const EYE_ASPECT: float = 2.4


func _build_cell(idx: int) -> Dictionary:
	var cx: float = _cell_w * (float(idx) + 0.5)
	var px: float = cx - _portrait_w * 0.5

	# 초상화 뒤판 — 이미지가 없을 때(단독 실행 / INTL) 그대로 보이는 폴백이다.
	var bg := ColorRect.new()
	bg.position = Vector2(px, 0.0)
	bg.size = Vector2(_portrait_w, _portrait_h)
	bg.color = Color(0.12, 0.13, 0.19)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	var eye := TextureRect.new()
	eye.position = Vector2(px, 0.0)
	eye.size = Vector2(_portrait_w, _portrait_h)
	eye.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	eye.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	eye.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(eye)

	# 스킬 준비도 딤 — 초상화 **오른쪽 남은 만큼**을 덮는다. `rim` 보다 먼저
	# 붙여 팀색 테두리가 딤 위에 남게 한다(테두리까지 어두워지면 어느 팀인지가
	# 준비도에 따라 흐려진다).
	var skill_dim := ColorRect.new()
	skill_dim.position = Vector2(px, 0.0)
	skill_dim.size = Vector2(_portrait_w, _portrait_h)
	skill_dim.color = SKILL_DIM
	skill_dim.visible = false
	skill_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(skill_dim)

	# 팀색 테두리 — 얇은 사각 프레임. Panel 하나로 그린다.
	var rim := Panel.new()
	rim.position = Vector2(px, 0.0)
	rim.size = Vector2(_portrait_w, _portrait_h)
	rim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var rim_sb := StyleBoxFlat.new()
	rim_sb.bg_color = Color(0, 0, 0, 0)
	rim_sb.border_color = TEAM_RIM[_team]
	rim_sb.border_width_top = 2
	rim_sb.border_width_bottom = 2
	rim_sb.border_width_left = 2
	rim_sb.border_width_right = 2
	rim.add_theme_stylebox_override("panel", rim_sb)
	add_child(rim)

	# 역할 태그 — 초상화 좌하단. 어두운 받침 위에 흰 글자 + 검은 외곽선.
	# 외곽선만으로는 검은 머리카락 위에서 한 글자 태그(T / F)가 거의 안 보였다.
	var tag_bg := ColorRect.new()
	tag_bg.position = Vector2(px + 2.0, _portrait_h - _tag_h - 2.0)
	tag_bg.size = Vector2(_tag_w, _tag_h)
	tag_bg.color = Color(0.0, 0.0, 0.0, 0.55)
	tag_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(tag_bg)

	var role_lbl := Label.new()
	role_lbl.add_theme_font_size_override("font_size", _tag_font)
	role_lbl.add_theme_color_override("font_color", ROLE_TAG_COLOR)
	role_lbl.add_theme_color_override("font_outline_color", ROLE_TAG_OUTLINE)
	role_lbl.add_theme_constant_override("outline_size", 4)
	role_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	role_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	role_lbl.position = tag_bg.position
	role_lbl.size = tag_bg.size
	role_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(role_lbl)

	# 부활까지 남은 턴 — 쓰러져 있는 동안 초상화 한가운데에 크게.
	var dead_lbl := Label.new()
	dead_lbl.add_theme_font_size_override("font_size", int(_portrait_h * 0.55))
	dead_lbl.add_theme_color_override("font_color", Color(1.0, 0.55, 0.5))
	dead_lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	dead_lbl.add_theme_constant_override("outline_size", 5)
	dead_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	dead_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	dead_lbl.position = Vector2(px, 0.0)
	dead_lbl.size = Vector2(_portrait_w, _portrait_h)
	dead_lbl.visible = false
	dead_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dead_lbl)

	# 체력 바는 **ColorRect 두 장**이다 — ProgressBar 로 두면 안 된다.
	# ProgressBar 는 테마 스타일박스의 컨텐트 마진에서 최소 크기를 계산하고
	# `size` 를 거기까지 끌어올린다(기본 테마에서 약 24px). 6~10px 짜리 스트립
	# 바를 요청해도 24px 로 그려져 바로 아래의 성장치 라벨을 덮어썼다 —
	# 실측으로 확인한 문제다. 두 장짜리 사각형은 픽셀을 정확히 지킨다.
	var bar_y: float = _portrait_h + 3.0
	var bar_bg := ColorRect.new()
	bar_bg.position = Vector2(px, bar_y)
	bar_bg.size = Vector2(_portrait_w, _hp_h)
	bar_bg.color = HP_BG
	bar_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bar_bg)

	var bar := ColorRect.new()
	bar.position = Vector2(px, bar_y)
	bar.size = Vector2(_portrait_w, _hp_h)
	bar.color = HP_FILL_HI
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bar)

	var score_lbl := Label.new()
	score_lbl.add_theme_font_size_override("font_size", _score_font)
	score_lbl.add_theme_color_override("font_color", SCORE_COLOR)
	score_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	score_lbl.position = Vector2(px, bar_y + _hp_h + 2.0)
	score_lbl.size = Vector2(_portrait_w, float(_score_font) + 8.0)
	score_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(score_lbl)

	# 스킬 숫자 — 초상화 오른쪽 위. 쿨타임이면 남은 턴, 충전식/충전 패시브면
	# 충전 수다. 빈 문자열이면 숨는다(준비된 쿨타임 스킬 · 충전 없는 패시브).
	var badge_w: float = _portrait_w * SKILL_BADGE_W_RATIO
	var badge_h: float = _portrait_h * SKILL_BADGE_H_RATIO
	var badge_bg := ColorRect.new()
	badge_bg.position = Vector2(px + _portrait_w - badge_w - 2.0, 2.0)
	badge_bg.size = Vector2(badge_w, badge_h)
	badge_bg.color = Color(0.0, 0.0, 0.0, 0.55)
	badge_bg.visible = false
	badge_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(badge_bg)

	var badge := Label.new()
	badge.add_theme_font_size_override("font_size",
			maxi(9, int(round(badge_h * SKILL_BADGE_FONT_RATIO))))
	badge.add_theme_color_override("font_outline_color", SKILL_BADGE_OUTLINE)
	badge.add_theme_constant_override("outline_size", 4)
	badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	badge.position = badge_bg.position
	badge.size = badge_bg.size
	badge.visible = false
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(badge)

	# 히트 버튼 — 칸 전체를 덮는 투명 버튼. Label / TextureRect 는 기본
	# MOUSE_FILTER_IGNORE 라 스스로 클릭을 받지 못하므로 입력만 여기서 가져간다.
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
		"bg": bg, "eye": eye, "rim": rim, "tag_bg": tag_bg, "role": role_lbl,
		"dead": dead_lbl, "bar_bg": bar_bg, "bar": bar, "score": score_lbl,
		"btn": btn, "skill_dim": skill_dim,
		"badge_bg": badge_bg, "badge": badge, "px": px,
	}


func _on_cell_pressed(idx: int) -> void:
	if idx >= _pilots.size():
		return
	pilot_pressed.emit(_pilots[idx] as PilotData)


## 이 스트립이 보여 줄 파일럿 5인. `HudBuilder` 가 레인 순으로 정렬해 넘긴다.
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
	(cell["bg"] as ColorRect).visible = on
	(cell["eye"] as TextureRect).visible = on
	(cell["rim"] as Panel).visible = on
	(cell["tag_bg"] as ColorRect).visible = on
	(cell["role"] as Label).visible = on
	(cell["bar_bg"] as ColorRect).visible = on
	(cell["bar"] as ColorRect).visible = on
	(cell["score"] as Label).visible = on
	if not on:
		(cell["dead"] as Label).visible = false
		(cell["skill_dim"] as ColorRect).visible = false
		(cell["badge_bg"] as ColorRect).visible = false
		(cell["badge"] as Label).visible = false


func _apply_cell(cell: Dictionary, p: PilotData) -> void:
	var eye := cell["eye"] as TextureRect
	eye.texture = PilotImages.eye_for(p.pilot_id)
	eye.modulate = Color.WHITE if p.alive else DEAD_TINT

	(cell["role"] as Label).text = _bs.ROLE_NAMES[p.role] \
			if p.role < _bs.ROLE_NAMES.size() else "?"

	var dead_lbl := cell["dead"] as Label
	dead_lbl.visible = not p.alive
	if not p.alive:
		dead_lbl.text = str(_bs.turns_until_return(p))

	var bar := cell["bar"] as ColorRect
	var ratio: float = 0.0
	if p.max_hp > 0:
		ratio = clampf(float(p.hp) / float(p.max_hp), 0.0, 1.0)
	bar.size = Vector2(_portrait_w * ratio, _hp_h)
	# 보호막이 붙어 있으면 노란색으로 알린다 — 바를 이어 붙이는 대신 색으로
	# 바꾸는 이유는 스트립 바가 6~10px 로 얇아 두 구간이 구분되지 않아서다.
	if p.shield > 0:
		bar.color = SHIELD_FILL
	else:
		bar.color = HP_FILL_HI if ratio >= HP_LOW_RATIO else HP_FILL_LOW

	(cell["score"] as Label).text = BattleSim.fmt_score(p.score)
	_apply_skill_state(cell, p)


## 스킬 준비도 딤과 숫자. **아군 스트립에만** 뜬다 — 스킬은 아군만 누를 수 있고,
## 적 칸까지 어둡게 덮으면 상대 얼굴이 스킬과 무관하게 흐려 보인다.
func _apply_skill_state(cell: Dictionary, p: PilotData) -> void:
	var dim := cell["skill_dim"] as ColorRect
	var badge_bg := cell["badge_bg"] as ColorRect
	var badge := cell["badge"] as Label
	var sk: PilotSkillSystem = _bs.skill if _bs != null else null
	if _team != 0 or sk == null or not sk.has_skill(p):
		dim.visible = false
		badge_bg.visible = false
		badge.visible = false
		return
	# 채움만큼 왼쪽이 밝아진다 = 딤의 왼쪽 끝을 그만큼 오른쪽으로 민다.
	var filled: float = clampf(sk.progress(p), 0.0, 1.0)
	var px: float = float(cell["px"])
	dim.visible = filled < 1.0
	dim.position = Vector2(px + _portrait_w * filled, 0.0)
	dim.size = Vector2(_portrait_w * (1.0 - filled), _portrait_h)

	var text: String = sk.badge_text(p)
	var show: bool = not text.is_empty()
	badge_bg.visible = show
	badge.visible = show
	if show:
		badge.text = text
		badge.add_theme_color_override("font_color",
				SKILL_BADGE_READY if sk.can_activate(p) else SKILL_BADGE_WAIT)
