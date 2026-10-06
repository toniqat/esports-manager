extends Control

# 런 정산 화면 — `GameManager.last_run_result` 를 읽어 보여 준다.
# 계약: docs/outgame_dev_plan.md §10.3. 계산은 `RunResult.gd`, 여기는 그리기만.
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
# 결과 딕셔너리만으로 그린다 — 표시용 키(`team_name` · `scenario_name` · `pilots` ·
# `breakdown` · `phases_cleared`)를 `RunResult.build_result` 가 미리 담아 둔다.

const LOBBY_SCENE: String = "res://scenes/Lobby.tscn"
const RUN_SETUP_SCENE: String = "res://scenes/RunSetup.tscn"

const CARD_X: float = 80.0
const CARD_W: float = 920.0
const CARD_PAD: float = 40.0
const CARD_GAP: float = 28.0
const SECTION_TITLE_H: float = 56.0
const ROW_H: float = 48.0
const PILOT_ROW_H: float = 104.0
const PORTRAIT_D: float = 76.0
const BODY_TOP: float = 360.0
const TRUE_END_ROW_H: float = 184.0
const TRUE_END_PORTRAIT_D: float = 128.0
const TRAIT_ROW_H: float = 104.0
const GROWTH_ROW_H: float = 88.0
const GROWTH_PORTRAIT_D: float = 60.0

const OUTCOME_TITLES: Dictionary = {
	"clear":   "런 클리어",
	"fail":    "런 실패",
	"abandon": "런 포기",
}

@onready var _gm: Node = get_node("/root/GameManager")

var _result: Dictionary = {}
var _built: bool = false


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_result = _gm.last_run_result
	if not _built:
		_build()
		_built = true
	if String(_result.get("outcome", "")) == RunResult.OUTCOME_CLEAR:
		Haptics.play(Haptics.Kind.SUCCESS)


# ── Build ────────────────────────────────────────────────────────────────────
func _build() -> void:
	ScreenMetrics.indent_to_safe_top(self)
	OutgameTheme.add_background(self)
	if _result.is_empty():
		_build_empty()
	else:
		_build_header()
		_build_body()
	_build_bottom_bar()


func _card_x() -> float:
	return maxf(CARD_X, ScreenMetrics.center_x() - CARD_W * 0.5)


func _build_header() -> void:
	var vp_w: float = ScreenMetrics.vp_w()
	var outcome: String = String(_result.get("outcome", ""))
	var color: Color = OutgameTheme.TEXT_SUB
	if outcome == RunResult.OUTCOME_CLEAR:
		color = OutgameTheme.ACCENT_TEXT
	elif outcome == RunResult.OUTCOME_FAIL:
		color = OutgameTheme.NEGATIVE
	UiHelpers.mk_label(self, String(OUTCOME_TITLES.get(outcome, "런 종료")), 64, color,
			Vector2(0, 120), Vector2(vp_w, 88), HORIZONTAL_ALIGNMENT_CENTER)
	var rule := ColorRect.new()
	rule.color = OutgameTheme.ACCENT
	rule.position = Vector2(ScreenMetrics.center_x() - 40.0, 218)
	rule.size = Vector2(80, 6)
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(rule)

	var parts: Array = []
	var scen: String = String(_result.get("scenario_name", ""))
	var team: String = String(_result.get("team_name", ""))
	if scen != "":
		parts.append(scen)
	if team != "":
		parts.append(team)
	UiHelpers.mk_label(self, " · ".join(PackedStringArray(parts)) if not parts.is_empty() else "—", 26,
			OutgameTheme.TEXT, Vector2(0, 244), Vector2(vp_w, 38),
			HORIZONTAL_ALIGNMENT_CENTER)
	if bool(_result.get("test_run", false)):
		var chip_w: float = 380.0
		OutgameTheme.add_chip(self, "테스트 런 — 프로필 미반영",
				Vector2(ScreenMetrics.center_x() - chip_w * 0.5, 296),
				Vector2(chip_w, 42), OutgameTheme.ACCENT_DIM,
				OutgameTheme.ACCENT_TEXT, 20)


