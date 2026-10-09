class_name ShopTab
extends Control

# 로비 탭 — 상점 (M10). 탭 계약은 `features/meta/lobby/LobbyScreen.gd` 머리말,
# 기능 범위는 계획서 §12 (작업 E). 규칙은 `features/meta/shop/README.md`.
#
#   ┌ segmented control: 선수 영입 · 특성 연구 · 파편 상점 · 특성 제작 · 교환소 ┐
#   │ the selected section (refilled from the profile after every purchase)     │
#   └───────────────────────────────────────────────────────────────────────────┘
#
# **Layout lives in `UI_View_ShopTab.tscn`** (+ the row / chip item scenes). Two faces under `Body`:
# `%GachaView` (선수 영입 · 특성 연구) and `%ListView` (head + scroll rows for 파편 상점 ·
# 특성 제작 · 교환소). Code owns texts, button states, instancing rows, and the data colours
# (banner tint per pool, rarity chips, trait +/− mark).
#
# No action bar (every section has its own buttons). Logic lives in `Gacha` / `ShopCatalog`;
# this file only fills and, after a successful purchase, saves once and refreshes the
# host (`refresh_currency` · `refresh_badges`). Popups (`ShopPopup`) are our own CanvasLayer.

const SCENE_PATH: String = "res://features/meta/shop/UI_View_ShopTab.tscn"
const RATE_CHIP_SCENE: String = "res://features/meta/shop/UI_Comp_ShopRateChip.tscn"
const SHARD_ROW_SCENE: String = "res://features/meta/shop/UI_Comp_ShopShardRow.tscn"
const CRAFT_ROW_SCENE: String = "res://features/meta/shop/UI_Comp_ShopCraftRow.tscn"
const EXCHANGE_ROW_SCENE: String = "res://features/meta/shop/UI_Comp_ShopExchangeRow.tscn"

## Section id → its segment button (`%` name in the scene).
const SECTIONS: Array = [
	{"id": "pilot",    "node": "SegPilot"},
	{"id": "trait",    "node": "SegTrait"},
	{"id": "shard",    "node": "SegShard"},
	{"id": "craft",    "node": "SegCraft"},
	{"id": "exchange", "node": "SegExchange"},
]

var section: String = "pilot"

var _host: LobbyScreen
var _pm: Node
var _seg_buttons: Dictionary = {}    # id → Button
var _scroll_owner: String = ""       # list section the scroll position belongs to ("" = gacha)
var _scroll_keep: Dictionary = {}    # section id → scroll_vertical
var _popup: ShopPopup


## Instances the scene. `ShopTab.new()` is an empty Control — don't use it.
static func create() -> ShopTab:
	return (load(SCENE_PATH) as PackedScene).instantiate() as ShopTab


func _ready() -> void:
	for s in SECTIONS:
		var b: Button = get_node_or_null("%" + String(s["node"]))
		if b == null:
			continue
		_seg_buttons[String(s["id"])] = b
		b.pressed.connect(select_section.bind(String(s["id"])))
	%RatesButton.pressed.connect(func() -> void: _popup.open_rates(_pool()))
	%PullOne.pressed.connect(func() -> void: _on_pull(_pool(), 1))
	%PullMulti.pressed.connect(func() -> void: _on_pull(_pool(), Gacha.multi_count()))
	%DevGrant.pressed.connect(_on_dev_premium)
	%DevDesc.text = UiHelpers.keep_words(Loc.t(L.SHOP_TAB_DEV_DESC))
	# Drag / fling scrolling instead of the engine's touch drag (`DragScroll`).
	DragScroll.attach(%Scroll)
	if UiPreview.is_standalone(self):
		_fill_preview()


func bar_specs() -> Array:
	return []


func setup(host: LobbyScreen) -> void:
	_host = host
	_pm = get_node("/root/ProfileManager")
	_popup = ShopPopup.create()
	add_child(_popup)


func on_shown() -> void:
	_rebuild()


