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
# The pilot pool is read once (`GameManager.load_match_data`, Lv1 CSV copies, mobs
# dropped). Those copies are never mutated — the sheet builds its own leveled copy.

const PAD_X: float = 24.0
const SUMMARY_Y: float = 20.0
const SUMMARY_H: float = 128.0

const FILTER_GAP_TOP: float = 20.0
const FILTER_H: float = 64.0
const FILTER_GAP: float = 8.0
const FILTER_LABELS: Array = ["전체", "탑", "정글", "미드", "원딜", "서폿"]

const GRID_GAP_TOP: float = 20.0
const GRID_COLS: int = 4
const GRID_GAP: float = 16.0
const GRID_BOTTOM_PAD: float = 24.0

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
var _grid_body: Control
var _grid_scroll: ScrollContainer

var _owned_lbl: Label
var _owned_fill: ColorRect
var _owned_track_w: float = 0.0
var _levelup_lbl: Label
var _shard_lbl: Label

var _sheet: CollectionDetailSheet


func bar_specs() -> Array:
	return []


func setup(host: LobbyScreen) -> void:
	_host = host
	_gm = get_node("/root/GameManager")
	_pm = get_node("/root/ProfileManager")
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_load_pool()
	_build()


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


# ── Build ────────────────────────────────────────────────────────────────────
func _build() -> void:
	_build_summary()
	_build_filter_row()
	_build_grid()
	if _load_error != "":
		UiHelpers.mk_label(self, "선수 데이터를 읽지 못했습니다: " + _load_error, 24,
				OutgameTheme.NEGATIVE, Vector2(PAD_X, _grid_y() + 20.0),
				Vector2(size.x - PAD_X * 2.0, 34))
	_sheet = CollectionDetailSheet.new()
	add_child(_sheet)
	_sheet.leveled_up.connect(_on_leveled_up)


func _build_summary() -> void:
	var w: float = size.x - PAD_X * 2.0
	var card: Panel = OutgameTheme.add_card(self, Vector2(PAD_X, SUMMARY_Y),
			Vector2(w, SUMMARY_H), 20)
	UiHelpers.mk_label(card, "보유 선수", 22, OutgameTheme.TEXT_SUB,
			Vector2(28, 16), Vector2(300, 30))
	_owned_lbl = UiHelpers.mk_label(card, "", 40, OutgameTheme.TEXT,
			Vector2(28, 44), Vector2(300, 50))
	# Owned bar under the count.
	_owned_track_w = 300.0
	var track := Panel.new()
	track.mouse_filter = Control.MOUSE_FILTER_IGNORE
	track.position = Vector2(28, 100)
	track.size = Vector2(_owned_track_w, 10)
	track.add_theme_stylebox_override("panel",
			OutgameTheme.flat_style(OutgameTheme.SURFACE_SUNK, 5))
	card.add_child(track)
	_owned_fill = ColorRect.new()
	_owned_fill.color = OutgameTheme.ACCENT
	_owned_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_owned_fill.position = Vector2.ZERO
	_owned_fill.size = Vector2(0, 10)
	track.add_child(_owned_fill)

	# Right: the two currencies this tab spends / shows.
	var col_w: float = 220.0
	var x2: float = w - 28.0 - col_w
	var x1: float = x2 - 16.0 - col_w
	UiHelpers.mk_label(card, "레벨업 재화", 22, OutgameTheme.TEXT_SUB,
			Vector2(x1, 16), Vector2(col_w, 30), HORIZONTAL_ALIGNMENT_RIGHT)
	_levelup_lbl = UiHelpers.mk_label(card, "", 40, OutgameTheme.ACCENT_TEXT,
			Vector2(x1, 44), Vector2(col_w, 50), HORIZONTAL_ALIGNMENT_RIGHT)
	UiHelpers.mk_label(card, "선수 파편", 22, OutgameTheme.TEXT_SUB,
			Vector2(x2, 16), Vector2(col_w, 30), HORIZONTAL_ALIGNMENT_RIGHT)
	_shard_lbl = UiHelpers.mk_label(card, "", 40, OutgameTheme.TEXT,
			Vector2(x2, 44), Vector2(col_w, 50), HORIZONTAL_ALIGNMENT_RIGHT)


