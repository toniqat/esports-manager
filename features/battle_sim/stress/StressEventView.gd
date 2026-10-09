class_name StressEventView
extends CanvasLayer

# 스트레스 시험 연출 한 장 — 다키스트 던전의 "결의 시험" 처럼 경기를 멈추고 보여 준다.
#   1. 중앙 상단 토스트 "{이름}이 시험받고 있습니다..."
#   2. 딤이 짙어지며 그 파일럿 전신 일러스트가 떠오른다
#   3. 결과(각성 / 패닉)가 뜬다 → `revealed` (이때 능력치가 바뀐다)
#   4. 잠깐 뒤 화면을 누르면 `closed`
#
# **레이아웃의 정본은 `UI_View_StressEvent.tscn` 이다.** 스크립트는 `%이름` 노드에 글 · 그림을
# 넣고 연출 순서만 돈다. 색은 `Root` 의 전투 테마 변형(`StressEvent*Label`, `BattleTheme._add_stress_variations`).
# 코드가 정하는 것: 안전 영역, 결과 글자 변형(각성 / 패닉), 전신 크기(그림 비율), 연출 시간.
#
# 쓰는 법 (`StressEvents._pump`):
#   var v := StressEventView.create()
#   add_child(v)
#   v.revealed.connect(...); v.closed.connect(...)
#   v.open(name, portrait_id, mood)

signal revealed
signal closed

const SCENE_PATH: String = "res://features/battle_sim/stress/UI_View_StressEvent.tscn"

## 연출 시간(s) — 토스트만 보이는 구간 · 전신이 떠오르는 구간 · 결과 뒤 탭을 받기까지.
const TOAST_SEC := 1.3
const ART_SEC := 0.9
const TAP_ARM_SEC := 0.6
const FADE_SEC := 0.3
## 전신이 떠오르는 거리(px) · 패닉 흔들림 폭(px) · 각성 결과 글자 튀어나옴 배율.
const ART_RISE := 60.0
const PANIC_SHAKE := 18.0
const RESULT_POP := 1.25
## 전신 최대 크기(디자인 px). 그림이 없으면 전신 자리는 비운다.
const ART_MAX_H := 1100.0
const ART_MAX_W := 900.0

var _art_tex: Texture2D = null
var _mood: int = StressSystem.Mood.NONE
var _armed: bool = false
var _closing: bool = false


## 씬을 인스턴스한다. `StressEventView.new()` 는 빈 CanvasLayer 라 쓰지 않는다.
static func create() -> StressEventView:
	return (load(SCENE_PATH) as PackedScene).instantiate() as StressEventView


## 결과 글자 변형 — 각성 = 금색, 패닉 = 빨강.
static func mood_variation(mood: int) -> StringName:
	return &"StressEventAwakenLabel" if mood == StressSystem.Mood.AWAKEN else &"StressEventPanicLabel"


func _ready() -> void:
	$Root.gui_input.connect(_on_root_input)
	%ArtArea.resized.connect(_layout_art)
	if UiPreview.is_standalone(self):
		_fill_preview()


