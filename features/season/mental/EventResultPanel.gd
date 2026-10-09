class_name EventResultPanel
extends VBoxContainer

# Event result body: what an answer / visit did, one block per pilot.
#
#   (portrait)  Evelyn
#               스트레스          72 / 100   -15     ← row: label · value now · delta
#               [██████████░░░░░░░░░]                ← EventResultBar, before → after
#               신뢰도 Lv.3          64%    +16%
#               [██████░░░░░░░░░░░░░]
#               (공격 명중 +1) (능력치 EXP +40)       ← chips: compact stat gains
#               ( 외출 2회째 · … )                    ← lines: other notes (MessengerNoteChip)
#
# Rows: stress (bar = `STRESS_THRESHOLD`, overflow up to `STRESS_MAX` drawn red), trust (level +
# progress in the level) and 깨달음 레벨 EXP (EXP in the level / the bar, over level-ups; locked =
# "한계돌파 필요"). Notes without a pilot (team trust, manager mods, coach points) go to a
# last block without portrait. The data comes from `MentalEvents.result_blocks` (merged notes —
# several stress sources of one result are one row with the sum).
#
# **Layout lives in `UI_Comp_EventResultPanel.tscn`**: blocks, rows and chips are duplicates of
# the hidden templates `%BlockTemplate` / `%RowTemplate` / `%ChipTemplate`. Create with
# `EventResultPanel.create()`. Self-contained — any result screen can host it.

const SCENE_PATH: String = "res://features/season/mental/UI_Comp_EventResultPanel.tscn"

@onready var _blocks: VBoxContainer = %Blocks
@onready var _block_tpl: Control = %BlockTemplate
@onready var _row_tpl: Control = %RowTemplate
@onready var _chip_tpl: Control = %ChipTemplate


static func create() -> EventResultPanel:
	return (load(SCENE_PATH) as PackedScene).instantiate() as EventResultPanel


func _ready() -> void:
	_block_tpl.visible = false
	_row_tpl.visible = false
	_chip_tpl.visible = false
	if UiPreview.is_standalone(self):
		_fill_preview()


# ── API ──────────────────────────────────────────────────────────────────────
## Fill from note dicts **right after** their effects were applied (the bars read the values
## now: previous = now − delta). `pid` = the result's pilot (its block comes first, an `outing`
## note joins it). `animate` = the bars run before → after once the panel is in the tree.
func show_result(state: Dictionary, pid: int, notes: Array, animate: bool = true) -> void:
	show_blocks(MentalEvents.result_blocks(state, notes, pid), animate)


## Fill from precomputed blocks (`MentalEvents.result_blocks`, also `outcome_view.result_blocks`).
func show_blocks(blocks: Array, animate: bool = true) -> void:
	clear()
	for b in blocks:
		_add_block(b as Dictionary, animate)


## Text-only notes (an outcome view without blocks, e.g. the limit-break goal) → one
## `MessengerNoteChip` line each, no portrait.
func show_texts(texts: Array) -> void:
	clear()
	if texts.is_empty():
		return
	_add_block({"pid": -2, "name": "", "rows": [], "chips": [], "lines": texts}, false)


func clear() -> void:
	for c in _blocks.get_children():
		_blocks.remove_child(c)
		c.queue_free()


func is_empty() -> bool:
	return _blocks.get_child_count() == 0


# ── Blocks ───────────────────────────────────────────────────────────────────
func _add_block(b: Dictionary, animate: bool) -> void:
	var block: Control = _block_tpl.duplicate() as Control
	block.visible = true
	_blocks.add_child(block)
	var pid: int = int(b.get("pid", -1))
	var portrait: Control = block.get_node("Portrait")
	portrait.visible = pid >= 0
	if pid >= 0:
		OutgameTheme.add_round_portrait(portrait, PilotImages.circle_for(pid), Vector2.ZERO,
				portrait.custom_minimum_size.x)
	var name_lbl: Label = block.get_node("Body/Name")
	name_lbl.text = String(b.get("name", ""))
	name_lbl.visible = not name_lbl.text.is_empty()
	var rows: Control = block.get_node("Body/Rows")
	for r in (b.get("rows", []) as Array):
		rows.add_child(_row(r as Dictionary, animate))
	rows.visible = rows.get_child_count() > 0
	var chips: Control = block.get_node("Body/Chips")
	for t in (b.get("chips", []) as Array):
		var chip: Control = _chip_tpl.duplicate() as Control
		chip.visible = true
		(chip.get_node("Text") as Label).text = String(t)
		chips.add_child(chip)
	chips.visible = chips.get_child_count() > 0
	var lines: Control = block.get_node("Body/Lines")
	for t in (b.get("lines", []) as Array):
		var line := MessengerNoteChip.create()
		line.setup(String(t), true)
		lines.add_child(line)
	lines.visible = lines.get_child_count() > 0


func _row(r: Dictionary, animate: bool) -> Control:
	var row: Control = _row_tpl.duplicate() as Control
	row.visible = true
	(row.get_node("Head/Label") as Label).text = String(r.get("label", ""))
	var value: Label = row.get_node("Head/Value")
	value.text = String(r.get("value", ""))
	value.theme_type_variation = &"NegativeLabel" if bool(r.get("over", false)) else &"BodyLabel"
	var delta: Label = row.get_node("Head/Delta")
	delta.text = String(r.get("delta", ""))
	delta.visible = not delta.text.is_empty()
	# 0 (sources that cancelled out, `±0`) reads grey — neither welcome nor not.
	if bool(r.get("neutral", false)):
		delta.theme_type_variation = &"CaptionLabel"
	else:
		delta.theme_type_variation = &"PositiveLabel" if bool(r.get("good", true)) else &"NegativeLabel"
	var bar: EventResultBar = row.get_node("Bar")
	# The bar needs its size: start it once the row is laid out.
	bar.play.call_deferred(r, animate)
	return row


## F6 단독 실행 미리보기 — 메모리 런의 내 첫 두 선수에게 실제 효과를 넣고(스트레스 두 출처 · 신뢰 ·
## 깨달음 레벨 EXP · 능력치 EXP) 그 노트로 판을 채운다.
func _fill_preview() -> void:
	UiPreview.stage(self)
	var gm: Node = UiPreview.ensure_run()
	if gm == null:
		return
	var s: Dictionary = gm.season_state
	var ids: Array = MentalSystem.my_pilot_ids(s)
	if ids.size() < 2:
		return
	var a: int = int(ids[0])
	var b: int = int(ids[1])
	StressSystem.add(s, a, 80)
	StressSystem.add(s, b, 130)
	var notes: Array = []
	notes.append(MentalEvents.stress_note(s, a, StressSystem.add(s, a, -6)))
	notes.append(MentalEvents.stress_note(s, a, StressSystem.add(s, a, -10)))
	var d: int = MentalSystem.add_trust(s, a, 30)
	notes.append({"type": "trust", "pid": a, "delta": d, "after": MentalSystem.trust(s, a)})
	notes.append(FocusTraining.add_training_exp(s, a, 450, "preview"))
	notes.append_array(FocusTraining.add_stat_exp(s, a, {"field_hit": 260, "engage_hit": 260}))
	notes.append(MentalEvents.stress_note(s, b, StressSystem.add(s, b, 12)))
	notes.append({"type": "trust_all", "delta": 3})
	notes.append({"type": "outing", "count": 2})
	show_result(s, a, notes)
