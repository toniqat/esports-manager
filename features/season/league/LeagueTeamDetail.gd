class_name LeagueTeamDetail
extends VBoxContainer

# Body of the standings **team detail sheet** (`HubSheet`): the record line + the team's five
# pilots under the analysis reveal rule (`IntelView` — the same scene MatchFlow PREP uses).
#
# **Layout lives in `UI_View_LeagueTeamDetail.tscn`.** Like the hub panels (`FinancePanel` …) it is one
# instance under `sheet.body`, top-wide, and the sheet scrolls exactly this node's height
# (`set_body_height(size.y)` on `resized`). Opened by `LeagueView.open_team_detail`.

const SCENE_PATH: String = "res://features/season/league/UI_View_LeagueTeamDetail.tscn"

var _sheet: HubSheet = null


static func create() -> LeagueTeamDetail:
	return (load(SCENE_PATH) as PackedScene).instantiate() as LeagueTeamDetail


## Opens a `HubSheet` titled `title` under `host` with this body; returns the sheet.
static func open(host: Node, title: String, record: String, intel: Dictionary) -> HubSheet:
	var sheet := HubSheet.open_on(host, title)
	var detail := create()
	sheet.body.add_child(detail)
	detail.bind(sheet, record, intel)
	return sheet


func _ready() -> void:
	resized.connect(_fit_sheet)
	if UiPreview.is_standalone(self):
		_fill_preview()


func bind(sheet: HubSheet, record: String, intel: Dictionary) -> void:
	_sheet = sheet
	show_detail(record, intel)
	_fit_sheet()


func show_detail(record: String, intel: Dictionary) -> void:
	%Record.text = record
	(%IntelView_Intel as IntelView).show_intel(intel)


func _fit_sheet() -> void:
	if _sheet != null:
		_sheet.set_body_height(size.y)


## F6 단독 실행 미리보기 — 메모리 런의 다른 팀 하나(런의 실제 분석 단계). 시트 없이 본문만.
func _fill_preview() -> void:
	UiPreview.stage(self)
	var gm: Node = UiPreview.ensure_run()
	if gm == null:
		return
	var s: Dictionary = gm.season_state
	var tid: int = (int(s["player_team_id"]) + 1) % 8
	show_detail("2위 · 3승 1패",
			OpponentIntel.build(s, OpponentIntel.team_roster(s, tid), false))
