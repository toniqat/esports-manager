class_name ManagerTab
extends Control

# Lobby tab — 감독 (Manager). Tab contract: header of `features/meta/lobby/LobbyScreen.gd`;
# scope: plan §12 (work C), rules: `ManagerProgress` / `TraitSystem`.
#
#   ┌ header card — type · Lv · EXP bar · prestige count · [프레스티지] ┐
#   │ preset chips (all presets; ● 사용 중 / 재설정 필요)                │
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
# - Body = one `OutgameTheme.add_vscroll`, rebuilt after every change (scroll kept).

const PAD_X: float = 24.0
const CARD_PAD: float = 28.0
const SECTION_GAP: float = 28.0
const HEADER_H: float = 236.0
const STAT_ROW_H: float = 92.0
const STAT_HEAD_H: float = 108.0
const STEP_W: float = 80.0
const STEP_H: float = 68.0

var _host: LobbyScreen
var _pm: Node
var _scroll: ScrollContainer
var _body: Control
var _traits_view: TraitPickerView
var _type_popup: ManagerTypePopup = null

var _edit_idx: int = -1
var _draft: Dictionary = {}
var _dirty: bool = false
## Trait ids that were unseen when this tab was opened — "NEW" until the lobby closes.
var _new_ids: Array = []


# ── Tab contract ─────────────────────────────────────────────────────────────
func bar_specs() -> Array:
	return [
		{"text": _use_text(), "style": "ghost", "font": 28, "weight": 1.0},
		{"text": _save_text(), "style": "primary", "font": 32, "weight": 1.4},
	]


func setup(host: LobbyScreen) -> void:
	_host = host
	_pm = get_node("/root/ProfileManager")
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sv: Dictionary = OutgameTheme.add_vscroll(self, Vector2.ZERO, size)
	_scroll = sv["scroll"]
	_body = sv["body"]
	_body.mouse_filter = Control.MOUSE_FILTER_IGNORE


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
			_host.show_toast("프로필 저장 실패: " + err, true)
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
		return "이 프리셋 사용"
	if _edit_idx == ManagerProgress.active_index(_pm.profile) and not _dirty:
		return "사용 중"
	return "저장 후 사용" if _dirty else "이 프리셋 사용"


func _save_text() -> String:
	return "저장" if _dirty or _pm == null else "저장됨"


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
			_host.show_toast("저장할 수 없습니다 — " + err, true)
			return
	elif make_active:
		var verr: String = ManagerProgress.validate_preset(prof,
				ManagerProgress.preset_at(prof, _edit_idx), _owned())
		if verr != "":
			_host.show_toast("사용할 수 없습니다 — " + verr, true)
			return
	if _dirty:
		ManagerProgress.store_preset(prof, _edit_idx, _draft)
	if make_active:
		prof["active_preset"] = _edit_idx
	var serr: String = _pm.save_profile()
	if serr != "":
		_host.show_toast("프로필 저장 실패: " + serr, true)
		return
	_dirty = false
	_draft = ManagerProgress.preset_copy(prof, _edit_idx)
	Haptics.play(Haptics.Kind.SUCCESS)
	if make_active:
		_host.show_toast("%s 을(를) 다음 런에 사용합니다" % ManagerUi.preset_name(_edit_idx))
	else:
		_host.show_toast("%s 저장됨" % ManagerUi.preset_name(_edit_idx))
	_rebuild()


func _mark_dirty() -> void:
	_dirty = true
	_rebuild()