func on_bar_pressed(_i: int) -> void:
	pass


## Public so headless checks can switch sections.
func select_section(id: String) -> void:
	section = id
	_rebuild()


# ── Segments ─────────────────────────────────────────────────────────────────
func _paint_segments() -> void:
	for k in _seg_buttons.keys():
		var b: Button = _seg_buttons[k]
		if String(k) == section:
			b.theme_type_variation = &"GhostButton"
			b.add_theme_color_override("font_color", OutgameTheme.ACCENT_TEXT)
			b.add_theme_color_override("font_hover_color", OutgameTheme.ACCENT_TEXT)
		else:
			b.theme_type_variation = &"TextButton"
			b.remove_theme_color_override("font_color")
			b.remove_theme_color_override("font_hover_color")


# ── Body ─────────────────────────────────────────────────────────────────────
func _rebuild() -> void:
	_paint_segments()
	if _scroll_owner != "":
		_scroll_keep[_scroll_owner] = (%Scroll as ScrollContainer).scroll_vertical
	_scroll_owner = ""
	var is_gacha: bool = section == "pilot" or section == "trait"
	%GachaView.visible = is_gacha
	%ListView.visible = not is_gacha
	_clear(%Rows)
	%DevRow.visible = false
	match section:
		"pilot":    _fill_gacha(Gacha.POOL_PILOT)
		"trait":    _fill_gacha(Gacha.POOL_TRAIT)
		"shard":    _fill_shard()
		"craft":    _fill_craft()
		"exchange": _fill_exchange()


## Pool of the current gacha section.
func _pool() -> String:
	return Gacha.POOL_PILOT if section == "pilot" else Gacha.POOL_TRAIT


## Items from the previous fill are removed **now** (not just queued) so the
## container lays out only the new ones this frame.
func _clear(box: Node) -> void:
	for c in box.get_children():
		box.remove_child(c)
		c.queue_free()


