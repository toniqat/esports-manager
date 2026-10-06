class_name PassTab
extends Control

# 로비 탭 — 주간패스 (M10). 탭 계약은 `features/meta/lobby/LobbyScreen.gd` 머리말,
# 규칙은 `PassSystem` + `features/meta/shop/README.md`.
#
#   ┌ header card: week id · time to reset · level · exp bar · how exp is earned ┐
#   │ scroll: one row per pass level (reward · 수령 / 수령 완료 / 잠김)            │
#   ├ action bar: 모두 수령 (claim every reached level)                            ┤
#
# Every activation runs `PassSystem.ensure_week` (and saves when the week turned).
# A claim saves once and refreshes the host currency strip.

const SIDE: float = 40.0
const HEAD_H: float = 330.0
const ROW_H: float = 104.0
const ROW_GAP: float = 10.0

var _host: LobbyScreen
var _pm: Node
var _view: Control = null
var _scroll: ScrollContainer = null
var _scroll_v: int = -1      # -1 = jump to the first claimable / current level


func bar_specs() -> Array:
	return [{"text": "모두 수령", "style": "primary", "font": 32, "weight": 1.0}]


func setup(host: LobbyScreen) -> void:
	_host = host
	_pm = get_node("/root/ProfileManager")
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func on_shown() -> void:
	if PassSystem.ensure_week(_pm.profile):
		_pm.save_profile()
	_scroll_v = -1
	_rebuild()


func on_bar_pressed(_i: int) -> void:
	claim_all()


## Public for headless checks.
func claim_all() -> void:
	var got: Dictionary = PassSystem.claim_all(_pm.profile)
	if int(got["count"]) <= 0:
		_host.show_toast("받을 보상이 없습니다", true)
		return
	var parts: Array = []
	for k in (got["gained"] as Dictionary).keys():
		parts.append("%s +%d" % [ShopPopup.currency_label(String(k)), int(got["gained"][k])])
	_after_claim("%d개 수령 · %s" % [int(got["count"]), ", ".join(parts)])


func claim_level(level: int) -> void:
	var err: String = PassSystem.claim(_pm.profile, level)
	if err != "":
		_host.show_toast(err, true)
		return
	var rw: Dictionary = PassSystem.reward_at(level)
	_after_claim("Lv %d 보상 · %s +%d" % [level, ShopPopup.currency_label(String(rw["currency"])),
			int(rw["amount"])])


func _after_claim(msg: String) -> void:
	var err: String = String(_pm.save_profile())
	_host.refresh_currency()
	_host.refresh_badges()
	if _scroll != null and is_instance_valid(_scroll):
		_scroll_v = _scroll.scroll_vertical
	_rebuild()
	if err != "":
		_host.show_toast("저장 실패: " + err, true)
	else:
		_host.show_toast(msg)


# ── Build ────────────────────────────────────────────────────────────────────
func _rebuild() -> void:
	if _view != null and is_instance_valid(_view):
		_view.queue_free()
	_view = Control.new()
	_view.position = Vector2.ZERO
	_view.size = size
	_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_view)
	_build_head()
	_build_rows()
	var bar: Array = _host.bar_buttons()
	if not bar.is_empty():
		(bar[0] as Button).disabled = PassSystem.claimable_levels(_pm.profile).is_empty()


func _build_head() -> void:
	var w: float = size.x - SIDE * 2.0
	var card: Panel = OutgameTheme.add_card(_view, Vector2(SIDE, 20), Vector2(w, HEAD_H), 24)
	var p: Dictionary = _pm.profile
	var lv: int = PassSystem.level_of(p)
	var max_lv: int = PassSystem.max_level()
	UiHelpers.mk_label(card, "주간패스", 40, OutgameTheme.TEXT, Vector2(36, 26), Vector2(300, 54))
	var week: String = String((p.get("pass", {}) as Dictionary).get("week_id", ""))
	UiHelpers.mk_label(card, "%s · 초기화까지 %s" % [week, _reset_text()], 22,
			OutgameTheme.TEXT_SUB, Vector2(w - 536, 40), Vector2(500, 32), HORIZONTAL_ALIGNMENT_RIGHT)

	UiHelpers.mk_label(card, "Lv %d" % lv, 56, OutgameTheme.ACCENT_TEXT,
			Vector2(36, 92), Vector2(260, 72))
	UiHelpers.mk_label(card, "/ %d" % max_lv, 28, OutgameTheme.TEXT_SUB,
			Vector2(36 + 150, 116), Vector2(120, 40))
	var prog: Dictionary = PassSystem.level_progress(p)
	var exp_txt: String = "최고 레벨" if int(prog["need"]) == 0 \
			else "EXP %d / %d" % [int(prog["into"]), int(prog["need"])]
	UiHelpers.mk_label(card, exp_txt, 26, OutgameTheme.TEXT, Vector2(w - 436, 116),
			Vector2(400, 40), HORIZONTAL_ALIGNMENT_RIGHT)
	# Exp bar — two flat panels (a ProgressBar ignores a thin height).
	var bar_w: float = w - 72.0
	var track := Panel.new()
	track.add_theme_stylebox_override("panel", OutgameTheme.flat_style(OutgameTheme.SURFACE_SUNK, 9))
	track.position = Vector2(36, 176)
	track.size = Vector2(bar_w, 18)
	track.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(track)
	var frac: float = 1.0 if int(prog["need"]) == 0 else float(prog["into"]) / float(prog["need"])
	if frac > 0.0:
		var fill := Panel.new()
		fill.add_theme_stylebox_override("panel", OutgameTheme.flat_style(OutgameTheme.ACCENT, 9))
		fill.position = Vector2.ZERO
		fill.size = Vector2(maxf(18.0, bar_w * frac), 18)
		fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
		track.add_child(fill)
	var info := UiHelpers.mk_label(card, UiHelpers.keep_words(
			"런을 마치면 런 점수만큼 패스 EXP 를 얻습니다. Lv %d 를 넘긴 EXP 는 아웃게임 재화로 바뀝니다. 보상은 직접 수령해야 하며, 매주 월요일 0시(기기 시각)에 초기화됩니다." % max_lv),
			22, OutgameTheme.TEXT_SUB, Vector2(36, 214), Vector2(bar_w, 100))
	ShopPopup.wrap_label(info, Vector2(bar_w, 100))