# ── Build ────────────────────────────────────────────────────────────────────
func _rebuild() -> void:
	var keep: int = _scroll.scroll_vertical
	for c in _body.get_children():
		_body.remove_child(c)
		c.queue_free()
	_traits_view = null
	var w: float = size.x - PAD_X * 2.0
	var y: float = 24.0
	y += _build_header(Vector2(PAD_X, y), w) + SECTION_GAP
	y += _build_presets(Vector2(PAD_X, y), w) + SECTION_GAP
	y += _build_stats(Vector2(PAD_X, y), w) + SECTION_GAP

	_traits_view = TraitPickerView.new()
	_traits_view.position = Vector2(PAD_X, y)
	_body.add_child(_traits_view)
	y += _traits_view.build(w, _draft.get("traits", []), _owned(), _new_ids)
	_traits_view.trait_pressed.connect(_on_trait_pressed)
	y += 40.0
	_body.custom_minimum_size = Vector2(size.x, y)
	_scroll.set_deferred("scroll_vertical", keep)
	if _host != null and not _host.bar_buttons().is_empty():
		_refresh_bar()


func _build_header(pos: Vector2, w: float) -> float:
	var prof: Dictionary = _pm.profile
	var card: Panel = OutgameTheme.add_card(_body, pos, Vector2(w, HEADER_H), 20)
	var inner: float = w - CARD_PAD * 2.0
	var mgr: Dictionary = prof.get("manager", {})
	var trow: Dictionary = StaffSystem.manager_type_row(int(mgr.get("type", 0)))
	UiHelpers.mk_label(card, "%s 감독" % String(trow.get("name", "감독")), 36, OutgameTheme.TEXT,
			Vector2(CARD_PAD, 22), Vector2(inner - 300, 48))
	var pcount: int = int(mgr.get("prestige", 0))
	OutgameTheme.add_chip(card, "프레스티지 %d회" % pcount, Vector2(w - CARD_PAD - 200, 28),
			Vector2(200, 40), OutgameTheme.ACCENT_DIM if pcount > 0 else OutgameTheme.SURFACE_SUNK,
			OutgameTheme.ACCENT_TEXT if pcount > 0 else OutgameTheme.TEXT_SUB, 20)

	var lp: Dictionary = ManagerProgress.level_progress(prof)
	UiHelpers.mk_label(card, "Lv %d" % int(lp["level"]), 34, OutgameTheme.ACCENT_TEXT,
			Vector2(CARD_PAD, 82), Vector2(160, 46))
	var bar_x: float = CARD_PAD + 150.0
	var bar_w: float = inner - 150.0 - 250.0
	var track := Panel.new()
	track.add_theme_stylebox_override("panel", OutgameTheme.flat_style(OutgameTheme.SURFACE_SUNK, 8))
	track.position = Vector2(bar_x, 98)
	track.size = Vector2(bar_w, 16)
	track.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(track)
	var ratio: float = 1.0 if bool(lp["is_max"]) \
			else float(int(lp["into"])) / float(maxi(1, int(lp["span"])))
	var fill := Panel.new()
	fill.add_theme_stylebox_override("panel", OutgameTheme.flat_style(OutgameTheme.ACCENT, 8))
	fill.position = Vector2.ZERO
	fill.size = Vector2(maxf(16.0, bar_w * ratio) if ratio > 0.0 else 0.0, 16)
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	track.add_child(fill)
	var exp_text: String = "최고 레벨" if bool(lp["is_max"]) \
			else "EXP %d / %d" % [int(lp["into"]), int(lp["span"])]
	UiHelpers.mk_label(card, exp_text, 22, OutgameTheme.TEXT_SUB,
			Vector2(bar_x, 120), Vector2(bar_w, 30))

	var perr: String = ManagerProgress.can_prestige(prof)
	var pb := Button.new()
	pb.focus_mode = Control.FOCUS_NONE
	pb.mouse_filter = Control.MOUSE_FILTER_PASS
	pb.text = "프레스티지" if perr == "" else "Lv%d 프레스티지" % ManagerProgress.prestige_level()
	if perr == "":
		OutgameTheme.style_primary_button(pb, 26)
	else:
		OutgameTheme.style_ghost_button(pb, 24)
	pb.disabled = perr != ""
	pb.position = Vector2(w - CARD_PAD - 230, 76)
	pb.size = Vector2(230, 72)
	pb.pressed.connect(_on_prestige_pressed)
	card.add_child(pb)

	var info: String = "레벨업마다 제거 포인트 %d · 스탯 하나를 영구히 낮추면 전문화 포인트 1" \
			% ConstTable.int_of("MANAGER_REMOVE_PER_LEVEL")
	var il := UiHelpers.mk_label(card, info, 20, OutgameTheme.TEXT_FAINT,
			Vector2(CARD_PAD, 172), Vector2(inner, 30))
	il.clip_text = true
	return HEADER_H