func _build_body() -> void:
	var top: float = BODY_TOP
	var h: float = OutgameTheme.bottom_bar_top() - 16.0 - top
	var sv: Dictionary = OutgameTheme.add_vscroll(self, Vector2(0, top),
			Vector2(ScreenMetrics.vp_w(), h))
	var body: Control = sv["body"]
	var y: float = 0.0
	# M7 — the true ending leads the body: it is the rarest thing a run can show.
	if not (_result.get("true_endings", []) as Array).is_empty():
		y = _build_true_ending_card(body, y) + CARD_GAP
	# M8 — newly unlocked traits come next: they change what the next run can equip.
	if not _new_trait_ids().is_empty():
		y = _build_unlocked_traits_card(body, y) + CARD_GAP
	y = _build_progress_card(body, y) + CARD_GAP
	y = _build_score_card(body, y) + CARD_GAP
	y = _build_reward_card(body, y) + CARD_GAP
	if not (_result.get("pilots", []) as Array).is_empty():
		y = _build_growth_card(body, y) + CARD_GAP
	y = _build_achievement_card(body, y) + CARD_GAP
	body.custom_minimum_size.y = y


## True-ending section (M7): one row per pilot in `result.true_endings` —
## large ringed portrait, name, the promise line. Names come from `pilots`.
func _build_true_ending_card(parent: Control, y: float) -> float:
	var ids: Array = _result.get("true_endings", [])
	var names: Dictionary = {}
	for p in (_result.get("pilots", []) as Array):
		names[int((p as Dictionary).get("id", -1))] = String((p as Dictionary).get("name", ""))
	var card: Panel = OutgameTheme.add_card(parent, Vector2(_card_x(), y),
			Vector2(CARD_W, SECTION_TITLE_H + CARD_PAD * 1.5 + ids.size() * TRUE_END_ROW_H),
			24, OutgameTheme.ACCENT_DIM)
	UiHelpers.mk_label(card, "진엔딩", 24, OutgameTheme.ACCENT_TEXT,
			Vector2(CARD_PAD, CARD_PAD * 0.5 + 8.0), Vector2(CARD_W - CARD_PAD * 2.0, 34))
	OutgameTheme.add_divider(card, Vector2(CARD_PAD, SECTION_TITLE_H + 8.0),
			CARD_W - CARD_PAD * 2.0, OutgameTheme.ACCENT)
	var ry: float = SECTION_TITLE_H + CARD_PAD * 0.5
	for raw in ids:
		var pid: int = int(raw)
		var nm: String = String(names.get(pid, "#%d" % pid))
		OutgameTheme.add_round_portrait(card, PilotImages.circle_for(pid),
				Vector2(CARD_PAD, ry + (TRUE_END_ROW_H - TRUE_END_PORTRAIT_D) * 0.5),
				TRUE_END_PORTRAIT_D, OutgameTheme.ACCENT)
		var tx: float = CARD_PAD + TRUE_END_PORTRAIT_D + 28.0
		var tw: float = CARD_W - tx - CARD_PAD
		UiHelpers.mk_label(card, nm, 34, OutgameTheme.TEXT,
				Vector2(tx, ry + 22.0), Vector2(tw, 44))
		var l1 := UiHelpers.mk_label(card, "우승 트로피를 들고, %s 선수가 미뤄 둔 말을 꺼냈다." % nm,
				22, OutgameTheme.TEXT_SUB, Vector2(tx, ry + 70.0), Vector2(tw, 60))
		l1.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		OutgameTheme.add_chip(card, "외출 %d회 · 약속을 지켰다" % ConstTable.int_of("TRUE_ENDING_OUTINGS"),
				Vector2(tx, ry + 128.0), Vector2(300, 36), OutgameTheme.SURFACE,
				OutgameTheme.ACCENT_TEXT, 18)
		ry += TRUE_END_ROW_H
	return y + card.size.y


func _build_progress_card(parent: Control, y: float) -> float:
	var rows: Array = [
		["도달 페이즈", _phase_name(int(_result.get("phase_reached", 0)))],
		["끝낸 페이즈", "%d / %d" % [int(_result.get("phases_cleared", 0)),
				RunResult.CAMPAIGN_ORDER.size()]],
		["전적", "%d승 %d패" % [int(_result.get("wins", 0)), int(_result.get("losses", 0))]],
		["대회 우승", "%d회" % int(_result.get("titles", 0))],
	]
	var card: Panel = _section_card(parent, y, "진척", rows.size())
	for i in rows.size():
		_row(card, SECTION_TITLE_H + CARD_PAD * 0.5 + i * ROW_H,
				String(rows[i][0]), String(rows[i][1]), OutgameTheme.TEXT)
	return y + card.size.y


