class_name IntelResearchBody
extends ScrollContainer

# Intel facility body (`IntelResearch.make_body` → `FacilityView` %BodySlot, Body contract in
# `features/season/facility/README.md`): one `IntelTeamRow` card per team of the competition I play
# in now (`IntelResearch.field`, next opponent first). No row picking: the card's `분석` button makes
# that team the target of the single row `in_scout` (`ResearchSystem.select`, HUB only).
#
# **Layout lives in `UI_View_IntelResearchBody.tscn`** (scroll + `%Rows`) and `UI_Comp_IntelTeamRow.tscn`;
# the list scrolls inside the body (`DragScroll`), the facility screen itself never scrolls.

signal changed
signal message(text: String)

const SCENE_PATH: String = "res://features/season/facility/research/UI_View_IntelResearchBody.tscn"
const FID: String = "intel"
const ROW_ID: String = "in_scout"

var _state: Dictionary = {}


static func create() -> IntelResearchBody:
	return (load(SCENE_PATH) as PackedScene).instantiate() as IntelResearchBody


func _ready() -> void:
	DragScroll.attach(self)
	for c in %Rows.get_children():   # editor preview row
		%Rows.remove_child(c)
		c.queue_free()
	if UiPreview.is_standalone(self):
		_fill_preview()
		return
	if not _state.is_empty():
		refresh()


## Shows the run `state`. Callable before `_ready` (applied there).
func fill(state: Dictionary) -> void:
	_state = state
	if is_node_ready():
		refresh()


## Rebuilds the cards in place (rows reused): rank, progress, button state per team.
func refresh() -> void:
	var state: Dictionary = _state
	var ids: Array = IntelResearch.field(state)
	var rows: Node = %Rows
	while rows.get_child_count() > ids.size():
		var extra: Node = rows.get_child(rows.get_child_count() - 1)
		rows.remove_child(extra)
		extra.queue_free()
	while rows.get_child_count() < ids.size():
		var r := IntelTeamRow.create()
		rows.add_child(r)
		r.analyse_pressed.connect(_on_analyse)
	var next_id: int = IntelResearch.next_opponent(state)
	var act: Dictionary = ResearchSystem.active(state, FID)
	var active_tid: int = int(act["target"]) if String(act.get("rid", "")) == ROW_ID \
			and String(act.get("target", "")).is_valid_int() else -1
	var can: bool = ResearchSystem.can_select(state)
	for i in ids.size():
		var tid: int = int(ids[i])
		var rank: int = IntelResearch.rank(state, tid)
		var mode: IntelTeamRow.Mode = IntelTeamRow.Mode.IDLE
		if rank >= IntelResearch.MAX_RANK:
			mode = IntelTeamRow.Mode.DONE
		elif tid == active_tid:
			mode = IntelTeamRow.Mode.ACTIVE
		elif not can:
			mode = IntelTeamRow.Mode.LOCKED
		(rows.get_child(i) as IntelTeamRow).fill(tid, rank,
				ResearchSystem.progress(state, FID, ROW_ID, str(tid)), tid == next_id, mode)


func _on_analyse(team_id: int) -> void:
	var why: String = ResearchSystem.select(_state, FID, ROW_ID, str(team_id))
	if why != "":
		message.emit(why)
		return
	refresh()
	changed.emit()


## F6 단독 실행 미리보기 — 메모리 런 + 미리보기 리그(다음 상대), 세 팀에 분석 1~3단계,
## 한 팀은 분석 중(포인트 일부).
func _fill_preview() -> void:
	UiPreview.stage(self)
	var gm: Node = UiPreview.ensure_run()
	if gm == null:
		return
	UiPreview.ensure_league(self, 0)
	var s: Dictionary = gm.season_state
	var pid: int = int(s["player_team_id"])
	var ranks: Dictionary = {}
	for i in 3:
		ranks[str((pid + 2 + i) % 8)] = i + 1
	s["intel_rank"] = ranks
	var target: String = str((pid + 3) % 8)   # rank 2 → analysing toward 3
	ResearchSystem.select(s, FID, ROW_ID, target)
	var res: Dictionary = s["research"]
	(res["points"] as Dictionary)[ResearchSystem.key_of(ROW_ID, target)] = \
			int(ResearchSystem.cost(ResearchSystem.row(ROW_ID)) * 0.6)
	fill(s)
