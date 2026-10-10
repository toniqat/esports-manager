class_name ManagerTab
extends Control

# 감독 (Manager) screen body, shown in the lobby 감독 modal (`ManagerPopup`, its host). Host
# services: header of `features/meta/lobby/LobbyScreen.gd` (toast, confirm, currency / badges);
# scope: plan §12 (work C), rules: `ManagerProgress` / `TraitSystem`.
#
#   ┌ header card — Lv · prestige count · EXP bar · [프레스티지]          ┐
#   │                              ( I  II  III  IV  V )  preset capsule  │
#   │ (prestige preset → reset card)                                     │
#   │ 감독 능력치 ······· 전문화 포인트 used/total  |  제거 포인트 n [확정]   │
#   │   [훈련][전술][지식][멘탈][분석][관리]   6 cards in one row, each with  │
#   │   [−7+] [−4+] …                       an adjust strip at the bottom │
#   └ TraitPickerView — (보너스 점수 +n), equipped trait cards, [교체]      ┘
#
# Editing model — **everything saves at once** (no draft / save bar):
# - A preset tap makes it the active preset (saved). A prestige preset can't be used: the tap only
#   selects it so its reset card shows; it stays read-only until `재설정` (`reset_preset`).
# - Stat cards have two modes. **Spec mode** (no removal points left): − value + steps the selected
#   preset's specialisation; the value includes it. **Removal mode** (removal points left — after a
#   level-up): the strips turn light green, − places a removal on that stat, + takes it back
#   (`_pending`, nothing saved yet); `확정` → danger confirm → `remove_stat` per placed point → save.
#   Removals are profile-level (every preset) and permanent until prestige. Steppers are shown
#   only when that step is possible (never dimmed).
# - Spec steps and trait swaps edit the selected preset; each change is validated with
#   `ManagerProgress.validate_preset` and stored + saved (`_store`). An invalid result is never
#   stored (the screen falls back to the saved preset). Trait sets are edited in the swap popup
#   (`TraitPickerView.open_swap`), which only hands back valid sets.
# - Layout lives in `UI_View_ManagerTab.tscn` (+ one `UI_Comp_ManagerStatCard.tscn` per stat, and the shared
#   `ManagerPresetChips` / `TraitPickerView` scenes); every change refills the same nodes
#   (`_rebuild`), so the scroll position stays.

const SCENE_PATH: String = "res://features/meta/manager/UI_View_ManagerTab.tscn"
const STAT_CARD_SCENE: PackedScene = preload("res://features/meta/manager/UI_Comp_ManagerStatCard.tscn")

## Order of the prestige reward items (profile currency keys).
const REWARD_ORDER: Array = ["outgame", "gacha_ticket_pilot", "gacha_ticket_trait"]

var _host = null     # ManagerPopup (duck-typed host services)
var _pm: Node
var _type_popup: ManagerTypePopup = null

var _edit_idx: int = -1
var _draft: Dictionary = {}          # working copy of preset `_edit_idx` (= the saved one between taps)
## Trait ids that were unseen when this screen was opened — "NEW" until the lobby closes.
var _new_ids: Array = []
var _cards: Dictionary = {}          # String stat key → ManagerStatCard instance
## Removal mode: removal points placed but not confirmed yet (stat key → count).
var _pending: Dictionary = {}

@onready var _traits_view: TraitPickerView = %TraitPickerView_Traits
@onready var _preset_chips: ManagerPresetChips = %ManagerPresetChips_PresetChips


## Layout lives in `UI_View_ManagerTab.tscn` — build with this, not `.new()`.
static func create() -> ManagerTab:
	return (load(SCENE_PATH) as PackedScene).instantiate() as ManagerTab


func _ready() -> void:
	%Prestige.pressed.connect(_on_prestige_pressed)
	%Reset.pressed.connect(_on_reset_pressed)
	_traits_view.swap_requested.connect(_on_swap_requested)
	_traits_view.traits_applied.connect(_on_traits_applied)
	_preset_chips.chip_pressed.connect(_on_chip_pressed)
	%RemoveConfirm.pressed.connect(_on_remove_confirm_pressed)
	for key in StaffSystem.STATS:
		var card: Control = STAT_CARD_SCENE.instantiate()
		%StatCards.add_child(card)
		(card.get_node("%Icon") as TextureRect).texture = ManagerUi.stat_icon(String(key))
		card.get_node("%Key").text = StaffSystem.stat_label(String(key))
		(card.get_node("%Minus") as Button).pressed.connect(_on_step_pressed.bind(String(key), -1))
		(card.get_node("%Plus") as Button).pressed.connect(_on_step_pressed.bind(String(key), 1))
		_cards[String(key)] = card
	if UiPreview.is_standalone(self):
		_fill_preview()