func _build_score_card(parent: Control, y: float) -> float:
	var bd: Dictionary = _result.get("breakdown", {})
	var rows: Array = [
		["끝낸 페이즈 × %d" % int(_result.get("phases_cleared", 0)), int(bd.get("phase", 0))],
		["승리 × %d" % int(_result.get("wins", 0)), int(bd.get("wins", 0))],
		["대회 우승 × %d" % int(_result.get("titles", 0)), int(bd.get("titles", 0))],
		["클리어 보너스", int(bd.get("clear", 0))],
		["특성 보너스 × %d" % int(_result.get("bonus_points", 0)), int(bd.get("bonus", 0))],
	]
	# 합계 줄은 구분선 + 큰 글씨라 한 줄 반을 쓴다.
	var card: Panel = _section_card(parent, y, "점수", rows.size() + 2)
	var ry: float = SECTION_TITLE_H + CARD_PAD * 0.5
	for r in rows:
		var v: int = int(r[1])
		_row(card, ry, String(r[0]), "+%d" % v,
				OutgameTheme.TEXT if v > 0 else OutgameTheme.TEXT_FAINT)
		ry += ROW_H
	OutgameTheme.add_divider(card, Vector2(CARD_PAD, ry + 12.0), CARD_W - CARD_PAD * 2.0)
	ry += 28.0
	UiHelpers.mk_label(card, "합계", 28, OutgameTheme.TEXT,
			Vector2(CARD_PAD, ry), Vector2(300, 56))
	UiHelpers.mk_label(card, "%d" % int(_result.get("score", 0)), 44,
			OutgameTheme.ACCENT_TEXT, Vector2(CARD_W * 0.5, ry - 6.0),
			Vector2(CARD_W * 0.5 - CARD_PAD, 60), HORIZONTAL_ALIGNMENT_RIGHT)
	return y + card.size.y


## Rewards: both currencies, pass EXP (+ pass level change, overflow payout),
## manager EXP (+ level change and the removal points it grants). Level changes
## come from `profile_delta` only — a test run has none.
func _build_reward_card(parent: Control, y: float) -> float:
	var test_run: bool = bool(_result.get("test_run", false))
	var delta: Dictionary = _profile_delta()
	var cur: Dictionary = _result.get("currency", {})
	var rows: Array = [
		["아웃게임 재화", "+%d" % int(cur.get("outgame", 0)), OutgameTheme.POSITIVE],
		["레벨업 재화", "+%d" % int(cur.get("levelup", 0)), OutgameTheme.POSITIVE],
	]
	var pass_d: Dictionary = delta.get("pass", {})
	var pass_txt: String = "+%d" % int(_result.get("pass_exp", 0))
	var pass_up: bool = int(pass_d.get("to", 0)) > int(pass_d.get("from", 0))
	if pass_up:
		pass_txt += "  ·  Lv %d → %d" % [int(pass_d["from"]), int(pass_d["to"])]
	rows.append(["주간 패스 EXP", pass_txt,
			OutgameTheme.ACCENT_TEXT if pass_up else OutgameTheme.POSITIVE])
	var overflow: int = int(pass_d.get("overflow_outgame", 0))
	if overflow > 0:
		rows.append(["패스 초과분 → 아웃게임 재화", "+%d" % overflow, OutgameTheme.POSITIVE])
	var mgr_d: Dictionary = delta.get("manager", {})
	var mgr_from: int = int(mgr_d.get("from", 0))
	var mgr_to: int = int(mgr_d.get("to", 0))
	var mgr_up: bool = mgr_to > mgr_from
	var mgr_txt: String = "+%d" % int(_result.get("manager_exp", 0))
	if mgr_up:
		mgr_txt += "  ·  Lv %d → %d" % [mgr_from, mgr_to]
	rows.append(["감독 EXP", mgr_txt, OutgameTheme.ACCENT_TEXT if mgr_up else OutgameTheme.POSITIVE])
	if mgr_up:
		var pts: int = (mgr_to - mgr_from) * maxi(0, ConstTable.int_of("MANAGER_REMOVE_PER_LEVEL"))
		rows.append(["새 제거 포인트 (감독 탭)", "+%d" % pts, OutgameTheme.ACCENT_TEXT])

	var card: Panel = _section_card(parent, y, "보상", rows.size() + (1 if test_run else 0))
	var ry: float = SECTION_TITLE_H + CARD_PAD * 0.5
	for r in rows:
		_row(card, ry, String(r[0]), String(r[1]), r[2] as Color)
		ry += ROW_H
	if test_run:
		UiHelpers.mk_label(card, "테스트 런이라 프로필에 더하지 않았습니다", 22,
				OutgameTheme.TEXT_FAINT, Vector2(CARD_PAD, ry),
				Vector2(CARD_W - CARD_PAD * 2.0, ROW_H))
	return y + card.size.y


