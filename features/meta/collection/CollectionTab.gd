class_name CollectionTab
extends Control

# Lobby tab — 컬렉션 (M10, plan §12 work D). Tab contract: `LobbyScreen.gd` header.
#
#   ┌ summary card: 보유 선수 n · 레벨업 재화 · 승급석         ┐
#   ├ role filter row (전체 + ROLE_DISPLAY_ORDER)            ┤
#   └ scrolling 4-column grid of the OWNED pilots (CollectionCell) ┘
#
# Order: rank desc → level desc → stars desc → lane seat → id. Tapping a cell opens
# `CollectionDetailSheet` (own CanvasLayer) — stats at the current rank + level, the rank
# table, and the 레벨업 / 랭크업 actions.
#
# No action bar (`bar_specs()` = []): both actions belong to one pilot, so they live in the
# detail sheet next to the numbers they change.
#
# Layout lives in `UI_View_CollectionTab.tscn` (`create()`); this script binds `%` nodes, fills data
# and adds one `UI_Comp_CollectionCell.tscn` item per pilot to `%Grid`.
#
# The pilot pool is read once (`GameManager.load_match_data`, CSV copies, mobs dropped).
# Those copies are never mutated — the sheet builds its own fielded copy. Cells exist only
# for owned pilots; `on_shown` adds cells for pilots gained in another tab (gacha, pass).

const SCENE_PATH: String = "res://features/meta/collection/UI_View_CollectionTab.tscn"

var _host: LobbyScreen
var _gm: Node
var _pm: Node

var _pool: Array = []                # Array[PlayerData] — every named pilot, CSV copies
var _by_id: Dictionary = {}          # int → PlayerData
var _load_error: String = ""
var _filter_role: int = -1           # -1 = 전체
var _filter_btns: Array = []
var _cells: Dictionary = {}          # int pilot_id → CollectionCell (owned pilots only)
var _order: Array = []               # Array[int] — current sorted pilot ids

var _sheet: CollectionDetailSheet

@onready var _grid_scroll: ScrollContainer = %Scroll
@onready var _grid: GridContainer = %Grid
@onready var _filters: HBoxContainer = %Filters
@onready var _owned_lbl: Label = %OwnedCount
@onready var _levelup_lbl: Label = %Levelup
@onready var _rank_stone_lbl: Label = %RankStone


## Layout lives in `UI_View_CollectionTab.tscn` — build with this, not `.new()`.
static func create() -> CollectionTab:
	return (load(SCENE_PATH) as PackedScene).instantiate() as CollectionTab


func _ready() -> void:
	if UiPreview.is_standalone(self):
		_fill_preview()


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


func _owned(pilot_id: int) -> bool:
	return _pm.owns_pilot(pilot_id)


