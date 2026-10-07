class_name BanPickMechCell
extends Button

# One **mech grid cell** of the pick pane: square portrait + name line, the role badge
# (top-left), mastery / analysis tags, and the BAN / BLUE / RED slab over a taken mech.
#
# **Layout lives in `BanPickMechCell.tscn`** (cell size = the grid's column width, art fills
# the square part). `BanPickController` instantiates one per mech (`create()`) into the grid
# and fills / refreshes it. Data colours stay in code: the role badge fill (role colour), the
# tag fills, the slab tint, and the highlight border (`set_highlight`) — the scene's StyleBox
# is the plain cell and the highlights are derived from it.
#
# The button is `MOUSE_FILTER_PASS` in the scene on purpose — STOP kills drag scrolling of
# the grid on phones (`docs/mobile_safe_area.md` §5).

const SCENE_PATH: String = "res://features/match_flow/ban_pick/BanPickMechCell.tscn"
const STYLE_STATES: Array = ["normal", "hover", "pressed", "focus", "disabled"]

var art: TextureRect = null
var role_badge: Panel = null
var role_label: Label = null
var name_label: Label = null
## Top-right tag (enemy likely pick / analyst ban). Optional.
var intel: Panel = null
var intel_label: Label = null
## Bottom-left tag (my rider's tier). Optional.
var mine: Panel = null
var mine_label: Label = null
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
	name_label = %NameLabel
	intel = get_node_or_null("%Intel") as Panel
	intel_label = get_node_or_null("%IntelLabel") as Label
	mine = get_node_or_null("%Mine") as Panel
	mine_label = get_node_or_null("%MineLabel") as Label
	veil = %Veil
	tag = %Tag
	_base_style = get_theme_stylebox("normal") as StyleBoxFlat
	if UiPreview.is_standalone(self):
		_fill_preview()


## Name, portrait and role badge (`initial` = two letters, `role_col` = role colour; an
## empty `initial` hides the badge).
func setup(mech_name: String, tex: Texture2D, initial: String, role_col: Color) -> void:
	name_label.text = mech_name
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


## F6 단독 실행 미리보기 — 시트로 열어 본(앰버 테두리) 정글 기체 한 칸: 역할 배지 ·
## `예상 픽` 태그 · 내 라이더 `능숙` 태그. 색은 `BanPickController` 와 같은 값.
func _fill_preview() -> void:
	UiPreview.stage(self)
	UiPreview.trace(pressed, "cell pressed")
	setup("Triumph", MechImages.portrait_for(6), "Fi", Color(1.00, 0.55, 0.20))
	set_highlight(OutgameTheme.ACCENT, 4)
	veil.visible = false
	tag.visible = false
	_preview_tag(intel, intel_label, "예상 픽", Color(0.88, 0.27, 0.27))
	_preview_tag(mine, mine_label, MechMastery.tier_name(2), MechMastery.tier_color(2))


func _preview_tag(panel: Panel, label: Label, text: String, bg: Color) -> void:
	if panel == null:
		return
	panel.visible = true
	panel.add_theme_stylebox_override("panel", OutgameTheme.flat_style(bg, 8))
	if label != null:
		label.text = text
