class_name CollectionTab
extends Control

# Lobby tab — 컬렉션 (M10, plan §12 work D). Tab contract: `LobbyScreen.gd` header.
#
#   ┌ summary card: 보유 선수 n / 25 + bar · 레벨업 재화 · 선수 파편 ┐
#   ├ role filter row (전체 + ROLE_DISPLAY_ORDER)                     ┤
#   └ scrolling 4-column grid of the 25 named pilots (CollectionCell) ┘
#
# Order: owned first, then rarity desc, then lane seat, then id. Tapping a cell
# opens `CollectionDetailSheet` (own CanvasLayer) — stats at the max level incl.
# breakthrough, breakthrough table, and the 레벨업 action.
#
# No action bar (`bar_specs()` = []): the only action (레벨업) belongs to one pilot,
# so it lives in the detail sheet next to the numbers it changes.
#
# Layout lives in `CollectionTab.tscn` (`create()`); this script binds `%` nodes, fills data
# and adds one code-built `CollectionCell` per pilot to `%Grid`.
#
# The pilot pool is read once (`GameManager.load_match_data`, Lv1 CSV copies, mobs
# dropped). Those copies are never mutated — the sheet builds its own leveled copy.

const SCENE_PATH: String = "res://features/meta/collection/CollectionTab.tscn"

var _host: LobbyScreen
var _gm: Node
var _pm: Node

var _pool: Array = []                # Array[PlayerData] — 25 named pilots, Lv1 copies
var _by_id: Dictionary = {}          # int → PlayerData
var _load_error: String = ""
var _filter_role: int = -1           # -1 = 전체
var _filter_btns: Array = []
var _cells: Dictionary = {}          # int pilot_id → CollectionCell
var _order: Array = []               # Array[int] — current sorted pilot ids

var _sheet: CollectionDetailSheet

@onready var _grid_scroll: ScrollContainer = %Scroll
@onready var _grid: GridContainer = %Grid
@onready var _filters: HBoxContainer = %Filters
@onready var _owned_lbl: Label = %OwnedCount
@onready var _owned_fill: Panel = %OwnedFill
@onready var _levelup_lbl: Label = %Levelup
@onready var _shard_lbl: Label = %Shards


## Layout lives in `CollectionTab.tscn` — build with this, not `.new()`.
static func create() -> CollectionTab:
	return (load(SCENE_PATH) as PackedScene).instantiate() as CollectionTab


func bar_specs() -> Array:
	return []


func setup(host: LobbyScreen) -> void:
	_host = host
	_gm = get_node("/root/GameManager")
	_pm = get_node("/root/ProfileManager")
	_load_pool()
	_bind()


func on_shown() -> void:
	# The profile may have changed in another tab (gacha, pass) — redraw.
	_refresh_all()


func on_bar_pressed(_i: int) -> void:
	pass


# ── Data ─────────────────────────────────────────────────────────────────────
func _load_pool() -> void:
	var data: Dictionary = _gm.load_match_data()
	if data.has("error"):
		_load_error = String(data["error"])
		return
	for raw in data["players"]:
		var pd := raw as PlayerData
		if pd == null or pd.is_mob:
			continue
		_pool.append(pd)
		_by_id[pd.id] = pd


func pool_size() -> int:
	return _pool.size()


## Owned first → rarity desc → lane seat → id.
func _sorted_ids() -> Array:
	var list: Array = _pool.duplicate()
	list.sort_custom(func(a: PlayerData, b: PlayerData) -> bool:
		var oa: bool = _pm.max_level_of(a.id) > 0
		var ob: bool = _pm.max_level_of(b.id) > 0
		if oa != ob:
			return oa
		if a.rarity != b.rarity:
			return a.rarity > b.rarity
		var sa: int = GameEnums.role_seat(int(a.role))
		var sb: int = GameEnums.role_seat(int(b.role))
		if sa != sb:
			return sa < sb
		return a.id < b.id)
	var out: Array = []
	for p in list:
		out.append((p as PlayerData).id)
	return out