# ── Host contract ────────────────────────────────────────────────────────────
func setup(host: Node) -> void:
	_host = host
	_pm = get_node("/root/ProfileManager")


## Every open of the modal: back on the active preset, NEW traits marked for this visit.
func on_shown() -> void:
	var prof: Dictionary = _pm.profile
	_load_draft(ManagerProgress.active_index(prof))
	_pending.clear()
	# Newly unlocked traits: mark them NEW for this visit, then clear the pending list.
	var tr: Dictionary = prof.get("traits", {})
	var pending: Array = tr.get("unlocked_pending", [])
	if not pending.is_empty():
		for raw in pending:
			if not _new_ids.has(int(raw)):
				_new_ids.append(int(raw))
		tr["unlocked_pending"] = []
		var err: String = _pm.save_profile()
		if err != "":
			_host.show_toast(Loc.t(L.UI_ERROR_PROFILE_SAVE_FAILED, {"error": err}), true)
		_host.refresh_badges()
	_rebuild()


# ── State ────────────────────────────────────────────────────────────────────
func _load_draft(idx: int) -> void:
	_edit_idx = clampi(idx, 0, maxi(0, ManagerProgress.presets(_pm.profile).size() - 1))
	_draft = ManagerProgress.preset_copy(_pm.profile, _edit_idx)


func _is_prestige_kind() -> bool:
	return String(_draft.get("kind", ManagerProgress.KIND_NORMAL)) == ManagerProgress.KIND_PRESTIGE


func _owned() -> Array:
	return _pm.owned_trait_ids()


## Validates the draft and stores + saves it. Invalid → red toast, the draft goes back to the
## saved preset. Returns true when stored and saved.
func _store() -> bool:
	var prof: Dictionary = _pm.profile
	var err: String = ManagerProgress.validate_preset(prof, _draft, _owned())
	if err != "":
		_host.show_toast(Loc.t(L.MANAGER_TAB_CANNOT_SAVE, {"error": err}), true)
		_load_draft(_edit_idx)
		_rebuild()
		return false
	ManagerProgress.store_preset(prof, _edit_idx, _draft)
	var serr: String = _pm.save_profile()
	if serr != "":
		_host.show_toast(Loc.t(L.UI_ERROR_PROFILE_SAVE_FAILED, {"error": serr}), true)
	_draft = ManagerProgress.preset_copy(prof, _edit_idx)
	_rebuild()
	return serr == ""


# ── Fill ─────────────────────────────────────────────────────────────────────
## Refills every block from the profile + draft. Nodes are reused, so the scroll
## position stays where it was.
func _rebuild() -> void:
	_fill_header()
	_preset_chips.fill(_pm.profile, _edit_idx)
	%ResetBox.visible = _is_prestige_kind()
	_fill_stats()
	_traits_view.fill(_draft.get("traits", []), _owned(), _new_ids)


func _fill_header() -> void:
	var prof: Dictionary = _pm.profile
	var mgr: Dictionary = prof.get("manager", {})
	var pcount: int = int(mgr.get("prestige", 0))
	_paint_chip(%PrestigeChip, %PrestigeChipText, Loc.t(L.MANAGER_TAB_PRESTIGE_COUNT, {"n": pcount}),
			OutgameTheme.ACCENT_DIM if pcount > 0 else OutgameTheme.SURFACE_SUNK,
			OutgameTheme.ACCENT_TEXT if pcount > 0 else OutgameTheme.TEXT_SUB)

	var lp: Dictionary = ManagerProgress.level_progress(prof)
	%Level.text = "Lv %d" % int(lp["level"])
	var ratio: float = 1.0 if bool(lp["is_max"]) \
			else float(int(lp["into"])) / float(maxi(1, int(lp["span"])))
	var fill: Panel = %ExpFill
	fill.visible = ratio > 0.0
	fill.anchor_right = ratio
	fill.custom_minimum_size.x = fill.size.y if ratio > 0.0 else 0.0   # never thinner than round
	%ExpText.text = Loc.t(L.UI_WORD_MAX_LEVEL) if bool(lp["is_max"]) \
			else "EXP %d / %d" % [int(lp["into"]), int(lp["span"])]

	var perr: String = ManagerProgress.can_prestige(prof)
	var pb: Button = %Prestige
	pb.text = Loc.t(L.MANAGER_TAB_PRESTIGE) if perr == "" \
			else Loc.t(L.MANAGER_TAB_PRESTIGE_AT, {"level": ManagerProgress.prestige_level()})
	pb.theme_type_variation = &"PrimaryButton" if perr == "" else &"GhostButton"
	pb.add_theme_font_size_override("font_size", 26 if perr == "" else 24)
	pb.disabled = perr != ""


