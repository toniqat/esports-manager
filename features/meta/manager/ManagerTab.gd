class_name ManagerTab
extends Control

# 감독 (Manager) screen body, shown in the lobby 감독 modal (`ManagerPopup`, its host). Tab
# contract: header of `features/meta/lobby/LobbyScreen.gd`;
# scope: plan §12 (work C), rules: `ManagerProgress` / `TraitSystem`.
#
#   ┌ header card — type · Lv · EXP bar · prestige count · [프레스티지] ┐
#   │ ManagerPresetChips (all presets; ● 사용 중 / 재설정 필요)          │
#   │ (prestige preset → reset card)                                  │
#   │ stats card — removal / specialisation counters, six rows:        │
#   │   label · 유형 n · 제거 −n · 전문화 +n · final · [제거] [−] n [+]   │
#   │ TraitPickerView — bonus gauge, slots, owned / locked traits      │
#   └ action bar: [이 프리셋 사용 (1) | 저장 (2)]                       ┘
#
# Editing model:
# - The chip-selected preset is edited on a **draft copy** (`_draft`); `저장` validates
#   it with `ManagerProgress.validate_preset` and writes it back + `save_profile()`.
#   Over-budget trait sets (bonus < 0) may be built on the draft — shown red — but
#   never saved. Switching preset / prestiging with unsaved edits asks first.
# - Removals are profile-level and permanent: confirm → `remove_stat` → save at once.
# - Prestige presets are read-only until `재설정` (`reset_preset`, saved at once).
# - Layout lives in `UI_View_ManagerTab.tscn` (+ one `UI_Comp_ManagerStatRow.tscn` per stat, and the shared
#   `ManagerPresetChips` / `TraitPickerView` scenes); every change refills the same nodes
#   (`_rebuild`), so the scroll position stays.

const SCENE_PATH: String = "res://features/meta/manager/UI_View_ManagerTab.tscn"
const STAT_ROW_SCENE: PackedScene = preload("res://features/meta/manager/UI_Comp_ManagerStatRow.tscn")

## Order of the prestige reward items (profile currency keys).
const REWARD_ORDER: Array = ["outgame", "gacha_ticket_pilot", "gacha_ticket_trait"]

var _host = null     # LobbyScreen or ManagerPopup (duck-typed host services)
var _pm: Node
var _type_popup: ManagerTypePopup = null

var _edit_idx: int = -1
var _draft: Dictionary = {}
var _dirty: bool = false
## Trait ids that were unseen when this tab was opened — "NEW" until the lobby closes.
var _new_ids: Array = []
var _rows: Dictionary = {}           # String stat key → ManagerStatRow instance

@onready var _scroll: ScrollContainer = %Scroll
@onready var _traits_view: TraitPickerView = %TraitPickerView_Traits
@onready var _preset_chips: ManagerPresetChips = %ManagerPresetChips_PresetChips


## Layout lives in `UI_View_ManagerTab.tscn` — build with this, not `.new()`.
static func create() -> ManagerTab:
	return (load(SCENE_PATH) as PackedScene).instantiate() as ManagerTab


func _ready() -> void:
	%Prestige.pressed.connect(_on_prestige_pressed)
	%Reset.pressed.connect(_on_reset_pressed)
	_traits_view.trait_pressed.connect(_on_trait_pressed)
	_preset_chips.chip_pressed.connect(_on_chip_pressed)
	for i in StaffSystem.STATS.size():
		var key: String = String(StaffSystem.STATS[i])
		var row: Control = STAT_ROW_SCENE.instantiate()
		%StatRows.add_child(row)
		row.get_node("%Divider").visible = i > 0
		row.get_node("%Key").text = StaffSystem.stat_label(key)
		(row.get_node("%Remove") as Button).pressed.connect(_on_remove_pressed.bind(key))
		(row.get_node("%Minus") as Button).pressed.connect(_on_alloc_pressed.bind(key, -1))
		(row.get_node("%Plus") as Button).pressed.connect(_on_alloc_pressed.bind(key, 1))
		_rows[key] = row
	if UiPreview.is_standalone(self):
		_fill_preview()


# ── Tab contract ─────────────────────────────────────────────────────────────
func bar_specs() -> Array:
	return [
		{"text": _use_text(), "style": "ghost", "font": 28, "weight": 1.0},
		{"text": _save_text(), "style": "primary", "font": 32, "weight": 1.4},
	]


