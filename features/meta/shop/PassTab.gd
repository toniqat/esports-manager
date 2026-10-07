class_name PassTab
extends Control

# 로비 탭 — 주간패스 (M10). 탭 계약은 `features/meta/lobby/LobbyScreen.gd` 머리말,
# 규칙은 `PassSystem` + `features/meta/shop/README.md`.
#
#   ┌ header card: week id · time to reset · level · exp bar · how exp is earned ┐
#   │ scroll: one row per pass level (reward · 수령 / 수령 완료 / 잠김)            │
#   ├ action bar: 모두 수령 (claim every reached level)                            ┤
#
# **Layout lives in `PassTab.tscn`** (+ `PassRow.tscn` per level). Code owns texts, the exp
# ratio (`%Fill` anchor), instancing rows and the per-state row colours (claimable amber /
# reached white / locked sunk, Lv chip, reward / status text colour).
#
# Every activation runs `PassSystem.ensure_week` (and saves when the week turned).
# A claim saves once and refreshes the host currency strip.

const SCENE_PATH: String = "res://features/meta/shop/PassTab.tscn"
const ROW_SCENE: String = "res://features/meta/shop/PassRow.tscn"

var _host: LobbyScreen
var _pm: Node
var _scroll_v: int = -1      # -1 = jump to the first claimable / current level


## Instances the scene. `PassTab.new()` is an empty Control — don't use it.
static func create() -> PassTab:
	return (load(SCENE_PATH) as PackedScene).instantiate() as PassTab


func _ready() -> void:
	# Drag / fling scrolling instead of the engine's touch drag (`DragScroll`).
	DragScroll.attach(%Scroll)
	if UiPreview.is_standalone(self):
		_fill_preview()


func bar_specs() -> Array:
	return [{"text": "모두 수령", "style": "primary", "font": 32, "weight": 1.0}]


func setup(host: LobbyScreen) -> void:
	_host = host
	_pm = get_node("/root/ProfileManager")


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
	_scroll_v = (%Scroll as ScrollContainer).scroll_vertical
	_rebuild()
	if err != "":
		_host.show_toast("저장 실패: " + err, true)
	else:
		_host.show_toast(msg)


# ── Fill ─────────────────────────────────────────────────────────────────────
func _rebuild() -> void:
	_fill_head()
	_fill_rows()
	var bar: Array = _host.bar_buttons()
	if not bar.is_empty():
		(bar[0] as Button).disabled = PassSystem.claimable_levels(_pm.profile).is_empty()


func _fill_head() -> void:
	var p: Dictionary = _pm.profile
	var max_lv: int = PassSystem.max_level()
	var week: String = String((p.get("pass", {}) as Dictionary).get("week_id", ""))
	%Week.text = "%s · 초기화까지 %s" % [week, _reset_text()]
	%Level.text = "Lv %d" % PassSystem.level_of(p)
	%MaxLevel.text = "/ %d" % max_lv
	var prog: Dictionary = PassSystem.level_progress(p)
	%Exp.text = "최고 레벨" if int(prog["need"]) == 0 			else "EXP %d / %d" % [int(prog["into"]), int(prog["need"])]
	var frac: float = 1.0 if int(prog["need"]) == 0 else float(prog["into"]) / float(prog["need"])
	var fill: Control = %Fill
	fill.visible = frac > 0.0
	fill.anchor_right = clampf(frac, 0.0, 1.0)
	fill.offset_right = 0.0
	%Info.text = UiHelpers.keep_words(
			"런을 마치면 런 점수만큼 패스 EXP 를 얻습니다. Lv %d 를 넘긴 EXP 는 아웃게임 재화로 바뀝니다. 보상은 직접 수령해야 하며, 매주 월요일 0시(기기 시각)에 초기화됩니다." % max_lv)


func _reset_text() -> String:
	var s: int = PassSystem.seconds_until_reset()
	var d: int = s / 86400
	var h: int = (s % 86400) / 3600
	if d > 0:
		return "%d일 %d시간" % [d, h]
	return "%d시간 %d분" % [h, (s % 3600) / 60]


func _fill_rows() -> void:
	var rows: Node = %Rows
	for c in rows.get_children():
		rows.remove_child(c)
		c.queue_free()
	var row_scene := load(ROW_SCENE) as PackedScene
	var p: Dictionary = _pm.profile
	var lv_now: int = PassSystem.level_of(p)
	var first_focus: int = -1
	var row_step: float = 0.0
	for lv in range(1, PassSystem.max_level() + 1):
		var rw: Dictionary = PassSystem.reward_at(lv)
		var reached: bool = lv <= lv_now
		var claimed: bool = PassSystem.is_claimed(p, lv)
		var can: bool = reached and not claimed and not rw.is_empty()
		if first_focus < 0 and (can or lv == lv_now):
			first_focus = lv
		var row: Panel = row_scene.instantiate()
		rows.add_child(row)
		row_step = row.custom_minimum_size.y + float((rows as VBoxContainer).get_theme_constant("separation"))
		var bg: Color = OutgameTheme.ACCENT_DIM if can else 				(OutgameTheme.SURFACE if reached else OutgameTheme.SURFACE_SUNK)
		row.add_theme_stylebox_override("panel", OutgameTheme.flat_style(bg, 16,
				OutgameTheme.ACCENT if can else OutgameTheme.BORDER))
		var chip: Panel = row.get_node("%Chip")
		chip.add_theme_stylebox_override("panel", OutgameTheme.flat_style(
				OutgameTheme.ACCENT if reached else OutgameTheme.BORDER_STRONG, int(chip.size.y * 0.5)))
		(row.get_node("%ChipText") as Label).text = "Lv %d" % lv
		var reward: Label = row.get_node("%Reward")
		reward.text = "—" if rw.is_empty() else "%s × %d" % [
				ShopPopup.currency_label(String(rw["currency"])), int(rw["amount"])]
		if not reached:
			reward.add_theme_color_override("font_color", OutgameTheme.TEXT_SUB)
		var b: Button = row.get_node("%Claim")
		b.visible = can
		if can:
			b.pressed.connect(claim_level.bind(lv))
		else:
			row.get_node("%StatusBox").visible = true
			var st: Label = row.get_node("%Status")
			st.text = "수령 완료" if claimed else ("잠김" if not reached else "")
			st.add_theme_color_override("font_color",
					OutgameTheme.TEXT_FAINT if not claimed else OutgameTheme.POSITIVE)
	var target: int = _scroll_v
	if target < 0:
		target = int(maxf(0.0, (first_focus - 2) * row_step))
	_restore_scroll.call_deferred(%Scroll, target)


func _restore_scroll(sc: ScrollContainer, v: int) -> void:
	if is_instance_valid(sc):
		sc.scroll_vertical = v


## F6 단독 실행 미리보기 — 실제 프로필의 이번 주 패스 (`resources/UiPreview.gd`).
## `on_shown` · `_rebuild` 는 주가 바뀌면 저장하고 호스트의 행동 바를 읽으므로 쓰지 않고
## 머리 · 줄만 채운다(주 넘김은 메모리에만). 수령 버튼은 저장하므로 누름을 출력만 한다.
func _fill_preview() -> void:
	# 호스트가 하듯 탭 루트를 화면 전체로 편다(씬의 1080 × n 은 에디터 미리보기 크기일 뿐).
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	UiPreview.stage(self)
	setup(null)
	PassSystem.ensure_week(_pm.profile)
	_fill_head()
	_fill_rows()
	for row in %Rows.get_children():
		var b: Button = row.get_node("%Claim")
		if b.visible:
			UiPreview.mute(b, self, "수령")