## 연출을 시작한다. `mood` = `StressSystem.Mood.AWAKEN` / `PANIC`.
func open(pilot_name: String, portrait_id: int, mood: int) -> void:
	_mood = mood
	_fit_safe_area()
	%ToastText.text = Loc.t(L.BATTLE_STRESS_TOAST, {"name": pilot_name})
	_art_tex = PilotImages.full_for(portrait_id)
	%Art.texture = _art_tex
	%Art.visible = _art_tex != null
	_layout_art()
	var awaken: bool = mood == StressSystem.Mood.AWAKEN
	%Result.text = StressSystem.mood_label(mood)
	%Result.theme_type_variation = mood_variation(mood)
	%Effect.text = Loc.t(L.BATTLE_STRESS_EFFECT_AWAKEN if awaken else L.BATTLE_STRESS_EFFECT_PANIC)
	# 딤 위에 바로 서는 줄 — 외곽선 두른 밝은 변형.
	%Effect.theme_type_variation = &"BattleOutlinedPositiveLabel" if awaken else &"BattleOutlinedNegativeLabel"

	# 처음엔 토스트만 — 딤 · 전신 · 결과는 숨겨 둔다.
	var dim: Control = %Dim
	var toast: Control = %Toast
	var holder: Control = %ArtHolder
	var result_box: Control = %ResultBox
	dim.modulate.a = 0.0
	toast.modulate.a = 0.0
	holder.modulate.a = 0.0
	holder.position.y = ART_RISE
	result_box.modulate.a = 0.0
	%Hint.modulate.a = 0.0

	var tw := create_tween()
	tw.tween_property(toast, "modulate:a", 1.0, FADE_SEC)
	tw.parallel().tween_property(dim, "modulate:a", 0.5, FADE_SEC)
	tw.tween_interval(TOAST_SEC)
	tw.tween_property(dim, "modulate:a", 1.0, FADE_SEC)
	tw.parallel().tween_property(holder, "modulate:a", 1.0, ART_SEC)
	tw.parallel().tween_property(holder, "position:y", 0.0, ART_SEC) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_callback(_reveal)


## 결과를 보여 준다 — 능력치는 이 순간 바뀐다(`revealed`).
func _reveal() -> void:
	var awaken: bool = _mood == StressSystem.Mood.AWAKEN
	Haptics.play(Haptics.Kind.SUCCESS if awaken else Haptics.Kind.ERROR)
	var result_box: Control = %ResultBox
	result_box.pivot_offset = result_box.size * 0.5
	result_box.scale = Vector2.ONE * RESULT_POP
	var tw := create_tween().set_parallel(true)
	tw.tween_property(result_box, "modulate:a", 1.0, FADE_SEC)
	tw.tween_property(result_box, "scale", Vector2.ONE, FADE_SEC * 1.5) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	if not awaken:
		# 패닉 — 전신이 좌우로 떤다.
		var art: Control = %Art
		var x0: float = art.position.x
		var shake := create_tween()
		for i in 4:
			var dx: float = PANIC_SHAKE if i % 2 == 0 else -PANIC_SHAKE
			shake.tween_property(art, "position:x", x0 + dx, 0.05)
		shake.tween_property(art, "position:x", x0, 0.05)
	revealed.emit()
	get_tree().create_timer(TAP_ARM_SEC).timeout.connect(_arm)


func _arm() -> void:
	_armed = true
	create_tween().tween_property(%Hint, "modulate:a", 1.0, FADE_SEC)


## 닫는다(한 번만). 탭 · 헤드리스 검증이 같은 길을 탄다.
func close() -> void:
	if _closing:
		return
	_closing = true
	closed.emit()


func _fit_safe_area() -> void:
	var safe: Control = %SafeArea
	safe.offset_top = ScreenMetrics.top_y()
	safe.offset_bottom = ScreenMetrics.bottom_y() - ScreenMetrics.viewport_size().y


## 전신은 칸 아래 가운데에 그림 비율대로(`ART_MAX_*` 를 넘지 않게).
func _layout_art() -> void:
	if _art_tex == null or _art_tex.get_size().y <= 0.0:
		return
	var area: Control = %ArtArea
	var aspect: float = _art_tex.get_size().x / _art_tex.get_size().y
	var h: float = minf(ART_MAX_H, area.size.y)
	var w: float = minf(ART_MAX_W, h * aspect)
	h = w / aspect
	var art: Control = %Art
	art.offset_left = -w * 0.5
	art.offset_right = w * 0.5
	art.offset_top = -h
	art.offset_bottom = 0.0


func _on_root_input(event: InputEvent) -> void:
	if not _armed:
		return
	var tapped: bool = (event is InputEventMouseButton
			and (event as InputEventMouseButton).pressed) \
			or (event is InputEventScreenTouch and (event as InputEventScreenTouch).pressed)
	if tapped:
		close()


## F6 단독 실행 미리보기 — 그림 있는 0번 파일럿, 패닉. 이름은 미리보기 글자.
func _fill_preview() -> void:  # l10n-ignore
	UiPreview.trace(closed)
	open("미리보기 선수", 0, StressSystem.Mood.PANIC)