func _fill_stats() -> void:
	var prof: Dictionary = _pm.profile
	var removing: bool = _removal_mode()
	var left: int = ManagerProgress.removal_points_left(prof) - _pending_total()
	var spec_total: int = ManagerProgress.spec_points(prof)
	var used: int = ManagerProgress.alloc_used(_draft)
	(%RemoveChip as Control).visible = removing
	(%RemoveConfirm as Button).visible = removing
	(%SpecChip as Control).visible = not removing
	if removing:
		_paint_chip(%RemoveChip, %RemoveChipText, Loc.t(L.MANAGER_TAB_REMOVAL_POINTS, {"n": left}),
				OutgameTheme.ACCENT_DIM if left > 0 else OutgameTheme.SURFACE_SUNK,
				OutgameTheme.ACCENT_TEXT if left > 0 else OutgameTheme.TEXT_SUB)
		(%RemoveConfirm as Button).disabled = _pending_total() == 0
	else:
		_paint_chip(%SpecChip, %SpecChipText,
				Loc.t(L.MANAGER_TAB_SPEC_POINTS, {"used": used, "total": spec_total}),
				OutgameTheme.SURFACE_SUNK,
				OutgameTheme.NEGATIVE if used > spec_total else OutgameTheme.TEXT_SUB)

	var base: Dictionary = ManagerProgress.base_stats(prof)
	var final_stats: Dictionary = ManagerProgress.preset_stats(prof, _draft)
	var alloc: Dictionary = _draft.get("alloc", {})
	var editable: bool = not _is_prestige_kind()
	for key in _cards.keys():
		var card: Control = _cards[key]
		(card.get_node("%Adjust") as Control).theme_type_variation = \
				&"ManagerStatAdjustRemove" if removing else &"ManagerStatAdjust"
		var vl: Label = card.get_node("%Value")
		var minus: Button = card.get_node("%Minus")
		var plus: Button = card.get_node("%Plus")
		if removing:
			# The base value after the placed removals (every preset), red while lowered.
			var p: int = int(_pending.get(key, 0))
			vl.text = str(_base_after_pending(base, key))
			vl.theme_type_variation = &"NegativeLabel" if p > 0 else &"BodyLabel"
			minus.visible = _can_place_removal(base, key)
			plus.visible = p > 0
		else:
			# One number: the stat as this preset gives it (type − removals + specialisation).
			var a: int = int(alloc.get(key, 0))
			vl.text = str(int(final_stats[key]))
			vl.theme_type_variation = &"AccentLabel" if a > 0 else &"BodyLabel"
			minus.visible = editable and ManagerProgress.can_alloc(prof, _draft, key, -1) == ""
			plus.visible = editable and ManagerProgress.can_alloc(prof, _draft, key, 1) == ""


## Removal mode = the profile still has removal points to spend (after a level-up).
func _removal_mode() -> bool:
	return ManagerProgress.removal_points_left(_pm.profile) > 0


func _pending_total() -> int:
	var n: int = 0
	for k in _pending.keys():
		n += int(_pending[k])
	return n


func _base_after_pending(base: Dictionary, stat: String) -> int:
	return int(base[stat]) - int(_pending.get(stat, 0)) * ManagerProgress.remove_stat_drop()


## One more removal fits: a point is left and the base stays at or above `STAT_MIN`.
func _can_place_removal(base: Dictionary, stat: String) -> bool:
	if ManagerProgress.removal_points_left(_pm.profile) - _pending_total() <= 0:
		return false
	return _base_after_pending(base, stat) - ManagerProgress.remove_stat_drop() >= StaffSystem.STAT_MIN


## A pill whose fill / text colours are data (`OutgameTheme.add_chip` look: radius = half height).
func _paint_chip(chip: Panel, text_lbl: Label, text: String, bg: Color, fg: Color) -> void:
	chip.add_theme_stylebox_override("panel", OutgameTheme.flat_style(bg, int(chip.size.y * 0.5)))
	text_lbl.text = text
	text_lbl.add_theme_color_override("font_color", fg)


