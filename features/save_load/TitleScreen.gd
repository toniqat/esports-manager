extends Control

# Project entry point. Lists the 3 save slots; player chooses one to start a
# new campaign or continue an existing one. Sets GameManager.active_save_slot
# (so phase-boundary auto-saves know where to write) and changes scene to
# Season.tscn.

const SLOT_COUNT: int = SaveSystem.SLOT_COUNT

@onready var _gm: Node = get_node("/root/GameManager")

var _slot_cards: Array = []  # Array[SlotCard]
var _toast_lbl: Label
var _built: bool = false


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	if not _built:
		_build()
		_built = true
	_refresh_all()


# ── Build ────────────────────────────────────────────────────────────────────
func _build() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.05, 0.10, 1.0)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	UiHelpers.mk_label(self, "ESPORTS MANAGER", 56, Color(1.0, 0.85, 0.20),
			Vector2(0, 140), Vector2(1080, 80), HORIZONTAL_ALIGNMENT_CENTER)
	UiHelpers.mk_label(self, "세이브 슬롯을 선택하세요", 26, Color(0.85, 0.88, 0.95),
			Vector2(0, 230), Vector2(1080, 36), HORIZONTAL_ALIGNMENT_CENTER)

	var card_w: float = 880.0
	var card_h: float = 380.0
	var top: float = 320.0
	var gap: float = 40.0
	var start_x: float = (1080.0 - card_w) / 2.0

	for i in SLOT_COUNT:
		var card := SlotCard.new()
		card.position = Vector2(start_x, top + float(i) * (card_h + gap))
		card.size = Vector2(card_w, card_h)
		card.slot_index = i
		card.on_new_game = _on_new_game
		card.on_continue = _on_continue
		card.on_delete = _on_delete
		add_child(card)
		_slot_cards.append(card)

	_toast_lbl = UiHelpers.mk_label(self, "", 22, Color(1.0, 0.85, 0.40),
			Vector2(0, 1820), Vector2(1080, 30), HORIZONTAL_ALIGNMENT_CENTER)


# ── Refresh ──────────────────────────────────────────────────────────────────
func _refresh_all() -> void:
	var metas: Array = SaveSystem.list_slots()
	for i in SLOT_COUNT:
		_slot_cards[i].set_meta_data(metas[i])


# ── Slot callbacks ───────────────────────────────────────────────────────────
func _on_new_game(idx: int) -> void:
	_gm.reset_season_state()
	_gm.active_save_slot = idx
	get_tree().change_scene_to_file("res://scenes/Season.tscn")


func _on_continue(idx: int) -> void:
	var err: String = SaveSystem.load_slot(idx)
	if err != "":
		_toast_lbl.text = "불러오기 실패: " + err
		return
	_gm.active_save_slot = idx
	# Mid-match save: jump straight back into MatchFlow (which reads
	# season_state.match_resume on _ready and skips ahead to the saved
	# phase). Otherwise drop into the campaign hub.
	if _gm.season_state.get("match_resume", null) != null:
		get_tree().change_scene_to_file("res://scenes/MatchFlow.tscn")
	else:
		get_tree().change_scene_to_file("res://scenes/Season.tscn")


func _on_delete(idx: int) -> void:
	var err: String = SaveSystem.delete_slot(idx)
	if err != "":
		_toast_lbl.text = err
		return
	_toast_lbl.text = "슬롯 %d 삭제됨" % (idx + 1)
	_refresh_all()