# ── Gacha sections ───────────────────────────────────────────────────────────
func _fill_gacha(pool: String) -> void:
	var is_pilot: bool = pool == Gacha.POOL_PILOT
	var tint: Color = OutgameTheme.CARD_TINTS[3] if is_pilot else OutgameTheme.CARD_TINTS[2]
	# 배너 모양 = 테마 변형 `ShopBannerCard`, 색면만 풀이 정한다.
	var banner := OutgameTheme.variation_box(&"ShopBannerCard")
	banner.bg_color = tint
	%Banner.add_theme_stylebox_override("panel", banner)
	%BannerTitle.text = Loc.t(L.SHOP_TAB_POOL_PILOT) if is_pilot else Loc.t(L.SHOP_TAB_POOL_TRAIT)
	var sub: String = Loc.t(L.SHOP_TAB_BANNER_SUB_PILOT, {"n": Gacha.named_pilots().size()}) if is_pilot \
			else Loc.t(L.SHOP_TAB_BANNER_SUB_TRAIT, {"n": TraitSystem.rows().size()})
	%BannerSub.text = UiHelpers.keep_words(sub)
	# Rate chips — one per tier (pilots: stars, traits: rarity).
	var chips: Node = %RateChips
	_clear(chips)
	var chip_scene := load(RATE_CHIP_SCENE) as PackedScene
	for raw in Gacha.rates(pool):
		var r: Dictionary = raw
		var chip: Control = chip_scene.instantiate()
		chips.add_child(chip)
		var t: Label = chip.get_node("%Text")
		t.text = "%s %s%%" % [ShopPopup.tier_label(pool, int(r["rarity"])), _pct(float(r["pct"]))]
		t.add_theme_color_override("font_color", ShopPopup.tier_color(pool, int(r["rarity"])))

	# Holdings.
	var tk: String = Gacha.ticket_key(pool)
	%TicketLabel.text = ShopPopup.currency_label(tk)
	%TicketValue.text = Loc.t(L.SHOP_TAB_TICKET_COUNT, {"n": int(_pm.currency_of(tk))})
	%MoneyLabel.text = ShopPopup.currency_label("outgame")
	%MoneyValue.text = "%d" % int(_pm.currency_of("outgame"))
	if is_pilot:
		var owned_named: int = 0
		for r in Gacha.named_pilots():
			if bool(_pm.owns_pilot(int((r as Dictionary)["id"]))):
				owned_named += 1
		%OwnedLabel.text = Loc.t(L.TERM_PILOT_OWNED)
		%OwnedValue.text = "%d / %d" % [owned_named, Gacha.named_pilots().size()]
	else:
		%OwnedLabel.text = Loc.t(L.SHOP_TAB_OWNED_TRAITS)
		%OwnedValue.text = "%d / %d" % [(_pm.owned_trait_ids() as Array).size(), TraitSystem.rows().size()]

	# Pull buttons — 1 (ghost) : multi (primary), primary on the right.
	var multi: int = Gacha.multi_count()
	var one: Button = %PullOne
	var one_p: Dictionary = {"cost": _cost_text(pool, 1)}
	one.text = Loc.t(L.SHOP_TAB_PULL_ONE_PILOT, one_p) if is_pilot else Loc.t(L.SHOP_TAB_PULL_ONE_TRAIT, one_p)
	one.disabled = Gacha.check(_pm, pool, 1) != ""
	var many: Button = %PullMulti
	var many_p: Dictionary = {"n": multi, "cost": _cost_text(pool, multi)}
	many.text = Loc.t(L.SHOP_TAB_PULL_MULTI_PILOT, many_p) if is_pilot \
			else Loc.t(L.SHOP_TAB_PULL_MULTI_TRAIT, many_p)
	many.disabled = Gacha.check(_pm, pool, multi) != ""

	var disc: int = ConstTable.int_of("GACHA_MULTI_DISCOUNT_PCT")
	var note_p: Dictionary = {"ticket": ShopPopup.currency_label(tk), "n": multi, "pct": disc}
	var note_txt: String = Loc.t(L.SHOP_TAB_NOTE, note_p)
	if disc > 0:
		note_txt = Loc.t(L.SHOP_TAB_NOTE_DISCOUNT_PILOT, note_p) if is_pilot \
				else Loc.t(L.SHOP_TAB_NOTE_DISCOUNT_TRAIT, note_p)
	%Note.text = UiHelpers.keep_words(note_txt)


func _cost_text(pool: String, count: int) -> String:
	var c: Dictionary = Gacha.cost_of(pool, count, int(_pm.currency_of(Gacha.ticket_key(pool))))
	var parts: Array = []
	if int(c["tickets"]) > 0:
		parts.append("%s %d" % [ShopPopup.currency_label(Gacha.ticket_key(pool)), int(c["tickets"])])
	if int(c["currency"]) > 0 or parts.is_empty():
		parts.append("%s %d" % [ShopPopup.currency_label("outgame"), int(c["currency"])])
	return " + ".join(parts)


func _pct(p: float) -> String:
	return str(int(round(p))) if is_equal_approx(p, round(p)) else "%.1f" % p


func _on_pull(pool: String, count: int) -> void:
	var res: Dictionary = Gacha.pull(_pm, pool, count)
	if String(res["error"]) != "":
		_host.show_toast(String(res["error"]), true)
		return
	if String(res["save_error"]) != "":
		_host.show_toast(Loc.t(L.UI_ERROR_SAVE_FAILED, {"error": String(res["save_error"])}), true)
	_after_purchase()
	_popup.open_reveal(Loc.t(L.SHOP_TAB_RESULT_PILOT) if pool == Gacha.POOL_PILOT
			else Loc.t(L.SHOP_TAB_RESULT_TRAIT), res["results"])
	_toast_rank_stones(Gacha.rank_stone_total(res["results"]))


