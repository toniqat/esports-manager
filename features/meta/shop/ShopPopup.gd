class_name ShopPopup
extends CanvasLayer

# Shop / pass modal — two faces on one CanvasLayer:
#   open_reveal(results)  gacha result cards (one per pull) with NEW / 돌파 n / 파편 +n / 재료 +n
#   open_rates(pool)      the pool's rate table (per-rarity %, item count, per-item %)
#
# Pattern C of `docs/mobile_safe_area.md` (same as `ConfirmPopup`): the dim is a flat
# viewport-sized Button (tap = close), the white card is centred between
# `ScreenMetrics.top_y()` and `bottom_y()` and is STOP so taps on it don't close it.
# Also owns the shop's small display tables (rarity colours, currency labels).

signal closed

const OVERLAY_LAYER: int = 20
const DIM_COLOR := Color(0.11, 0.11, 0.18, 0.58)
const CARD_W: float = 980.0
const PAD: float = 40.0
const BTN_H: float = 104.0

const ITEM_W: float = 168.0
const ITEM_H: float = 300.0
const ITEM_GAP: float = 14.0
const ITEM_COLS: int = 5

## Display names of the eight profile currencies.
const CURRENCY_LABELS: Dictionary = {
	"outgame": "재화", "levelup": "레벨업 재화",
	"gacha_ticket_pilot": "선수권", "gacha_ticket_trait": "특성권",
	"trait_mat": "특성 재료", "cosmetic": "치장 재화",
	"premium": "유료 재화", "pilot_shard": "선수 파편",
}

var _root: Control = null


func _init() -> void:
	layer = OVERLAY_LAYER


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
	return _root != null and is_instance_valid(_root)


func close() -> void:
	if not is_open():
		return
	_root.queue_free()
	_root = null
	closed.emit()


# ── Reveal ───────────────────────────────────────────────────────────────────
func open_reveal(title: String, results: Array) -> void:
	var n: int = results.size()
	var cols: int = clampi(n, 1, ITEM_COLS)
	var rows: int = int(ceil(float(n) / float(cols)))
	var grid_h: float = rows * ITEM_H + maxi(0, rows - 1) * ITEM_GAP
	var card: Panel = _open_card(title, grid_h)
	var grid_w: float = cols * ITEM_W + (cols - 1) * ITEM_GAP
	var x0: float = (CARD_W - grid_w) * 0.5
	for i in n:
		var pos := Vector2(x0 + (i % cols) * (ITEM_W + ITEM_GAP),
				_body_top() + (i / cols) * (ITEM_H + ITEM_GAP))
		_add_item(card, results[i], pos)


func _add_item(card: Control, e: Dictionary, pos: Vector2) -> void:
	var rar: int = int(e.get("rarity", 0))
	var col: Color = rarity_color(rar)
	var box := Panel.new()
	var sb: StyleBoxFlat = OutgameTheme.flat_style(OutgameTheme.SURFACE, 14, col, 3)
	box.add_theme_stylebox_override("panel", sb)
	box.position = pos
	box.size = Vector2(ITEM_W, ITEM_H)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(box)
	var band := Panel.new()
	var band_sb: StyleBoxFlat = OutgameTheme.flat_style(col, 0)
	band_sb.corner_radius_top_left = 12
	band_sb.corner_radius_top_right = 12
	band.add_theme_stylebox_override("panel", band_sb)
	band.position = Vector2(3, 3)
	band.size = Vector2(ITEM_W - 6, 34)
	band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(band)
	var rl := UiHelpers.mk_label(band, TraitSystem.rarity_name(rar), 20,
			OutgameTheme.TEXT_ON_FILL, Vector2.ZERO, band.size, HORIZONTAL_ALIGNMENT_CENTER)
	rl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER

	var id: int = int(e.get("id", -1))
	var name_text: String
	if String(e.get("pool", "")) == Gacha.POOL_PILOT:
		name_text = String(Gacha.pilot_row(id).get("name", "?"))
		var tr := TextureRect.new()
		tr.texture = PilotImages.face_for(id)
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		tr.position = Vector2(14, 48)
		tr.size = Vector2(ITEM_W - 28, ITEM_W - 28)
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(tr)
	else:
		var trow: Dictionary = TraitSystem.row(id)
		name_text = String(trow.get("name", "?"))
		var pos_trait: bool = TraitSystem.is_positive(id)
		var mark := Panel.new()
		mark.add_theme_stylebox_override("panel", OutgameTheme.flat_style(
				OutgameTheme.POSITIVE if pos_trait else OutgameTheme.NEGATIVE, 56))
		mark.position = Vector2((ITEM_W - 112) * 0.5, 56)
		mark.size = Vector2(112, 112)
		mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(mark)
		var ml := UiHelpers.mk_label(mark, "+" if pos_trait else "−", 64,
				OutgameTheme.TEXT_ON_FILL, Vector2.ZERO, mark.size, HORIZONTAL_ALIGNMENT_CENTER)
		ml.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var nl := UiHelpers.mk_label(box, name_text, 24, OutgameTheme.TEXT,
			Vector2(6, 192), Vector2(ITEM_W - 12, 34), HORIZONTAL_ALIGNMENT_CENTER)
	nl.clip_text = true

	var tag: String = ""
	var tag_bg: Color = OutgameTheme.SURFACE_SUNK
	var tag_fg: Color = OutgameTheme.TEXT_SUB
	match String(e.get("result", "")):
		"new":
			tag = "NEW"
			tag_bg = OutgameTheme.ACCENT
			tag_fg = OutgameTheme.TEXT_ON_FILL
		"breakthrough":
			tag = "돌파 %d" % int(e.get("stage", 0))
			tag_bg = OutgameTheme.CARD_TINTS[3]
			tag_fg = OutgameTheme.TEXT_ON_FILL
		"shard":
			tag = "파편 +%d" % int(e.get("shards", 0))
		"material":
			tag = "재료 +%d" % int(e.get("amount", 0))
	if tag != "":
		OutgameTheme.add_chip(box, tag, Vector2(14, 240), Vector2(ITEM_W - 28, 42),
				tag_bg, tag_fg, 22)