# ── Actions ──────────────────────────────────────────────────────────────────
## Preset tap = use it (saved at once). A prestige preset is only selected (its reset card shows).
func _on_chip_pressed(idx: int) -> void:
	if idx == _edit_idx:
		return
	Haptics.play(Haptics.Kind.SELECT)
	_load_draft(idx)
	if not _is_prestige_kind():
		_pm.profile["active_preset"] = _edit_idx
		var serr: String = _pm.save_profile()
		if serr != "":
			_host.show_toast(Loc.t(L.UI_ERROR_PROFILE_SAVE_FAILED, {"error": serr}), true)
	_rebuild()


## − / + on a stat card: places / takes back a removal in removal mode, steps the
## specialisation otherwise.
func _on_step_pressed(stat: String, delta: int) -> void:
	if _removal_mode():
		var base: Dictionary = ManagerProgress.base_stats(_pm.profile)
		if delta < 0 and _can_place_removal(base, stat):
			_pending[stat] = int(_pending.get(stat, 0)) + 1
		elif delta > 0 and int(_pending.get(stat, 0)) > 0:
			_pending[stat] = int(_pending[stat]) - 1
		else:
			return
		Haptics.play(Haptics.Kind.SELECT)
		_rebuild()
		return
	var err: String = ManagerProgress.alloc_step(_pm.profile, _draft, stat, delta)
	if err != "":
		_host.show_toast(err, true)
		return
	Haptics.play(Haptics.Kind.SELECT)
	_store()


func _on_swap_requested() -> void:
	if _is_prestige_kind():
		_host.show_toast(Loc.t(L.MANAGER_TAB_PRESTIGE_READONLY), true)
		return
	_traits_view.open_swap()


func _on_traits_applied(traits: Array) -> void:
	_draft["traits"] = traits
	if _store():
		Haptics.play(Haptics.Kind.SUCCESS)
		_host.show_toast(Loc.t(L.MANAGER_TAB_TOAST_SAVED, {"preset": ManagerUi.preset_name(_edit_idx)}))


## 확정 (removal mode): danger confirm listing every lowered base value, then spends them.
func _on_remove_confirm_pressed() -> void:
	var n: int = _pending_total()
	if n <= 0:
		return
	var base: Dictionary = ManagerProgress.base_stats(_pm.profile)
	var lines: PackedStringArray = []
	for key in StaffSystem.STATS:
		if int(_pending.get(key, 0)) > 0:
			lines.append(Loc.t(L.MANAGER_TAB_REMOVE_ITEM, {"stat": StaffSystem.stat_label(String(key)),
					"from": int(base[key]), "to": _base_after_pending(base, String(key))}))
	Haptics.play(Haptics.Kind.WARNING)
	_host.open_confirm(Loc.t(L.MANAGER_TAB_REMOVE_BATCH_TITLE),
			Loc.t(L.MANAGER_TAB_REMOVE_BATCH_BODY, {"n": n, "list": "\n".join(lines),
					"gain": n * ManagerProgress.spec_per_removal()}),
			Loc.t(L.UI_BUTTON_CANCEL), Loc.t(L.UI_BUTTON_REMOVE), true, _apply_pending_removals)


func _apply_pending_removals() -> void:
	var prof: Dictionary = _pm.profile
	var spent: int = 0
	for key in StaffSystem.STATS:
		for i in int(_pending.get(key, 0)):
			var err: String = ManagerProgress.remove_stat(prof, String(key))
			if err != "":
				_host.show_toast(err, true)
				break
			spent += 1
	_pending.clear()
	var serr: String = _pm.save_profile()
	if serr != "":
		_host.show_toast(Loc.t(L.UI_ERROR_PROFILE_SAVE_FAILED, {"error": serr}), true)
	elif spent > 0:
		Haptics.play(Haptics.Kind.MEDIUM)
		_host.show_toast(Loc.t(L.MANAGER_TAB_REMOVED_BATCH_TOAST,
				{"gain": spent * ManagerProgress.spec_per_removal()}))
	_load_draft(_edit_idx)
	_rebuild()


func _on_reset_pressed() -> void:
	var prof: Dictionary = _pm.profile
	var p: Dictionary = ManagerProgress.preset_at(prof, _edit_idx)
	if p.is_empty():
		return
	ManagerProgress.reset_preset(p)
	var serr: String = _pm.save_profile()
	if serr != "":
		_host.show_toast(Loc.t(L.UI_ERROR_PROFILE_SAVE_FAILED, {"error": serr}), true)
	else:
		_host.show_toast(Loc.t(L.MANAGER_TAB_RESET_TOAST, {"preset": ManagerUi.preset_name(_edit_idx)}))
	_load_draft(_edit_idx)
	_rebuild()