func setup(host: Node) -> void:
	_host = host
	_pm = get_node("/root/ProfileManager")


func on_shown() -> void:
	var prof: Dictionary = _pm.profile
	if not _dirty or _edit_idx < 0 or _edit_idx >= ManagerProgress.presets(prof).size():
		_load_draft(ManagerProgress.active_index(prof) if _edit_idx < 0 else _edit_idx)
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


func on_bar_pressed(i: int) -> void:
	if i == 0:
		_commit(true)
	else:
		_commit(false)


# ── State ────────────────────────────────────────────────────────────────────
func _load_draft(idx: int) -> void:
	_edit_idx = clampi(idx, 0, maxi(0, ManagerProgress.presets(_pm.profile).size() - 1))
	_draft = ManagerProgress.preset_copy(_pm.profile, _edit_idx)
	_dirty = false


func _is_prestige_kind() -> bool:
	return String(_draft.get("kind", ManagerProgress.KIND_NORMAL)) == ManagerProgress.KIND_PRESTIGE


func _use_text() -> String:
	if _pm == null:
		return Loc.t(L.MANAGER_TAB_USE_PRESET)
	if _edit_idx == ManagerProgress.active_index(_pm.profile) and not _dirty:
		return Loc.t(L.MANAGER_TAB_IN_USE)
	return Loc.t(L.MANAGER_TAB_SAVE_AND_USE) if _dirty else Loc.t(L.MANAGER_TAB_USE_PRESET)


func _save_text() -> String:
	return Loc.t(L.MANAGER_TAB_SAVE) if _dirty or _pm == null else Loc.t(L.MANAGER_TAB_SAVED)


func _refresh_bar() -> void:
	var bs: Array = _host.bar_buttons()
	if bs.size() < 2:
		return
	var use_btn: Button = bs[0]
	var save_btn: Button = bs[1]
	use_btn.text = _use_text()
	use_btn.disabled = _edit_idx == ManagerProgress.active_index(_pm.profile) and not _dirty
	save_btn.text = _save_text()
	save_btn.disabled = not _dirty


func _owned() -> Array:
	return _pm.owned_trait_ids()


## `저장` (make_active = false) / `이 프리셋 사용` (true). Never stores an invalid preset.
func _commit(make_active: bool) -> void:
	var prof: Dictionary = _pm.profile
	if _dirty:
		var err: String = ManagerProgress.validate_preset(prof, _draft, _owned())
		if err != "":
			_host.show_toast(Loc.t(L.MANAGER_TAB_CANNOT_SAVE, {"error": err}), true)
			return
	elif make_active:
		var verr: String = ManagerProgress.validate_preset(prof,
				ManagerProgress.preset_at(prof, _edit_idx), _owned())
		if verr != "":
			_host.show_toast(Loc.t(L.MANAGER_TAB_CANNOT_USE, {"error": verr}), true)
			return
	if _dirty:
		ManagerProgress.store_preset(prof, _edit_idx, _draft)
	if make_active:
		prof["active_preset"] = _edit_idx
	var serr: String = _pm.save_profile()
	if serr != "":
		_host.show_toast(Loc.t(L.UI_ERROR_PROFILE_SAVE_FAILED, {"error": serr}), true)
		return
	_dirty = false
	_draft = ManagerProgress.preset_copy(prof, _edit_idx)
	Haptics.play(Haptics.Kind.SUCCESS)
	if make_active:
		_host.show_toast(Loc.t(L.MANAGER_TAB_TOAST_USE, {"preset": ManagerUi.preset_name(_edit_idx)}))
	else:
		_host.show_toast(Loc.t(L.MANAGER_TAB_TOAST_SAVED, {"preset": ManagerUi.preset_name(_edit_idx)}))
	_rebuild()


func _mark_dirty() -> void:
	_dirty = true
	_rebuild()


# ── Fill ─────────────────────────────────────────────────────────────────────
## Refills every block from the profile + draft. Nodes are reused, so the scroll
## position stays where it was.
func _rebuild() -> void:
	_fill_header()
	_preset_chips.fill(_pm.profile, _edit_idx)
	%ResetBox.visible = _is_prestige_kind()
	_fill_stats()
	_traits_view.fill(_draft.get("traits", []), _owned(), _new_ids)
	if _host != null and not _host.bar_buttons().is_empty():
		_refresh_bar()


