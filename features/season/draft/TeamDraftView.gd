class_name TeamDraftView
extends Control

# Procedural UI for the initial team draft. Lives as a child of the TeamDraft
# Control node and reads the **네임드 25인** pool through
# TeamDraft.get_pool_grid() (모브 15명은 그 함수가 걸러 낸다 — 스킬이 없는
# 이름 없는 선수라 플레이어가 뽑을 대상이 아니다).
# Tap a card to pick that pilot for its role; tap the same card again to unpick;
# tap a different card in the same role to swap. Confirm button activates once
# all five roles are filled, then calls TeamDraft.apply_draft() and routes the
# hub to Screen.HUB.

const PILOT_CARD_SCN: PackedScene = preload("res://features/season/draft/PilotCard.tscn")

const ROLE_NAMES: Array = ["TANK", "FIGHTER", "ASSASSIN", "SUPPORT", "SNIPER"]
const ROLE_COLORS: Array = [
	Color(0.30, 0.55, 1.00),
	Color(1.00, 0.55, 0.20),
	Color(0.75, 0.40, 1.00),
	Color(0.30, 0.85, 0.45),
	Color(1.00, 0.35, 0.35),
]

const COLS: int = 5
## 역할당 후보 수 = 네임드 파일럿 25 ÷ 5역할. 예전에는 40인 풀 전체라 8이었다.
const ROWS: int = 5
const COL_W: float = 200.0
const ROW_H: float = 175.0
const GRID_X0: float = 40.0
const GRID_Y0: float = 280.0

@onready var _draft: TeamDraft = get_parent() as TeamDraft
@onready var _gm: Node = get_node("/root/GameManager")

var _picks: Array = [-1, -1, -1, -1, -1]   # role -> pilot id (-1 if empty)
var _cards_by_id: Dictionary = {}             # pilot_id(int) -> PilotCard
var _summary_name_lbls: Array = []            # 5 Label
var _summary_team_lbls: Array = []            # 5 Label
var _summary_count_lbl: Label
var _confirm_btn: Button


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_PASS
	_build_ui()
	_refresh_summary()
	_refresh_confirm_btn()


# ── Build ────────────────────────────────────────────────────────────────────
func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.07, 0.08, 0.14, 1.0)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	UiHelpers.mk_label(self, "TEAM DRAFT", 42, Color(1.0, 0.85, 0.2),
			Vector2(0, 18), Vector2(1080, 50), HORIZONTAL_ALIGNMENT_CENTER)

	_summary_count_lbl = UiHelpers.mk_label(self, "내 팀 (0/5)", 22,
			Color(0.9, 0.95, 1.0),
			Vector2(0, 76), Vector2(1080, 28), HORIZONTAL_ALIGNMENT_CENTER)

	_build_summary_row()
	_build_role_headers()
	_build_grid()
	_build_confirm_btn()


func _build_summary_row() -> void:
	for r in COLS:
		var slot := Panel.new()
		var sty := StyleBoxFlat.new()
		sty.bg_color = Color(0.10, 0.12, 0.18, 1.0)
		sty.border_color = ROLE_COLORS[r]
		sty.border_width_left = 2; sty.border_width_right = 2
		sty.border_width_top = 2;  sty.border_width_bottom = 2
		sty.corner_radius_top_left     = 6
		sty.corner_radius_top_right    = 6
		sty.corner_radius_bottom_left  = 6
		sty.corner_radius_bottom_right = 6
		slot.add_theme_stylebox_override("panel", sty)
		slot.position = Vector2(GRID_X0 + r * COL_W + 8, 110)
		slot.size     = Vector2(COL_W - 16, 110)
		add_child(slot)

		UiHelpers.mk_label(slot, ROLE_NAMES[r], 16, ROLE_COLORS[r],
				Vector2(0, 6), Vector2(slot.size.x, 22),
				HORIZONTAL_ALIGNMENT_CENTER)

		var name_lbl := UiHelpers.mk_label(slot, "—", 22, Color(1, 1, 1),
				Vector2(0, 36), Vector2(slot.size.x, 32),
				HORIZONTAL_ALIGNMENT_CENTER)
		_summary_name_lbls.append(name_lbl)

		var team_lbl := UiHelpers.mk_label(slot, "", 14,
				Color(0.7, 0.75, 0.85),
				Vector2(0, 76), Vector2(slot.size.x, 22),
				HORIZONTAL_ALIGNMENT_CENTER)
		_summary_team_lbls.append(team_lbl)