# ── Shard shop ───────────────────────────────────────────────────────────────
func _fill_shard() -> void:
	_section_head(_holding("pilot_shard"), Loc.t(L.SHOP_TAB_SHARD_SUB))
	var pilots: Array = Gacha.named_pilots().duplicate()
	pilots.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a["rarity"]) != int(b["rarity"]):
			return int(a["rarity"]) > int(b["rarity"])
		return int(a["id"]) < int(b["id"]))
	var row_scene := load(SHARD_ROW_SCENE) as PackedScene
	for raw in pilots:
		var r: Dictionary = raw
		var pid: int = int(r["id"])
		var rar_col: Color = ShopPopup.star_color(int(r["rarity"]))
		var row: Control = _add_row(row_scene)
		var slot: Control = row.get_node("%FaceSlot")
		OutgameTheme.add_round_portrait(slot, PilotImages.face_for(pid), Vector2.ZERO,
				slot.size.x, rar_col)
		(row.get_node("%Name") as Label).text = Gacha.pilot_name(pid)
		_paint_chip(row.get_node("%Chip"), rar_col)
		(row.get_node("%ChipText") as Label).text = GameEnums.star_label(int(r["rarity"]))
		(row.get_node("%PositionBadge_Position") as PositionBadge).set_role(int(r["role"]))
		var owned: bool = bool(_pm.owns_pilot(pid))
		(row.get_node("%Status") as Label).text = Loc.t(L.SHOP_TAB_BT_PROGRESS, {
				"n": int(_pm.breakthrough_of(pid)), "max": int(_pm.breakthrough_cap_of(pid))}) if owned \
				else Loc.t(L.UI_WORD_UNOWNED)
		var why: String = ShopCatalog.shard_block_reason(_pm, pid)
		var price: int = ShopCatalog.shard_price(pid)
		var b: Button = row.get_node("%Buy")
		if why != "":
			b.text = why
		else:
			b.text = Loc.t(L.SHOP_TAB_BUY_BREAKTHROUGH, {"n": price}) if owned \
					else Loc.t(L.SHOP_TAB_BUY_RECRUIT, {"n": price})
		b.disabled = why != "" or int(_pm.currency_of("pilot_shard")) < price
		b.pressed.connect(_on_buy_pilot.bind(pid))


func _on_buy_pilot(pid: int) -> void:
	var g: Dictionary = {}
	var err: String = ShopCatalog.buy_pilot(_pm, pid, g)
	if err != "":
		_host.show_toast(err, true)
		return
	_after_purchase()
	var r: Dictionary = Gacha.pilot_row(pid)
	_popup.open_reveal(Loc.t(L.SHOP_TAB_BOUGHT), [{"pool": Gacha.POOL_PILOT, "id": pid,
			"rarity": int(r.get("rarity", 0)), "result": String(g.get("result", "")),
			"stage": int(g.get("stage", 0)), "shards": int(g.get("shards", 0)),
			"rank_stone": int(g.get("rank_stone", 0))}])
	_toast_rank_stones(int(g.get("rank_stone", 0)))


# ── Trait craft ──────────────────────────────────────────────────────────────
func _fill_craft() -> void:
	_section_head(_holding("trait_mat"), Loc.t(L.SHOP_TAB_CRAFT_SUB))
	var row_scene := load(CRAFT_ROW_SCENE) as PackedScene
	for raw in TraitSystem.rows():
		var r: Dictionary = raw
		var tid: int = int(r["id"])
		var row: Control = _add_row(row_scene)
		var pos_trait: bool = String(r["polarity"]) == TraitSystem.POLARITY_POS
		_paint_chip(row.get_node("%Mark"), OutgameTheme.POSITIVE if pos_trait else OutgameTheme.NEGATIVE)
		(row.get_node("%MarkText") as Label).text = "+" if pos_trait else "−"
		(row.get_node("%Name") as Label).text = TraitSystem.name_of(tid)
		_paint_chip(row.get_node("%Chip"), TraitUi.rarity_color(int(r["rarity"])))
		(row.get_node("%ChipText") as Label).text = GameEnums.rarity_label(int(r["rarity"]))
		(row.get_node("%Desc") as Label).text = TraitSystem.desc_of(tid)
		var why: String = ShopCatalog.craft_block_reason(_pm, tid)
		var cost: int = ShopCatalog.craft_cost(tid)
		var b: Button = row.get_node("%Buy")
		b.text = Loc.t(L.SHOP_TAB_CRAFT_BUTTON, {"n": cost}) if why == "" else why
		b.disabled = why != "" or int(_pm.currency_of("trait_mat")) < cost
		b.pressed.connect(_on_craft.bind(tid))


