class_name ShopTab
extends Control

# 로비 탭 — 상점 (M10). 탭 계약은 `features/meta/lobby/LobbyScreen.gd` 머리말,
# 기능 범위는 계획서 §12 (작업 E). 규칙은 `features/meta/shop/README.md`.
#
#   ┌ segmented control: 선수 영입 · 특성 연구 · 파편 상점 · 특성 제작 · 교환소 ┐
#   │ the selected section (rebuilt from the profile after every purchase)      │
#   └───────────────────────────────────────────────────────────────────────────┘
#
# No action bar (every section has its own buttons). Logic lives in `Gacha` / `ShopCatalog`;
# this file only draws and, after a successful purchase, saves once and refreshes the
# host (`refresh_currency` · `refresh_badges`). Popups (`ShopPopup`) are our own CanvasLayer.

const SECTIONS: Array = [
	{"id": "pilot",    "label": "선수 영입"},
	{"id": "trait",    "label": "특성 연구"},
	{"id": "shard",    "label": "파편 상점"},
	{"id": "craft",    "label": "특성 제작"},
	{"id": "exchange", "label": "교환소"},
]

const SIDE: float = 40.0
const SEG_Y: float = 20.0
const SEG_H: float = 80.0
const BODY_Y: float = 124.0
const ROW_H: float = 132.0
const ROW_GAP: float = 12.0

var section: String = "pilot"

var _host: LobbyScreen
var _pm: Node
var _seg_buttons: Dictionary = {}    # id → Button
var _view: Control = null
var _scroll: ScrollContainer = null
var _scroll_owner: String = ""       # section the current `_scroll` belongs to
var _scroll_keep: Dictionary = {}    # section id → scroll_vertical
var _popup: ShopPopup


func bar_specs() -> Array:
	return []


func setup(host: LobbyScreen) -> void:
	_host = host
	_pm = get_node("/root/ProfileManager")
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_segments()
	_popup = ShopPopup.new()
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
func _build_segments() -> void:
	var n: int = SECTIONS.size()
	var w: float = (size.x - SIDE * 2.0) / float(n)
	var back := Panel.new()
	back.add_theme_stylebox_override("panel", OutgameTheme.flat_style(OutgameTheme.SURFACE_SUNK, 16))
	back.position = Vector2(SIDE, SEG_Y)
	back.size = Vector2(size.x - SIDE * 2.0, SEG_H)
	back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(back)
	for i in n:
		var id: String = String(SECTIONS[i]["id"])
		var b := Button.new()
		b.text = String(SECTIONS[i]["label"])
		b.focus_mode = Control.FOCUS_NONE
		b.position = Vector2(SIDE + w * i + 4.0, SEG_Y + 4.0)
		b.size = Vector2(w - 8.0, SEG_H - 8.0)
		b.pressed.connect(select_section.bind(id))
		add_child(b)
		_seg_buttons[id] = b


func _paint_segments() -> void:
	for k in _seg_buttons.keys():
		var b: Button = _seg_buttons[k]
		if String(k) == section:
			OutgameTheme.style_ghost_button(b, 24)
			b.add_theme_color_override("font_color", OutgameTheme.ACCENT_TEXT)
			b.add_theme_color_override("font_hover_color", OutgameTheme.ACCENT_TEXT)
		else:
			OutgameTheme.style_text_button(b, 24)


# ── Body ─────────────────────────────────────────────────────────────────────
func _rebuild() -> void:
	_paint_segments()
	if _view != null and is_instance_valid(_view):
		if _scroll != null and is_instance_valid(_scroll):
			_scroll_keep[_scroll_owner] = _scroll.scroll_vertical
		_view.queue_free()
	_scroll = null
	_view = Control.new()
	_view.position = Vector2(0, BODY_Y)
	_view.size = Vector2(size.x, size.y - BODY_Y)
	_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_view)
	match section:
		"pilot":    _build_gacha(Gacha.POOL_PILOT)
		"trait":    _build_gacha(Gacha.POOL_TRAIT)
		"shard":    _build_shard()
		"craft":    _build_craft()
		"exchange": _build_exchange()


func _inner_w() -> float:
	return size.x - SIDE * 2.0