## Pilot growth (M10): per pilot the run's pilot EXP (`pilot_exp`) and, when the
## profile raised it, the max-level change (`profile_delta.pilots`, amber chip).
func _build_growth_card(parent: Control, y: float) -> float:
	var pilots: Array = _result.get("pilots", [])
	var pexp: Dictionary = _result.get("pilot_exp", {})
	var pdelta: Dictionary = _profile_delta().get("pilots", {})
	var card: Panel = OutgameTheme.add_card(parent, Vector2(_card_x(), y),
			Vector2(CARD_W, SECTION_TITLE_H + CARD_PAD * 1.5 + pilots.size() * GROWTH_ROW_H), 24)
	_section_title(card, "선수 성장")
	var ry: float = SECTION_TITLE_H + CARD_PAD * 0.5
	for p in pilots:
		var pd: Dictionary = p
		var pid: int = int(pd.get("id", -1))
		OutgameTheme.add_round_portrait(card, PilotImages.circle_for(pid),
				Vector2(CARD_PAD, ry + (GROWTH_ROW_H - GROWTH_PORTRAIT_D) * 0.5), GROWTH_PORTRAIT_D)
		var tx: float = CARD_PAD + GROWTH_PORTRAIT_D + 20.0
		UiHelpers.mk_label(card, String(pd.get("name", "")), 26, OutgameTheme.TEXT,
				Vector2(tx, ry + 12.0), Vector2(360, 36))
		UiHelpers.mk_label(card, "선수 EXP +%d" % int(pexp.get(str(pid), 0)), 20,
				OutgameTheme.TEXT_SUB, Vector2(tx, ry + 48.0), Vector2(360, 28))
		var d: Dictionary = pdelta.get(str(pid), {})
		if int(d.get("to", 0)) > int(d.get("from", 0)):
			var chip_w: float = 240.0
			OutgameTheme.add_chip(card, "최대 Lv %d → %d" % [int(d["from"]), int(d["to"])],
					Vector2(CARD_W - CARD_PAD - chip_w, ry + (GROWTH_ROW_H - 40.0) * 0.5),
					Vector2(chip_w, 40), OutgameTheme.ACCENT_DIM, OutgameTheme.ACCENT_TEXT, 20)
		ry += GROWTH_ROW_H
	return y + card.size.y


