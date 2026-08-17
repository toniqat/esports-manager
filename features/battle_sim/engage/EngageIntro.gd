class_name EngageIntro
extends Control

# 전투 개시 카드를 **제출한 순간** 뜨는 VS 화면.
#
# 예전에는 이 명단이 카드를 **고른** 순간 화면 좌/우에 뜨는 두 개의 세로 패널
# (`CardTargetingOverlay` 의 PREVIEW 팀 패널)이었다. 두 가지가 그 자리를 못 버티게
# 했다:
#   1. **시점이 틀렸다.** 카드를 집기만 해도 명단이 떴으므로, 아직 낼지 말지도
#      정하지 않은 상태에서 화면 절반이 표로 덮였다. 정작 명단이 궁금해지는
#      순간은 카드를 낸 **직후**, 즉 "이제 누가 싸우는가"가 확정된 시점이다.
#   2. **좌/우 세로 패널은 진영을 말하지 않는다.** 세로 스크롤 목록 두 개가
#      나란히 선 모양은 어느 쪽이 내 팀인지를 위치로 알려 주지 못한다. 상단 =
#      적, 하단 = 아군은 전장 화면(`ui/PilotStrip.gd`)이 이미 쓰는 규칙이라
#      배울 것이 없다.
#
# 지금 구성은 딤드된 전체 화면 위에:
#     [적군 헤더]  eye 초상화 ×N   ← 상단
#            VS  /  N라운드        ← 중앙
#     [아군 헤더]  eye 초상화 ×N   ← 하단
#              취소 / 확인          ← 아군 줄 아래
# 초상화는 전장 스트립과 같은 **eye 크롭**(480×200, 가로 밴드)이고, 그 아래에
# 체력 바 + `hp / max` 숫자가 붙는다.
#
# **취소는 카드 제출 자체를 무른다.** `CardPhaseManager._effect_engage` 가
# `_on_overlay_cancel` 로 스냅샷을 복원하므로 비용도 카드도 그대로 돌아온다 —
# 버리기 / 찾기 오버레이의 취소와 같은 경로다. AI 가 낸 카드에는 무를 주체가
# 없으므로 `allow_cancel = false` 로 열려 확인 버튼만 뜬다.

## 확인(true) / 취소(false). 버튼을 누른 프레임에 한 번만 발화한다.
signal decided(confirmed: bool)

const DIM_COLOR := Color(0.0, 0.0, 0.0, 0.88)

## 화면 크기는 `EngageArena` 와 같은 방식으로 **절대 좌표로 박는다** — CanvasLayer
## 밑의 Control 은 PRESET_FULL_RECT 만으로 사이즈가 잡히지 않아 (0,0) 으로 남고,
## 그러면 딤이 안 그려지고 MOUSE_FILTER_STOP 도 뒤쪽 입력을 못 막는다.
const VP_W: float = 1080.0
const VP_H: float = 1920.0

## eye 크롭의 가로:세로 비 — `PilotStrip.EYE_ASPECT` 와 같은 값이다. 임의 높이로
## 늘리면 얼굴이 찌그러진다.
const EYE_ASPECT: float = 2.4

const CELL_W: float      = 186.0
const CELL_GAP: float    = 14.0
const HP_BAR_H: float    = 10.0
const HP_BAR_GAP: float  = 6.0
const HP_TEXT_H: float   = 24.0

## 세로 앵커. 상단 = 적, 하단 = 아군.
const ENEMY_HEADER_Y: float = 330.0
const ENEMY_ROW_Y: float    = 380.0
const VS_Y: float           = 760.0
const ROUNDS_Y: float       = 900.0
const ALLY_HEADER_Y: float  = 1140.0
const ALLY_ROW_Y: float     = 1190.0
const BTN_Y: float          = 1470.0
const BTN_W: float          = 240.0
const BTN_H: float          = 76.0
const BTN_GAP: float        = 32.0

const TEAM_RIM := [Color(0.32, 0.62, 0.95), Color(0.95, 0.40, 0.32)]
const HP_FILL_HI  := Color(0.30, 0.85, 0.45)
const HP_FILL_LOW := Color(0.90, 0.55, 0.25)
const HP_BG       := Color(0.08, 0.09, 0.13)
const SHIELD_FILL := Color(0.85, 0.85, 0.30)
const HP_LOW_RATIO: float = 0.30

## 등장 연출 — 두 줄이 각자 바깥(적은 위, 아군은 아래)에서 밀려 들어온다.
const SLIDE_PX: float  = 70.0
const SLIDE_SEC: float = 0.22

var _decided: bool = false


func _ready() -> void:
	# 모달이다 — 뒤의 전장 / 손패로 클릭이 새 나가면 안 된다.
	mouse_filter = Control.MOUSE_FILTER_STOP
	# 앵커는 **건드리지 않는다**(기본값 = 네 모서리 모두 0). CanvasLayer 밑의
	# Control 에 `PRESET_FULL_RECT` 를 걸면 마주 보는 앵커가 서로 달라져
	# "size will be overridden after _ready()" 경고와 함께 여기서 쓴 크기가
	# 레이아웃 패스에 덮인다 — 부모가 rect 를 주지 않으므로 결과는 0×0 이고,
	# 그러면 딤도 안 그려지고 MOUSE_FILTER_STOP 도 뒤쪽 입력을 못 막는다.
	# 앵커가 전부 0 이면 아래 두 줄이 그대로 남는다.
	position = Vector2.ZERO
	size = Vector2(VP_W, VP_H)


