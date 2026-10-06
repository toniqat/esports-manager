class_name CollectionCell
extends Button

# One cell of the lobby 컬렉션 grid: square face (rounded, role badge top-left,
# rarity stars top-right), name, then `Lv N` + breakthrough pips (0..BREAKTHROUGH_MAX).
# Unowned pilots are dimmed with a "미보유" pill over the face and no level row.
#
# Face crop / role badge come from `PilotThumb`'s static helpers (read-only reuse) so
# the same pilot looks the same here and in the run-setup lineup grid.
#
# **MOUSE_FILTER_PASS** — the cell sits inside a `DragScroll` ScrollContainer; STOP
# would swallow the press the scroll needs to start a drag.

signal cell_tapped(pilot_id: int)

const CELL_W: float = 240.0
const CELL_H: float = 330.0
const ART_MARGIN: float = 8.0
const RADIUS: int = 16
const ART_RADIUS: int = RADIUS - int(ART_MARGIN * 0.5)

const NAME_Y: float = 240.0
const NAME_H: float = 36.0
const LV_Y: float = 280.0
const LV_H: float = 34.0

const PIP_W: float = 16.0
const PIP_H: float = 16.0
const PIP_GAP: float = 6.0

const STAR_PILL_H: float = 30.0

## Owned-but-dim tint for unowned faces (grey wash, still recognisable).
const UNOWNED_MODULATE := Color(0.62, 0.62, 0.66, 0.55)

var pilot: PlayerData = null
var _face: TextureRect
var _face_mask: Control


## `max_level` 0 = not owned.
func setup(p: PlayerData, max_level: int, breakthrough: int) -> void:
	pilot = p
	custom_minimum_size = Vector2(CELL_W, CELL_H)
	size = Vector2(CELL_W, CELL_H)
	focus_mode = Control.FOCUS_NONE
	mouse_filter = Control.MOUSE_FILTER_PASS
	text = ""
	if not pressed.is_connected(_on_pressed):
		pressed.connect(_on_pressed)
	refresh(max_level, breakthrough)


## Rebuilds the cell's content for a new owned state (after a level-up etc.).
func refresh(max_level: int, breakthrough: int) -> void:
	for c in get_children():
		c.queue_free()
	var owned: bool = max_level > 0
	_apply_style(owned)

	var art_sz: float = CELL_W - ART_MARGIN * 2.0
	_face = PilotThumb.add_rounded_art(self, Vector2(ART_MARGIN, ART_MARGIN),
			Vector2(art_sz, art_sz), ART_RADIUS)
	_face_mask = _face.get_parent() as Control
	_face.texture = PilotImages.face_for(pilot.id)
	if not owned:
		_face_mask.modulate = UNOWNED_MODULATE
	PilotThumb.add_role_badge(self, int(pilot.role),
			Vector2(ART_MARGIN + 6.0, ART_MARGIN + 6.0))
	add_rarity_pill(self, pilot.rarity,
			Vector2(CELL_W - ART_MARGIN - 6.0, ART_MARGIN + 6.0), STAR_PILL_H, 18, true)

	if not owned:
		var pill_w: float = 120.0
		OutgameTheme.add_chip(self, "미보유",
				Vector2((CELL_W - pill_w) * 0.5, ART_MARGIN + art_sz * 0.5 - 20.0),
				Vector2(pill_w, 40), OutgameTheme.RAIL, OutgameTheme.TEXT_ON_FILL, 22)

	var name_lbl := UiHelpers.mk_label(self, pilot.name, 26,
			OutgameTheme.TEXT if owned else OutgameTheme.TEXT_SUB,
			Vector2(12, NAME_Y), Vector2(CELL_W - 24.0, NAME_H))
	name_lbl.clip_text = true
	name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE

	if owned:
		var lv := UiHelpers.mk_label(self, "Lv %d" % max_level, 24,
				OutgameTheme.ACCENT_TEXT, Vector2(12, LV_Y), Vector2(90, LV_H))
		lv.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		lv.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var n: int = RunRules.breakthrough_max()
		var pips_w: float = float(n) * PIP_W + float(maxi(0, n - 1)) * PIP_GAP
		add_pips(self, Vector2(CELL_W - 12.0 - pips_w, LV_Y + (LV_H - PIP_H) * 0.5),
				breakthrough, n, PIP_W, PIP_H, PIP_GAP)
	else:
		var hint := UiHelpers.mk_label(self, "상점에서 영입", 20, OutgameTheme.TEXT_FAINT,
				Vector2(12, LV_Y), Vector2(CELL_W - 24.0, LV_H))
		hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		hint.mouse_filter = Control.MOUSE_FILTER_IGNORE


func _apply_style(owned: bool) -> void:
	var sb := OutgameTheme.flat_style(
			OutgameTheme.SURFACE if owned else OutgameTheme.SURFACE_SUNK, RADIUS,
			OutgameTheme.BORDER_STRONG if owned else OutgameTheme.BORDER, 2)
	for n in ["normal", "hover", "pressed", "focus", "disabled"]:
		add_theme_stylebox_override(n, sb)


func _on_pressed() -> void:
	if pilot != null:
		cell_tapped.emit(pilot.id)


# ── Shared pieces (also used by `CollectionDetailSheet`) ─────────────────────
## Rarity colour: 1 grey · 2 blue · 3 purple · 4+ amber (placeholder grades, `players.rarity`).
static func rarity_color(rarity: int) -> Color:
	match rarity:
		2: return OutgameTheme.CARD_TINTS[3]
		3: return OutgameTheme.CARD_TINTS[2]
	if rarity >= 4:
		return OutgameTheme.ACCENT
	return OutgameTheme.NEUTRAL


## A rarity pill (`★` × rarity on the rarity colour). `anchor_right` = `pos` is the
## pill's top-right corner instead of its top-left. Returns the pill.
static func add_rarity_pill(parent: Control, rarity: int, pos: Vector2, h: float,
		font_size: int, anchor_right: bool = false) -> Panel:
	var stars: String = "★".repeat(maxi(1, rarity))
	var w: float = 16.0 + float(font_size) * 0.95 * float(maxi(1, rarity))
	var at: Vector2 = pos - Vector2(w, 0.0) if anchor_right else pos
	return OutgameTheme.add_chip(parent, stars, at, Vector2(w, h),
			rarity_color(rarity), OutgameTheme.TEXT_ON_FILL, font_size)


## Breakthrough pips: `filled` of `total` small rounded squares, left to right.
static func add_pips(parent: Control, pos: Vector2, filled: int, total: int,
		w: float, h: float, gap: float) -> void:
	for i in total:
		var on: bool = i < filled
		var pip := Panel.new()
		pip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		pip.position = pos + Vector2(float(i) * (w + gap), 0.0)
		pip.size = Vector2(w, h)
		pip.add_theme_stylebox_override("panel", OutgameTheme.flat_style(
				OutgameTheme.ACCENT if on else OutgameTheme.SURFACE_SUNK, 4,
				OutgameTheme.ACCENT_TEXT if on else OutgameTheme.BORDER_STRONG, 1))
		parent.add_child(pip)