func _on_craft(tid: int) -> void:
	var err: String = ShopCatalog.craft_trait(_pm, tid)
	if err != "":
		_host.show_toast(err, true)
		return
	_after_purchase()
	_popup.open_reveal(Loc.t(L.SHOP_TAB_CRAFTED), [{"pool": Gacha.POOL_TRAIT, "id": tid,
			"rarity": int(TraitSystem.row(tid).get("rarity", 0)), "result": "new"}])


# ── Exchange ─────────────────────────────────────────────────────────────────
func _fill_exchange() -> void:
	_section_head(_holding("premium"), Loc.t(L.SHOP_TAB_EXCHANGE_SUB))
	var specs: Array = [
		{"title": Loc.t(L.SHOP_TAB_EX_LEVELUP_TITLE),
		 "desc": Loc.t(L.SHOP_TAB_EX_LEVELUP_DESC, {"cost": ShopCatalog.levelup_exchange_cost(),
				"gain": ShopCatalog.levelup_exchange_gain()}),
		 "have": Loc.t(L.SHOP_TAB_EX_LEVELUP_HAVE, {"coins": int(_pm.currency_of("outgame")),
				"levelup": int(_pm.currency_of("levelup"))}),
		 "btn": Loc.t(L.UI_BUTTON_EXCHANGE), "ok": int(_pm.currency_of("outgame")) >= ShopCatalog.levelup_exchange_cost(),
		 "cb": _on_exchange_levelup},
		{"title": Loc.t(L.SHOP_TAB_EX_RANK_STONE_TITLE),
		 "desc": Loc.t(L.SHOP_TAB_EX_RANK_STONE_DESC, {"cost": ShopCatalog.rank_stone_exchange_cost(),
				"gain": ShopCatalog.rank_stone_exchange_gain()}),
		 "have": Loc.t(L.SHOP_TAB_EX_RANK_STONE_HAVE, {"coins": int(_pm.currency_of("outgame")),
				"stones": int(_pm.currency_of("rank_stone"))}),
		 "btn": Loc.t(L.UI_BUTTON_EXCHANGE), "ok": int(_pm.currency_of("outgame")) >= ShopCatalog.rank_stone_exchange_cost(),
		 "cb": _on_exchange_rank_stone},
		{"title": Loc.t(L.SHOP_TAB_EX_PILOT_TICKET_TITLE),
		 "desc": Loc.t(L.SHOP_TAB_EX_PILOT_TICKET_DESC, {"cost": ShopCatalog.ticket_premium_price(Gacha.POOL_PILOT),
				"gain": ShopCatalog.ticket_exchange_gain()}),
		 "have": Loc.t(L.SHOP_TAB_EX_PILOT_TICKET_HAVE, {"premium": int(_pm.currency_of("premium")),
				"tickets": int(_pm.currency_of("gacha_ticket_pilot"))}),
		 "btn": Loc.t(L.UI_BUTTON_BUY), "ok": int(_pm.currency_of("premium")) >= ShopCatalog.ticket_premium_price(Gacha.POOL_PILOT),
		 "cb": _on_buy_ticket.bind(Gacha.POOL_PILOT)},
		{"title": Loc.t(L.SHOP_TAB_EX_TRAIT_TICKET_TITLE),
		 "desc": Loc.t(L.SHOP_TAB_EX_TRAIT_TICKET_DESC, {"cost": ShopCatalog.ticket_premium_price(Gacha.POOL_TRAIT),
				"gain": ShopCatalog.ticket_exchange_gain()}),
		 "have": Loc.t(L.SHOP_TAB_EX_TRAIT_TICKET_HAVE, {"premium": int(_pm.currency_of("premium")),
				"tickets": int(_pm.currency_of("gacha_ticket_trait"))}),
		 "btn": Loc.t(L.UI_BUTTON_BUY), "ok": int(_pm.currency_of("premium")) >= ShopCatalog.ticket_premium_price(Gacha.POOL_TRAIT),
		 "cb": _on_buy_ticket.bind(Gacha.POOL_TRAIT)},
	]
	var row_scene := load(EXCHANGE_ROW_SCENE) as PackedScene
	for raw in specs:
		var s: Dictionary = raw
		var row: Control = _add_row(row_scene)
		(row.get_node("%Title") as Label).text = String(s["title"])
		(row.get_node("%Desc") as Label).text = String(s["desc"])
		(row.get_node("%Have") as Label).text = String(s["have"])
		var b: Button = row.get_node("%Buy")
		b.text = String(s["btn"])
		b.disabled = not bool(s["ok"])
		b.pressed.connect(s["cb"])

	# Dev-only premium grant — clearly labelled (premium is a local number, §12.0).
	%DevRow.visible = true
	%DevGrant.text = Loc.t(L.SHOP_TAB_DEV_GRANT, {"n": ShopCatalog.dev_premium_grant()})


