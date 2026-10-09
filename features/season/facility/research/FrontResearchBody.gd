class_name FrontResearchBody
extends VBoxContainer

# Front facility sheet section (`FrontResearch.make_body`, §16): permanent upkeep cut,
# running research boosts, the expansion ladder (one line per front level 2..max), and the
# "no facility above the front" rule with every facility's level.
# Layout lives in `UI_View_FrontResearchBody.tscn`; this script fills the `%` nodes. The
# template-line lists (`%Boosts`, `%Expands`, `%Caps`) duplicate their first `Label`.
# Line colours are data (state of the rung / capped or not).

const SCENE_PATH: String = "res://features/season/facility/research/UI_View_FrontResearchBody.tscn"

var _state: Dictionary = {}


## Instantiates the scene bound to `state` (filled on `_ready`, or now via `refresh`).
static func create(state: Dictionary) -> FrontResearchBody:
	var body := (load(SCENE_PATH) as PackedScene).instantiate() as FrontResearchBody
	body._state = state
	return body


func _ready() -> void:
	if UiPreview.is_standalone(self):
		_fill_preview()
		return
	refresh()


## Refills every line from the bound state.
func refresh() -> void:
	if _state.is_empty():
		return
	var state: Dictionary = _state
	%CutLine.text = Loc.t(L.RESEARCH_FRONT_BODY_CUT_LINE,
			{"pct": FinanceSystem.upkeep_cut_pct(state), "max": FinanceSystem.upkeep_cut_max()})

	var boosts: Array = []
	for raw in ((state.get("research", {}) as Dictionary).get("boosts", []) as Array):
		var b: Dictionary = raw
		boosts.append([Loc.t(L.RESEARCH_FRONT_BODY_BOOST_LINE,
				{"pct": int(b.get("pct", 0)), "weeks": int(b.get("weeks_left", 0))}), OutgameTheme.POSITIVE])
	if boosts.is_empty():
		boosts.append([Loc.t(L.RESEARCH_FRONT_BODY_BOOST_NONE), OutgameTheme.TEXT_SUB])
	_fill_lines(%Boosts, boosts)

	var front: int = FacilitySystem.level(state, FacilitySystem.FRONT)
	var ladder: Array = []
	for n in range(2, FacilitySystem.max_level() + 1):
		if n <= front:
			ladder.append([Loc.t(L.RESEARCH_FRONT_BODY_EXPAND_REACHED, {"level": n}), OutgameTheme.TEXT_SUB])
		elif FacilitySystem.front_expand_done(state, n):
			ladder.append([Loc.t(L.RESEARCH_FRONT_BODY_EXPAND_READY, {"level": n}), OutgameTheme.POSITIVE])
		elif n - 1 <= front:
			var pct: int = int(round(FrontResearch.expand_progress(state, n) * 100.0))
			ladder.append([Loc.t(L.RESEARCH_FRONT_BODY_EXPAND_PROGRESS, {"level": n, "pct": pct}), OutgameTheme.TEXT])
		else:
			ladder.append([Loc.t(L.RESEARCH_FRONT_BODY_EXPAND_LOCKED, {"level": n, "need": n - 1}),
					OutgameTheme.TEXT_FAINT])
	_fill_lines(%Expands, ladder)

	%CapRule.text = Loc.t(L.RESEARCH_FRONT_BODY_CAP_RULE, {"level": front})
	var caps: Array = []
	for raw in FacilitySystem.FACILITIES:
		var fid: String = String(raw)
		if fid == FacilitySystem.FRONT:
			continue
		var lvl: int = FacilitySystem.level(state, fid)
		var capped: bool = lvl >= front
		caps.append([Loc.t(L.RESEARCH_FRONT_BODY_CAP_LINE_FULL if capped else L.RESEARCH_FRONT_BODY_CAP_LINE,
				{"name": FacilitySystem.facility_name(fid), "level": lvl}),
				OutgameTheme.TEXT_SUB if capped else OutgameTheme.TEXT])
	_fill_lines(%Caps, caps)


## Template-line list: the scene's first Label is duplicated per `[text, colour]` entry.
static func _fill_lines(list: Node, entries: Array) -> void:
	if list.get_child_count() == 0:
		return
	while list.get_child_count() > maxi(1, entries.size()):
		var last: Node = list.get_child(list.get_child_count() - 1)
		list.remove_child(last)
		last.queue_free()
	var tpl: Label = list.get_child(0)
	while list.get_child_count() < entries.size():
		list.add_child(tpl.duplicate())
	for i in entries.size():
		var line: Label = list.get_child(i)
		line.text = String(entries[i][0])
		line.add_theme_color_override("font_color", entries[i][1])
	(list as CanvasItem).visible = not entries.is_empty()


## F6 미리보기 — 메모리 런에 절감 · 지원 · 확장 진행을 조금 넣어 모든 줄이 차게 한다.
func _fill_preview() -> void:
	UiPreview.stage(self)
	var gm: Node = UiPreview.ensure_run()
	if gm == null:
		return
	var state: Dictionary = gm.season_state
	FinanceSystem.add_upkeep_cut(state, 10)
	ResearchSystem.add_boost(state, 10, FrontResearch.boost_weeks())
	var front: int = FacilitySystem.level(state, FacilitySystem.FRONT)
	var row: Dictionary = FrontResearch.expand_row(front + 1)
	if not row.is_empty():
		var pts: Dictionary = (state.get("research", {}) as Dictionary).get("points", {})
		pts[ResearchSystem.key_of(String(row["id"]), "")] = int(ResearchSystem.cost(row) * 0.5)
	_state = state
	refresh()
