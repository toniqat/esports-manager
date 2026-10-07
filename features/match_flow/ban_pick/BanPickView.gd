class_name BanPickView
extends Control

# The ban/pick **screen** — `BanPickController` builds one per `enter` (`create()`) under
# `MatchFlow.canvas` and drives it. This script owns no rules: it binds the scene's nodes for
# the controller, fits the screen to the device (safe area insets, the grid height), and plays
# the turn banner. What to show (picks, bans, tags, sheet text, colours) is the controller's.
#
# **Layout lives in `BanPickView.tscn`** — edit it in the editor:
#
#   BanPickView (full rect, OutgameTheme.tres)
#   ├ Background                 BG over the whole viewport (incl. notch / home-indicator bands)
#   ├ %SafeArea                  full rect shrunk to the safe area (offsets from code)
#   │ ├ %EnemyBlock              BanPickTeamBlock, anchored top: ban row · mechs · portraits
#   │ ├ %PlayerBlock             mirrored, anchored bottom, grows upward in the assign step
#   │ ├ %Band                    the space between the blocks (scene offsets)
#   │ │ └ %Pane                  pick pane, height = grid fit (`fit_pane`), centred in the band
#   │ │   ├ PaneCard · Content (%OrderRow · %Tabs · %Scroll/%Grid)
#   │ │   ├ %SheetDim            dims the pane only (team blocks stay readable)
#   │ │   └ %Sheet               bottom sheet, bottom-aligned to the grid
#   │ ├ %StartButton            assign-step bottom bar ("게임 시작")
#   │ └ %DragGhost              the mech slot under the finger while dragging
#   └ %Banner                    turn banner (viewport-centred, above everything)

const SCENE_PATH: String = "res://features/match_flow/ban_pick/BanPickView.tscn"

## Rows of the grid visible at once. Not an integer on purpose — the half-cut fifth row is
## the only "there's more below" signal.
const GRID_VISIBLE_ROWS: float = 4.5
const GRID_MIN_H: float = 240.0
const BAND_MIN_H: float = 200.0
## Sheet height = grid height − this, clamped to [`SHEET_MIN_H`, `SHEET_MAX_H`].
const SHEET_GRID_INSET: float = 40.0
const SHEET_MIN_H: float = 560.0
const SHEET_MAX_H: float = 700.0

# Turn banner — a side-coloured band sweeping across the centre (same shape as the in-game
# "당신의 차례"): spreads from the centre → holds → fades. Never blocks input.
const BANNER_IN_SEC: float   = 0.22
const BANNER_HOLD_SEC: float = 0.45
const BANNER_OUT_SEC: float  = 0.25
const BANNER_ALPHA: float    = 0.92

var safe_area: Control = null
var enemy_block: BanPickTeamBlock = null
var player_block: BanPickTeamBlock = null
var band: Control = null
var pane: Control = null
var order_row: BanPickOrderRow = null
var tab_buttons: Array = []     # Array[Button], left → right
var scroll: ScrollContainer = null
var grid: BanPickGrid = null

var sheet_dim: ColorRect = null
var sheet: Panel = null
var sheet_art: TextureRect = null
var sheet_art_placeholder: ColorRect = null
var sheet_name: Label = null
var sheet_stats: Label = null
var sheet_no_passive: Label = null
var sheet_passive_head: Label = null
var sheet_passive_desc: Label = null
var sheet_cards_header: Label = null
var sheet_card_row: HBoxContainer = null
var sheet_no_cards: Label = null
var sheet_rider: Label = null
var sheet_intel: Label = null
var sheet_close: Button = null
var sheet_confirm: Button = null

var start_button: Button = null
var drag_ghost: Panel = null
var drag_ghost_art: TextureRect = null

var _banner_bar: ColorRect = null
var _banner_label: Label = null
var _banner_gen: int = 0
var _banner_tween: Tween = null


## Instantiates the scene. `BanPickView.new()` is an empty Control — don't use it.
## Load (not preload) — preloading its own scene is a script ↔ scene cycle.
static func create() -> BanPickView:
	return (load(SCENE_PATH) as PackedScene).instantiate() as BanPickView