func _on_exchange_levelup() -> void:
	_simple_action(ShopCatalog.exchange_levelup(_pm),
			Loc.t(L.SHOP_TAB_TOAST_LEVELUP, {"n": ShopCatalog.levelup_exchange_gain()}))


func _on_exchange_rank_stone() -> void:
	_simple_action(ShopCatalog.exchange_rank_stone(_pm),
			Loc.t(L.SHOP_TAB_TOAST_RANK_STONE, {"n": ShopCatalog.rank_stone_exchange_gain()}))


## Capped-breakthrough dupes also pay rank stones — the reveal tag shows the shards, this
## toast the stones (nothing when `n` = 0).
func _toast_rank_stones(n: int) -> void:
	if n > 0:
		_host.show_toast(Loc.t(L.SHOP_TAB_TOAST_RANK_STONE, {"n": n}))


func _on_buy_ticket(pool: String) -> void:
	_simple_action(ShopCatalog.buy_ticket(_pm, pool),
			Loc.t(L.SHOP_TAB_TOAST_TICKET, {"currency": ShopPopup.currency_label(Gacha.ticket_key(pool)),
					"n": ShopCatalog.ticket_exchange_gain()}))


func _on_dev_premium() -> void:
	_simple_action(ShopCatalog.dev_add_premium(_pm),
			Loc.t(L.SHOP_TAB_TOAST_PREMIUM, {"n": ShopCatalog.dev_premium_grant()}))


func _simple_action(err: String, ok_msg: String) -> void:
	if err != "":
		_host.show_toast(err, true)
		return
	if _after_purchase():
		_host.show_toast(ok_msg)


# ── Shared pieces ────────────────────────────────────────────────────────────
## Save once, refresh the host and redraw. false when the save failed (toast shown).
func _after_purchase() -> bool:
	var err: String = String(_pm.save_profile())
	_host.refresh_currency()
	_host.refresh_badges()
	_rebuild()
	if err != "":
		_host.show_toast(Loc.t(L.UI_ERROR_SAVE_FAILED, {"error": err}), true)
		return false
	return true


## "보유 <currency> n" — the list head title of a shop section.
func _holding(currency_key: String) -> String:
	return Loc.t(L.SHOP_TAB_HOLDING, {"currency": ShopPopup.currency_label(currency_key),
			"n": int(_pm.currency_of(currency_key))})


