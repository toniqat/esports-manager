class_name PhaseIntro
extends CanvasLayer

# Phase start title card (프리시즌 · 프리시즌 국제대회 · 미드시즌 …) — a dark full-screen card over
# the hub, played by `SeasonHub._maybe_phase_intro` on the first HUB of every phase (run start
# included). Fades in, holds `HOLD` seconds, fades out and frees itself, revealing the hub; a tap
# anywhere skips straight to the fade out.
#
# **Layout lives in `UI_View_PhaseIntro.tscn`** (backdrop `PhaseIntroBackdrop`, step / title /
# accent line / sub / hint). This script fills the texts and animates modulate + the line width.

signal finished

const SCENE_PATH: String = "res://features/season/calendar/UI_View_PhaseIntro.tscn"
const FADE_IN: float = 0.35
const HOLD: float = 1.8
const FADE_OUT: float = 0.4

var _line_w: float = 0.0
var _closing: bool = false


static func create() -> PhaseIntro:
	return (load(SCENE_PATH) as PackedScene).instantiate() as PhaseIntro


## Adds the card for `phase` under `host` and starts it. Returns it (connect `finished`).
static func play(host: Node, phase: int) -> PhaseIntro:
	var p := create()
	host.add_child(p)
	p.show_phase(phase)
	p.start()
	return p


func _ready() -> void:
	_line_w = (%Line as Control).custom_minimum_size.x
	%Tap.pressed.connect(close)
	_fit_safe_area()
	if UiPreview.is_standalone(self):
		_fill_preview()


func show_phase(phase: int) -> void:
	var total: int = GameEnums.SeasonPhase.size()
	%Step.text = Loc.t(L.SEASON_PHASE_INTRO_STEP, {"n": phase + 1, "total": total})
	%Title.text = GameEnums.phase_label(phase)
	var league: int = int(CalendarSystem.LEAGUE_WEEKS.get(phase, 0))
	var weeks: int = int(CalendarSystem.PHASE_WEEKS.get(phase, 1))
	if league > 0:
		%Sub.text = Loc.t(L.SEASON_PHASE_INTRO_LEAGUE, {"league": league, "playoff": maxi(0, weeks - league)})
	else:
		%Sub.text = Loc.t(L.SEASON_PHASE_INTRO_INTL, {"weeks": weeks})


func start() -> void:
	var root: Control = %Root
	var center: Control = %Center
	var line: Control = %Line
	root.modulate.a = 0.0
	center.modulate.a = 0.0
	line.custom_minimum_size.x = 0.0
	var t := create_tween()
	t.tween_property(root, ^"modulate:a", 1.0, FADE_IN)
	t.tween_property(center, ^"modulate:a", 1.0, FADE_IN)
	t.parallel().tween_property(line, ^"custom_minimum_size:x", _line_w, FADE_IN * 2.0) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	t.tween_interval(HOLD)
	t.tween_callback(close)


## Fades out and frees (a tap skips here directly).
func close() -> void:
	if _closing:
		return
	_closing = true
	(%Tap as Button).disabled = true
	var t := create_tween()
	t.tween_property(%Root, ^"modulate:a", 0.0, FADE_OUT)
	t.tween_callback(_done)


func _done() -> void:
	finished.emit()
	queue_free()


func _fit_safe_area() -> void:
	(%Hint as Control).offset_top = -200.0 - OutgameTheme.bottom_inset()
	(%Hint as Control).offset_bottom = -150.0 - OutgameTheme.bottom_inset()


## F6 단독 실행 미리보기 — 미드시즌 카드를 멈춘 채(페이드 없이) 보여 준다.
func _fill_preview() -> void:
	show_phase(GameEnums.SeasonPhase.MIDSEASON)
	UiPreview.trace(finished, "finished")