func _filter_y() -> float:
	return SUMMARY_Y + SUMMARY_H + FILTER_GAP_TOP


func _grid_y() -> float:
	return _filter_y() + FILTER_H + GRID_GAP_TOP


func _build_filter_row() -> void:
	var n: int = FILTER_LABELS.size()
	var total_w: float = size.x - PAD_X * 2.0
	var w: float = (total_w - FILTER_GAP * float(n - 1)) / float(n)
	for i in n:
		var btn := Button.new()
		btn.text = String(FILTER_LABELS[i])
		btn.focus_mode = Control.FOCUS_NONE
		OutgameTheme.style_ghost_button(btn, 26)
		btn.position = Vector2(PAD_X + float(i) * (w + FILTER_GAP), _filter_y())
		btn.size = Vector2(w, FILTER_H)
		# i == 0 is 전체 (-1); then lane order, same table as the lineup step.
		var role: int = -1 if i == 0 else int(GameEnums.ROLE_DISPLAY_ORDER[i - 1])
		btn.pressed.connect(_on_filter_pressed.bind(role))
		add_child(btn)
		_filter_btns.append(btn)
	_apply_filter_styles()


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


func _build_grid() -> void:
	var gy: float = _grid_y()
	var vs: Dictionary = OutgameTheme.add_vscroll(self, Vector2(0, gy),
			Vector2(size.x, maxf(100.0, size.y - gy)))
	_grid_scroll = vs["scroll"]
	_grid_body = vs["body"]
	# PASS so the cells' presses travel up to the ScrollContainer (DragScroll).
	_grid_body.mouse_filter = Control.MOUSE_FILTER_PASS
	for p_raw in _pool:
		var p := p_raw as PlayerData
		var cell := CollectionCell.new()
		_grid_body.add_child(cell)
		cell.setup(p, _pm.max_level_of(p.id), _pm.breakthrough_of(p.id))
		cell.cell_tapped.connect(_on_cell_tapped)
		_cells[p.id] = cell


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
	var ratio: float = float(owned) / float(maxi(1, _pool.size()))
	_owned_fill.size = Vector2(_owned_track_w * ratio, 10)
	_levelup_lbl.text = str(_pm.currency_of("levelup"))
	_shard_lbl.text = str(_pm.currency_of("pilot_shard"))


## Only the visible cells take grid positions — hiding a cell in place would leave holes.
func _reflow_grid() -> void:
	var cell_w: float = CollectionCell.CELL_W
	var cell_h: float = CollectionCell.CELL_H
	var grid_w: float = float(GRID_COLS) * cell_w + float(GRID_COLS - 1) * GRID_GAP
	var x0: float = maxf(0.0, (size.x - grid_w) * 0.5)
	var shown: int = 0
	for pid in _order:
		var cell: CollectionCell = _cells[pid]
		var p: PlayerData = _by_id[pid]
		if _filter_role != -1 and int(p.role) != _filter_role:
			cell.visible = false
			continue
		cell.visible = true
		var col: int = shown % GRID_COLS
		var row: int = floori(float(shown) / float(GRID_COLS))
		cell.position = Vector2(x0 + float(col) * (cell_w + GRID_GAP),
				float(row) * (cell_h + GRID_GAP))
		_grid_body.move_child(cell, shown)
		shown += 1
	var rows: int = ceili(float(shown) / float(GRID_COLS))
	var body_h: float = float(rows) * cell_h + float(maxi(0, rows - 1)) * GRID_GAP \
			+ GRID_BOTTOM_PAD
	_grid_body.custom_minimum_size = Vector2(size.x, body_h)
	_grid_body.size = Vector2(size.x, body_h)


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
