class_name IntelTeamRow
extends PanelContainer

# One team card of the intel facility body (`IntelResearchBody`): logo · short name (big) with the
# analysis rank pips · `다음 상대` chip · full name (small) · the `분석` button on the right, and the
# progress to the next rank below (bar + percent). **Layout lives in `UI_Comp_IntelTeamRow.tscn`**;
# this script fills texts / states and forwards the button as `analyse_pressed(team_id)`.

signal analyse_pressed(team_id: int)

## Button / card state of a row.
enum Mode { IDLE, ACTIVE, DONE, LOCKED }   # pickable · being analysed · rank max · week running

const SCENE_PATH: String = "res://features/season/facility/research/UI_Comp_IntelTeamRow.tscn"

var team_id: int = -1


static func create() -> IntelTeamRow:
	return (load(SCENE_PATH) as PackedScene).instantiate() as IntelTeamRow


func _ready() -> void:
	(%Analyse as Button).pressed.connect(_on_analyse)
	if UiPreview.is_standalone(self):
		_fill_preview()


## `rank` 0..`IntelResearch.MAX_RANK`, `ratio` = progress to the next rank (0..1).
func fill(tid: int, rank: int, ratio: float, is_next: bool, mode: Mode) -> void:
	team_id = tid
	(%Logo as TextureRect).texture = TeamLogos.texture(tid)
	(%Short as Label).text = IntelResearch.team_short(tid)
	(%Full as Label).text = IntelResearch.team_full(tid)
	(%NextChip as Control).visible = is_next
	(%NextText as Label).text = Loc.t(L.RESEARCH_INTEL_BODY_NEXT)
	var top: int = IntelResearch.MAX_RANK
	var pips: Node = %Pips
	for i in pips.get_child_count():
		(pips.get_child(i) as Control).theme_type_variation = &"ProgressFill" if i < rank else &"ProgressTrack"
	(%RankText as Label).text = Loc.t(L.RESEARCH_INTEL_BODY_RANK, {"rank": rank, "max": top})

	var done: bool = rank >= top
	var shown: float = 1.0 if done else clampf(ratio, 0.0, 1.0)
	(%Fill as Control).anchor_right = shown
	var pct: Label = %Percent
	pct.text = Loc.t(L.RESEARCH_INTEL_BODY_COMPLETE) if done else ResearchBubble.percent_text(shown)
	pct.theme_type_variation = &"AccentLabel" if done or mode == Mode.ACTIVE else &"SubLabel"

	theme_type_variation = &"SelectableCardOn" if mode == Mode.ACTIVE else &"SelectableCard"
	var btn: Button = %Analyse
	match mode:
		Mode.ACTIVE:
			btn.text = Loc.t(L.RESEARCH_INTEL_BODY_ANALYSING)
			btn.theme_type_variation = &"SelectableTileOn"
			btn.disabled = false
			btn.mouse_filter = Control.MOUSE_FILTER_IGNORE   # active look, not pressable
		Mode.DONE:
			btn.text = Loc.t(L.RESEARCH_INTEL_BODY_DONE)
			btn.theme_type_variation = &"GhostButton"
			btn.disabled = true
			btn.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_:
			btn.text = Loc.t(L.RESEARCH_INTEL_BODY_ANALYSE)
			btn.theme_type_variation = &"PrimaryButton"
			btn.disabled = mode == Mode.LOCKED
			btn.mouse_filter = Control.MOUSE_FILTER_STOP


func _on_analyse() -> void:
	analyse_pressed.emit(team_id)


## F6 단독 실행 미리보기 — 손으로 적은 값: 다음 상대, 분석 1단계, 40 %.
func _fill_preview() -> void:
	UiPreview.stage(self)
	custom_minimum_size.x = 1000.0
	UiPreview.ensure_run()
	fill(3, 1, 0.4, true, Mode.IDLE)
	UiPreview.trace(analyse_pressed, "analyse")
