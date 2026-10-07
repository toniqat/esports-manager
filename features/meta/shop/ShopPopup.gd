class_name ShopPopup
extends CanvasLayer

# Shop / pass modal — two faces on one CanvasLayer:
#   open_reveal(results)  gacha result cards (one `ShopRevealItem` per pull) with NEW / 돌파 n / 파편 +n / 재료 +n
#   open_rates(pool)      the pool's rate table (one `ShopRateRow` per rarity: %, item count, per-item %)
#
# **Layout lives in `ShopPopup.tscn`** (+ the two item scenes). Pattern C of
# `docs/mobile_safe_area.md` (same as `ConfirmPopup`): `%Dim` is a flat full-rect Button
# (tap = close), the `PopupCard` sits in `%SafeArea` (CenterContainer) and is STOP so taps on
# it don't close it. Code owns only: texts, the grid's column count, instancing the items,
# rarity colours (data-driven), and the safe-area offsets. Open / close = `visible` toggle —
# the nodes are reused.
# Also owns the shop's small display tables (rarity colours, currency labels).

signal closed

const SCENE_PATH: String = "res://features/meta/shop/ShopPopup.tscn"
const RATE_ROW_SCENE: String = "res://features/meta/shop/ShopRateRow.tscn"
const ITEM_COLS: int = 5

## Display names of the eight profile currencies.
const CURRENCY_LABELS: Dictionary = {
	"outgame": "재화", "levelup": "레벨업 재화",
	"gacha_ticket_pilot": "선수권", "gacha_ticket_trait": "특성권",
	"trait_mat": "특성 재료", "cosmetic": "치장 재화",
	"premium": "유료 재화", "pilot_shard": "선수 파편",
}

## Instances the scene. `ShopPopup.new()` is an empty CanvasLayer — don't use it.
static func create() -> ShopPopup:
	# 씬 루트는 visible 로 저장한다(에디터에서 보이도록) — 닫힌 상태로 시작하는 건 여기서.
	var p := (load(SCENE_PATH) as PackedScene).instantiate() as ShopPopup
	p.visible = false
	return p


func _ready() -> void:
	%Dim.pressed.connect(close)
	%Ok.pressed.connect(close)


## Rarity 0..4 → colour — the shared trait table (`TraitUi.rarity_color`), used for
## both gacha pools so pilot and trait results read the same.
static func rarity_color(rarity: int) -> Color:
	return TraitUi.rarity_color(rarity)


## Turns `l` into a word-wrapped block of `sz`. The size is set **after** autowrap: a Label
## created without wrap already grew to its one-line width and keeps it otherwise.
static func wrap_label(l: Label, sz: Vector2) -> Label:
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(sz.x, 0)
	l.size = sz
	return l


static func currency_label(key: String) -> String:
	return String(CURRENCY_LABELS.get(key, key))


func is_open() -> bool:
	return visible


func close() -> void:
	if not is_open():
		return
	visible = false
	closed.emit()


# ── Reveal ───────────────────────────────────────────────────────────────────
func open_reveal(title: String, results: Array) -> void:
	var grid: GridContainer = %Grid
	_clear(grid)
	grid.columns = clampi(results.size(), 1, ITEM_COLS)
	for raw in results:
		var item := ShopRevealItem.create()
		grid.add_child(item)
		item.show_result(raw)
	_show(title, true)


# ── Rates ────────────────────────────────────────────────────────────────────
func open_rates(pool: String) -> void:
	var rows_box: VBoxContainer = %RateRows
	_clear(rows_box)
	var row_scene := load(RATE_ROW_SCENE) as PackedScene
	for raw in Gacha.rates(pool):
		var r: Dictionary = raw
		var rar: int = int(r["rarity"])
		var n_items: int = Gacha.candidates(pool, rar).size()
		var row: Control = row_scene.instantiate()
		rows_box.add_child(row)
		var chip: Panel = row.get_node("%Chip")
		chip.add_theme_stylebox_override("panel",
				OutgameTheme.flat_style(rarity_color(rar), int(chip.size.y * 0.5)))
		var chip_text: Label = row.get_node("%ChipText")
		chip_text.text = TraitSystem.rarity_name(rar)
		(row.get_node("%Pct") as Label).text = "%.1f%%" % float(r["pct"])
		(row.get_node("%Count") as Label).text = "%d" % n_items
		(row.get_node("%Each") as Label).text = "—" if n_items == 0 				else "%.2f%%" % (float(r["pct"]) / float(n_items))
	%Note.text = UiHelpers.keep_words(
			"대상이 없는 등급이 뽑히면 가장 가까운 등급에서 뽑습니다. " +
			("중복 선수는 돌파, 돌파를 다 채운 뒤엔 선수 파편이 됩니다." if pool == Gacha.POOL_PILOT
			else "이미 가진 특성은 특성 재료가 됩니다."))
	_show("선수 영입 확률" if pool == Gacha.POOL_PILOT else "특성 연구 확률", false)


# ── Shell ────────────────────────────────────────────────────────────────────
## Shows one face (reveal grid or rates table) under `title` and opens the layer.
## Re-opening while open just swaps the content.
func _show(title: String, reveal: bool) -> void:
	%Title.text = title
	%Grid.visible = reveal
	%Rates.visible = not reveal
	_fit_safe_area()
	visible = true


## Items from the previous open are removed **now** (not just queued) so the
## container lays out only the new ones this frame.
func _clear(box: Container) -> void:
	for c in box.get_children():
		box.remove_child(c)
		c.queue_free()


## The card is centred in `%SafeArea`; shrinking that box to the safe area keeps it
## clear of the notch and the bottom gesture zone.
func _fit_safe_area() -> void:
	var safe: Control = %SafeArea
	safe.offset_top = ScreenMetrics.top_y()
	safe.offset_bottom = ScreenMetrics.bottom_y() - ScreenMetrics.viewport_size().y