func _build_presets(pos: Vector2, w: float) -> float:
	var y: float = pos.y
	UiHelpers.mk_label(_body, "프리셋 — 전문화 분배 + 특성", 30, OutgameTheme.TEXT,
			Vector2(pos.x, y), Vector2(w, 44))
	y += 52.0
	y += ManagerUi.add_preset_chips(_body, Vector2(pos.x, y), w, _pm.profile, _edit_idx,
			_on_chip_pressed)
	if _is_prestige_kind():
		y += 16.0
		var card := Panel.new()
		card.add_theme_stylebox_override("panel", OutgameTheme.flat_style(
				OutgameTheme.NEGATIVE.lightened(0.88), 16, OutgameTheme.NEGATIVE, 2))
		card.position = Vector2(pos.x, y)
		card.size = Vector2(w, 120)
		card.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_body.add_child(card)
		UiHelpers.mk_label(card, "프레스티지 프리셋 — 재설정해야 쓸 수 있습니다", 24,
				OutgameTheme.NEGATIVE, Vector2(CARD_PAD, 18), Vector2(w - 300, 34))
		UiHelpers.mk_label(card, "전문화 분배가 비워지고, 특성은 그대로 남습니다", 20,
				OutgameTheme.TEXT_SUB, Vector2(CARD_PAD, 62), Vector2(w - 300, 30))
		var rb := Button.new()
		rb.text = "재설정"
		rb.focus_mode = Control.FOCUS_NONE
		rb.mouse_filter = Control.MOUSE_FILTER_PASS
		OutgameTheme.style_primary_button(rb, 26)
		rb.position = Vector2(w - CARD_PAD - 200, 24)
		rb.size = Vector2(200, 72)
		rb.pressed.connect(_on_reset_pressed)
		card.add_child(rb)
		y += 120.0
	return y - pos.y


