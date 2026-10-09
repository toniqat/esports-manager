extends Control

# 런 정산 화면 — `GameManager.last_run_result` 를 읽어 보여 준다.
# 계약: docs/outgame_dev_plan.md §10.3. 계산은 `RunResult.gd`, 여기는 채우기만.
#
# **레이아웃 · 스타일은 씬(`scenes/RunResult.tscn`)이 소유한다** (docs/ui_scene_migration.md §3).
# 이 스크립트는 `%노드` 에 데이터를 넣고, 데이터 색을 칠하고, 반복 줄을 아이템 씬
# (`RunResult*Row.tscn`)으로 채우고, 기기별 안전 영역 오프셋만 넣는다.
# 씬에서 지운 노드는 의도된 삭제다 — 여기서 되살리지 않는다.
#
# 위에서부터: 결과 머리(클리어 / 실패 / 포기) · 시나리오와 팀 · (테스트 런 칩) →
# 스크롤 본문 카드(진엔딩 · 새 특성 해금 · 진척 · 점수 내역 · 보상 · 선수 성장 ·
# 이번 런 업적, 앞 둘은 있을 때만) → 전폭 하단 바 하나.
# M8~M10 rewards (both currencies, pass EXP, manager level, pilot max level, new
# traits) are drawn from `result.profile_delta` (the before/after settlement wrote
# into the profile) — test runs have no such key, so only computed values show.
# 하단 바는 평소 `로비로`, 로비에서 런을 포기하고 왔으면(`outcome == "abandon"`)
# `새 런`(→ 런 준비). 결과가 비어 있으면(씬을 바로 연 경우) 빈 상태 한 장.
#
# 결과 딕셔너리만으로 그린다 — 표시용 키(`team_name` · `pilots` ·
# `breakdown` · `phases_cleared`)를 `RunResult.build_result` 가 미리 담아 둔다.

const LOBBY_SCENE: String = "res://scenes/Lobby.tscn"
const RUN_SETUP_SCENE: String = "res://scenes/RunSetup.tscn"

const ROW_SCENE: PackedScene = preload("res://features/meta/run_result/UI_Comp_RunResultRow.tscn")
const TRUE_END_ROW_SCENE: PackedScene = preload("res://features/meta/run_result/UI_Comp_RunResultTrueEndRow.tscn")
const TRAIT_ROW_SCENE: PackedScene = preload("res://features/meta/run_result/UI_Comp_RunResultTraitRow.tscn")
const GROWTH_ROW_SCENE: PackedScene = preload("res://features/meta/run_result/UI_Comp_RunResultGrowthRow.tscn")
const PILOT_ROW_SCENE: PackedScene = preload("res://features/meta/run_result/UI_Comp_RunResultPilotRow.tscn")

const OUTCOME_TITLES: Dictionary = {    # l10n-keys: run_result.outcome.*
	"clear":   L.RUN_RESULT_OUTCOME_CLEAR,
	"fail":    L.RUN_RESULT_OUTCOME_FAIL,
	"abandon": L.RUN_RESULT_OUTCOME_ABANDON,
}

@onready var _gm: Node = get_node("/root/GameManager")

var _result: Dictionary = {}
var _filled: bool = false


func _ready() -> void:
	_result = _gm.last_run_result
	if not _filled:
		_fill()
		_filled = true
	if String(_result.get("outcome", "")) == RunResult.OUTCOME_CLEAR:
		Haptics.play(Haptics.Kind.SUCCESS)


# ── Fill ─────────────────────────────────────────────────────────────────────
func _fill() -> void:
	_apply_safe_area()
	var empty: bool = _result.is_empty()
	%Empty.visible = empty
	%Header.visible = not empty
	%Scroll.visible = not empty
	if not empty:
		_fill_header()
		_fill_body()
	_fill_bottom_bar()