## Fills the list head and claims the scroll for this section (its kept position is
## restored once the new rows are laid out).
func _section_head(title: String, sub: String) -> void:
	%HeadTitle.text = title
	%HeadSub.text = UiHelpers.keep_words(sub)
	_scroll_owner = section
	_restore_scroll.call_deferred(%Scroll, int(_scroll_keep.get(section, 0)))


func _restore_scroll(sc: ScrollContainer, v: int) -> void:
	if is_instance_valid(sc):
		sc.scroll_vertical = v


func _add_row(row_scene: PackedScene) -> Control:
	var row: Control = row_scene.instantiate()
	%Rows.add_child(row)
	return row


## Pill / disc fill whose colour is data (rarity, trait polarity) — radius = half the height.
func _paint_chip(p: Panel, col: Color) -> void:
	p.add_theme_stylebox_override("panel", OutgameTheme.flat_style(col, int(p.size.y * 0.5)))


## F6 단독 실행 미리보기 — 실제 프로필로 채운 선수 영입 칸 (`resources/UiPreview.gd`).
## 뽑기 · 구매 · 교환은 프로필을 바꾸고 저장하므로 전부 끊는다: 1회 / 여러 회 버튼은
## 프로필을 건드리지 않는 가짜 결과로 결과 팝업만 열고, 목록 칸의 구매 버튼과 개발용 지급은
## 누름을 출력만 한다(칸을 바꿀 때마다 새로 생기는 줄도 붙은 뒤에 끊는다).
func _fill_preview() -> void:  # l10n-ignore
	# 호스트가 하듯 탭 루트를 화면 전체로 편다(씬의 1080 × n 은 에디터 미리보기 크기일 뿐).
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	UiPreview.stage(self)
	setup(null)
	UiPreview.mute(%PullOne, self, "1회 뽑기")
	UiPreview.mute(%PullMulti, self, "여러 회 뽑기")
	UiPreview.mute(%DevGrant, self, "개발용 지급")
	%PullOne.pressed.connect(func() -> void: _preview_reveal(1))
	%PullMulti.pressed.connect(func() -> void: _preview_reveal(Gacha.multi_count()))
	%Rows.child_entered_tree.connect(func(row: Node) -> void:
		_preview_mute_row.call_deferred(row))
	on_shown()


## 미리보기 전용 — 지금 칸의 풀에서 프로필 없이 굴린 가짜 결과로 결과 팝업을 연다.
func _preview_reveal(count: int) -> void:  # l10n-ignore
	var pool: String = _pool()
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var kinds: Array = ["new", "breakthrough", "shard", "new", "material"]
	var results: Array = []
	for i in count:
		var id: int = Gacha.roll_item(pool, rng)
		if id < 0:
			continue
		var row: Dictionary = Gacha.pilot_row(id) if pool == Gacha.POOL_PILOT else TraitSystem.row(id)
		var kind: String = String(kinds[i % kinds.size()])
		if pool == Gacha.POOL_TRAIT and kind != "new":
			kind = "material"
		elif pool == Gacha.POOL_PILOT and kind == "material":
			kind = "shard"
		results.append({"pool": pool, "id": id, "rarity": int(row.get("rarity", 0)),
				"result": kind, "stage": 1 + i % 3, "shards": 5, "amount": 2})
	_popup.open_reveal("%s 결과 (미리보기)" % ("선수 영입" if pool == Gacha.POOL_PILOT else "특성 연구"),
			results)


## 미리보기 전용 — 방금 붙은 목록 줄의 구매 버튼을 끊는다(배선은 줄을 붙인 뒤에 이어진다).
func _preview_mute_row(row: Node) -> void:  # l10n-ignore
	if not is_instance_valid(row):
		return
	var b := row.get_node_or_null("%Buy") as BaseButton
	if b != null:
		UiPreview.mute(b, self, "구매")
