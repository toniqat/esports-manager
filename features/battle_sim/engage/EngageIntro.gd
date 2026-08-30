class_name EngageIntro
extends Control

# 전투 개시 카드를 **제출한 순간** 뜨는 VS 화면.
#
# **이 화면은 교전 무대를 그대로 미리 보여 준다.** `EngageArena` 를 미리보기
# 모드로 한 장 띄우고(제목 · 라운드 칸 · 무대 · 하단 정사각 썸네일 스트립이
# 전부 실제 교전과 같은 자리에 있다) 그 아래에 확인 / 취소만 얹는다. 무대는
# 이미 **시작 위치까지 잡혀 있는** 진짜 시뮬레이터(`TurnEngageSim`)이고,
# 확인을 누르면 `EngagePhaseManager._begin` 이 그 무대를 그대로 이어받는다 —
# 화면에서 본 배치와 실제로 싸우는 배치가 같아야 이 화면이 "명단 확인"이
# 아니라 **판단**이 된다. 위 타일에 둘 · 아래 타일에 둘 · 왼쪽 정글에 정글러
# 하나가 서 있는 그림을 보고 이 교전을 열지 말지를 고르는 것이 요점이다.
#
# 예전에는 여기에 eye 초상화 두 줄(상단 = 적, 하단 = 아군)과 큰 VS 글자만
# 있었다. 명단은 알려 주었지만 **어디에 서 있는가**는 한 글자도 말하지 않아,
# 무대가 열리고 나서야 진형을 알 수 있었다. 그보다 더 예전에는 카드를 **고른**
# 순간 화면 좌/우에 뜨는 세로 팀 패널 두 개였고(`CardTargetingOverlay` 의
# PREVIEW), 그건 아직 낼지도 정하지 않은 카드에 화면 절반을 덮었다.
#
# **취소는 카드 제출 자체를 무른다.** `CardPhaseManager._effect_engage` 가
# `_on_overlay_cancel` 로 스냅샷을 복원하므로 비용도 카드도 그대로 돌아온다 —
# 버리기 / 찾기 오버레이의 취소와 같은 경로다. AI 가 낸 카드는 플레이어가 무를
# 수 있는 것이 아니므로 `allow_cancel = false` 로 열려 확인 버튼만 뜬다.

## 확인(true) / 취소(false). 버튼을 누른 프레임에 한 번만 발화한다.
signal decided(confirmed: bool)

## 세로 앵커는 전부 아레나의 스트립 밑단에서 역산한다 — 아레나 쪽 상수가
## 움직이면 이 화면의 버튼도 함께 따라와야 두 화면이 같은 그림으로 남는다.
const SUBTITLE_Y: float = EngageArena.STRIP_BOTTOM + 10.0
const BTN_Y: float      = EngageArena.STRIP_BOTTOM + 60.0
const BTN_W: float      = 240.0
const BTN_H: float      = 76.0
const BTN_GAP: float    = 32.0

## 등장 연출 — 무대가 살짝 떠오르며 나타난다. 예전의 "두 줄이 위아래에서 밀려
## 들어온다"는 줄이 사라지면서 함께 사라졌다.
const FADE_SEC: float = 0.20
const RISE_PX: float  = 34.0

var _decided: bool = false
var _arena: EngageArena = null


func _ready() -> void:
	# 모달이다 — 뒤의 전장 / 손패로 클릭이 새 나가면 안 된다.
	mouse_filter = Control.MOUSE_FILTER_STOP
	# 앵커는 **건드리지 않는다**(기본값 = 네 모서리 모두 0). CanvasLayer 밑의
	# Control 에 `PRESET_FULL_RECT` 를 걸면 마주 보는 앵커가 서로 달라져
	# "size will be overridden after _ready()" 경고와 함께 여기서 쓴 크기가
	# 레이아웃 패스에 덮인다 — 부모가 rect 를 주지 않으므로 결과는 0×0 이고,
	# 그러면 MOUSE_FILTER_STOP 도 뒤쪽 입력을 못 막는다.
	position = Vector2.ZERO
	size = Vector2(ScreenMetrics.vp_w(), ScreenMetrics.vp_h())