func _reset_text() -> String:
	var s: int = PassSystem.seconds_until_reset()
	var d: int = s / 86400
	var h: int = (s % 86400) / 3600
	if d > 0:
		return "%d일 %d시간" % [d, h]
	return "%d시간 %d분" % [h, (s % 3600) / 60]


func _build_rows() -> void:
	var top: float = 20.0 + HEAD_H + 20.0
	var w: float = size.x - SIDE * 2.0
	var max_lv: int = PassSystem.max_level()
	var sv: Dictionary = OutgameTheme.add_vscroll(_view, Vector2(0, top), Vector2(size.x, size.y - top))
	_scroll = sv["scroll"]
	var body: Control = sv["body"]
	body.custom_minimum_size.y = max_lv * (ROW_H + ROW_GAP) + 16.0
	var p: Dictionary = _pm.profile
	var lv_now: int = PassSystem.level_of(p)
	var first_focus: int = -1
	for lv in range(1, max_lv + 1):
		var rw: Dictionary = PassSystem.reward_at(lv)
		var reached: bool = lv <= lv_now
		var claimed: bool = PassSystem.is_claimed(p, lv)
		var can: bool = reached and not claimed and not rw.is_empty()
		if first_focus < 0 and (can or lv == lv_now):
			first_focus = lv
		var row := Panel.new()
		var bg: Color = OutgameTheme.ACCENT_DIM if can else \
				(OutgameTheme.SURFACE if reached else OutgameTheme.SURFACE_SUNK)
		row.add_theme_stylebox_override("panel", OutgameTheme.flat_style(bg, 16,
				OutgameTheme.ACCENT if can else OutgameTheme.BORDER))
		row.position = Vector2(SIDE, 8.0 + (lv - 1) * (ROW_H + ROW_GAP))
		row.size = Vector2(w, ROW_H)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		body.add_child(row)
		OutgameTheme.add_chip(row, "Lv %d" % lv, Vector2(24, (ROW_H - 48.0) * 0.5), Vector2(112, 48),
				OutgameTheme.ACCENT if reached else OutgameTheme.BORDER_STRONG,
				OutgameTheme.TEXT_ON_FILL, 24)
		var reward_txt: String = "—" if rw.is_empty() else "%s × %d" % [
				ShopPopup.currency_label(String(rw["currency"])), int(rw["amount"])]
		UiHelpers.mk_label(row, reward_txt, 30, OutgameTheme.TEXT if reached else OutgameTheme.TEXT_SUB,
				Vector2(164, (ROW_H - 42.0) * 0.5), Vector2(w - 164 - 230, 42))
		if can:
			var b := Button.new()
			b.text = "수령"
			b.focus_mode = Control.FOCUS_NONE
			OutgameTheme.style_primary_button(b, 26)
			b.position = Vector2(w - 200, 16)
			b.size = Vector2(180, ROW_H - 32)
			b.mouse_filter = Control.MOUSE_FILTER_PASS
			b.pressed.connect(claim_level.bind(lv))
			row.add_child(b)
		else:
			UiHelpers.mk_label(row, "수령 완료" if claimed else ("잠김" if not reached else ""), 24,
					OutgameTheme.TEXT_FAINT if not claimed else OutgameTheme.POSITIVE,
					Vector2(w - 220, (ROW_H - 36.0) * 0.5), Vector2(196, 36), HORIZONTAL_ALIGNMENT_CENTER)
	var target: int = _scroll_v
	if target < 0:
		target = int(maxf(0.0, (first_focus - 2) * (ROW_H + ROW_GAP)))
	if target > 0:
		_restore_scroll.call_deferred(_scroll, target)


func _restore_scroll(sc: ScrollContainer, v: int) -> void:
	if is_instance_valid(sc):
		sc.scroll_vertical = v