# ── Gacha sections ───────────────────────────────────────────────────────────
func _build_gacha(pool: String) -> void:
	var is_pilot: bool = pool == Gacha.POOL_PILOT
	var w: float = _inner_w()
	var tint: Color = OutgameTheme.CARD_TINTS[3] if is_pilot else OutgameTheme.CARD_TINTS[2]
	var banner: Panel = OutgameTheme.add_card(_view, Vector2(SIDE, 8), Vector2(w, 290), 24, tint)
	UiHelpers.mk_label(banner, "선수 영입" if is_pilot else "특성 연구", 52,
			OutgameTheme.TEXT_ON_FILL, Vector2(40, 36), Vector2(w - 80, 70))
	var sub: String = ("네임드 선수 %d인 중 한 명 · 중복은 돌파, 돌파를 다 채우면 선수 파편" %
			Gacha.named_pilots().size()) if is_pilot \
			else ("감독 특성 %d종 중 하나 · 이미 가진 특성은 특성 재료" % TraitSystem.rows().size())
	var sl := UiHelpers.mk_label(banner, UiHelpers.keep_words(sub), 24, OutgameTheme.TEXT_ON_FILL,
			Vector2(40, 112), Vector2(w - 80, 70))
	ShopPopup.wrap_label(sl, Vector2(w - 80, 70))
	# Rate chips — one per rarity.
	var rates: Array = Gacha.rates(pool)
	var cx: float = 40.0
	for raw in rates:
		var r: Dictionary = raw
		var txt: String = "%s %s%%" % [TraitSystem.rarity_name(int(r["rarity"])), _pct(float(r["pct"]))]
		OutgameTheme.add_chip(banner, txt, Vector2(cx, 214), Vector2(152, 44),
				OutgameTheme.SURFACE, ShopPopup.rarity_color(int(r["rarity"])), 22)
		cx += 164.0
	var rates_btn := Button.new()
	rates_btn.text = "확률 보기"
	rates_btn.focus_mode = Control.FOCUS_NONE
	OutgameTheme.style_text_button(rates_btn, 24)
	rates_btn.add_theme_color_override("font_color", OutgameTheme.TEXT_ON_FILL)
	rates_btn.add_theme_color_override("font_hover_color", OutgameTheme.TEXT_ON_FILL)
	rates_btn.position = Vector2(w - 200, 36)
	rates_btn.size = Vector2(170, 60)
	rates_btn.pressed.connect(_popup.open_rates.bind(pool))
	banner.add_child(rates_btn)

	# Holdings.
	var tk: String = Gacha.ticket_key(pool)
	var hold: Panel = OutgameTheme.add_card(_view, Vector2(SIDE, 322), Vector2(w, 120), 18)
	var cw: float = w / 3.0
	_hold_cell(hold, Vector2(0, 0), cw, ShopPopup.currency_label(tk),
			"%d장" % int(_pm.currency_of(tk)))
	_hold_cell(hold, Vector2(cw, 0), cw, ShopPopup.currency_label("outgame"),
			"%d" % int(_pm.currency_of("outgame")))
	if is_pilot:
		var owned_named: int = 0
		for r in Gacha.named_pilots():
			if int(_pm.max_level_of(int((r as Dictionary)["id"]))) > 0:
				owned_named += 1
		_hold_cell(hold, Vector2(cw * 2.0, 0), cw, "보유 선수",
				"%d / %d" % [owned_named, Gacha.named_pilots().size()])
	else:
		_hold_cell(hold, Vector2(cw * 2.0, 0), cw, "보유 특성",
				"%d / %d" % [(_pm.owned_trait_ids() as Array).size(), TraitSystem.rows().size()])

	# Pull buttons — 1 (ghost) : multi (primary), primary on the right.
	var multi: int = Gacha.multi_count()
	var gap: float = 20.0
	var bw: float = (w - gap) * 0.5
	var verb: String = "영입" if is_pilot else "연구"
	for k in 2:
		var count: int = 1 if k == 0 else multi
		var b := Button.new()
		b.text = "%d회 %s\n%s" % [count, verb, _cost_text(pool, count)]
		b.focus_mode = Control.FOCUS_NONE
		if k == 0:
			OutgameTheme.style_ghost_button(b, 30)
		else:
			OutgameTheme.style_primary_button(b, 30)
		b.position = Vector2(SIDE + k * (bw + gap), 472)
		b.size = Vector2(bw, 150)
		b.disabled = Gacha.check(_pm, pool, count) != ""
		b.pressed.connect(_on_pull.bind(pool, count))
		_view.add_child(b)

	var disc: int = ConstTable.int_of("GACHA_MULTI_DISCOUNT_PCT")
	var note_txt: String = "%s이 먼저 쓰이고, 모자란 만큼 재화로 치릅니다." % ShopPopup.currency_label(tk)
	if disc > 0:
		note_txt += " %d회 %s는 재화로 치르는 몫이 %d%% 할인됩니다." % [multi, verb, disc]
	var note := UiHelpers.mk_label(_view, UiHelpers.keep_words(note_txt), 22, OutgameTheme.TEXT_SUB,
			Vector2(SIDE, 642), Vector2(w, 70), HORIZONTAL_ALIGNMENT_CENTER)
	ShopPopup.wrap_label(note, Vector2(w, 70))


