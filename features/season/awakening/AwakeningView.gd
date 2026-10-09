class_name AwakeningView
extends CanvasLayer

# ── Awakening event screen (깨달음, §15 C) ────────────────────────────────────
# Opened by the week screen when `Awakening.next_pending` answers a pilot:
#
#   var v := AwakeningView.create()
#   add_child(v)
#   v.closed.connect(_on_awakening_closed)   # save the run there, then poll again
#   v.open(pid)
#
# 1. Intro — the screen dims (the week screen behind must not advance while this is open),
#    amber burst (`AwakeningBurst`), the pilot's round portrait, "깨달음" + one line. Tap.
# 2. Choose 1 of 3 — card upgrade / card swap / add preset (`Awakening.options`; a locked
#    option stays visible with its reason). Nothing available → a note + 확인 spends it.
# 3. Sub-screen of the option (preset tabs on top for upgrade / swap):
#    - upgrade: the preset's 3 cards at the bottom (already upgraded = locked); tap one →
#      its "+" card + description preview above → 확인.
#    - swap: 3 candidates on top, the preset's 3 cards below; pick one of each → 확인.
#    - add preset: 3 candidate presets (3 cards each); pick one → 확인.
#    뒤로 (bottom-left) returns to the choice; 확인 sits bottom-right.
# 4. 확인 → `Awakening.resolve_*` writes the state (loadout, queue, count) **before** the view
#    fades out and emits `closed`. Closing the app mid-way leaves the awakening queued.
#
# Layout lives in `UI_View_Awakening.tscn`; card cells are `AwakeningCardCell` instances,
# descriptions are `CardDescBox` panels (white), tabs / preset rows are duplicates of the
# hidden templates `%TabTemplate` / `%PresetRowTemplate`.

signal closed

const SCENE_PATH: String = "res://features/season/awakening/UI_View_Awakening.tscn"

enum Page { INTRO, CHOOSE, UPGRADE, SWAP, PRESET }

const FADE_SEC: float = 0.25
const INTRO_SEC: float = 1.1
## The intro accepts a tap only after this long (a tap that opened it must not skip it).
const INTRO_TAP_DELAY: float = 0.45
const BIG_CARD_SCALE: float = 1.3
const CARD_SCALE: float = 1.15
const PRESET_CARD_SCALE: float = 0.7

var pilot_id: int = -1
var _state: Dictionary = {}
var _page: int = Page.INTRO
var _preset: int = 0              # preset tab of upgrade / swap
var _pick_held: int = -1          # card of the preset (upgrade target / swap out)
var _pick_cand: int = -1          # swap candidate / preset candidate index
var _intro_ready: bool = false
var _busy: bool = false


static func create() -> AwakeningView:
	return (load(SCENE_PATH) as PackedScene).instantiate() as AwakeningView


func _ready() -> void:
	(%Root as Control).gui_input.connect(_on_root_input)
	(%Back as Button).pressed.connect(_on_back)
	(%Confirm as Button).pressed.connect(_on_confirm)
	(%OptUpgrade as Button).pressed.connect(_go.bind(Page.UPGRADE))
	(%OptSwap as Button).pressed.connect(_go.bind(Page.SWAP))
	(%OptPreset as Button).pressed.connect(_go.bind(Page.PRESET))
	(%TabTemplate as Control).visible = false
	(%PresetRowTemplate as Control).visible = false
	var safe: Control = %SafeArea
	safe.offset_top = ScreenMetrics.top_y()
	safe.offset_bottom = -OutgameTheme.bottom_inset()
	(%Root as Control).visible = false
	if UiPreview.is_standalone(self):
		_fill_preview()


func is_open() -> bool:
	return pilot_id >= 0


## Shows the awakening of my pilot `pid` (one queued in `Awakening`). A pilot with nothing
## queued closes again right away (`closed` on the next frame).
func open(pid: int) -> void:
	var gm: Node = get_node_or_null("/root/GameManager")
	_state = gm.season_state if gm != null else {}
	pilot_id = pid
	if Awakening.pending_count(_state, pid) <= 0:
		_finish.call_deferred()
		return
	var root: Control = %Root
	root.visible = true
	root.modulate = Color(1, 1, 1, 0)
	(%Panel as Control).visible = false
	var name_txt: String = MentalEvents.pilot_name(_state, pid)
	(%IntroLine as Label).text = Loc.t(L.AWAKENING_VIEW_INTRO, {"name": name_txt})
	(%Sub as Label).text = Loc.t(L.AWAKENING_VIEW_SUB, {"name": name_txt,
			"n": Awakening.count(_state, pid) + 1})
	var slot: Control = %IntroPortrait
	for c in slot.get_children():
		c.queue_free()
	OutgameTheme.add_round_portrait(slot, PilotImages.circle_for(pid), Vector2.ZERO, slot.size.x)
	_page = Page.INTRO
	_intro_ready = false
	_play_intro()


