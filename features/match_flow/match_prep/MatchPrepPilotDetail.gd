class_name MatchPrepPilotDetail
extends VBoxContainer

# PREP pilot detail for an **opponent** pilot (or my pilot outside a run, when
# `SeasonPilotDetail` has no run pilot to show) — a `HubSheet` body (title = pilot name):
# the reveal-tier line, then the pilot as one `IntelPilotRow` (six stats as `?` / ranges /
# exact, mech line from tier 2, card line at tier 3 — the same `OpponentIntel.build()` row the
# card was filled from, so the sheet never shows more than the tier allows).
#
# **Layout lives in `UI_View_MatchPrepPilotDetail.tscn`.** `open` puts one instance into the
# sheet's `body`; the sheet's scroll height follows this node's height (`resized`).

const SCENE_PATH: String = "res://features/match_flow/match_prep/UI_View_MatchPrepPilotDetail.tscn"

var _sheet: HubSheet = null


static func create() -> MatchPrepPilotDetail:
	return (load(SCENE_PATH) as PackedScene).instantiate() as MatchPrepPilotDetail


## Opens the sheet on `host` for `row` (an `OpponentIntel.build()` row) of `intel`.
static func open(host: Node, intel: Dictionary, row: Dictionary) -> HubSheet:
	var sheet := HubSheet.open_on(host, String(row["name"]))
	var panel := create()
	sheet.body.add_child(panel)
	panel.bind(sheet, intel, row)
	return sheet


func _ready() -> void:
	resized.connect(_fit_sheet)
	if UiPreview.is_standalone(self):
		_fill_preview()


func bind(sheet: HubSheet, intel: Dictionary, row: Dictionary) -> void:
	_sheet = sheet
	show_detail(intel, row)
	_fit_sheet()


func show_detail(intel: Dictionary, row: Dictionary) -> void:
	var tier: Label = %Tier
	tier.visible = not bool(intel.get("own", false))
	tier.text = Loc.t(L.MATCH_INTEL_TIER_HEADER,
			{"tier": int(intel.get("tier", 0)), "label": intel.get("tier_label", "")})
	(%IntelPilotRow_Pilot as IntelPilotRow).fill(row)


func _fit_sheet() -> void:
	if _sheet != null:
		_sheet.set_body_height(size.y)


## F6 단독 실행 미리보기 — 메모리 런의 다른 팀 첫 선수(런의 실제 분석 단계). 시트 없이 본문만.
func _fill_preview() -> void:
	UiPreview.stage(self)
	var gm: Node = UiPreview.ensure_run()
	if gm == null:
		return
	var s: Dictionary = gm.season_state
	var tid: int = (int(s["player_team_id"]) + 1) % 8
	var intel: Dictionary = OpponentIntel.build(s, OpponentIntel.team_roster(s, tid), false, tid)
	var rows: Array = intel["rows"]
	if not rows.is_empty():
		show_detail(intel, rows[0])