## `sim` 은 **이미 자리가 잡힌** 교전 무대다(`EngagePhaseManager.prepare_sim`).
## 아직 `begin()` 전이므로 이 화면이 떠 있는 동안 피해도 충전 소모도 일어나지
## 않는다 — 취소가 진짜로 아무 일도 없던 것이 되는 근거다.
##
## `confirm_text` / `cancel_text` 는 오브젝트 교전(전령 / 용)이 같은 화면을
## **참여 / 미참여** 결정 창으로 재사용하기 위한 것이다. 결정의 모양은 카드
## 교전과 같다 — 무대를 보고 두 갈래 중 하나를 고른다 — 이므로 화면을 새로
## 만들 이유가 없다. `subtitle` 은 버튼 위 한 줄(보상 안내)이다.
func setup(bs: BattleSim, sim: TurnEngageSim, title: String,
		allow_cancel: bool, confirm_text: String = "확인",
		cancel_text: String = "취소", subtitle: String = "") -> void:
	# 딤도 제목도 라운드 칸도 아레나가 들고 있다 — 여기서 또 깔면 두 겹이 된다.
	_arena = EngageArena.new()
	_arena.name = "PreviewArena"
	add_child(_arena)
	_arena.setup(bs, sim, title, sim != null and sim.is_duel, true)
	_arena.set_hint("시작 위치 — 이대로 교전을 시작한다" if allow_cancel
			else "시작 위치")

	if not subtitle.is_empty():
		_build_subtitle(subtitle)
	_build_buttons(allow_cancel, confirm_text, cancel_text)
	_play_intro()


# ─── 구성 ────────────────────────────────────────────────────────────────────
## 버튼 바로 위 한 줄. 오브젝트 교전이 보상을 알리는 자리다.
func _build_subtitle(text: String) -> void:
	var lbl := _mk_label(text, 30, Color(0.80, 0.86, 0.95))
	lbl.position = Vector2(0.0, SUBTITLE_Y)
	lbl.size = Vector2(ScreenMetrics.vp_w(), 42.0)
	add_child(lbl)


func _build_buttons(allow_cancel: bool, confirm_text: String = "확인",
		cancel_text: String = "취소") -> void:
	var confirm := _mk_button(confirm_text, Color(0.22, 0.52, 0.34))
	if allow_cancel:
		var cancel := _mk_button(cancel_text, Color(0.36, 0.20, 0.22))
		cancel.position = Vector2(ScreenMetrics.vp_w() * 0.5 - BTN_W - BTN_GAP * 0.5, BTN_Y)
		cancel.pressed.connect(func() -> void: _decide(false))
		add_child(cancel)
		confirm.position = Vector2(ScreenMetrics.vp_w() * 0.5 + BTN_GAP * 0.5, BTN_Y)
	else:
		confirm.position = Vector2((ScreenMetrics.vp_w() - BTN_W) * 0.5, BTN_Y)
	confirm.pressed.connect(func() -> void: _decide(true))
	# 교전 / 오브젝트 참여를 여는 커밋. 취소는 기본값(LIGHT) 그대로 — 무른
	# 것은 아무 일도 안 일어난 것이다.
	HapticUi.kind(confirm, Haptics.Kind.MEDIUM)
	add_child(confirm)


func _decide(confirmed: bool) -> void:
	# 두 버튼을 같은 프레임에 두 번 누르는 경로는 없지만, 한 번만 발화한다는
	# 계약이 있어야 호출 측이 await 한 번으로 끝낼 수 있다.
	if _decided:
		return
	_decided = true
	decided.emit(confirmed)


## 무대가 살짝 떠오르며 나타난다. 버튼은 처음부터 눌린다 — 연출이 입력을
## 붙잡으면 반복 관전이 느려진다.
func _play_intro() -> void:
	if _arena == null:
		return
	_arena.position.y = RISE_PX
	_arena.modulate.a = 0.0
	var tw := create_tween().set_parallel() \
			.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(_arena, "position:y", 0.0, FADE_SEC)
	tw.tween_property(_arena, "modulate:a", 1.0, FADE_SEC)


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