func _fill_header() -> void:
	var prof: Dictionary = _pm.profile
	var mgr: Dictionary = prof.get("manager", {})
	var trow: Dictionary = StaffSystem.manager_type_row(int(mgr.get("type", 0)))
	%TypeTitle.text = Loc.t(L.MANAGER_TAB_TYPE_TITLE,
			{"type": Loc.t(String(trow.get("name_key", "")))})  # l10n-dynamic: manager.type.*.name
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
	%Info.text = Loc.t(L.MANAGER_TAB_INFO, {"n": ConstTable.int_of("MANAGER_REMOVE_PER_LEVEL"),
			"gain": ManagerProgress.spec_per_removal()})


func _fill_stats() -> void:
	var prof: Dictionary = _pm.profile
	var left: int = ManagerProgress.removal_points_left(prof)
	var spec_total: int = ManagerProgress.spec_points(prof)
	var used: int = ManagerProgress.alloc_used(_draft)
	_paint_chip(%RemoveChip, %RemoveChipText, Loc.t(L.MANAGER_TAB_REMOVAL_POINTS, {"n": left}),
			OutgameTheme.ACCENT_DIM if left > 0 else OutgameTheme.SURFACE_SUNK,
			OutgameTheme.ACCENT_TEXT if left > 0 else OutgameTheme.TEXT_SUB)
	_paint_chip(%SpecChip, %SpecChipText,
			Loc.t(L.MANAGER_TAB_SPEC_POINTS, {"used": used, "total": spec_total}),
			OutgameTheme.SURFACE_SUNK,
			OutgameTheme.NEGATIVE if used > spec_total else OutgameTheme.TEXT_SUB)
	%Formula.text = Loc.t(L.MANAGER_TAB_FORMULA, {"cap": ManagerProgress.stat_cap()})

	var tstats: Dictionary = ManagerProgress.type_stats(int((prof.get("manager", {}) as Dictionary).get("type", 0)))
	var rm: Dictionary = ManagerProgress.removed(prof)
	var final_stats: Dictionary = ManagerProgress.preset_stats(prof, _draft)
	var alloc: Dictionary = _draft.get("alloc", {})
	var editable: bool = not _is_prestige_kind()
	for key in _rows.keys():
		var row: Control = _rows[key]
		var a: int = int(alloc.get(key, 0))
		# Breakdown items joined with the symbol separator " · " (a list, not a sentence).
		var parts: PackedStringArray = [Loc.t(L.MANAGER_TAB_PART_TYPE, {"n": int(tstats[key])})]
		if int(rm[key]) > 0:
			parts.append(Loc.t(L.MANAGER_TAB_PART_REMOVED,
					{"n": int(rm[key]) * ManagerProgress.remove_stat_drop()}))
		if a > 0:
			parts.append(Loc.t(L.MANAGER_TAB_PART_SPEC, {"n": a}))
		row.get_node("%Parts").text = " · ".join(parts)
		var fl: Label = row.get_node("%Final")
		fl.text = str(int(final_stats[key]))
		fl.theme_type_variation = &"AccentLabel" if a > 0 else &"BodyLabel"
		var al: Label = row.get_node("%Alloc")
		al.text = "+%d" % a if a > 0 else "0"
		al.theme_type_variation = &"AccentLabel" if a > 0 else &"FaintLabel"
		(row.get_node("%Remove") as Button).disabled = ManagerProgress.can_remove(prof, key) != ""
		(row.get_node("%Minus") as Button).disabled = not editable \
				or ManagerProgress.can_alloc(prof, _draft, key, -1) != ""
		(row.get_node("%Plus") as Button).disabled = not editable \
				or ManagerProgress.can_alloc(prof, _draft, key, 1) != ""


## A pill whose fill / text colours are data (`OutgameTheme.add_chip` look: radius = half height).
func _paint_chip(chip: Panel, text_lbl: Label, text: String, bg: Color, fg: Color) -> void:
	chip.add_theme_stylebox_override("panel", OutgameTheme.flat_style(bg, int(chip.size.y * 0.5)))
	text_lbl.text = text
	text_lbl.add_theme_color_override("font_color", fg)