# ── Rates ────────────────────────────────────────────────────────────────────
func open_rates(pool: String) -> void:
	var rows: Array = Gacha.rates(pool)
	var row_h: float = 64.0
	var body_h: float = row_h * (rows.size() + 1) + 96.0
	var card: Panel = _open_card("선수 영입 확률" if pool == Gacha.POOL_PILOT else "특성 연구 확률", body_h)
	var y: float = _body_top()
	var inner: float = CARD_W - PAD * 2.0
	var cols: Array = [0.0, 0.30, 0.55, 0.78]
	var heads: Array = ["등급", "확률", "대상 수", "개별 확률"]
	for c in heads.size():
		UiHelpers.mk_label(card, String(heads[c]), 22, OutgameTheme.TEXT_SUB,
				Vector2(PAD + inner * float(cols[c]), y), Vector2(inner * 0.24, 40))
	y += row_h
	for raw in rows:
		var r: Dictionary = raw
		var rar: int = int(r["rarity"])
		var n_items: int = Gacha.candidates(pool, rar).size()
		OutgameTheme.add_divider(card, Vector2(PAD, y - 10.0), inner)
		OutgameTheme.add_chip(card, TraitSystem.rarity_name(rar), Vector2(PAD, y),
				Vector2(120, 40), rarity_color(rar), OutgameTheme.TEXT_ON_FILL, 22)
		UiHelpers.mk_label(card, "%.1f%%" % float(r["pct"]), 26, OutgameTheme.TEXT,
				Vector2(PAD + inner * 0.30, y), Vector2(inner * 0.24, 40))
		UiHelpers.mk_label(card, "%d" % n_items, 26, OutgameTheme.TEXT,
				Vector2(PAD + inner * 0.55, y), Vector2(inner * 0.2, 40))
		var each: String = "—" if n_items == 0 else "%.2f%%" % (float(r["pct"]) / float(n_items))
		UiHelpers.mk_label(card, each, 26, OutgameTheme.TEXT,
				Vector2(PAD + inner * 0.78, y), Vector2(inner * 0.22, 40))
		y += row_h
	var note := UiHelpers.mk_label(card, UiHelpers.keep_words(
			"대상이 없는 등급이 뽑히면 가장 가까운 등급에서 뽑습니다. " +
			("중복 선수는 돌파, 돌파를 다 채운 뒤엔 선수 파편이 됩니다." if pool == Gacha.POOL_PILOT
			else "이미 가진 특성은 특성 재료가 됩니다.")),
			22, OutgameTheme.TEXT_SUB, Vector2(PAD, y + 4.0), Vector2(inner, 80))
	wrap_label(note, Vector2(inner, 80))


# ── Shell ────────────────────────────────────────────────────────────────────
func _body_top() -> float:
	return PAD + 52.0 + 28.0


## Dim + centred card with a title, `body_h` of free space and a full-width 확인.
func _open_card(title: String, body_h: float) -> Panel:
	if is_open():
		_root.queue_free()
	var vp: Vector2 = ScreenMetrics.viewport_size()
	_root = Control.new()
	_root.position = Vector2.ZERO
	_root.size = vp
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	var dim := Button.new()
	dim.flat = true
	dim.focus_mode = Control.FOCUS_NONE
	dim.position = Vector2.ZERO
	dim.size = vp
	dim.pressed.connect(close)
	_root.add_child(dim)
	var dim_rect := ColorRect.new()
	dim_rect.color = DIM_COLOR
	dim_rect.size = vp
	dim_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(dim_rect)

	var card_h: float = _body_top() + body_h + 32.0 + BTN_H + PAD
	var top: float = ScreenMetrics.top_y()
	var avail: float = ScreenMetrics.bottom_y() - top
	var card: Panel = OutgameTheme.add_card(_root,
			Vector2(ScreenMetrics.center_x() - CARD_W * 0.5, top + maxf(0.0, (avail - card_h) * 0.5)),
			Vector2(CARD_W, card_h), 24)
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	UiHelpers.mk_label(card, title, 36, OutgameTheme.TEXT,
			Vector2(PAD, PAD), Vector2(CARD_W - PAD * 2.0, 52))
	var ok := Button.new()
	ok.text = "확인"
	ok.focus_mode = Control.FOCUS_NONE
	OutgameTheme.style_primary_button(ok, 30)
	ok.position = Vector2(PAD, card_h - PAD - BTN_H)
	ok.size = Vector2(CARD_W - PAD * 2.0, BTN_H)
	ok.pressed.connect(close)
	card.add_child(ok)
	return card
