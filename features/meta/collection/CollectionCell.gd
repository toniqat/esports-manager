class_name CollectionCell
extends Button

# One cell of the lobby 컬렉션 grid: square face (rounded, role badge top-left,
# rarity stars top-right), name, then `Lv N` + breakthrough pips (0..BREAKTHROUGH_MAX).
# Unowned pilots are dimmed with a "미보유" pill over the face and no level row.
#
# **The layout is `CollectionCell.tscn`** (cell size, face mask, badge / pill / pip spots,
# label variations). Build with `CollectionCell.create()` — `.new()` is an empty button.
# Code fills data only: face texture, role badge (`RoleBadge.set_role`), rarity pill
# (stars, colour, width), owned state (frame / name variation, dim face, which row shows)
# and the pips (count = `RunRules.breakthrough_max()`, reached = `CollectionCellPipOn`).
#
# **MOUSE_FILTER_PASS** (scene) — the cell sits inside a `DragScroll` ScrollContainer; STOP
# would swallow the press the scroll needs to start a drag.

signal cell_tapped(pilot_id: int)

const SCENE_PATH: String = "res://features/meta/collection/CollectionCell.tscn"

## Cell size — the scene's `custom_minimum_size`.
const CELL_W: float = 240.0
const CELL_H: float = 330.0

## Frame variation per owned state (screen variations, `OutgameTheme._add_screen_variations`).
const FRAME_OWNED: StringName = &"CollectionCellFrame"
const FRAME_UNOWNED: StringName = &"CollectionCellFrameUnowned"

## Owned-but-dim tint for unowned faces (grey wash, still recognisable).
const UNOWNED_MODULATE := Color(0.62, 0.62, 0.66, 0.55)

var pilot: PlayerData = null


static func create() -> CollectionCell:
	return (load(SCENE_PATH) as PackedScene).instantiate() as CollectionCell


func _ready() -> void:
	pressed.connect(_on_pressed)
	if UiPreview.is_standalone(self):
		_fill_preview()


## `max_level` 0 = not owned.
func setup(p: PlayerData, max_level: int, breakthrough: int) -> void:
	pilot = p
	(%Face as TextureRect).texture = PilotImages.face_for(p.id)
	(%RoleBadge as RoleBadge).set_role(int(p.role))
	set_rarity(%Rarity, %RarityText, p.rarity, 18)
	refresh(max_level, breakthrough)


## Refills the owned state (after a level-up etc.).
func refresh(max_level: int, breakthrough: int) -> void:
	var owned: bool = max_level > 0
	theme_type_variation = FRAME_OWNED if owned else FRAME_UNOWNED
	(%ArtMask as Control).modulate = Color.WHITE if owned else UNOWNED_MODULATE
	(%Unowned as Control).visible = not owned
	(%Name as Label).text = pilot.name if pilot != null else ""
	(%Name as Label).theme_type_variation = &"BodyLabel" if owned else &"SubLabel"
	(%Level as Control).visible = owned
	(%Pips as Control).visible = owned
	(%Hint as Control).visible = not owned
	if not owned:
		return
	(%Level as Label).text = "Lv %d" % max_level
	_fill_pips(breakthrough, RunRules.breakthrough_max())


## `%Pip` is the template — duplicated up to `total`; the first `filled` show as reached.
func _fill_pips(filled: int, total: int) -> void:
	var box: HBoxContainer = %Pips
	var pip: Control = %Pip
	while box.get_child_count() < total:
		var d: Control = pip.duplicate()
		d.unique_name_in_owner = false
		box.add_child(d)
	for i in box.get_child_count():
		var c: Control = box.get_child(i)
		c.visible = i < total
		c.theme_type_variation = &"CollectionCellPipOn" if i < filled else &"CollectionCellPip"


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
	var w: float = rarity_pill_w(rarity, font_size)
	var at: Vector2 = pos - Vector2(w, 0.0) if anchor_right else pos
	return OutgameTheme.add_chip(parent, stars, at, Vector2(w, h),
			rarity_color(rarity), OutgameTheme.TEXT_ON_FILL, font_size)


## Pill width for `rarity` stars at `font_size`.
static func rarity_pill_w(rarity: int, font_size: int) -> float:
	return 16.0 + float(font_size) * 0.95 * float(maxi(1, rarity))


## Fills a scene-placed rarity pill (`Panel` on the `AccentChip` shape + a centred label):
## stars, rarity colour (data → a `variation_box` copy) and width. The pill keeps its right
## edge (`offset_right`) and grows left.
static func set_rarity(pill: Panel, text_lbl: Label, rarity: int, font_size: int) -> void:
	text_lbl.text = "★".repeat(maxi(1, rarity))
	var sb := OutgameTheme.variation_box(&"AccentChip")
	sb.bg_color = rarity_color(rarity)
	pill.add_theme_stylebox_override("panel", sb)
	pill.offset_left = pill.offset_right - rarity_pill_w(rarity, font_size)


## F6 단독 실행 미리보기 — 보유 칸(Lv 7, 돌파 3), 손으로 적은 값 (`resources/UiPreview.gd`).
## id 는 얼굴 그림이 있는 실제 선수(2 = Corin).
func _fill_preview() -> void:
	UiPreview.stage(self)
	UiPreview.trace(cell_tapped)
	var p := PlayerData.new(2, "Corin", GameEnums.Role.ASSASSIN, 5, 80, 85, 82, 80, 81, 82, 19)
	p.rarity = 3
	setup(p, 7, 3)