func _hold_cell(parent: Control, pos: Vector2, w: float, label: String, value: String) -> void:
	UiHelpers.mk_label(parent, label, 22, OutgameTheme.TEXT_SUB,
			pos + Vector2(0, 16), Vector2(w, 32), HORIZONTAL_ALIGNMENT_CENTER)
	UiHelpers.mk_label(parent, value, 38, OutgameTheme.TEXT,
			pos + Vector2(0, 52), Vector2(w, 50), HORIZONTAL_ALIGNMENT_CENTER)


func _cost_text(pool: String, count: int) -> String:
	var c: Dictionary = Gacha.cost_of(pool, count, int(_pm.currency_of(Gacha.ticket_key(pool))))
	var parts: Array = []
	if int(c["tickets"]) > 0:
		parts.append("%s %d" % [ShopPopup.currency_label(Gacha.ticket_key(pool)), int(c["tickets"])])
	if int(c["currency"]) > 0 or parts.is_empty():
		parts.append("재화 %d" % int(c["currency"]))
	return " + ".join(parts)


func _pct(p: float) -> String:
	return str(int(round(p))) if is_equal_approx(p, round(p)) else "%.1f" % p


func _on_pull(pool: String, count: int) -> void:
	var res: Dictionary = Gacha.pull(_pm, pool, count)
	if String(res["error"]) != "":
		_host.show_toast(String(res["error"]), true)
		return
	if String(res["save_error"]) != "":
		_host.show_toast("저장 실패: " + String(res["save_error"]), true)
	_after_purchase()
	_popup.open_reveal("%s 결과" % ("선수 영입" if pool == Gacha.POOL_PILOT else "특성 연구"),
			res["results"])


# ── Shard shop ───────────────────────────────────────────────────────────────
func _build_shard() -> void:
	var w: float = _inner_w()
	_section_head("보유 %s %d" % [ShopPopup.currency_label("pilot_shard"),
			int(_pm.currency_of("pilot_shard"))],
			"원하는 선수를 확정 구매합니다. 보유한 선수면 돌파 단계가 오릅니다.")
	var pilots: Array = Gacha.named_pilots().duplicate()
	pilots.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a["rarity"]) != int(b["rarity"]):
			return int(a["rarity"]) > int(b["rarity"])
		return int(a["id"]) < int(b["id"]))
	var body: Control = _make_scroll(pilots.size())
	for i in pilots.size():
		var r: Dictionary = pilots[i]
		var pid: int = int(r["id"])
		var row: Panel = _row_card(body, i)
		OutgameTheme.add_round_portrait(row, PilotImages.face_for(pid), Vector2(20, 16),
				ROW_H - 32.0, ShopPopup.rarity_color(int(r["rarity"])))
		var role_txt: String = String(GameEnums.POSITION_LABELS.get(
				GameEnums.position_key(int(r["role"])), ""))
		UiHelpers.mk_label(row, String(r["name"]), 30, OutgameTheme.TEXT,
				Vector2(140, 18), Vector2(360, 42))
		OutgameTheme.add_chip(row, TraitSystem.rarity_name(int(r["rarity"])), Vector2(140, 70),
				Vector2(96, 36), ShopPopup.rarity_color(int(r["rarity"])), OutgameTheme.TEXT_ON_FILL, 20)
		var owned: bool = int(_pm.max_level_of(pid)) > 0
		var status: String = role_txt + " · " + ("돌파 %d/%d" % [int(_pm.breakthrough_of(pid)),
				RunRules.breakthrough_max()] if owned else "미보유")
		UiHelpers.mk_label(row, status, 22, OutgameTheme.TEXT_SUB,
				Vector2(250, 72), Vector2(300, 34))
		var why: String = ShopCatalog.shard_block_reason(_pm, pid)
		var price: int = ShopCatalog.shard_price(pid)
		var b := _row_button(row, w, "%s\n파편 %d" % ["돌파" if owned else "영입", price]
				if why == "" else why)
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
	_popup.open_reveal("구매 완료", [{"pool": Gacha.POOL_PILOT, "id": pid,
			"rarity": int(r.get("rarity", 0)), "result": String(g.get("result", "")),
			"stage": int(g.get("stage", 0)), "shards": int(g.get("shards", 0))}])


