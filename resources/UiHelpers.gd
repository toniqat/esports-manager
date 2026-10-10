class_name UiHelpers
extends RefCounted

# Shared helpers for procedurally-built UI panels.

## Create and parent a styled Label. Used by MatchFlow controllers and HudBuilder
## so each panel doesn't need its own copy of the boilerplate.
static func mk_label(parent: Control, text: String, font_size: int, color: Color,
		pos: Vector2, sz: Vector2,
		align: int = HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.position = pos
	l.size     = sz
	l.horizontal_alignment = align as HorizontalAlignment
	parent.add_child(l)
	return l


## U+2060 WORD JOINER between every two adjacent non-space characters, so an
## autowrapped label breaks Korean text only at spaces. The text server follows
## ICU line breaking, which allows a break between any two Hangul syllables —
## harmless on a wide panel, but a narrow one splits words mid-way ("비/용").
## The joiner is zero-width and invisible; run the same text through this before
## measuring it, or the measured height disagrees with the label's.
static func keep_words(text: String) -> String:
	var out := ""
	var prev_word: bool = false
	for i in text.length():
		var ch: String = text[i]
		var is_word: bool = ch != " " and ch != "\n" and ch != "\t" and ch != "\u00a0"
		if is_word and prev_word:
			out += "\u2060"
		out += ch
		prev_word = is_word
	return out


## Lobby modals that drop from the top edge (감독 · 재화 구매 · 특성 교체): `fade` (the modal's
## root Control) fades in / out while `sheet` slides from a quarter screen above its resting
## `rest_y`. Kills the previous `tween`; `on_hidden` runs once a hide finishes. Returns the tween.
static func slide_top_sheet(owner: Node, prev: Tween, fade: CanvasItem, sheet: Control, rest_y: float,
		show_it: bool, on_hidden: Callable = Callable(), sec: float = 0.24) -> Tween:
	if prev != null:
		prev.kill()
	var off: float = sheet.get_viewport_rect().size.y * 0.25
	var tw: Tween = owner.create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC)
	if show_it:
		fade.modulate.a = 0.0
		sheet.position.y = rest_y - off
		tw.set_ease(Tween.EASE_OUT)
		tw.tween_property(fade, "modulate:a", 1.0, sec * 0.6)
		tw.tween_property(sheet, "position:y", rest_y, sec)
	else:
		tw.set_ease(Tween.EASE_IN)
		tw.tween_property(fade, "modulate:a", 0.0, sec * 0.8)
		tw.tween_property(sheet, "position:y", rest_y - off, sec * 0.8)
		if on_hidden.is_valid():
			tw.chain().tween_callback(on_hidden)
	return tw


## Bottom-right floating close capsule (`resources/UI_Comp_FloatingCloseButton.tscn`): anchored
## to the parent's bottom-right, 40 px from the right, `lift` px above the bottom, raised by the
## device inset. Returns the capsule's top y (offset from the parent's bottom) so a sheet can
## stop above it.
static func place_floating_close(btn: Control, lift: float = 32.0) -> float:
	var below: float = OutgameTheme.bottom_inset()
	btn.anchor_left = 1.0
	btn.anchor_right = 1.0
	btn.anchor_top = 1.0
	btn.anchor_bottom = 1.0
	var sz: Vector2 = btn.custom_minimum_size
	btn.offset_right = -40.0
	btn.offset_left = -40.0 - sz.x
	btn.offset_bottom = -lift - below
	btn.offset_top = btn.offset_bottom - sz.y
	return btn.offset_top
