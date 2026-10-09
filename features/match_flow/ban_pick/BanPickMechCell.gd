class_name BanPickMechCell
extends Button

# One **mech grid cell** of the pick pane: square portrait, the role badge (top-left), pilot
# badges — my pilots 능숙+ with this mech in the strip under the art, the enemy's 능숙+ pilots
# (analysis tier >= 2) top-right over the art — and the BAN / BLUE / RED slab over a taken mech.
# No mech name: it is in the sheet / `MechDetailPanel`.
#
# **Layout lives in `UI_Comp_BanPickMechCell.tscn`** (cell size = the grid's column width, art fills
# the square part). `BanPickController` instantiates one per mech (`create()`) into the grid
# and fills / refreshes it. Data colours stay in code: the role badge fill (role colour), the
# badge rings (side colour / accent when highlighted, `BanPickPilotDot`), the slab tint, and the
# highlight border (`set_highlight`) — the scene's StyleBox is the plain cell and the
# highlights are derived from it.
#
# The button is `MOUSE_FILTER_PASS` in the scene on purpose — STOP kills drag scrolling of
# the grid on phones (`docs/mobile_safe_area.md` §5).

const SCENE_PATH: String = "res://features/match_flow/ban_pick/UI_Comp_BanPickMechCell.tscn"
const STYLE_STATES: Array = ["normal", "hover", "pressed", "focus", "disabled"]

var art: TextureRect = null
var role_badge: Panel = null
var role_label: Label = null
## Badge rows (optional — a row deleted from the scene is skipped).
var my_dots: Control = null
var enemy_dots: Control = null
var veil: ColorRect = null
var tag: Label = null

var _base_style: StyleBoxFlat = null


## Instantiates the scene. `BanPickMechCell.new()` is an empty Button — don't use it.
static func create() -> BanPickMechCell:
	return (load(SCENE_PATH) as PackedScene).instantiate() as BanPickMechCell


func _ready() -> void:
	art = %Art
	role_badge = get_node_or_null("%RoleBadge") as Panel
	role_label = get_node_or_null("%RoleLabel") as Label
	my_dots = get_node_or_null("%MyDots") as Control
	enemy_dots = get_node_or_null("%EnemyDots") as Control
	veil = %Veil
	tag = %Tag
	_base_style = get_theme_stylebox("normal") as StyleBoxFlat
	if UiPreview.is_standalone(self):
		_fill_preview()


## Portrait and role badge (`initial` = two letters, `role_col` = role colour; an empty
## `initial` hides the badge).
func setup(tex: Texture2D, initial: String, role_col: Color) -> void:
	art.texture = tex
	if role_badge == null:
		return
	role_badge.visible = initial != ""
	if initial == "":
		return
	var sb := OutgameTheme.flat_style(role_col.darkened(0.15), 8, Color(0, 0, 0, 0.55), 1)
	role_badge.add_theme_stylebox_override("panel", sb)
	if role_label != null:
		role_label.text = initial


## Border highlight: `width` 0 = the scene's plain cell; otherwise the same box with a
## `col` border of `width` px (amber = opened in the sheet, side colour = AI hovering).
func set_highlight(col: Color, width: int) -> void:
	var sb: StyleBox = _base_style
	if width > 0 and _base_style != null:
		var d := _base_style.duplicate() as StyleBoxFlat
		d.border_color = col
		d.set_border_width_all(width)
		sb = d
	for st in STYLE_STATES:
		add_theme_stylebox_override(st, sb)


## Pilot badges. `mine` = my pilot ids (seat order, ≤ 5), `enemy` = enemy pilot ids (best
## first, ≤ 2); `*_col` = side colour of the ring; `focus_*` = highlight that row (my pick
## turn → mine, my ban turn → enemy). Empty arrays hide the badges.
func set_pilot_dots(mine: Array, enemy: Array, mine_col: Color, enemy_col: Color,
		focus_mine: bool, focus_enemy: bool) -> void:
	_fill_dots(my_dots, mine, mine_col, focus_mine)
	_fill_dots(enemy_dots, enemy, enemy_col, focus_enemy)


static func _fill_dots(row: Control, ids: Array, col: Color, focus: bool) -> void:
	if row == null:
		return
	var dots: Array = row.get_children()
	for i in dots.size():
		var dot := dots[i] as BanPickPilotDot
		dot.visible = i < ids.size()
		if dot.visible:
			dot.show_pilot(int(ids[i]), col, focus)


## F6 단독 실행 미리보기 — 시트로 열어 본(앰버 테두리) 정글 기체 한 칸: 역할 배지 · 내 능숙
## 선수 셋(내 픽 차례라 강조) · 상대 능숙 선수 둘. 색은 `BanPickController` 와 같은 값.
func _fill_preview() -> void:
	UiPreview.stage(self)
	UiPreview.trace(pressed, "cell pressed")
	setup(MechImages.portrait_for(6), "Fi", Color(1.00, 0.55, 0.20))
	set_highlight(OutgameTheme.ACCENT, 4)
	veil.visible = false
	tag.visible = false
	set_pilot_dots([0, 2, 5], [7, 11], Color(0.20, 0.45, 0.92), Color(0.88, 0.27, 0.27),
			true, false)
