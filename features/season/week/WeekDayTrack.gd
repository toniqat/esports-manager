class_name WeekDayTrack
extends Control

# The week screen's day progress bar (`%DayTrack` in `UI_View_WeekProgressView.tscn`): a thin
# horizontal line with seven circles (Mon → Sun) at the centres of seven equal cells — the
# weekday labels of `%DayAbbrs` (an HBox of the same width, seven equal cells) sit under them.
# The line fills left → right up to `progress` (a circle index; fractions = between two
# circles), the circles up to it are filled, today's circle (`today`) is drawn larger with a
# white core. `WeekProgressView` tweens `progress` from the last shown day to today.
# A `_draw` widget placed as a node; the scene owns its rect.

const DAYS: int = 7
## Line thickness, circle radius, today's circle radius and its white core.
const LINE_W: float = 6.0
const DOT_R: float = 13.0
const TODAY_R: float = 18.0
const CORE_R: float = 7.0
const RING_W: float = 3.0

## Filled up to this circle index (0 = Monday … 6 = Sunday; -1 = nothing).
@export var progress: float = 0.0:
	set(v):
		progress = v
		queue_redraw()

## Today's circle (-1 = none).
@export var today: int = 0:
	set(v):
		today = v
		queue_redraw()

@export var track_color: Color = OutgameTheme.BORDER
@export var fill_color: Color = OutgameTheme.ACCENT


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()


## x of circle `i` (the centre of cell `i` of seven equal cells).
func dot_x(i: int) -> float:
	return (float(i) + 0.5) * size.x / float(DAYS)


func _draw() -> void:
	if size.x <= 0.0:
		return
	var y: float = size.y * 0.5
	var x0: float = dot_x(0)
	var x6: float = dot_x(DAYS - 1)
	draw_line(Vector2(x0, y), Vector2(x6, y), track_color, LINE_W, true)
	if progress >= 0.0:
		var xf: float = lerpf(x0, x6, clampf(progress / float(DAYS - 1), 0.0, 1.0))
		draw_line(Vector2(x0, y), Vector2(xf, y), fill_color, LINE_W, true)
	for i in DAYS:
		var c := Vector2(dot_x(i), y)
		var reached: bool = float(i) <= progress + 0.001
		if i == today:
			draw_circle(c, TODAY_R, fill_color if reached else OutgameTheme.SURFACE)
			draw_arc(c, TODAY_R - RING_W * 0.5, 0.0, TAU, 48, fill_color, RING_W, true)
			draw_circle(c, CORE_R, OutgameTheme.TEXT_ON_FILL)
		elif reached:
			draw_circle(c, DOT_R, fill_color)
		else:
			draw_circle(c, DOT_R, OutgameTheme.SURFACE)
			draw_arc(c, DOT_R - RING_W * 0.5, 0.0, TAU, 40, track_color, RING_W, true)