## Pattern B (docs/mobile_safe_area.md): the whole screen moves down to the safe top,
## only the background reaches back up under the notch; the scroll and the bar make
## room for the bottom inset (the bar's colour field runs down over it).
func _apply_safe_area() -> void:
	ScreenMetrics.indent_to_safe_top(self)
	ScreenMetrics.extend_background(%Background)
	var below: float = maxf(0.0, ScreenMetrics.insets().w)
	%Scroll.offset_bottom -= below
	# The bar's shape is the scene (`BarPrimaryButton`); only the device inset is code.
	OutgameTheme.fit_bottom_bar(%BottomButton)


func _fill_header() -> void:
	var outcome: String = String(_result.get("outcome", ""))
	var color: Color = OutgameTheme.TEXT_SUB
	if outcome == RunResult.OUTCOME_CLEAR:
		color = OutgameTheme.ACCENT_TEXT
	elif outcome == RunResult.OUTCOME_FAIL:
		color = OutgameTheme.NEGATIVE
	var title: Label = %OutcomeTitle
	title.text = Loc.t(String(OUTCOME_TITLES.get(outcome, L.RUN_RESULT_OUTCOME_ENDED)))  # l10n-dynamic: run_result.outcome.*
	title.add_theme_color_override("font_color", color)

	var parts: Array = []
	var scen: String = ""
	if _result.has("scenario"):
		scen = Loc.t(String(RunRules.scenario(int(_result["scenario"])).get("name_key", "")))  # l10n-dynamic: scenario.*.name
	var team: String = String(_result.get("team_name", ""))
	if scen != "":
		parts.append(scen)
	if team != "":
		parts.append(team)
	%Subtitle.text = " · ".join(PackedStringArray(parts)) if not parts.is_empty() else "—"
	%TestChip.visible = bool(_result.get("test_run", false))


func _fill_body() -> void:
	# M7 — the true ending leads the body: it is the rarest thing a run can show.
	_fill_true_ending_card()
	# M8 — newly unlocked traits come next: they change what the next run can equip.
	_fill_unlocked_traits_card()
	_fill_progress_card()
	_fill_score_card()
	_fill_reward_card()
	_fill_growth_card()
	_fill_achievement_card()


## True-ending section (M7): one row per pilot in `result.true_endings` —
## large ringed portrait, name, the promise line. Names come from `pilots`.
func _fill_true_ending_card() -> void:
	var ids: Array = _result.get("true_endings", [])
	%TrueEndCard.visible = not ids.is_empty()
	var names: Dictionary = {}
	for p in (_result.get("pilots", []) as Array):
		names[int((p as Dictionary).get("id", -1))] = String((p as Dictionary).get("name", ""))
	var chip_text: String = Loc.t(L.RUN_RESULT_TRUE_END_CHIP,
			{"n": ConstTable.int_of("TRUE_ENDING_OUTINGS")})
	for raw in ids:
		var pid: int = int(raw)
		var nm: String = String(names.get(pid, "#%d" % pid))
		var row: Control = TRUE_END_ROW_SCENE.instantiate()
		_portrait(row.get_node("%Portrait"), pid, OutgameTheme.ACCENT)
		(row.get_node("%Name") as Label).text = nm
		(row.get_node("%Line") as Label).text = Loc.t(L.RUN_RESULT_TRUE_END_LINE, {"name": nm})
		(row.get_node("%ChipText") as Label).text = chip_text
		%TrueEndRows.add_child(row)


