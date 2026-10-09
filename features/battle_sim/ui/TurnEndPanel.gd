class_name TurnEndPanel
extends Control

## 턴 넘기기 판 — the wide horizontal "hold to end turn" panel that slides in from the
## left in place of the player's strategy point donut (`CostDonut` opens / closes it).
##
##  - press anywhere inside the hit zone (the panel grown by `HIT_PAD_RATIO` of its size on
##    every side) and **hold `HOLD_SEC`** → the gauge fills left → right; when full
##    `hold_completed` fires. Releasing early drains it back in `DRAIN_SEC`.
##  - disabled (`set_end_enabled(false)`) = grey, a hold does nothing.
##  - a press outside the zone → `dismissed` (the donut slides back). That press is left
##    unhandled so whatever was actually touched still reacts.
##
## Input runs in `_input` (hand cards `accept_event()`), through `PointerPress` so one
## physical tap is one press even with mouse-from-touch emulation on.
## Scene: `UI_Comp_TurnEndPanel.tscn` (look) — this script only moves it, fills the gauge
## and listens.

signal hold_completed
signal dismissed

const SCENE_PATH := "res://features/battle_sim/ui/UI_Comp_TurnEndPanel.tscn"
const HOLD_SEC := 0.5
## Full → empty after an early release.
const DRAIN_SEC := 0.15
const SLIDE_SEC := 0.24
## Hit zone = panel rect grown by this fraction of its own size on every side.
const HIT_PAD_RATIO := 0.5
## Extra room past the screen's left edge when slid out.
const OFFSCREEN_GAP := 24.0

var _plate: Control = null
var _gauge: Panel = null
var _open: bool = false
var _rest_x: float = 0.0
var _end_enabled: bool = false
var _holding: bool = false
var _fill: float = 0.0
var _slide: Tween = null


static func create() -> TurnEndPanel:
	return (load(SCENE_PATH) as PackedScene).instantiate() as TurnEndPanel


func _ready() -> void:
	_plate = %Plate as Control
	_gauge = %Gauge as Panel
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# 판 · 게이지 · 글자의 모양은 씬의 변형(`TurnEndPanelPlate` · `TurnEndGauge` · `TurnEndLabel`).
	visible = false
	set_process(false)
	_apply_fill()
	_apply_enabled()
	if UiPreview.is_standalone(self):
		_fill_preview()


## Rest spot: left edge `left_x`, vertical centre `center_y` (canvas coordinates).
func place(left_x: float, center_y: float) -> void:
	_rest_x = left_x
	position = Vector2(left_x if _open else _hidden_x(), center_y - size.y * 0.5)


func is_open() -> bool:
	return _open


func is_holding() -> bool:
	return _holding


## Gauge 0..1 (tests / debug).
func fill_ratio() -> float:
	return _fill


func slide_in() -> void:
	if _open:
		return
	_open = true
	_holding = false
	_fill = 0.0
	_apply_fill()
	visible = true
	_slide_to(_rest_x, Tween.EASE_OUT)


func slide_out() -> void:
	if not _open:
		return
	_open = false
	_holding = false
	_slide_to(_hidden_x(), Tween.EASE_IN)


func set_end_enabled(enabled: bool) -> void:
	if _end_enabled == enabled:
		return
	_end_enabled = enabled
	if not enabled:
		_holding = false
	_apply_enabled()


## The press zone in canvas coordinates — the panel plus `HIT_PAD_RATIO` of its size
## around it.
func hit_rect() -> Rect2:
	var r := get_global_rect()
	return r.grow_individual(r.size.x * HIT_PAD_RATIO, r.size.y * HIT_PAD_RATIO,
			r.size.x * HIT_PAD_RATIO, r.size.y * HIT_PAD_RATIO)


# ── Internals ────────────────────────────────────────────────────────────────

func _hidden_x() -> float:
	return -size.x - OFFSCREEN_GAP


func _slide_to(x: float, ease_kind: Tween.EaseType) -> void:
	if _slide != null and _slide.is_running():
		_slide.kill()
	_slide = create_tween()
	(_slide.tween_property(self, "position:x", x, SLIDE_SEC)
			.set_ease(ease_kind).set_trans(Tween.TRANS_CUBIC))
	if not _open:
		_slide.tween_callback(func() -> void: visible = _open)


func _apply_fill() -> void:
	if _gauge == null or _plate == null:
		return
	var inset: float = _gauge.position.x
	var full_w: float = _plate.size.x - inset * 2.0
	_gauge.size.x = full_w * _fill
	_gauge.visible = _fill > 0.001


func _apply_enabled() -> void:
	if _plate == null:
		return
	modulate = Color.WHITE if _end_enabled else BattleTheme.STRIP_DRAG_DIM


func _input(event: InputEvent) -> void:
	if not _open or not is_visible_in_tree():
		return
	var st: int = PointerPress.state(event)
	if st == PointerPress.NONE:
		return
	if st == PointerPress.RELEASE:
		if _holding:
			_holding = false
			get_viewport().set_input_as_handled()
		return
	if not hit_rect().has_point(PointerPress.position_of(event)):
		# 바깥 누름 — 판을 걷는다. 이벤트는 그대로 흘려 눌린 것이 반응하게 둔다.
		slide_out()
		dismissed.emit()
		return
	get_viewport().set_input_as_handled()
	if _end_enabled:
		_holding = true
		set_process(true)


func _process(delta: float) -> void:
	if _holding and _end_enabled:
		_fill = minf(1.0, _fill + delta / HOLD_SEC)
	else:
		_fill = maxf(0.0, _fill - delta / DRAIN_SEC)
	_apply_fill()
	if _fill >= 1.0:
		_holding = false
		_fill = 0.0
		set_process(false)
		hold_completed.emit()
		return
	if not _holding and _fill <= 0.0:
		set_process(false)


# ── F6 preview ───────────────────────────────────────────────────────────────

func _fill_preview() -> void:
	place(40.0, 400.0)
	set_end_enabled(true)
	slide_in()
	hold_completed.connect(func() -> void: print("TurnEndPanel preview: hold_completed"))
	dismissed.connect(func() -> void:
		print("TurnEndPanel preview: dismissed")
		get_tree().create_timer(0.6).timeout.connect(slide_in))