func _ready() -> void:
	safe_area = %SafeArea
	enemy_block = %EnemyBlock
	player_block = %PlayerBlock
	band = %Band
	pane = %Pane
	order_row = %OrderRow
	for c in (%Tabs as Control).get_children():
		if c is Button:
			tab_buttons.append(c)
	scroll = %Scroll
	grid = %Grid
	sheet_dim = %SheetDim
	sheet = %Sheet
	sheet_art = %SheetArt
	sheet_art_placeholder = %SheetArtPlaceholder
	sheet_name = %SheetName
	sheet_stats = %SheetStats
	sheet_no_passive = %SheetNoPassive
	sheet_passive_head = %SheetPassiveHead
	sheet_passive_desc = %SheetPassiveDesc
	sheet_cards_header = %SheetCardsHeader
	sheet_card_row = %SheetCardRow
	sheet_no_cards = %SheetNoCards
	sheet_rider = %SheetRider
	sheet_intel = %SheetIntel
	sheet_close = %SheetClose
	sheet_confirm = %SheetConfirm
	start_button = %StartButton
	drag_ghost = %DragGhost
	drag_ghost_art = %DragGhostArt
	_banner_bar = %BannerBar
	_banner_label = %BannerLabel
	# Finger / mouse drag scrolling instead of the engine's touch drag (`DragScroll`).
	DragScroll.attach(scroll)


## Device insets → offsets (`docs/mobile_safe_area.md` pattern B as a scene: the background
## covers the whole viewport, everything else lives in `%SafeArea`). The bottom bar reaches
## down through the bottom inset; its text stays above it (`OutgameTheme.style_bottom_button`).
func fit_safe_area() -> void:
	var ins: Vector4 = ScreenMetrics.insets()
	safe_area.offset_top = ScreenMetrics.top_y()
	safe_area.offset_bottom = -maxf(0.0, ins.w)
	start_button.offset_bottom = maxf(0.0, ins.w)


## Grid height for this device: 4.5 rows of `cell_h` (+ the grid's row gap), clamped to what
## the band between the two team blocks leaves. The pane takes exactly that height and sits
## vertically centred in the band; the sheet keeps its bottom on the grid's bottom.
func fit_pane(cell_h: float) -> void:
	var content := pane.get_node("Content") as Control
	var band_h: float = maxf(BAND_MIN_H,
			ScreenMetrics.safe_h() - band.offset_top + band.offset_bottom)
	# Everything in the pane but the grid: padding + order row + tabs + gap.
	var fixed_h: float = content.offset_top - content.offset_bottom \
			+ content.get_combined_minimum_size().y
	var gap: float = grid.v_gap
	var grid_want: float = GRID_VISIBLE_ROWS * (cell_h + gap) - gap
	var grid_h: float = clampf(grid_want, GRID_MIN_H, maxf(GRID_MIN_H, band_h - fixed_h))
	var group_h: float = fixed_h + grid_h
	pane.offset_top = maxf(0.0, (band_h - group_h) * 0.5)
	pane.offset_bottom = pane.offset_top + group_h
	var sheet_h: float = clampf(grid_h - SHEET_GRID_INSET, SHEET_MIN_H, SHEET_MAX_H)
	sheet.offset_top = sheet.offset_bottom - sheet_h


## Sweeps the turn banner (`msg` on a `col` band). A new banner removes the previous one.
func play_banner(msg: String, col: Color) -> void:
	clear_banner()
	_banner_gen += 1
	var gen: int = _banner_gen
	var vp: Vector2 = ScreenMetrics.viewport_size()
	var bh: float = _banner_bar.size.y
	var y: float = vp.y * 0.5 - bh * 0.5
	_banner_bar.color = Color(col.r, col.g, col.b, BANNER_ALPHA)
	_banner_bar.modulate = Color.WHITE
	_banner_bar.position = Vector2(vp.x * 0.5, y)
	_banner_bar.size = Vector2(0.0, bh)
	_banner_bar.visible = true
	_banner_label.text = msg
	_banner_label.modulate = Color(1, 1, 1, 0)
	_banner_label.visible = true

	var tw := create_tween().set_parallel()
	_banner_tween = tw
	tw.tween_property(_banner_bar, "size:x", vp.x, BANNER_IN_SEC) \
			.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(_banner_bar, "position:x", 0.0, BANNER_IN_SEC) \
			.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(_banner_label, "modulate", Color.WHITE, BANNER_IN_SEC)
	tw.chain().tween_interval(BANNER_HOLD_SEC)
	tw.chain().tween_property(_banner_bar, "modulate", Color(1, 1, 1, 0), BANNER_OUT_SEC)
	tw.parallel().tween_property(_banner_label, "modulate", Color(1, 1, 1, 0), BANNER_OUT_SEC)
	tw.chain().tween_callback(func() -> void:
		if gen == _banner_gen:
			clear_banner(false))


func clear_banner(kill_tween: bool = true) -> void:
	if kill_tween and _banner_tween != null and _banner_tween.is_valid():
		_banner_tween.kill()
	_banner_tween = null
	_banner_bar.visible = false
	_banner_label.visible = false