## Newly unlocked traits (M8) — amber card like the true ending: +/- chip, name,
## filled-in description, rarity chip (`TraitUi.rarity_color`).
func _fill_unlocked_traits_card() -> void:
	var ids: Array = _new_trait_ids()
	%TraitCard.visible = not ids.is_empty()
	%TraitNote.text = Loc.t(L.RUN_RESULT_TRAIT_NOTE_TEST if bool(_result.get("test_run", false)) \
			else L.RUN_RESULT_TRAIT_NOTE)
	for raw in ids:
		var tid: int = int(raw)
		var r: Dictionary = TraitSystem.row(tid)
		var pos: bool = TraitSystem.is_positive(tid)
		var row: Control = TRAIT_ROW_SCENE.instantiate()
		var sign_chip: Panel = row.get_node("%Sign")
		_paint_chip(sign_chip, OutgameTheme.POSITIVE if pos else OutgameTheme.NEGATIVE)
		(row.get_node("%SignText") as Label).text = "+" if pos else "−"
		(row.get_node("%Name") as Label).text = TraitSystem.name_of(tid)
		(row.get_node("%Desc") as Label).text = TraitSystem.desc_of(tid)
		var rarity: int = int(r.get("rarity", 0))
		_paint_chip(row.get_node("%Rarity"), TraitUi.rarity_color(rarity))
		(row.get_node("%RarityText") as Label).text = TraitSystem.rarity_name(rarity)
		%TraitRows.add_child(row)


func _fill_progress_card() -> void:
	var rows: Array = [
		[Loc.t(L.RUN_RESULT_PROGRESS_PHASE_REACHED), _phase_name(int(_result.get("phase_reached", 0)))],
		[Loc.t(L.RUN_RESULT_PROGRESS_PHASES_CLEARED), "%d / %d" % [int(_result.get("phases_cleared", 0)),
				RunResult.CAMPAIGN_ORDER.size()]],
		[Loc.t(L.RUN_RESULT_PROGRESS_RECORD), Loc.t(L.TERM_RECORD_WIN_LOSS,
				{"win": int(_result.get("wins", 0)), "loss": int(_result.get("losses", 0))})],
		[Loc.t(L.RUN_RESULT_PROGRESS_TITLES), Loc.t(L.RUN_RESULT_PROGRESS_TITLES_VALUE,
				{"n": int(_result.get("titles", 0))})],
	]
	for r in rows:
		_add_row(%ProgressRows, String(r[0]), String(r[1]), OutgameTheme.TEXT)


func _fill_score_card() -> void:
	var bd: Dictionary = _result.get("breakdown", {})
	var rows: Array = [
		[Loc.t(L.RUN_RESULT_SCORE_PHASES, {"n": int(_result.get("phases_cleared", 0))}),
				int(bd.get("phase", 0))],
		[Loc.t(L.RUN_RESULT_SCORE_WINS, {"n": int(_result.get("wins", 0))}), int(bd.get("wins", 0))],
		[Loc.t(L.RUN_RESULT_SCORE_TITLES, {"n": int(_result.get("titles", 0))}),
				int(bd.get("titles", 0))],
		[Loc.t(L.RUN_RESULT_SCORE_CLEAR_BONUS), int(bd.get("clear", 0))],
		[Loc.t(L.RUN_RESULT_SCORE_TRAIT_BONUS, {"n": int(_result.get("bonus_points", 0))}),
				int(bd.get("bonus", 0))],
	]
	for r in rows:
		var v: int = int(r[1])
		_add_row(%ScoreRows, String(r[0]), "+%d" % v,
				OutgameTheme.TEXT if v > 0 else OutgameTheme.TEXT_FAINT)
	%ScoreTotal.text = "%d" % int(_result.get("score", 0))