func _build_stats(pos: Vector2, w: float) -> float:
	var prof: Dictionary = _pm.profile
	var n: int = StaffSystem.STATS.size()
	var h: float = STAT_HEAD_H + float(n) * STAT_ROW_H + 16.0
	var card: Panel = OutgameTheme.add_card(_body, pos, Vector2(w, h), 20)
	var inner: float = w - CARD_PAD * 2.0
	UiHelpers.mk_label(card, "감독 스탯", 30, OutgameTheme.TEXT,
			Vector2(CARD_PAD, 20), Vector2(240, 42))
	var left: int = ManagerProgress.removal_points_left(prof)
	var spec_total: int = ManagerProgress.spec_points(prof)
	var used: int = ManagerProgress.alloc_used(_draft)
	OutgameTheme.add_chip(card, "제거 포인트 %d" % left, Vector2(w - CARD_PAD - 460, 24),
			Vector2(210, 40), OutgameTheme.ACCENT_DIM if left > 0 else OutgameTheme.SURFACE_SUNK,
			OutgameTheme.ACCENT_TEXT if left > 0 else OutgameTheme.TEXT_SUB, 20)
	OutgameTheme.add_chip(card, "전문화 포인트 %d / %d" % [used, spec_total],
			Vector2(w - CARD_PAD - 240, 24), Vector2(240, 40),
			OutgameTheme.SURFACE_SUNK, OutgameTheme.NEGATIVE if used > spec_total
			else OutgameTheme.TEXT_SUB, 20)
	UiHelpers.mk_label(card, "최종 = 유형 − 제거 + 전문화 · 상한 %d" % ManagerProgress.stat_cap(),
			20, OutgameTheme.TEXT_FAINT, Vector2(CARD_PAD, 68), Vector2(inner, 28))

	var tstats: Dictionary = ManagerProgress.type_stats(int((prof.get("manager", {}) as Dictionary).get("type", 0)))
	var rm: Dictionary = ManagerProgress.removed(prof)
	var final_stats: Dictionary = ManagerProgress.preset_stats(prof, _draft)
	var alloc: Dictionary = _draft.get("alloc", {})
	var editable: bool = not _is_prestige_kind()
	for i in n:
		var key: String = String(StaffSystem.STATS[i])
		var y: float = STAT_HEAD_H + float(i) * STAT_ROW_H
		if i > 0:
			OutgameTheme.add_divider(card, Vector2(CARD_PAD, y), inner)
		var cy: float = y + (STAT_ROW_H - STEP_H) * 0.5
		UiHelpers.mk_label(card, String(StaffSystem.STAT_LABELS.get(key, key)), 28,
				OutgameTheme.TEXT, Vector2(CARD_PAD, y + 24), Vector2(90, 40))
		var a: int = int(alloc.get(key, 0))
		var parts: String = "유형 %d" % int(tstats[key])
		if int(rm[key]) > 0:
			parts += " · 제거 −%d" % int(rm[key])
		if a > 0:
			parts += " · 전문화 +%d" % a
		UiHelpers.mk_label(card, parts, 20, OutgameTheme.TEXT_SUB,
				Vector2(CARD_PAD + 96, y + 30), Vector2(300, 30))
		var fv: int = int(final_stats[key])
		var fl := UiHelpers.mk_label(card, str(fv), 40,
				OutgameTheme.ACCENT_TEXT if a > 0 else OutgameTheme.TEXT,
				Vector2(CARD_PAD + 400, y + 16), Vector2(70, 56), HORIZONTAL_ALIGNMENT_CENTER)
		fl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER

		var rb := _small_button("제거", Vector2(CARD_PAD + 490, cy), Vector2(118, STEP_H), false)
		rb.disabled = ManagerProgress.can_remove(prof, key) != ""
		rb.pressed.connect(_on_remove_pressed.bind(key))
		card.add_child(rb)

		var sx: float = w - CARD_PAD - (STEP_W * 2.0 + 64.0)
		var minus := _small_button("−", Vector2(sx, cy), Vector2(STEP_W, STEP_H), true)
		minus.disabled = not editable or ManagerProgress.can_alloc(prof, _draft, key, -1) != ""
		minus.pressed.connect(_on_alloc_pressed.bind(key, -1))
		card.add_child(minus)
		var al := UiHelpers.mk_label(card, "+%d" % a if a > 0 else "0", 26,
				OutgameTheme.ACCENT_TEXT if a > 0 else OutgameTheme.TEXT_FAINT,
				Vector2(sx + STEP_W, cy), Vector2(64, STEP_H), HORIZONTAL_ALIGNMENT_CENTER)
		al.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		var plus := _small_button("+", Vector2(sx + STEP_W + 64.0, cy), Vector2(STEP_W, STEP_H), true)
		plus.disabled = not editable or ManagerProgress.can_alloc(prof, _draft, key, 1) != ""
		plus.pressed.connect(_on_alloc_pressed.bind(key, 1))
		card.add_child(plus)
	return h


func _small_button(text: String, pos: Vector2, sz: Vector2, big_font: bool) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_filter = Control.MOUSE_FILTER_PASS
	OutgameTheme.style_ghost_button(b, 36 if big_font else 24)
	b.position = pos
	b.size = sz
	return b