# ── Trait craft ──────────────────────────────────────────────────────────────
func _build_craft() -> void:
	var w: float = _inner_w()
	_section_head("보유 %s %d" % [ShopPopup.currency_label("trait_mat"),
			int(_pm.currency_of("trait_mat"))],
			"특성 재료로 아직 없는 특성을 만듭니다. 재료는 특성 중복 · 주간패스에서 얻습니다.")
	var rows: Array = TraitSystem.rows()
	var body: Control = _make_scroll(rows.size())
	for i in rows.size():
		var r: Dictionary = rows[i]
		var tid: int = int(r["id"])
		var row: Panel = _row_card(body, i)
		var pos_trait: bool = String(r["polarity"]) == TraitSystem.POLARITY_POS
		var mark := Panel.new()
		mark.add_theme_stylebox_override("panel", OutgameTheme.flat_style(
				OutgameTheme.POSITIVE if pos_trait else OutgameTheme.NEGATIVE, 32))
		mark.position = Vector2(24, (ROW_H - 64.0) * 0.5)
		mark.size = Vector2(64, 64)
		mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(mark)
		var ml := UiHelpers.mk_label(mark, "+" if pos_trait else "−", 40,
				OutgameTheme.TEXT_ON_FILL, Vector2.ZERO, mark.size, HORIZONTAL_ALIGNMENT_CENTER)
		ml.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		UiHelpers.mk_label(row, String(r["name"]), 30, OutgameTheme.TEXT,
				Vector2(112, 14), Vector2(300, 42))
		TraitUi.add_rarity_chip(row, int(r["rarity"]), Vector2(400, 20), Vector2(96, 34), 20)
		var dl := UiHelpers.mk_label(row, TraitSystem.desc_of(tid), 22, OutgameTheme.TEXT_SUB,
				Vector2(112, 66), Vector2(w - 112 - 230, 52))
		dl.clip_text = true
		var why: String = ShopCatalog.craft_block_reason(_pm, tid)
		var cost: int = ShopCatalog.craft_cost(tid)
		var b := _row_button(row, w, ("제작\n재료 %d" % cost) if why == "" else why)
		b.disabled = why != "" or int(_pm.currency_of("trait_mat")) < cost
		b.pressed.connect(_on_craft.bind(tid))


func _on_craft(tid: int) -> void:
	var err: String = ShopCatalog.craft_trait(_pm, tid)
	if err != "":
		_host.show_toast(err, true)
		return
	_after_purchase()
	_popup.open_reveal("제작 완료", [{"pool": Gacha.POOL_TRAIT, "id": tid,
			"rarity": int(TraitSystem.row(tid).get("rarity", 0)), "result": "new"}])


# ── Exchange ─────────────────────────────────────────────────────────────────
func _build_exchange() -> void:
	var w: float = _inner_w()
	_section_head("보유 %s %d" % [ShopPopup.currency_label("premium"), int(_pm.currency_of("premium"))],
			"재화를 다른 재화로 바꿉니다.")
	var body: Control = _make_scroll(4)
	var specs: Array = [
		{"title": "레벨업 재화 교환",
		 "desc": "재화 %d → 레벨업 재화 %d" % [ShopCatalog.levelup_exchange_cost(),
				ShopCatalog.levelup_exchange_gain()],
		 "have": "보유 재화 %d · 레벨업 재화 %d" % [int(_pm.currency_of("outgame")),
				int(_pm.currency_of("levelup"))],
		 "btn": "교환", "ok": int(_pm.currency_of("outgame")) >= ShopCatalog.levelup_exchange_cost(),
		 "cb": _on_exchange_levelup},
		{"title": "선수권 구매",
		 "desc": "유료 재화 %d → 선수권 1장" % ShopCatalog.ticket_premium_price(Gacha.POOL_PILOT),
		 "have": "보유 유료 재화 %d · 선수권 %d" % [int(_pm.currency_of("premium")),
				int(_pm.currency_of("gacha_ticket_pilot"))],
		 "btn": "구매", "ok": int(_pm.currency_of("premium")) >= ShopCatalog.ticket_premium_price(Gacha.POOL_PILOT),
		 "cb": _on_buy_ticket.bind(Gacha.POOL_PILOT)},
		{"title": "특성권 구매",
		 "desc": "유료 재화 %d → 특성권 1장" % ShopCatalog.ticket_premium_price(Gacha.POOL_TRAIT),
		 "have": "보유 유료 재화 %d · 특성권 %d" % [int(_pm.currency_of("premium")),
				int(_pm.currency_of("gacha_ticket_trait"))],
		 "btn": "구매", "ok": int(_pm.currency_of("premium")) >= ShopCatalog.ticket_premium_price(Gacha.POOL_TRAIT),
		 "cb": _on_buy_ticket.bind(Gacha.POOL_TRAIT)},
	]
	for i in specs.size():
		var s: Dictionary = specs[i]
		var row: Panel = _row_card(body, i)
		UiHelpers.mk_label(row, String(s["title"]), 30, OutgameTheme.TEXT,
				Vector2(32, 14), Vector2(w - 300, 42))
		UiHelpers.mk_label(row, String(s["desc"]), 24, OutgameTheme.ACCENT_TEXT,
				Vector2(32, 58), Vector2(w - 300, 32))
		UiHelpers.mk_label(row, String(s["have"]), 20, OutgameTheme.TEXT_SUB,
				Vector2(32, 92), Vector2(w - 300, 28))
		var b := _row_button(row, w, String(s["btn"]))
		b.disabled = not bool(s["ok"])
		b.pressed.connect(s["cb"])

	# Dev-only premium grant — clearly labelled (premium is a local number, §12.0).
	var dev: Panel = _row_card(body, 3, OutgameTheme.SURFACE_SUNK)
	UiHelpers.mk_label(dev, "개발용", 30, OutgameTheme.NEGATIVE, Vector2(32, 14), Vector2(w - 300, 42))
	var dl := UiHelpers.mk_label(dev, UiHelpers.keep_words(
			"유료 재화는 지금 기기 안의 숫자일 뿐입니다 (결제 없음)."), 22, OutgameTheme.TEXT_SUB,
			Vector2(32, 62), Vector2(w - 300, 56))
	ShopPopup.wrap_label(dl, Vector2(w - 330, 56))
	var db := _row_button(dev, w, "유료 재화 +%d (개발용)" % ShopCatalog.dev_premium_grant(), 300.0)
	OutgameTheme.style_ghost_button(db, 22)
	db.pressed.connect(_on_dev_premium)