## Rewards: the currencies (outgame · levelup · rank stones when > 0), pass EXP (+ pass level change, overflow payout),
## manager EXP (+ level change and the removal points it grants). Level changes
## come from `profile_delta` only — a test run has none.
func _fill_reward_card() -> void:
	var delta: Dictionary = _profile_delta()
	var cur: Dictionary = _result.get("currency", {})
	var rows: Array = [
		[Loc.t(L.TERM_CURRENCY_OUTGAME), "+%d" % int(cur.get("outgame", 0)), OutgameTheme.POSITIVE],
		[Loc.t(L.TERM_CURRENCY_LEVELUP), "+%d" % int(cur.get("levelup", 0)), OutgameTheme.POSITIVE],
	]
	# B — rank stones (승급석); hidden while a run pays none (old results / short runs).
	if int(cur.get("rank_stone", 0)) > 0:
		rows.append([Loc.t(L.TERM_CURRENCY_RANK_STONE), "+%d" % int(cur["rank_stone"]), OutgameTheme.POSITIVE])
	var pass_d: Dictionary = delta.get("pass", {})
	var pass_txt: String = "+%d" % int(_result.get("pass_exp", 0))
	var pass_up: bool = int(pass_d.get("to", 0)) > int(pass_d.get("from", 0))
	if pass_up:
		pass_txt += "  ·  Lv %d → %d" % [int(pass_d["from"]), int(pass_d["to"])]
	rows.append([Loc.t(L.RUN_RESULT_REWARD_PASS_EXP), pass_txt,
			OutgameTheme.ACCENT_TEXT if pass_up else OutgameTheme.POSITIVE])
	var overflow: int = int(pass_d.get("overflow_outgame", 0))
	if overflow > 0:
		rows.append([Loc.t(L.RUN_RESULT_REWARD_PASS_OVERFLOW), "+%d" % overflow, OutgameTheme.POSITIVE])
	var mgr_d: Dictionary = delta.get("manager", {})
	var mgr_from: int = int(mgr_d.get("from", 0))
	var mgr_to: int = int(mgr_d.get("to", 0))
	var mgr_up: bool = mgr_to > mgr_from
	var mgr_txt: String = "+%d" % int(_result.get("manager_exp", 0))
	if mgr_up:
		mgr_txt += "  ·  Lv %d → %d" % [mgr_from, mgr_to]
	rows.append([Loc.t(L.RUN_RESULT_REWARD_MANAGER_EXP), mgr_txt, OutgameTheme.ACCENT_TEXT if mgr_up else OutgameTheme.POSITIVE])
	if mgr_up:
		var pts: int = (mgr_to - mgr_from) * maxi(0, ConstTable.int_of("MANAGER_REMOVE_PER_LEVEL"))
		rows.append([Loc.t(L.RUN_RESULT_REWARD_REMOVE_POINTS), "+%d" % pts, OutgameTheme.ACCENT_TEXT])
	for r in rows:
		_add_row(%RewardRows, String(r[0]), String(r[1]), r[2] as Color)
	%RewardNote.visible = bool(_result.get("test_run", false))


## Pilot growth (M10): per pilot the run's pilot EXP (`pilot_exp`) and, when the
## profile raised it, the level change (`profile_delta.pilots`, amber chip — capped at the
## rank's level cap).
func _fill_growth_card() -> void:
	var pilots: Array = _result.get("pilots", [])
	%GrowthCard.visible = not pilots.is_empty()
	var pexp: Dictionary = _result.get("pilot_exp", {})
	var pdelta: Dictionary = _profile_delta().get("pilots", {})
	for p in pilots:
		var pd: Dictionary = p
		var pid: int = int(pd.get("id", -1))
		var row: Control = GROWTH_ROW_SCENE.instantiate()
		_portrait(row.get_node("%Portrait"), pid)
		(row.get_node("%Name") as Label).text = String(pd.get("name", ""))
		(row.get_node("%Exp") as Label).text = Loc.t(L.RUN_RESULT_GROWTH_EXP, {"n": int(pexp.get(str(pid), 0))})
		var d: Dictionary = pdelta.get(str(pid), {})
		var up: bool = int(d.get("to", 0)) > int(d.get("from", 0))
		(row.get_node("%MaxLv") as Control).visible = up
		if up:
			(row.get_node("%MaxLvText") as Label).text = \
					Loc.t(L.RUN_RESULT_GROWTH_MAX_LV, {"from": int(d["from"]), "to": int(d["to"])})
		%GrowthRows.add_child(row)


