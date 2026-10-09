class_name FrontBody
extends VBoxContainer

# Front facility body (`FacilityView` %BodySlot, `ResearchSystem.make_body` for kind `front`).
# The front has no research (removed 2026-10-09) — the body shows the cap rule and every other
# facility's level against the front's. **Layout lives in `UI_View_FrontBody.tscn`**; `%Rows/Row`
# is the template row, duplicated per facility (children read by path).

const SCENE_PATH: String = "res://features/season/facility/UI_View_FrontBody.tscn"

var _state: Dictionary = {}
var _template: Control = null


static func create(state: Dictionary) -> FrontBody:
	var b := (load(SCENE_PATH) as PackedScene).instantiate() as FrontBody
	b._state = state
	return b


func _ready() -> void:
	_template = %Rows.get_child(0)
	%Rows.remove_child(_template)
	if UiPreview.is_standalone(self):
		_fill_preview()
		return
	refresh()


func _exit_tree() -> void:
	if _template != null and not _template.is_inside_tree():
		_template.free()
		_template = null


func refresh() -> void:
	var state: Dictionary = _state
	var front_lv: int = FacilitySystem.level(state, FacilitySystem.FRONT)
	var fids: Array = []
	for f in FacilitySystem.FACILITIES:
		if String(f) != FacilitySystem.FRONT:
			fids.append(String(f))
	var rows: Node = %Rows
	while rows.get_child_count() < fids.size():
		rows.add_child(_template.duplicate())
	for i in fids.size():
		var row: Node = rows.get_child(i)
		var fid: String = fids[i]
		var lvl: int = FacilitySystem.level(state, fid)
		(row.get_node("Box/Icon") as TextureRect).texture = FacilitySystem.icon_of(fid)
		(row.get_node("Box/Name") as Label).text = FacilitySystem.facility_name(fid)
		var lv_l: Label = row.get_node("Box/Level")
		var at_cap: bool = lvl >= front_lv
		lv_l.text = Loc.t(L.FACILITY_UI_FRONT_LEVEL_CAP if at_cap else L.FACILITY_UI_FRONT_LEVEL, {"level": lvl})
		lv_l.theme_type_variation = &"AccentLabel" if at_cap else &"BodyLabel"


## F6 단독 실행 미리보기 — 메모리 런의 시설 레벨.
func _fill_preview() -> void:
	UiPreview.stage(self)
	var gm: Node = UiPreview.ensure_run()
	if gm == null:
		return
	_state = gm.season_state
	refresh()