## `t0` = 팀0(아군) 참가자, `t1` = 팀1(적군) 참가자. `rounds` 는 engage:N 의 N
## 그대로(라운드 수). `allow_cancel` 이 false 면 확인 버튼만 놓는다.
##
## `BattleSim` 핸들을 받지 않는다 — 이 화면이 읽는 것은 `PilotData` 의 hp /
## max_hp / shield / role / pilot_id 뿐이고, 그 전부가 인자로 들어온다.
func setup(title: String, rounds: int,
		t0: Array, t1: Array, allow_cancel: bool) -> void:
	var dim := ColorRect.new()
	dim.color = DIM_COLOR
	dim.position = Vector2.ZERO
	dim.size = Vector2(VP_W, VP_H)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)

	_build_title(title)
	_build_center(rounds)
	var enemy_row := _build_row(t1, 1, "적군", ENEMY_HEADER_Y, ENEMY_ROW_Y)
	var ally_row  := _build_row(t0, 0, "아군", ALLY_HEADER_Y, ALLY_ROW_Y)
	_build_buttons(allow_cancel)
	_play_intro(enemy_row, ally_row)


# ─── 구성 ────────────────────────────────────────────────────────────────────
func _build_title(text: String) -> void:
	var lbl := _mk_label(text, 40, Color(1.0, 0.92, 0.62))
	lbl.position = Vector2(0.0, 220.0)
	lbl.size = Vector2(VP_W, 56.0)
	add_child(lbl)


func _build_center(rounds: int) -> void:
	var vs := _mk_label("VS", 148, Color(1.0, 0.96, 0.86))
	vs.position = Vector2(0.0, VS_Y)
	vs.size = Vector2(VP_W, 170.0)
	add_child(vs)

	var rd := _mk_label("%d라운드" % rounds, 46, Color(0.95, 0.80, 0.42))
	rd.position = Vector2(0.0, ROUNDS_Y)
	rd.size = Vector2(VP_W, 60.0)
	add_child(rd)


## 한 팀의 참가자 줄. 반환한 Control 하나만 움직이면 줄 전체가 함께 움직이므로
## 등장 연출이 자식 수와 무관하다.
func _build_row(pilots: Array, team: int, header: String,
		header_y: float, row_y: float) -> Control:
	var sorted: Array = pilots.duplicate()
	sorted.sort_custom(func(a: PilotData, b: PilotData) -> bool:
		return (a as PilotData).role < (b as PilotData).role)

	var row := Control.new()
	row.position = Vector2.ZERO
	row.size = Vector2(VP_W, VP_H)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(row)

	var head := _mk_label("%s (%d)" % [header, sorted.size()], 30, TEAM_RIM[team])
	head.position = Vector2(0.0, header_y)
	head.size = Vector2(VP_W, 40.0)
	row.add_child(head)

	var n: int = sorted.size()
	if n == 0:
		return row
	var span: float = float(n) * CELL_W + float(n - 1) * CELL_GAP
	var first_x: float = (VP_W - span) * 0.5
	for i in n:
		_build_cell(row, sorted[i] as PilotData, team,
				Vector2(first_x + float(i) * (CELL_W + CELL_GAP), row_y))
	return row


## eye 초상화 → 체력 바 → `hp / max` 숫자. 전장 하단 스트립과 같은 세 줄 순서다.
func _build_cell(parent: Control, p: PilotData, team: int, at: Vector2) -> void:
	var portrait_h: float = CELL_W / EYE_ASPECT

	# 초상화 뒤판 — eye 이미지가 없을 때(단독 실행 / INTL) 그대로 보이는 폴백.
	var bg := ColorRect.new()
	bg.position = at
	bg.size = Vector2(CELL_W, portrait_h)
	bg.color = Color(0.12, 0.13, 0.19)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(bg)

	var eye := TextureRect.new()
	eye.position = at
	eye.size = Vector2(CELL_W, portrait_h)
	eye.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	eye.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	eye.texture = PilotImages.eye_for(p.pilot_id)
	eye.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(eye)

	var rim := Panel.new()
	rim.position = at
	rim.size = Vector2(CELL_W, portrait_h)
	rim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var rim_sb := StyleBoxFlat.new()
	rim_sb.bg_color = Color(0, 0, 0, 0)
	rim_sb.border_color = TEAM_RIM[team]
	rim_sb.border_width_top    = 3
	rim_sb.border_width_bottom = 3
	rim_sb.border_width_left   = 3
	rim_sb.border_width_right  = 3
	rim.add_theme_stylebox_override("panel", rim_sb)
	parent.add_child(rim)

	# 체력 바는 **ColorRect 두 장**이다 — ProgressBar 는 테마 컨텐트 마진에서
	# 최소 크기를 계산해 지정한 얇은 높이를 지키지 않는다(모듈 README 참고).
	var bar_y: float = at.y + portrait_h + HP_BAR_GAP
	var ratio: float = 0.0
	if p.max_hp > 0:
		ratio = clampf(float(p.hp) / float(p.max_hp), 0.0, 1.0)

	var bar_bg := ColorRect.new()
	bar_bg.position = Vector2(at.x, bar_y)
	bar_bg.size = Vector2(CELL_W, HP_BAR_H)
	bar_bg.color = HP_BG
	bar_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(bar_bg)

	var bar := ColorRect.new()
	bar.position = Vector2(at.x, bar_y)
	bar.size = Vector2(CELL_W * ratio, HP_BAR_H)
	# 보호막이 붙어 있으면 노란색으로 알린다 — 바가 얇아 두 구간을 이어 붙이면
	# 구분이 안 되므로 색으로 바꾼다(전장 스트립과 같은 규칙).
	if p.shield > 0:
		bar.color = SHIELD_FILL
	else:
		bar.color = HP_FILL_HI if ratio >= HP_LOW_RATIO else HP_FILL_LOW
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(bar)

	var hp_lbl := _mk_label("%d / %d" % [p.hp, p.max_hp], 22,
			Color(0.94, 0.94, 0.94))
	hp_lbl.position = Vector2(at.x, bar_y + HP_BAR_H + 2.0)
	hp_lbl.size = Vector2(CELL_W, HP_TEXT_H)
	parent.add_child(hp_lbl)