func _on_prestige_pressed() -> void:
	var err: String = ManagerProgress.can_prestige(_pm.profile)
	if err != "":
		_host.show_toast(err, true)
		return
	var rw: Dictionary = {"rewards": _reward_text(),
			"presets": maxi(1, ConstTable.int_of("PRESTIGE_NEW_PRESETS"))}
	Haptics.play(Haptics.Kind.WARNING)
	_host.open_confirm(Loc.t(L.MANAGER_TAB_PRESTIGE_TITLE), Loc.t(L.MANAGER_TAB_PRESTIGE_BODY, rw),
			Loc.t(L.UI_BUTTON_CANCEL), Loc.t(L.MANAGER_TAB_PICK_TYPE), false, _open_prestige_popup)


func _open_prestige_popup() -> void:
	if _type_popup == null:
		_type_popup = ManagerTypePopup.create()
		add_child(_type_popup)
		_type_popup.chosen.connect(_on_prestige_type_chosen)
	_type_popup.open(true, int((_pm.profile.get("manager", {}) as Dictionary).get("type", 0)))


func _on_prestige_type_chosen(type_id: int) -> void:
	var prof: Dictionary = _pm.profile
	var res: Dictionary = ManagerProgress.prestige(prof, type_id)
	if res.has("error"):
		_host.show_toast(String(res["error"]), true)
		return
	var serr: String = _pm.save_profile()
	_load_draft(ManagerProgress.active_index(prof))
	_rebuild()
	_host.refresh_currency()
	if serr != "":
		_host.show_toast(Loc.t(L.UI_ERROR_PROFILE_SAVE_FAILED, {"error": serr}), true)
		return
	Haptics.play(Haptics.Kind.SUCCESS)
	_host.show_toast(Loc.t(L.MANAGER_TAB_PRESTIGE_DONE, {"rewards": _reward_text(res.get("rewards", {}))}))


## "재화 500 · 선수권 3 · 특성권 2" — from `rewards` or the const values.
func _reward_text(rewards: Dictionary = {}) -> String:
	var r: Dictionary = rewards
	if r.is_empty():
		r = {
			"outgame": ConstTable.int_of("PRESTIGE_REWARD_OUTGAME"),
			"gacha_ticket_pilot": ConstTable.int_of("PRESTIGE_REWARD_PILOT_TICKETS"),
			"gacha_ticket_trait": ConstTable.int_of("PRESTIGE_REWARD_TRAIT_TICKETS"),
		}
	var out: Array = []
	for k in REWARD_ORDER:
		if int(r.get(k, 0)) > 0:
			out.append("%s +%d" % [ShopPopup.currency_label(k), int(r[k])])
	return " · ".join(PackedStringArray(out)) if not out.is_empty() else Loc.t(L.UI_WORD_NONE)


## F6 단독 실행 미리보기 — 실제 프로필의 사용 중 프리셋 (`resources/UiPreview.gd`).
## `on_shown` 은 새 특성 표시를 지우며 프로필을 저장하므로 쓰지 않고, 같은 채움만 한다
## (대기 중인 새 특성은 NEW 로 보이되 지우지 않는다). 저장하는 버튼(제거 · 재설정 ·
## 프레스티지 · 제거 확정)은 누름을 출력만 한다. 프리셋 · 스탯 · 특성 교체는 곧바로 저장하므로 실제
## 프로필이 바뀐다 — 미리보기에서는 누르지 말 것. 토스트는 호스트(`ManagerPopup`) 몫이라 없다.
func _fill_preview() -> void:  # l10n-ignore
	# 호스트가 하듯 루트를 화면 전체로 편다(씬의 1080 × n 은 에디터 미리보기 크기일 뿐).
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	UiPreview.stage(self)
	setup(null)
	UiPreview.mute(%Prestige, self, "프레스티지")
	UiPreview.mute(%Reset, self, "재설정")
	UiPreview.mute(%RemoveConfirm, self, "제거 확정")
	var pending: Array = (_pm.profile.get("traits", {}) as Dictionary).get("unlocked_pending", [])
	for raw in pending:
		_new_ids.append(int(raw))
	_load_draft(ManagerProgress.active_index(_pm.profile))
	_rebuild()