## Owned pilots: rank desc → level desc → stars (등급) desc → lane seat → id.
func _sorted_ids() -> Array:
	var list: Array = []
	for p in _pool:
		if _owned((p as PlayerData).id):
			list.append(p)
	list.sort_custom(func(a: PlayerData, b: PlayerData) -> bool:
		var ra: int = _pm.rank_of(a.id)
		var rb: int = _pm.rank_of(b.id)
		if ra != rb:
			return ra > rb
		var la: int = _pm.level_of(a.id)
		var lb: int = _pm.level_of(b.id)
		if la != lb:
			return la > lb
		var sa: int = _pm.stars_of(a.id)
		var sb: int = _pm.stars_of(b.id)
		if sa != sb:
			return sa > sb
		var ea: int = GameEnums.role_seat(int(a.role))
		var eb: int = GameEnums.role_seat(int(b.role))
		if ea != eb:
			return ea < eb
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
	if _load_error != "":
		%LoadErrorText.text = Loc.t(L.RUN_SETUP_LOAD_FAILED, {"error": _load_error})
		%LoadError.visible = true
	_sheet = CollectionDetailSheet.create()
	add_child(_sheet)
	_sheet.leveled_up.connect(_on_leveled_up)
	_sheet.ranked_up.connect(_on_ranked_up)


## 켜진 탭 = `SelectableTileOn`, 꺼진 탭 = `SelectableTile` (공용 테마의 선택형 타일 쌍 —
## 런 준비 · 밴픽 필터와 같은 모양). 상태는 변형 이름만 바꿔 고른다.
func _apply_filter_styles() -> void:
	for i in _filter_btns.size():
		var role: int = -1 if i == 0 else int(GameEnums.ROLE_DISPLAY_ORDER[i - 1])
		var on: bool = role == _filter_role
		(_filter_btns[i] as Button).theme_type_variation = \
				&"SelectableTileOn" if on else &"SelectableTile"


# ── Refresh ──────────────────────────────────────────────────────────────────
func _refresh_all() -> void:
	_order = _sorted_ids()
	_sync_cells()
	for pid in _cells.keys():
		_refresh_cell(int(pid))
	_reflow_grid()
	_refresh_summary()


## One cell per owned pilot: adds cells for pilots gained since the last refresh and drops
## cells whose pilot is no longer owned.
func _sync_cells() -> void:
	for pid in _order:
		if _cells.has(pid):
			continue
		var cell := CollectionCell.create()
		_grid.add_child(cell)
		var p: PlayerData = _by_id[pid]
		cell.setup(p, _pm.level_of(p.id), _pm.rank_of(p.id), _pm.max_rank_of(p.id))
		cell.cell_tapped.connect(_on_cell_tapped)
		_cells[pid] = cell
	for pid in _cells.keys():
		if not _order.has(pid):
			var gone: CollectionCell = _cells[pid]
			_cells.erase(pid)
			_grid.remove_child(gone)
			gone.queue_free()


func _refresh_cell(pilot_id: int) -> void:
	var cell: CollectionCell = _cells.get(pilot_id, null)
	if cell != null:
		cell.refresh(_pm.level_of(pilot_id), _pm.rank_of(pilot_id), _pm.max_rank_of(pilot_id))


func _refresh_summary() -> void:
	_owned_lbl.text = str(_cells.size())
	_levelup_lbl.text = str(_pm.currency_of("levelup"))
	_rank_stone_lbl.text = str(_pm.currency_of("rank_stone"))
	%Empty.visible = _cells.is_empty() and _load_error == ""


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


## The sheet raised a pilot's level and saved the profile.
func _on_leveled_up(pilot_id: int, new_level: int) -> void:
	_after_change(pilot_id, Loc.t(L.COLLECTION_TAB_TOAST_LEVEL_UP,
			{"name": _name_of(pilot_id), "level": new_level}))


## The sheet ranked a pilot up (level back to 0) and saved the profile.
func _on_ranked_up(pilot_id: int, new_rank: int) -> void:
	_after_change(pilot_id, Loc.t(L.COLLECTION_TAB_TOAST_RANK_UP,
			{"name": _name_of(pilot_id), "rank": new_rank}))


## Cell + order (rank / level are sort keys) + summary + host currency strip + toast.
func _after_change(pilot_id: int, toast: String) -> void:
	_refresh_cell(pilot_id)
	_order = _sorted_ids()
	_reflow_grid()
	_refresh_summary()
	if _host != null:
		_host.refresh_currency()
		_host.show_toast(toast)


func _name_of(pilot_id: int) -> String:
	var p: PlayerData = _by_id.get(pilot_id, null)
	return p.name if p != null else "?"


## F6 단독 실행 미리보기 — 실제 프로필의 보유 선수 격자 (`resources/UiPreview.gd`).
## 호스트(`LobbyScreen`)는 없다. 칸을 누르면 상세 시트가 뜨지만, 레벨업 · 랭크업은 프로필을
## 저장하므로 시트의 두 버튼 누름을 출력만 하게 끊는다. 메모리 프로필만 손봐(저장 안 함)
## ★★★☆ 칸과 랭크업 가능한 칸이 꼭 보이게 한다 (`CollectionDetailSheet.preview_stage_pilots`).
func _fill_preview() -> void:  # l10n-ignore
	# 호스트가 하듯 탭 루트를 화면 전체로 편다(씬의 1080 × n 은 에디터 미리보기 크기일 뿐).
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	UiPreview.stage(self)
	setup(null)
	UiPreview.mute(_sheet.get_node("%LevelUp"), _sheet, "레벨업")
	UiPreview.mute(_sheet.get_node("%RankUp"), _sheet, "랭크업")
	CollectionDetailSheet.preview_stage_pilots(_pm, _pool)
	on_shown()
