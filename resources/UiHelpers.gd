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