func _play_intro() -> void:
	var burst: AwakeningBurst = %Burst
	burst.progress = 0.0
	var intro: Control = %Intro
	intro.visible = true
	intro.modulate = Color(1, 1, 1, 0)
	var portrait: Control = %IntroPortrait
	portrait.pivot_offset = portrait.size * 0.5
	portrait.scale = Vector2.ONE * 0.6
	var tw: Tween = create_tween()
	tw.tween_property(%Root, "modulate:a", 1.0, FADE_SEC)
	tw.tween_property(burst, "progress", 1.0, INTRO_SEC).set_trans(Tween.TRANS_CUBIC) \
			.set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(intro, "modulate:a", 1.0, INTRO_SEC * 0.6)
	tw.parallel().tween_property(portrait, "scale", Vector2.ONE, INTRO_SEC * 0.7) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	get_tree().create_timer(INTRO_TAP_DELAY).timeout.connect(func() -> void: _intro_ready = true)


func _on_root_input(ev: InputEvent) -> void:
	if _page != Page.INTRO or not _intro_ready or _busy:
		return
	var released: bool = (ev is InputEventMouseButton and not (ev as InputEventMouseButton).pressed
			and (ev as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT) \
			or (ev is InputEventScreenTouch and not (ev as InputEventScreenTouch).pressed)
	if released:
		_leave_intro()


func _leave_intro() -> void:
	_busy = true
	var tw: Tween = create_tween()
	tw.tween_property(%Intro, "modulate:a", 0.0, FADE_SEC)
	tw.tween_callback(func() -> void:
		(%Intro as Control).visible = false
		var panel: Control = %Panel
		panel.visible = true
		panel.modulate = Color(1, 1, 1, 0)
		_go(Page.CHOOSE))
	tw.tween_property(%Panel, "modulate:a", 1.0, FADE_SEC)
	tw.tween_callback(func() -> void: _busy = false)


# ── Pages ────────────────────────────────────────────────────────────────────

func _go(page: int) -> void:
	_page = page
	_pick_held = -1
	_pick_cand = -1
	if page == Page.UPGRADE or page == Page.SWAP:
		_preset = _first_preset_for(page)
	(%PageChoose as Control).visible = page == Page.CHOOSE
	(%PageUpgrade as Control).visible = page == Page.UPGRADE
	(%PageSwap as Control).visible = page == Page.SWAP
	(%PagePreset as Control).visible = page == Page.PRESET
	(%Back as Control).visible = page != Page.CHOOSE
	(%Title as Label).text = _page_title(page)
	_build_tabs()
	match page:
		Page.CHOOSE:
			_fill_choose()
		Page.UPGRADE:
			_fill_upgrade()
		Page.SWAP:
			_fill_swap()
		Page.PRESET:
			_fill_preset()
	_refresh_confirm()


func _page_title(page: int) -> String:
	match page:
		Page.UPGRADE:
			return Loc.t(L.AWAKENING_OPTION_UPGRADE_NAME)
		Page.SWAP:
			return Loc.t(L.AWAKENING_OPTION_SWAP_NAME)
		Page.PRESET:
			return Loc.t(L.AWAKENING_OPTION_PRESET_NAME)
	return Loc.t(L.AWAKENING_VIEW_TITLE)


## Upgrade / swap open on the first preset that has something to do.
func _first_preset_for(page: int) -> int:
	var n: int = PilotLoadout.presets(_state, pilot_id).size()
	for i in n:
		if page == Page.UPGRADE and not Awakening.upgradable(_state, pilot_id, i).is_empty():
			return i
		if page == Page.SWAP and not Awakening.swap_candidates(_state, pilot_id, i).is_empty():
			return i
	return 0


func _fill_choose() -> void:
	var opt: Dictionary = Awakening.options(_state, pilot_id)
	_set_option(%OptUpgrade, bool(opt[Awakening.KIND_UPGRADE]), Loc.t(L.AWAKENING_OPTION_NONE_UPGRADE))
	_set_option(%OptSwap, bool(opt[Awakening.KIND_SWAP]), Loc.t(L.AWAKENING_OPTION_NONE_SWAP))
	var reason: String = String(opt.get("preset_reason", ""))
	var lock_txt: String = ""
	if reason == "level":
		lock_txt = Loc.t(L.AWAKENING_OPTION_LOCKED_LEVEL, {"n": ConstTable.int_of("LOADOUT_PRESET_MIN_TLEVEL")})
	elif reason == "max":
		lock_txt = Loc.t(L.AWAKENING_OPTION_LOCKED_MAX, {"n": ConstTable.int_of("LOADOUT_EXTRA_MAX")})
	_set_option(%OptPreset, bool(opt[Awakening.KIND_PRESET]), lock_txt)
	(%SkipNote as Control).visible = _nothing_available(opt)


func _nothing_available(opt: Dictionary) -> bool:
	return not (bool(opt[Awakening.KIND_UPGRADE]) or bool(opt[Awakening.KIND_SWAP])
			or bool(opt[Awakening.KIND_PRESET]))


## An option button: enabled, or disabled with its reason on the lock line.
func _set_option(btn: Button, on: bool, lock_text: String) -> void:
	btn.disabled = not on
	var lock: Label = btn.find_child("Lock", true, false) as Label
	if lock != null:
		lock.text = "" if on else lock_text
		lock.visible = not on and lock_text != ""
	btn.modulate = Color.WHITE if on else Color(1, 1, 1, 0.55)


## Preset tabs (upgrade / swap): one duplicate of `%TabTemplate` per preset.
func _build_tabs() -> void:
	var holder: HBoxContainer = %Tabs
	var template: Button = %TabTemplate
	for c in holder.get_children():
		if c != template:
			holder.remove_child(c)
			c.queue_free()
	var show_tabs: bool = _page == Page.UPGRADE or _page == Page.SWAP
	holder.visible = show_tabs
	if not show_tabs:
		return
	var n: int = PilotLoadout.presets(_state, pilot_id).size()
	for i in n:
		var b: Button = template.duplicate() as Button
		b.visible = true
		b.text = preset_label(i)
		b.theme_type_variation = &"SelectableTileOn" if i == _preset else &"SelectableTile"
		b.pressed.connect(_on_tab.bind(i))
		holder.add_child(b)


## "기본" / "프리셋 2" … — also used by the detail sheet and the ban/pick picker.
static func preset_label(idx: int) -> String:
	return Loc.t(L.AWAKENING_PRESET_TAB_BASE) if idx == 0 \
			else Loc.t(L.AWAKENING_PRESET_TAB_EXTRA, {"n": idx + 1})


func _on_tab(i: int) -> void:
	if i == _preset:
		return
	_preset = i
	_pick_held = -1
	_pick_cand = -1
	_build_tabs()
	if _page == Page.UPGRADE:
		_fill_upgrade()
	else:
		_fill_swap()
	_refresh_confirm()


func _fill_upgrade() -> void:
	var held: Array = PilotLoadout.preset(_state, pilot_id, _preset)
	var can: Array = Awakening.upgradable(_state, pilot_id, _preset)
	var row: Control = %UpCards
	_clear(row)
	for c in held:
		var cell := _add_cell(row, int(c), CARD_SCALE, _on_upgrade_pick)
		cell.set_locked(not can.has(int(c)))
		cell.set_selected(int(c) == _pick_held)
	var big: Control = %UpBig
	_clear(big)
	_clear(%UpDesc)
	(%UpHint as Control).visible = _pick_held < 0
	if _pick_held < 0:
		return
	var up: int = PilotLoadout.upgrade_of(_pick_held)
	var cell := _add_cell(big, up, BIG_CARD_SCALE, Callable())
	cell.set_selected(true)
	# The card as it is now (faded) above its + version — the change reads at a glance.
	var w: float = (%UpDesc as Control).size.x
	_add_desc(%UpDesc, _pick_held, w).modulate = Color(1, 1, 1, 0.6)
	_add_desc(%UpDesc, up, w)


func _on_upgrade_pick(card_id: int) -> void:
	_pick_held = card_id
	_fill_upgrade()
	_refresh_confirm()


func _fill_swap() -> void:
	var cands: Array = Awakening.swap_candidates(_state, pilot_id, _preset)
	var held: Array = PilotLoadout.preset(_state, pilot_id, _preset)
	var top: Control = %SwapCands
	var bottom: Control = %SwapHeld
	_clear(top)
	_clear(bottom)
	for c in cands:
		_add_cell(top, int(c), CARD_SCALE, _on_swap_cand).set_selected(int(c) == _pick_cand)
	for c in held:
		_add_cell(bottom, int(c), CARD_SCALE, _on_swap_held).set_selected(int(c) == _pick_held)


func _on_swap_cand(card_id: int) -> void:
	_pick_cand = card_id
	_fill_swap()
	_show_desc(%SwapDesc, card_id)
	_refresh_confirm()


func _on_swap_held(card_id: int) -> void:
	_pick_held = card_id
	_fill_swap()
	_show_desc(%SwapDesc, card_id)
	_refresh_confirm()


func _fill_preset() -> void:
	var holder: VBoxContainer = %PresetRows
	var template: Control = %PresetRowTemplate
	for c in holder.get_children():
		if c != template:
			holder.remove_child(c)
			c.queue_free()
	var cands: Array = Awakening.preset_candidates(_state, pilot_id)
	for i in cands.size():
		var row: PanelContainer = template.duplicate() as PanelContainer
		row.visible = true
		row.theme_type_variation = &"SelectableCardOn" if i == _pick_cand else &"SelectableCard"
		holder.add_child(row)
		(row.find_child("Label", true, false) as Label).text = Loc.t(L.AWAKENING_PRESET_CAND, {"n": i + 1})
		(row.find_child("RowHit", true, false) as Button).pressed.connect(_on_preset_pick.bind(i, -1))
		var cards: Control = row.find_child("Cards", true, false) as Control
		for c in (cands[i] as Array):
			_add_cell(cards, int(c), PRESET_CARD_SCALE, _on_preset_card.bind(i))
	(%PresetHint as Control).visible = _pick_cand < 0


func _on_preset_card(card_id: int, cand: int) -> void:
	_on_preset_pick(cand, card_id)


func _on_preset_pick(cand: int, card_id: int) -> void:
	_pick_cand = cand
	_fill_preset()
	if card_id >= 0:
		_show_desc(%PresetDesc, card_id)
	else:
		_clear(%PresetDesc)
	_refresh_confirm()


func _refresh_confirm() -> void:
	var ok: bool = false
	match _page:
		Page.CHOOSE:
			ok = _nothing_available(Awakening.options(_state, pilot_id))
		Page.UPGRADE:
			ok = _pick_held >= 0
		Page.SWAP:
			ok = _pick_held >= 0 and _pick_cand >= 0
		Page.PRESET:
			ok = _pick_cand >= 0
	var b: Button = %Confirm
	b.visible = _page != Page.CHOOSE or ok
	b.disabled = not ok


# ── Resolve ──────────────────────────────────────────────────────────────────

func _on_back() -> void:
	if not _busy and _page != Page.CHOOSE and _page != Page.INTRO:
		_go(Page.CHOOSE)


func _on_confirm() -> void:
	if _busy:
		return
	var out: Dictionary = {}
	match _page:
		Page.CHOOSE:
			out = Awakening.resolve_skip(_state, pilot_id)
		Page.UPGRADE:
			out = Awakening.resolve_upgrade(_state, pilot_id, _preset, _pick_held)
		Page.SWAP:
			out = Awakening.resolve_swap(_state, pilot_id, _preset, _pick_held, _pick_cand)
		Page.PRESET:
			out = Awakening.resolve_preset(_state, pilot_id, _pick_cand)
	if not bool(out.get("ok", false)):
		push_warning("AwakeningView: resolve refused %s" % str(out))
		return
	_busy = true
	var tw: Tween = create_tween()
	tw.tween_property(%Root, "modulate:a", 0.0, FADE_SEC)
	tw.tween_callback(_finish)


func _finish() -> void:
	(%Root as Control).visible = false
	pilot_id = -1
	_busy = false
	closed.emit()


# ── Helpers ──────────────────────────────────────────────────────────────────

func _add_cell(parent: Control, card_id: int, k: float, on_tap: Callable) -> AwakeningCardCell:
	var cell := AwakeningCardCell.create()
	parent.add_child(cell)
	cell.set_card_scale(k)
	cell.fill(card_id)
	if on_tap.is_valid():
		cell.tapped.connect(on_tap)
	else:
		(cell.get_node("%Hit") as Button).visible = false
	return cell


func _show_desc(holder: Control, card_id: int) -> void:
	_clear(holder)
	_add_desc(holder, card_id, holder.size.x)


func _add_desc(holder: Control, card_id: int, w: float) -> Control:
	var gm: Node = get_node_or_null("/root/GameManager")
	var def: Dictionary = gm.card_def(card_id) if gm != null else {}
	var box := CardDescBox.build(CardData.from_def(def) if not def.is_empty() else null,
			maxf(w, 320.0), true)
	box.custom_minimum_size = Vector2(0.0, box.size.y)
	holder.add_child(box)
	return box


static func _clear(n: Node) -> void:
	for c in n.get_children():
		n.remove_child(c)
		c.queue_free()


## F6 단독 실행 미리보기 — 메모리 런의 내 첫 선수에게 깨달음 하나를 쌓아 연다
## (`resources/UiPreview.gd`). 저장은 하지 않는다.
func _fill_preview() -> void:
	UiPreview.stage(self)
	UiPreview.trace(closed)
	var gm: Node = UiPreview.ensure_run()
	if gm == null:
		return
	var s: Dictionary = gm.season_state
	if not s.has(Awakening.KEY_GAUGE):
		Awakening.init_run(s)
		PilotLoadout.init_run(s)
	var pid: int = int(MentalSystem.my_pilot_ids(s)[0])
	if Awakening.pending_count(s, pid) == 0:
		Awakening.add_gauge(s, pid, Awakening.threshold(), "preview")
	open(pid)
