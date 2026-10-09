class_name CollectionCell
extends Button

# One cell of the lobby 컬렉션 grid (owned pilots only): square face with the role badge
# top-left, a level ribbon (`Lv N`) bottom-left and the rank stars bottom-right — filled =
# current rank, faint = ranks the breakthroughs unlocked but not reached yet, nothing past the
# max rank (★3 pilot, 1 breakthrough, rank 3 → ★★★ + one faint ★). No name, no 등급 stars.
#
# **The layout is `UI_Comp_CollectionCell.tscn`** (cell size, face mask, ribbon / plate spots,
# label variations). Build with `CollectionCell.create()` — `.new()` is an empty button.
# Code fills data only: face texture, position badge (`PositionBadge.set_role`), the level text
# and the stars (count = max rank, reached = `CollectionCellStarOn`).
#
# **MOUSE_FILTER_PASS** (scene) — the cell sits inside a `DragScroll` ScrollContainer; STOP
# would swallow the press the scroll needs to start a drag.

signal cell_tapped(pilot_id: int)

const SCENE_PATH: String = "res://features/meta/collection/UI_Comp_CollectionCell.tscn"

## Cell size — the scene's `custom_minimum_size`.
const CELL_W: float = 240.0
const CELL_H: float = 240.0

var pilot: PlayerData = null


static func create() -> CollectionCell:
	return (load(SCENE_PATH) as PackedScene).instantiate() as CollectionCell


func _ready() -> void:
	pressed.connect(_on_pressed)
	if UiPreview.is_standalone(self):
		_fill_preview()


func setup(p: PlayerData, level: int, rank: int, max_rank: int) -> void:
	pilot = p
	(%Face as TextureRect).texture = PilotImages.face_for(p.id)
	(%PositionBadge as PositionBadge).set_role(int(p.role))
	refresh(level, rank, max_rank)


## Refills the progress parts (after a level-up / rank-up etc.).
func refresh(level: int, rank: int, max_rank: int) -> void:
	(%Level as Label).text = "Lv %d" % level
	_fill_stars(rank, max_rank)


## `%Star` is the template — duplicated up to `total`; the first `filled` show as reached.
func _fill_stars(filled: int, total: int) -> void:
	var box: HBoxContainer = %Stars
	var star: Label = %Star
	while box.get_child_count() < total:
		var d: Label = star.duplicate()
		d.unique_name_in_owner = false
		box.add_child(d)
	for i in box.get_child_count():
		var c: Label = box.get_child(i)
		c.visible = i < total
		c.theme_type_variation = &"CollectionCellStarOn" if i < filled else &"CollectionCellStar"


func _on_pressed() -> void:
	if pilot != null:
		cell_tapped.emit(pilot.id)


# ── Shared pieces (used by `CollectionDetailSheet`) ──────────────────────────
## 등급 colour by stars: ★1 grey · ★2 blue · ★3 amber.
static func stars_color(stars: int) -> Color:
	if stars >= 3:
		return OutgameTheme.ACCENT
	if stars == 2:
		return OutgameTheme.CARD_TINTS[3]
	return OutgameTheme.NEUTRAL


## A 등급 pill (`★` × stars on the stars colour) at `pos` (top-left). Returns the pill.
static func add_stars_pill(parent: Control, stars: int, pos: Vector2, h: float,
		font_size: int) -> Panel:
	var n: int = maxi(1, stars)
	var w: float = 16.0 + float(font_size) * 0.95 * float(n)
	return OutgameTheme.add_chip(parent, "★".repeat(n), pos, Vector2(w, h),
			stars_color(n), OutgameTheme.TEXT_ON_FILL, font_size)


## F6 단독 실행 미리보기 — ★3 선수, 돌파 1, 랭크 3 → ★★★ + 흐린 ★ 하나, Lv 7 (손으로 적은 값,
## `resources/UiPreview.gd`). id 는 얼굴 그림이 있는 실제 선수(2 = Corin).
func _fill_preview() -> void:
	UiPreview.stage(self)
	UiPreview.trace(cell_tapped)
	var p := PlayerData.new(2, "tx_1TSM3CVTC7", GameEnums.Role.ASSASSIN, 5, 80, 85, 82, 80, 81, 82, 19)
	setup(p, 7, 3, 4)