# ── Actions ──────────────────────────────────────────────────────────────────
func _on_chip_pressed(idx: int) -> void:
	if idx == _edit_idx:
		return
	if _dirty:
		_host.open_confirm(Loc.t(L.MANAGER_TAB_DISCARD_TITLE),
				Loc.t(L.MANAGER_TAB_DISCARD_BODY, {
					"from": ManagerUi.preset_name(_edit_idx), "to": ManagerUi.preset_name(idx)}),
				Loc.t(L.UI_BUTTON_CANCEL), Loc.t(L.MANAGER_TAB_DISCARD_CONFIRM), true,
				_switch_preset.bind(idx))
		return
	_switch_preset(idx)


func _switch_preset(idx: int) -> void:
	Haptics.play(Haptics.Kind.SELECT)
	_load_draft(idx)
	_rebuild()


func _on_alloc_pressed(stat: String, delta: int) -> void:
	var err: String = ManagerProgress.alloc_step(_pm.profile, _draft, stat, delta)
	if err != "":
		_host.show_toast(err, true)
		return
	_mark_dirty()


func _on_trait_pressed(trait_id: int) -> void:
	if _is_prestige_kind():
		_host.show_toast(Loc.t(L.MANAGER_TAB_PRESTIGE_READONLY), true)
		return
	var err: String = ManagerProgress.toggle_trait(_draft, trait_id, _owned())
	if err != "":
		_host.show_toast(err, true)
		return
	Haptics.play(Haptics.Kind.SELECT)
	_mark_dirty()
	if TraitSystem.bonus_points(_draft.get("traits", [])) < 0:
		_host.show_toast(Loc.t(L.MANAGER_TAB_BONUS_NEGATIVE), true)


func _on_remove_pressed(stat: String) -> void:
	var prof: Dictionary = _pm.profile
	var err: String = ManagerProgress.can_remove(prof, stat)
	if err != "":
		_host.show_toast(err, true)
		return
	var label: String = StaffSystem.stat_label(stat)
	var cur: int = int(ManagerProgress.base_stats(prof)[stat])
	Haptics.play(Haptics.Kind.WARNING)
	_host.open_confirm(Loc.t(L.MANAGER_TAB_REMOVE_TITLE, {"stat": label}),
			Loc.t(L.MANAGER_TAB_REMOVE_BODY, {"stat": label, "from": cur,
					"to": maxi(StaffSystem.STAT_MIN, cur - ManagerProgress.remove_stat_drop()),
					"gain": ManagerProgress.spec_per_removal()}),
			Loc.t(L.UI_BUTTON_CANCEL), Loc.t(L.UI_BUTTON_REMOVE), true, _apply_remove.bind(stat))


func _apply_remove(stat: String) -> void:
	var err: String = ManagerProgress.remove_stat(_pm.profile, stat)
	if err != "":
		_host.show_toast(err, true)
		return
	var serr: String = _pm.save_profile()
	if serr != "":
		_host.show_toast(Loc.t(L.UI_ERROR_PROFILE_SAVE_FAILED, {"error": serr}), true)
	else:
		Haptics.play(Haptics.Kind.MEDIUM)
		_host.show_toast(Loc.t(L.MANAGER_TAB_REMOVED_TOAST, {"stat": StaffSystem.stat_label(stat),
				"drop": ManagerProgress.remove_stat_drop(), "gain": ManagerProgress.spec_per_removal()}))
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
	var body: String = Loc.t(L.MANAGER_TAB_PRESTIGE_BODY_UNSAVED, rw) if _dirty \
			else Loc.t(L.MANAGER_TAB_PRESTIGE_BODY, rw)
	Haptics.play(Haptics.Kind.WARNING)
	_host.open_confirm(Loc.t(L.MANAGER_TAB_PRESTIGE_TITLE), body,
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
## 프레스티지)은 누름을 출력만 한다. 행동 바 · 토스트는 호스트(`LobbyScreen`) 몫이라 없다.
func _fill_preview() -> void:  # l10n-ignore
	# 호스트가 하듯 탭 루트를 화면 전체로 편다(씬의 1080 × n 은 에디터 미리보기 크기일 뿐).
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	UiPreview.stage(self)
	setup(null)
	UiPreview.mute(%Prestige, self, "프레스티지")
	UiPreview.mute(%Reset, self, "재설정")
	for key in _rows.keys():
		UiPreview.mute((_rows[key] as Control).get_node("%Remove"), self, "제거 " + String(key))
	var pending: Array = (_pm.profile.get("traits", {}) as Dictionary).get("unlocked_pending", [])
	for raw in pending:
		_new_ids.append(int(raw))
	_load_draft(ManagerProgress.active_index(_pm.profile))
	_rebuild()