func _build_role_headers() -> void:
	for r in COLS:
		UiHelpers.mk_label(self, ROLE_NAMES[r], 18, ROLE_COLORS[r],
				Vector2(GRID_X0 + r * COL_W, 248),
				Vector2(COL_W, 26), HORIZONTAL_ALIGNMENT_CENTER)


func _build_grid() -> void:
	var entries: Array = _draft.get_pool_grid()
	for entry_raw in entries:
		var entry: Dictionary = entry_raw
		var role: int = entry["role"]
		var rank: int = entry["rank"]
		var pilot: PlayerData = entry["pilot"]
		var card: PilotCard = PILOT_CARD_SCN.instantiate()
		card.position = Vector2(GRID_X0 + role * COL_W,
				GRID_Y0 + rank * ROW_H)
		add_child(card)
		card.setup(pilot, false)
		card.card_tapped.connect(_on_card_tapped)
		_cards_by_id[pilot.id] = card


func _build_confirm_btn() -> void:
	_confirm_btn = Button.new()
	_confirm_btn.text = "드래프트 확정"
	_confirm_btn.position = Vector2(290, 1720)
	_confirm_btn.size     = Vector2(500, 120)
	_confirm_btn.add_theme_font_size_override("font_size", 36)
	_confirm_btn.disabled = true
	_confirm_btn.pressed.connect(_on_confirm_pressed)
	add_child(_confirm_btn)


# ── Interaction ──────────────────────────────────────────────────────────────
func _on_card_tapped(pilot_id: int) -> void:
	if not _cards_by_id.has(pilot_id):
		return
	var card: PilotCard = _cards_by_id[pilot_id]
	var pilot: PlayerData = card.pilot
	var role: int = int(pilot.role)

	if _picks[role] == pilot_id:
		_picks[role] = -1
		card.set_selected(false)
	else:
		var prev_id: int = int(_picks[role])
		if prev_id != -1 and _cards_by_id.has(prev_id):
			(_cards_by_id[prev_id] as PilotCard).set_selected(false)
		_picks[role] = pilot_id
		card.set_selected(true)

	_refresh_summary()
	_refresh_confirm_btn()


func _refresh_summary() -> void:
	var count: int = 0
	for r in 5:
		var pid: int = int(_picks[r])
		if pid != -1 and _cards_by_id.has(pid):
			count += 1
			var p: PlayerData = (_cards_by_id[pid] as PilotCard).pilot
			_summary_name_lbls[r].text = p.name
			_summary_team_lbls[r].text = "원소속: %s" % _team_short(p.team_id)
		else:
			_summary_name_lbls[r].text = "—"
			_summary_team_lbls[r].text = ""
	_summary_count_lbl.text = "내 팀 (%d/5)" % count


func _refresh_confirm_btn() -> void:
	for r in 5:
		if int(_picks[r]) == -1:
			_confirm_btn.disabled = true
			return
	_confirm_btn.disabled = false


func _team_short(team_id: int) -> String:
	var meta: Array = _gm.season_state.get("team_meta", [])
	if team_id < 0 or team_id >= meta.size():
		return "TEAM %d" % team_id
	return String(meta[team_id]["short_name"])


func _on_confirm_pressed() -> void:
	var ids: Array = _picks.duplicate()
	var err: String = _draft.apply_draft(ids)
	if err != "":
		push_error("TeamDraftView: confirm failed — " + err)
		return
	var hub: SeasonHub = _draft.get_parent() as SeasonHub
	if hub:
		hub.goto(SeasonHub.Screen.HUB)
