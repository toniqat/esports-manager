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