func _fill_achievement_card() -> void:
	var pilots: Array = _result.get("pilots", [])
	var ach: Dictionary = _result.get("achievements", {})
	%AchievementEmpty.visible = pilots.is_empty()
	for p in pilots:
		var pd: Dictionary = p
		var pid: int = int(pd.get("id", -1))
		var a: Dictionary = ach.get(str(pid), {})
		var row: Control = PILOT_ROW_SCENE.instantiate()
		_portrait(row.get_node("%Portrait"), pid)
		(row.get_node("%Name") as Label).text = String(pd.get("name", ""))
		(row.get_node("%PositionBadge_Role") as PositionBadge).set_role(int(pd.get("role", -1)))
		var mvp_n: int = int(a.get("mvp", 0))
		var pom_n: int = int(a.get("pom", 0))
		_count_chip(row.get_node("%Mvp"), row.get_node("%MvpText"), "MVP %d" % mvp_n, mvp_n > 0)
		_count_chip(row.get_node("%Pom"), row.get_node("%PomText"), "POM %d" % pom_n, pom_n > 0)
		%AchievementRows.add_child(row)


func _fill_bottom_bar() -> void:
	var to_new_run: bool = String(_result.get("outcome", "")) == RunResult.OUTCOME_ABANDON
	var btn: Button = %BottomButton
	btn.text = Loc.t(L.LOBBY_HOME_NEW_RUN if to_new_run else L.UI_BUTTON_TO_LOBBY)
	btn.pressed.connect(_on_new_run_pressed if to_new_run else _on_lobby_pressed)


# ── 채우기 조각 ──────────────────────────────────────────────────────────────
func _add_row(rows: Container, label: String, value: String, value_color: Color) -> void:
	var row: Control = ROW_SCENE.instantiate()
	(row.get_node("%Label") as Label).text = label
	var v: Label = row.get_node("%Value")
	v.text = value
	v.add_theme_color_override("font_color", value_color)
	rows.add_child(row)


## Round portrait drawn into a scene slot — the slot's width is the diameter.
func _portrait(slot: Control, pid: int, ring: Variant = null) -> void:
	OutgameTheme.add_round_portrait(slot, PilotImages.circle_for(pid), Vector2.ZERO,
			slot.custom_minimum_size.x, ring)


## Pill fill for a chip whose colour is data (radius = half its height, like `add_chip`).
func _paint_chip(chip: Panel, bg: Color) -> void:
	chip.add_theme_stylebox_override("panel",
			OutgameTheme.flat_style(bg, int((chip.offset_bottom - chip.offset_top) * 0.5)))


func _count_chip(chip: Panel, text_label: Label, text: String, lit: bool) -> void:
	_paint_chip(chip, OutgameTheme.ACCENT_DIM if lit else OutgameTheme.SURFACE_SUNK)
	text_label.text = text
	text_label.add_theme_color_override("font_color",
			OutgameTheme.ACCENT_TEXT if lit else OutgameTheme.TEXT_FAINT)


## `result.profile_delta` — what settlement changed in the profile (empty for test runs).
func _profile_delta() -> Dictionary:
	var d: Variant = _result.get("profile_delta", {})
	return d if typeof(d) == TYPE_DICTIONARY else {}


## Trait ids for the 새 특성 해금 card: granted ones (`profile_delta.traits`), or for a
## test run the computed `unlocked_traits` (not granted).
func _new_trait_ids() -> Array:
	var delta: Dictionary = _profile_delta()
	if delta.has("traits"):
		return delta["traits"]
	if bool(_result.get("test_run", false)):
		return _result.get("unlocked_traits", [])
	return []


func _phase_name(idx: int) -> String:
	if idx < 0 or idx >= RunResult.CAMPAIGN_ORDER.size():
		return "—"
	return GameEnums.phase_label(RunResult.CAMPAIGN_ORDER[idx])


# ── Button handlers ──────────────────────────────────────────────────────────
# 정산은 이미 프로필에 썼고 run.save 도 지웠다 — 남은 런 상태를 비우고 떠난다.
func _on_lobby_pressed() -> void:
	_gm.reset_season_state()
	get_tree().change_scene_to_file(LOBBY_SCENE)


func _on_new_run_pressed() -> void:
	_gm.reset_season_state()
	get_tree().change_scene_to_file(RUN_SETUP_SCENE)