# ── Bind ─────────────────────────────────────────────────────────────────────
func _bind() -> void:
	# Filter buttons: child 0 = 전체 (-1), then lane order — same table as the lineup step.
	for i in _filters.get_child_count():
		var btn: Button = _filters.get_child(i)
		var role: int = -1 if i == 0 else int(GameEnums.ROLE_DISPLAY_ORDER[i - 1])
		btn.pressed.connect(_on_filter_pressed.bind(role))
		_filter_btns.append(btn)
	_apply_filter_styles()
	for p_raw in _pool:
		var p := p_raw as PlayerData
		var cell := CollectionCell.new()
		_grid.add_child(cell)
		cell.setup(p, _pm.max_level_of(p.id), _pm.breakthrough_of(p.id))
		cell.cell_tapped.connect(_on_cell_tapped)
		_cells[p.id] = cell
	if _load_error != "":
		%LoadErrorText.text = "선수 데이터를 읽지 못했습니다: " + _load_error
		%LoadError.visible = true
	_sheet = CollectionDetailSheet.create()
	add_child(_sheet)
	_sheet.leveled_up.connect(_on_leveled_up)


func _apply_filter_styles() -> void:
	for i in _filter_btns.size():
		var role: int = -1 if i == 0 else int(GameEnums.ROLE_DISPLAY_ORDER[i - 1])
		var on: bool = role == _filter_role
		var btn: Button = _filter_btns[i]
		var sb := OutgameTheme.flat_style(
				OutgameTheme.ACCENT_DIM if on else OutgameTheme.SURFACE, 12,
				OutgameTheme.ACCENT if on else OutgameTheme.BORDER, 2)
		for n in ["normal", "hover", "pressed", "focus"]:
			btn.add_theme_stylebox_override(n, sb)
		var fg: Color = OutgameTheme.ACCENT_TEXT if on else OutgameTheme.TEXT_SUB
		btn.add_theme_color_override("font_color", fg)
		btn.add_theme_color_override("font_hover_color", fg)
		btn.add_theme_color_override("font_pressed_color", fg)


# ── Refresh ──────────────────────────────────────────────────────────────────
func _refresh_all() -> void:
	for pid in _cells.keys():
		(_cells[pid] as CollectionCell).refresh(_pm.max_level_of(int(pid)),
				_pm.breakthrough_of(int(pid)))
	_order = _sorted_ids()
	_reflow_grid()
	_refresh_summary()


func _refresh_summary() -> void:
	var owned: int = 0
	for p in _pool:
		if _pm.max_level_of((p as PlayerData).id) > 0:
			owned += 1
	_owned_lbl.text = "%d / %d" % [owned, _pool.size()]
	_owned_fill.anchor_right = float(owned) / float(maxi(1, _pool.size()))
	_levelup_lbl.text = str(_pm.currency_of("levelup"))
	_shard_lbl.text = str(_pm.currency_of("pilot_shard"))


## Sort order = child order; filtered-out cells are hidden, and the grid skips hidden
## children, so the visible ones close up without holes.
func _reflow_grid() -> void:
	for i in _order.size():
		var cell: CollectionCell = _cells[_order[i]]
		var p: PlayerData = _by_id[_order[i]]
		cell.visible = _filter_role == -1 or int(p.role) == _filter_role
		_grid.move_child(cell, i)


# ── Interaction ──────────────────────────────────────────────────────────────
func _on_filter_pressed(role: int) -> void:
	if _filter_role == role:
		return
	_filter_role = role
	_apply_filter_styles()
	_reflow_grid()
	_grid_scroll.scroll_vertical = 0


func _on_cell_tapped(pilot_id: int) -> void:
	var p: PlayerData = _by_id.get(pilot_id, null)
	if p != null:
		_sheet.open(p)


## The sheet raised a pilot's max level and saved the profile.
func _on_leveled_up(pilot_id: int, new_level: int) -> void:
	var cell: CollectionCell = _cells.get(pilot_id, null)
	if cell != null:
		cell.refresh(_pm.max_level_of(pilot_id), _pm.breakthrough_of(pilot_id))
	_refresh_summary()
	_host.refresh_currency()
	var p: PlayerData = _by_id.get(pilot_id, null)
	_host.show_toast("%s 최대 레벨 Lv %d" % [p.name if p != null else "?", new_level])
