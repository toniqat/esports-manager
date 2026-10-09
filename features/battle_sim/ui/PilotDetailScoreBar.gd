class_name PilotDetailScoreBar
extends Control

# Growth-points progress bar in the pilot detail "score" info plate
# (`UI_Comp_PilotDetailInfoMenu.tscn` `%ScoreBar`, shown only for that plate).
#
#   0 ─────■■■■■■■■■■■■──────┬──────┬──────┬──────┬ 50k
#          fill = score / max  ticks every spike step (reached = gold, else dim)
#
# A `_draw` widget placed as a node: the scene owns its place / height, `setup` feeds the
# numbers (`PilotDetailPanel._build_menu_content`). Defaults draw a sample bar, so the
# scene previews on its own.

const TRACK_H: float = 14.0
const TRACK_Y: float = 12.0
const TICK_R: float = 7.0
const LABEL_FONT: int = BattleTheme.FONT_SMALL
const LABEL_GAP: float = 8.0

var _score: float = 23.4
var _step: float = 10.0
var _max: float = 50.0


func setup(score: float, step: float, max_score: float) -> void:
	_score = score
	_step = step
	_max = maxf(0.001, max_score)
	queue_redraw()


func _draw() -> void:
	var w: float = size.x
	var track := Rect2(0.0, TRACK_Y, w, TRACK_H)
	draw_style_box(_bar_box(BattleTheme.DESC_CHIP_BG), track)
	var fill_w: float = w * clampf(_score / _max, 0.0, 1.0)
	if fill_w > 1.0:
		draw_style_box(_bar_box(BattleTheme.DESC_GROWTH), Rect2(0.0, TRACK_Y, fill_w, TRACK_H))
	var font: Font = get_theme_default_font()
	var cy: float = TRACK_Y + TRACK_H * 0.5
	_draw_label(font, "0", 0.0, w)
	if _step <= 0.0:
		return
	var n: int = int(floor(_max / _step + 0.000001))
	for i in range(1, n + 1):
		var v: float = _step * float(i)
		var x: float = w * v / _max
		var reached: bool = _score + 0.000001 >= v
		var col: Color = BattleTheme.DESC_GOLD if reached else BattleTheme.DESC_KEY
		# Dim ticks get a dark core so they read as "not yet".
		draw_circle(Vector2(x, cy), TICK_R, col)
		if not reached:
			draw_circle(Vector2(x, cy), TICK_R - 3.0, BattleTheme.DESC_BG)
		_draw_label(font, "%dk" % roundi(v), x, w, col)


## Label centred under `x`, kept inside the bar.
func _draw_label(font: Font, text: String, x: float, w: float,
		col: Color = BattleTheme.DESC_KEY) -> void:
	var tw: float = font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_FONT).x
	var lx: float = clampf(x - tw * 0.5, 0.0, maxf(0.0, w - tw))
	var base_y: float = TRACK_Y + TRACK_H + LABEL_GAP + font.get_ascent(LABEL_FONT)
	draw_string(font, Vector2(lx, base_y), text, HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_FONT, col)


static func _bar_box(bg: Color) -> StyleBoxFlat:
	var sb := BattleTheme.box(bg, int(TRACK_H * 0.5))
	sb.anti_aliasing = true
	return sb