# ── Actions ──────────────────────────────────────────────────────────────────
func _on_chip_pressed(idx: int) -> void:
	if idx == _edit_idx:
		return
	if _dirty:
		_host.open_confirm("저장하지 않은 변경이 있습니다",
				"%s 의 변경을 버리고 %s 로 넘어갈까요?" % [
					ManagerUi.preset_name(_edit_idx), ManagerUi.preset_name(idx)],
				"취소", "버리고 이동", true, _switch_preset.bind(idx))
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
		_host.show_toast("프레스티지 프리셋은 재설정한 뒤에 고칠 수 있습니다", true)
		return
	var err: String = ManagerProgress.toggle_trait(_draft, trait_id, _owned())
	if err != "":
		_host.show_toast(err, true)
		return
	Haptics.play(Haptics.Kind.SELECT)
	_mark_dirty()
	if TraitSystem.bonus_points(_draft.get("traits", [])) < 0:
		_host.show_toast("보너스 점수가 0 미만 — 이대로는 저장할 수 없습니다", true)


func _on_remove_pressed(stat: String) -> void:
	var prof: Dictionary = _pm.profile
	var err: String = ManagerProgress.can_remove(prof, stat)
	if err != "":
		_host.show_toast(err, true)
		return
	var label: String = String(StaffSystem.STAT_LABELS.get(stat, stat))
	var cur: int = int(ManagerProgress.base_stats(prof)[stat])
	Haptics.play(Haptics.Kind.WARNING)
	_host.open_confirm("%s 스탯을 낮출까요?" % label,
			"제거 포인트 1을 써서 %s 기본값을 %d → %d 로 영구히 낮춥니다(모든 프리셋).\n대신 전문화 포인트 1을 얻습니다.\n프레스티지 전까지 되돌릴 수 없습니다." % [
				label, cur, cur - 1],
			"취소", "제거", true, _apply_remove.bind(stat))


func _apply_remove(stat: String) -> void:
	var err: String = ManagerProgress.remove_stat(_pm.profile, stat)
	if err != "":
		_host.show_toast(err, true)
		return
	var serr: String = _pm.save_profile()
	if serr != "":
		_host.show_toast("프로필 저장 실패: " + serr, true)
	else:
		Haptics.play(Haptics.Kind.MEDIUM)
		_host.show_toast("%s −1 — 전문화 포인트 +1" % String(StaffSystem.STAT_LABELS.get(stat, stat)))
	_rebuild()


func _on_reset_pressed() -> void:
	var prof: Dictionary = _pm.profile
	var p: Dictionary = ManagerProgress.preset_at(prof, _edit_idx)
	if p.is_empty():
		return
	ManagerProgress.reset_preset(p)
	var serr: String = _pm.save_profile()
	if serr != "":
		_host.show_toast("프로필 저장 실패: " + serr, true)
	else:
		_host.show_toast("%s 재설정됨 — 전문화 포인트를 다시 나누세요" % ManagerUi.preset_name(_edit_idx))
	_load_draft(_edit_idx)
	_rebuild()


func _on_prestige_pressed() -> void:
	var err: String = ManagerProgress.can_prestige(_pm.profile)
	if err != "":
		_host.show_toast(err, true)
		return
	var lost: String = "\n(저장하지 않은 프리셋 변경은 버려집니다)" if _dirty else ""
	Haptics.play(Haptics.Kind.WARNING)
	_host.open_confirm("프레스티지할까요?",
			"Lv1 로 돌아가고 스탯 제거가 풀리며, 감독 유형을 다시 고릅니다.\n기존 프리셋은 재설정 후 사용 · 새 프리셋 +1.\n보상: %s%s" % [
				_reward_text(), lost],
			"취소", "유형 고르기", false, _open_prestige_popup)


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
		_host.show_toast("프로필 저장 실패: " + serr, true)
		return
	Haptics.play(Haptics.Kind.SUCCESS)
	_host.show_toast("프레스티지 완료 — " + _reward_text(res.get("rewards", {})))


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
	for spec in LobbyScreen.CURRENCY_STRIP:
		var k: String = String((spec as Dictionary)["key"])
		if int(r.get(k, 0)) > 0:
			out.append("%s +%d" % [String((spec as Dictionary)["label"]), int(r[k])])
	return " · ".join(PackedStringArray(out)) if not out.is_empty() else "없음"
