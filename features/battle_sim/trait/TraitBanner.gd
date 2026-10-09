class_name TraitBanner
extends CanvasLayer

# Brief "감독 특성" card shown once when BATTLE starts — lists the player's active
# in-game traits so their effects (extra opening points, bigger hand …) aren't a
# mystery. Purely informational: it never takes input (MOUSE_FILTER_IGNORE on
# every node) and frees itself after the fade. Spawned by `TraitHooks`.
#
# Placement: horizontally centred, at `TOP_FRAC` of the viewport height — the
# middle of the battlefield, clear of the top chrome and the bottom gesture
# zone (`docs/mobile_safe_area.md`), so no safe-area offset is needed.

const LAYER_INDEX := 3          # above the card description layer (2), below modals (10+)
const TOP_FRAC    := 0.30
const WIDTH       := 760.0
const PAD         := 22.0
const TITLE_FONT  := 30
const LINE_FONT   := 26
const LINE_GAP    := 6.0
const FADE_IN     := 0.25
const HOLD        := 3.0
const FADE_OUT    := 0.45

# The card is a white `BattleTheme.gold_box()` plate (amber rim, drop shadow): amber
# title, dark lines — the in-match white palette (`resources/README.md` → BattleTheme).
const TITLE_COLOR  := BattleTheme.TEXT_TITLE
const LINE_COLOR   := BattleTheme.TEXT


## Builds the card for `lines` and plays fade-in → hold → fade-out → free.
func show_lines(lines: Array) -> void:
	layer = LAYER_INDEX
	var vp: Vector2 = ScreenMetrics.viewport_size()
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := BattleTheme.gold_box()
	sb.set_content_margin_all(PAD)
	panel.add_theme_stylebox_override("panel", sb)
	add_child(panel)

	var col := VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_theme_constant_override("separation", int(LINE_GAP))
	panel.add_child(col)
	col.add_child(_mk_label(Loc.t(L.BATTLE_TRAIT_BANNER_TITLE), TITLE_FONT, TITLE_COLOR))
	for raw in lines:
		col.add_child(_mk_label(String(raw), LINE_FONT, LINE_COLOR))

	panel.custom_minimum_size = Vector2(WIDTH, 0.0)
	panel.reset_size()
	panel.position = Vector2((vp.x - WIDTH) * 0.5, vp.y * TOP_FRAC)
	panel.modulate = Color(1.0, 1.0, 1.0, 0.0)

	var tw := create_tween()
	tw.tween_property(panel, "modulate:a", 1.0, FADE_IN)
	tw.tween_interval(HOLD)
	tw.tween_property(panel, "modulate:a", 0.0, FADE_OUT)
	tw.tween_callback(queue_free)


func _mk_label(text: String, font_size: int, color: Color) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	# No autowrap: an autowrapped Label reports a huge minimum height before it
	# has a width, which stretched the card to the bottom of the screen. Lines
	# are short; an over-long one is clipped with an ellipsis instead.
	lbl.clip_text = true
	lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	lbl.custom_minimum_size = Vector2(WIDTH - PAD * 2.0, 0.0)
	lbl.add_theme_font_size_override("font_size", font_size)
	lbl.add_theme_color_override("font_color", color)
	return lbl
