class_name ShopPopup
extends CanvasLayer

# Shop / pass modal — two faces on one CanvasLayer:
#   open_reveal(results)  gacha result cards (one `ShopRevealItem` per pull) with NEW / 돌파 n / 파편 +n / 재료 +n
#   open_rates(pool)      the pool's rate table (one `ShopRateRow` per rarity: %, item count, per-item %)
#
# **Layout lives in `UI_View_ShopPopup.tscn`** (+ the two item scenes). Pattern C of
# `docs/mobile_safe_area.md`: `%Dim` is a flat full-rect Button (tap = close), the `PopupCard`
# is centred in `%Center` (CenterContainer = `%SafeArea` minus the scene's top / bottom margin)
# and is STOP so taps on it don't close it. The variable body (reveal grid / rates table) sits
# in `%Scroll` (+ `DragScroll`): while the card fits `%Center` the scroll is exactly the body's
# height (no scrolling); past that it is capped and the body scrolls — title and `%Ok` stay put.
# Code owns only: texts, the grid's column count, instancing the items, rarity colours
# (data-driven), the safe-area offsets and the scroll's height (`_fit_body`).
# Open / close = `visible` toggle — the nodes are reused.
# Also owns the shop's small display tables (rarity colours, currency labels).

signal closed

const SCENE_PATH: String = "res://features/meta/shop/UI_View_ShopPopup.tscn"
const RATE_ROW_SCENE: String = "res://features/meta/shop/UI_Comp_ShopRateRow.tscn"
const ITEM_COLS: int = 5

## Display-name keys of the nine profile currencies — show them with `currency_label`.
const CURRENCY_LABELS: Dictionary = {  # l10n-keys: term.currency.* term.currency.levelup
	"outgame": L.TERM_CURRENCY_OUTGAME, "levelup": L.TERM_CURRENCY_LEVELUP,
	"gacha_ticket_pilot": L.TERM_CURRENCY_GACHA_TICKET_PILOT, "gacha_ticket_trait": L.TERM_CURRENCY_GACHA_TICKET_TRAIT,
	"trait_mat": L.TERM_CURRENCY_TRAIT_MAT, "cosmetic": L.TERM_CURRENCY_COSMETIC,
	"premium": L.TERM_CURRENCY_PREMIUM, "pilot_shard": L.TERM_CURRENCY_PILOT_SHARD,
	"rank_stone": L.TERM_CURRENCY_RANK_STONE,
}

var _fit_queued: bool = false

## Instances the scene. `ShopPopup.new()` is an empty CanvasLayer — don't use it.
static func create() -> ShopPopup:
	# 씬 루트는 visible 로 저장한다(에디터에서 보이도록) — 닫힌 상태로 시작하는 건 여기서.
	var p := (load(SCENE_PATH) as PackedScene).instantiate() as ShopPopup
	p.visible = false
	return p


func _ready() -> void:
	%Dim.pressed.connect(close)
	%Ok.pressed.connect(close)
	# 손가락 / 마우스로 끌어 굴린다(`DragScroll`) — 본문이 안전 영역보다 길 때만 굴러간다.
	DragScroll.attach(%Scroll)
	# 줄바꿈 라벨은 첫 배치 뒤에야 높이가 정해진다 — 카드 최소 크기가 바뀔 때마다 다시 맞춘다.
	(%Card as Control).minimum_size_changed.connect(_queue_fit)
	(%SafeArea as Control).resized.connect(_queue_fit)
	if UiPreview.is_standalone(self):
		_fill_preview()


## Rarity 0..4 → colour — the shared trait table (`TraitUi.rarity_color`), used for
## both gacha pools so pilot and trait results read the same.
static func rarity_color(rarity: int) -> Color:
	return TraitUi.rarity_color(rarity)


## Pilot stars ★1..★3 → the shared palette's tiers (uncommon · rare · legendary).
const STAR_TIERS: Array = [0, 1, 2, 4]


static func star_color(stars: int) -> Color:
	return TraitUi.rarity_color(int(STAR_TIERS[clampi(stars, 0, STAR_TIERS.size() - 1)]))


## Tier name of a gacha item: pilots = stars (`GameEnums.star_label`), traits = rarity.
static func tier_label(pool: String, tier: int) -> String:
	return GameEnums.star_label(tier) if pool == Gacha.POOL_PILOT else GameEnums.rarity_label(tier)


## Tier colour of a gacha item: pilots = `star_color`, traits = `rarity_color`.
static func tier_color(pool: String, tier: int) -> Color:
	return star_color(tier) if pool == Gacha.POOL_PILOT else rarity_color(tier)