func _build_buttons(allow_cancel: bool) -> void:
	var confirm := _mk_button("확인", Color(0.22, 0.52, 0.34))
	if allow_cancel:
		var cancel := _mk_button("취소", Color(0.36, 0.20, 0.22))
		cancel.position = Vector2(VP_W * 0.5 - BTN_W - BTN_GAP * 0.5, BTN_Y)
		cancel.pressed.connect(func() -> void: _decide(false))
		add_child(cancel)
		confirm.position = Vector2(VP_W * 0.5 + BTN_GAP * 0.5, BTN_Y)
	else:
		confirm.position = Vector2((VP_W - BTN_W) * 0.5, BTN_Y)
	confirm.pressed.connect(func() -> void: _decide(true))
	add_child(confirm)


func _decide(confirmed: bool) -> void:
	# 두 버튼을 같은 프레임에 두 번 누르는 경로는 없지만, 한 번만 발화한다는
	# 계약이 있어야 호출 측이 await 한 번으로 끝낼 수 있다.
	if _decided:
		return
	_decided = true
	decided.emit(confirmed)


## 두 줄이 바깥에서 밀려 들어오며 나타난다. 버튼은 처음부터 눌린다 — 연출이
## 입력을 붙잡으면 반복 관전이 느려진다.
func _play_intro(enemy_row: Control, ally_row: Control) -> void:
	enemy_row.position.y = -SLIDE_PX
	ally_row.position.y = SLIDE_PX
	enemy_row.modulate.a = 0.0
	ally_row.modulate.a = 0.0
	var tw := create_tween().set_parallel() \
			.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(enemy_row, "position:y", 0.0, SLIDE_SEC)
	tw.tween_property(ally_row, "position:y", 0.0, SLIDE_SEC)
	tw.tween_property(enemy_row, "modulate:a", 1.0, SLIDE_SEC)
	tw.tween_property(ally_row, "modulate:a", 1.0, SLIDE_SEC)


# ─── 위젯 헬퍼 ───────────────────────────────────────────────────────────────
func _mk_label(text: String, font_size: int, color: Color) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	# 오른쪽/가운데 정렬 Label 은 글자가 rect 보다 넓으면 정렬을 포기하고 rect
	# 왼쪽부터 그려 밖으로 넘친다 — clip_text 가 그것을 막는다.
	lbl.clip_text = true
	lbl.add_theme_font_size_override("font_size", font_size)
	lbl.add_theme_color_override("font_color", color)
	lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	lbl.add_theme_constant_override("outline_size", 6)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return lbl


func _mk_button(text: String, tint: Color) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.size = Vector2(BTN_W, BTN_H)
	btn.focus_mode = Control.FOCUS_NONE
	btn.add_theme_font_size_override("font_size", 30)
	var sb := StyleBoxFlat.new()
	sb.bg_color = tint
	sb.border_color = Color(1, 1, 1, 0.35)
	sb.border_width_top    = 2
	sb.border_width_bottom = 2
	sb.border_width_left   = 2
	sb.border_width_right  = 2
	sb.corner_radius_top_left     = 10
	sb.corner_radius_top_right    = 10
	sb.corner_radius_bottom_left  = 10
	sb.corner_radius_bottom_right = 10
	btn.add_theme_stylebox_override("normal", sb)
	var hover := sb.duplicate() as StyleBoxFlat
	hover.bg_color = tint.lightened(0.16)
	btn.add_theme_stylebox_override("hover", hover)
	var pressed := sb.duplicate() as StyleBoxFlat
	pressed.bg_color = tint.darkened(0.18)
	btn.add_theme_stylebox_override("pressed", pressed)
	return btn