func _on_exchange_levelup() -> void:
	_simple_action(ShopCatalog.exchange_levelup(_pm), "레벨업 재화 +%d" % ShopCatalog.levelup_exchange_gain())


func _on_buy_ticket(pool: String) -> void:
	_simple_action(ShopCatalog.buy_ticket(_pm, pool),
			"%s +1" % ShopPopup.currency_label(Gacha.ticket_key(pool)))


func _on_dev_premium() -> void:
	_simple_action(ShopCatalog.dev_add_premium(_pm), "유료 재화 +%d" % ShopCatalog.dev_premium_grant())


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
		_host.show_toast("저장 실패: " + err, true)
		return false
	return true


func _section_head(title: String, sub: String) -> void:
	UiHelpers.mk_label(_view, title, 30, OutgameTheme.TEXT, Vector2(SIDE, 8), Vector2(_inner_w(), 42))
	var l := UiHelpers.mk_label(_view, UiHelpers.keep_words(sub), 22, OutgameTheme.TEXT_SUB,
			Vector2(SIDE, 52), Vector2(_inner_w(), 34))
	l.clip_text = true


## Scroll filling the view below the section head; returns its body (height set).
func _make_scroll(rows: int) -> Control:
	var top: float = 96.0
	var sv: Dictionary = OutgameTheme.add_vscroll(_view, Vector2(0, top),
			Vector2(size.x, _view.size.y - top))
	_scroll = sv["scroll"]
	var body: Control = sv["body"]
	body.custom_minimum_size.y = rows * (ROW_H + ROW_GAP) + 24.0
	_scroll_owner = section
	var keep: int = int(_scroll_keep.get(section, 0))
	if keep > 0:
		_restore_scroll.call_deferred(_scroll, keep)
	return body


func _restore_scroll(sc: ScrollContainer, v: int) -> void:
	if is_instance_valid(sc):
		sc.scroll_vertical = v


func _row_card(body: Control, i: int, tint: Variant = null) -> Panel:
	var p := Panel.new()
	p.add_theme_stylebox_override("panel", OutgameTheme.flat_style(OutgameTheme.SURFACE, 18,
			OutgameTheme.BORDER) if tint == null else OutgameTheme.flat_style(tint, 18, OutgameTheme.BORDER))
	p.position = Vector2(SIDE, 8.0 + i * (ROW_H + ROW_GAP))
	p.size = Vector2(_inner_w(), ROW_H)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(p)
	return p


## Right-hand action button of a row — PASS so the scroll still drags from it.
func _row_button(row: Control, w: float, text: String, bw: float = 190.0) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	OutgameTheme.style_primary_button(b, 24)
	b.position = Vector2(w - bw - 20.0, 18)
	b.size = Vector2(bw, ROW_H - 36)
	b.mouse_filter = Control.MOUSE_FILTER_PASS
	row.add_child(b)
	return b