## Turns `l` into a word-wrapped block of `sz`. The size is set **after** autowrap: a Label
## created without wrap already grew to its one-line width and keeps it otherwise.
static func wrap_label(l: Label, sz: Vector2) -> Label:
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(sz.x, 0)
	l.size = sz
	return l


## Currency name in the current locale (unknown keys as they are).
static func currency_label(key: String) -> String:
	if not CURRENCY_LABELS.has(key):
		return key
	return Loc.t(String(CURRENCY_LABELS[key]))  # l10n-dynamic: term.currency.* term.currency.levelup


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
				OutgameTheme.flat_style(tier_color(pool, rar), int(chip.size.y * 0.5)))
		var chip_text: Label = row.get_node("%ChipText")
		chip_text.text = tier_label(pool, rar)
		(row.get_node("%Pct") as Label).text = "%.1f%%" % float(r["pct"])
		(row.get_node("%Count") as Label).text = "%d" % n_items
		(row.get_node("%Each") as Label).text = "—" if n_items == 0 				else "%.2f%%" % (float(r["pct"]) / float(n_items))
	var is_pilot: bool = pool == Gacha.POOL_PILOT
	%Note.text = UiHelpers.keep_words(Loc.t(L.SHOP_POPUP_RATES_NOTE_PILOT) if is_pilot
			else Loc.t(L.SHOP_POPUP_RATES_NOTE_TRAIT))
	_show(Loc.t(L.SHOP_POPUP_RATES_TITLE_PILOT) if is_pilot else Loc.t(L.SHOP_POPUP_RATES_TITLE_TRAIT), false)


# ── Shell ────────────────────────────────────────────────────────────────────
## Shows one face (reveal grid or rates table) under `title` and opens the layer.
## Re-opening while open just swaps the content.
func _show(title: String, reveal: bool) -> void:
	%Title.text = title
	%Grid.visible = reveal
	%Rates.visible = not reveal
	_fit_safe_area()
	_fit_body()
	(%Scroll as ScrollContainer).scroll_vertical = 0
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


## **The card stays centred while it fits, then is capped** — `%Center` (the safe area minus
## the scene's margins) is the most height it may take. Everything but `%Scroll` (title, gaps,
## `%Ok`) keeps its height; `%Scroll` gets the body's full height, or only what is left when
## that is too much — then the body scrolls.
func _fit_body() -> void:
	_fit_queued = false
	var scroll: ScrollContainer = %Scroll
	var center: Control = %Center
	# Room from anchors / offsets — `center.size` may still be inflated by the previous content
	# (a container never shrinks below its minimum size).
	var room: float = (%SafeArea as Control).size.y - center.offset_top + center.offset_bottom
	var chrome: float = (%Card as Control).get_combined_minimum_size().y 			- scroll.get_combined_minimum_size().y
	var want: float = (%Body as Control).get_combined_minimum_size().y + scroll.get_minimum_size().y
	scroll.custom_minimum_size.y = minf(want, maxf(0.0, room - chrome))


## One refit per frame, after the containers have laid the new content out.
func _queue_fit() -> void:
	if _fit_queued or not visible:
		return
	_fit_queued = true
	_fit_body.call_deferred()


## F6 단독 실행 미리보기 — 10회 영입 결과판(NEW · 돌파 · 파편 · 재료가 섞인)
## (`resources/UiPreview.gd`). 선수 · 특성 id 만 실제 표에서 고르고 결과는 손으로 적는다.
func _fill_preview() -> void:
	UiPreview.stage(self)
	UiPreview.trace(closed)
	var kinds: Array = ["new", "breakthrough", "shard", "new", "shard"]
	var results: Array = []
	var pilots: Array = Gacha.named_pilots()
	for i in mini(10, pilots.size()):
		var r: Dictionary = pilots[(i * 3) % pilots.size()]
		results.append({"pool": Gacha.POOL_PILOT, "id": int(r["id"]),
				"rarity": int(r["rarity"]), "result": String(kinds[i % kinds.size()]),
				"stage": 1 + i % 3, "shards": 5})
	var traits: Array = TraitSystem.rows()
	if not traits.is_empty() and not results.is_empty():
		var t: Dictionary = traits[0]
		results[results.size() - 1] = {"pool": Gacha.POOL_TRAIT, "id": int(t["id"]),
				"rarity": int(t["rarity"]), "result": "material", "amount": 2}
	open_reveal(Loc.t(L.SHOP_TAB_RESULT_PILOT), results)