## Newly unlocked traits (M8) — amber card like the true ending: +/- chip, name,
## filled-in description, rarity chip.
func _build_unlocked_traits_card(parent: Control, y: float) -> float:
	var ids: Array = _new_trait_ids()
	var test_run: bool = bool(_result.get("test_run", false))
	var note_h: float = 40.0
	var card: Panel = OutgameTheme.add_card(parent, Vector2(_card_x(), y),
			Vector2(CARD_W, SECTION_TITLE_H + CARD_PAD * 1.5 + note_h + ids.size() * TRAIT_ROW_H),
			24, OutgameTheme.ACCENT_DIM)
	UiHelpers.mk_label(card, "새 특성 해금", 24, OutgameTheme.ACCENT_TEXT,
			Vector2(CARD_PAD, CARD_PAD * 0.5 + 8.0), Vector2(CARD_W - CARD_PAD * 2.0, 34))
	OutgameTheme.add_divider(card, Vector2(CARD_PAD, SECTION_TITLE_H + 8.0),
			CARD_W - CARD_PAD * 2.0, OutgameTheme.ACCENT)
	var ry: float = SECTION_TITLE_H + CARD_PAD * 0.5
	var note: String = "테스트 런 — 프로필에 지급하지 않았습니다" if test_run \
			else "다음 런부터 감독 탭에서 장착할 수 있습니다"
	UiHelpers.mk_label(card, note, 20, OutgameTheme.TEXT_SUB,
			Vector2(CARD_PAD, ry), Vector2(CARD_W - CARD_PAD * 2.0, 30))
	ry += note_h
	for raw in ids:
		var tid: int = int(raw)
		var r: Dictionary = TraitSystem.row(tid)
		var pos: bool = TraitSystem.is_positive(tid)
		var sign_color: Color = OutgameTheme.POSITIVE if pos else OutgameTheme.NEGATIVE
		var row_card: Panel = OutgameTheme.add_card(card, Vector2(CARD_PAD, ry + 6.0),
				Vector2(CARD_W - CARD_PAD * 2.0, TRAIT_ROW_H - 12.0), 16)
		var rw: float = row_card.size.x
		OutgameTheme.add_chip(row_card, "+" if pos else "−", Vector2(20, 24), Vector2(44, 44),
				sign_color, OutgameTheme.TEXT_ON_FILL, 26)
		UiHelpers.mk_label(row_card, String(r.get("name", "#%d" % tid)), 28, OutgameTheme.TEXT,
				Vector2(84, 8), Vector2(rw - 260, 38))
		UiHelpers.mk_label(row_card, TraitSystem.desc_of(tid), 20, OutgameTheme.TEXT_SUB,
				Vector2(84, 48), Vector2(rw - 260, 30))
		OutgameTheme.add_chip(row_card, TraitSystem.rarity_name(int(r.get("rarity", 0))),
				Vector2(rw - 156, 26), Vector2(132, 40), OutgameTheme.ACCENT,
				OutgameTheme.TEXT_ON_FILL, 20)
		ry += TRAIT_ROW_H
	return y + card.size.y


func _build_achievement_card(parent: Control, y: float) -> float:
	var pilots: Array = _result.get("pilots", [])
	var ach: Dictionary = _result.get("achievements", {})
	var rows_h: float = maxf(1.0, float(pilots.size())) * PILOT_ROW_H
	var card: Panel = OutgameTheme.add_card(parent, Vector2(_card_x(), y),
			Vector2(CARD_W, SECTION_TITLE_H + CARD_PAD * 1.5 + rows_h), 24)
	_section_title(card, "이번 런 업적")
	var ry: float = SECTION_TITLE_H + CARD_PAD * 0.5
	if pilots.is_empty():
		UiHelpers.mk_label(card, "기록된 선수가 없습니다", 24, OutgameTheme.TEXT_FAINT,
				Vector2(CARD_PAD, ry + 30.0), Vector2(CARD_W - CARD_PAD * 2.0, 40))
		return y + card.size.y
	for p in pilots:
		var pd: Dictionary = p
		var pid: int = int(pd.get("id", -1))
		var a: Dictionary = ach.get(str(pid), {})
		var tex: Texture2D = PilotImages.circle_for(pid)
		OutgameTheme.add_round_portrait(card, tex,
				Vector2(CARD_PAD, ry + (PILOT_ROW_H - PORTRAIT_D) * 0.5), PORTRAIT_D)
		var tx: float = CARD_PAD + PORTRAIT_D + 24.0
		UiHelpers.mk_label(card, String(pd.get("name", "")), 28, OutgameTheme.TEXT,
				Vector2(tx, ry + 18.0), Vector2(360, 40))
		var role: int = int(pd.get("role", -1))
		var role_name: String = String(OutgameTheme.ROLE_NAMES[role]) \
				if role >= 0 and role < OutgameTheme.ROLE_NAMES.size() else ""
		UiHelpers.mk_label(card, role_name, 20, OutgameTheme.TEXT_SUB,
				Vector2(tx, ry + 58.0), Vector2(360, 30))
		var mvp_n: int = int(a.get("mvp", 0))
		var pom_n: int = int(a.get("pom", 0))
		var chip_w: float = 140.0
		var cx: float = CARD_W - CARD_PAD - chip_w
		_count_chip(card, "POM %d" % pom_n, pom_n > 0, Vector2(cx, ry + 32.0), chip_w)
		_count_chip(card, "MVP %d" % mvp_n, mvp_n > 0,
				Vector2(cx - chip_w - 16.0, ry + 32.0), chip_w)
		ry += PILOT_ROW_H
	return y + card.size.y


