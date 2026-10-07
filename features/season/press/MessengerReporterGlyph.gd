@tool
class_name MessengerReporterGlyph
extends Control

# Reporter portrait placeholder — a microphone on a sunk disc (`_draw` widget), laid over the
# round portrait slot of `UI_Comp_MessengerNpcBubble.tscn` when the speaker has no portrait texture.
# Scales with the node's width (the scene places it at the portrait's 96 px).
# Delete once reporter art exists. `@tool` — the editor shows it.


func _draw() -> void:
	var d: float = size.x
	var c: Vector2 = Vector2(d, d) * 0.5
	var col: Color = OutgameTheme.TEXT_SUB
	draw_circle(c, d * 0.5 - 2.0, OutgameTheme.SURFACE_SUNK)
	draw_rect(Rect2(c.x - 11.0, c.y - 26.0, 22.0, 30.0), col)
	draw_circle(Vector2(c.x, c.y - 26.0), 11.0, col)
	draw_circle(Vector2(c.x, c.y + 4.0), 11.0, col)
	draw_rect(Rect2(c.x - 3.0, c.y + 4.0, 6.0, 22.0), col)
	draw_rect(Rect2(c.x - 16.0, c.y + 24.0, 32.0, 6.0), col)