func _build_empty() -> void:
	var vp_w: float = ScreenMetrics.vp_w()
	UiHelpers.mk_label(self, "런 정산", 64, OutgameTheme.TEXT,
			Vector2(0, 120), Vector2(vp_w, 88), HORIZONTAL_ALIGNMENT_CENTER)
	var card: Panel = OutgameTheme.add_card(self, Vector2(_card_x(), 420),
			Vector2(CARD_W, 220), 24)
	var l1 := UiHelpers.mk_label(card, "표시할 정산 결과가 없습니다", 30,
			OutgameTheme.TEXT_SUB, Vector2(0, 58), Vector2(CARD_W, 44),
			HORIZONTAL_ALIGNMENT_CENTER)
	l1.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	UiHelpers.mk_label(card, "런이 끝나면 이 화면에 점수와 보상이 나옵니다", 22,
			OutgameTheme.TEXT_FAINT, Vector2(0, 112), Vector2(CARD_W, 34),
			HORIZONTAL_ALIGNMENT_CENTER)


func _build_bottom_bar() -> void:
	var to_new_run: bool = String(_result.get("outcome", "")) == RunResult.OUTCOME_ABANDON
	var bar: Array = OutgameTheme.add_bottom_bar(self, [
		{"text": "새 런" if to_new_run else "로비로", "style": "primary",
				"font": 32, "weight": 1.0},
	])
	(bar[0] as Button).pressed.connect(_on_new_run_pressed if to_new_run else _on_lobby_pressed)


# ── 그리기 조각 ──────────────────────────────────────────────────────────────
# 제목 + `row_count` 줄짜리 카드 한 장.
func _section_card(parent: Control, y: float, title: String, row_count: int) -> Panel:
	var card: Panel = OutgameTheme.add_card(parent, Vector2(_card_x(), y),
			Vector2(CARD_W, SECTION_TITLE_H + CARD_PAD * 1.5 + row_count * ROW_H), 24)
	_section_title(card, title)
	return card


func _section_title(card: Control, title: String) -> void:
	UiHelpers.mk_label(card, title, 24, OutgameTheme.TEXT_SUB,
			Vector2(CARD_PAD, CARD_PAD * 0.5 + 8.0), Vector2(CARD_W - CARD_PAD * 2.0, 34))
	OutgameTheme.add_divider(card, Vector2(CARD_PAD, SECTION_TITLE_H + 8.0),
			CARD_W - CARD_PAD * 2.0)


func _row(card: Control, ry: float, label: String, value: String, value_color: Color) -> void:
	UiHelpers.mk_label(card, label, 24, OutgameTheme.TEXT_SUB,
			Vector2(CARD_PAD, ry + 6.0), Vector2(CARD_W * 0.55, 36))
	UiHelpers.mk_label(card, value, 26, value_color,
			Vector2(CARD_W * 0.45, ry + 4.0), Vector2(CARD_W * 0.55 - CARD_PAD, 38),
			HORIZONTAL_ALIGNMENT_RIGHT)


func _count_chip(card: Control, text: String, lit: bool, pos: Vector2, w: float) -> void:
	OutgameTheme.add_chip(card, text, pos, Vector2(w, 40),
			OutgameTheme.ACCENT_DIM if lit else OutgameTheme.SURFACE_SUNK,
			OutgameTheme.ACCENT_TEXT if lit else OutgameTheme.TEXT_FAINT, 20)


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
	return String(HubView.PHASE_NAMES.get(RunResult.CAMPAIGN_ORDER[idx], "—"))


# ── Button handlers ──────────────────────────────────────────────────────────
# 정산은 이미 프로필에 썼고 run.save 도 지웠다 — 남은 런 상태를 비우고 떠난다.
func _on_lobby_pressed() -> void:
	_gm.reset_season_state()
	get_tree().change_scene_to_file(LOBBY_SCENE)


func _on_new_run_pressed() -> void:
	_gm.reset_season_state()
	get_tree().change_scene_to_file(RUN_SETUP_SCENE)
