extends Node

# Pre-battle gambit (replaces the old lane-assignment UI):
# user picks which side of the jungle their assassin starts on.

signal phase_finished(result: Dictionary)

@onready var _mf: MatchFlow = get_parent() as MatchFlow

var _selected_dir: int = -1   # GameEnums.JungleStartDir or -1

var _panel: Panel
var _btn_left: Button
var _btn_right: Button
var _btn_launch: Button
var _lbl_status: Label


func enter() -> void:
	_selected_dir = GameEnums.JungleStartDir.LEFT  # default
	_build_ui()
	_refresh_ui()


func _build_ui() -> void:
	_panel = Panel.new()
	_panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.04, 0.06, 0.12, 1.0)
	_panel.add_theme_stylebox_override("panel", bg)
	_mf.canvas.add_child(_panel)

	_mk_label(_panel, "JUNGLE START", 56, Color(1.0, 0.85, 0.2),
			Vector2(0.0, 80.0), Vector2(1080.0, 80.0), HORIZONTAL_ALIGNMENT_CENTER)
	_mk_label(_panel, "Where does your Assassin start the jungle route?", 26, Color(0.7, 0.7, 0.7),
			Vector2(0.0, 180.0), Vector2(1080.0, 40.0), HORIZONTAL_ALIGNMENT_CENTER)

	_btn_left = Button.new()
	_btn_left.text = "← LEFT\n\nStart on the\nleft side"
	_btn_left.add_theme_font_size_override("font_size", 36)
	_btn_left.position = Vector2(60.0, 380.0)
	_btn_left.size     = Vector2(460.0, 700.0)
	_btn_left.pressed.connect(_on_dir_pressed.bind(GameEnums.JungleStartDir.LEFT))
	_panel.add_child(_btn_left)

	_btn_right = Button.new()
	_btn_right.text = "RIGHT →\n\nStart on the\nright side"
	_btn_right.add_theme_font_size_override("font_size", 36)
	_btn_right.position = Vector2(560.0, 380.0)
	_btn_right.size     = Vector2(460.0, 700.0)
	_btn_right.pressed.connect(_on_dir_pressed.bind(GameEnums.JungleStartDir.RIGHT))
	_panel.add_child(_btn_right)

	_lbl_status = _mk_label(_panel, "", 26, Color(0.85, 0.95, 0.85),
			Vector2(0.0, 1180.0), Vector2(1080.0, 50.0), HORIZONTAL_ALIGNMENT_CENTER)

	_btn_launch = Button.new()
	_btn_launch.text     = "Launch Battle"
	_btn_launch.position = Vector2(290.0, 1280.0)
	_btn_launch.size     = Vector2(500.0, 130.0)
	_btn_launch.add_theme_font_size_override("font_size", 40)
	_btn_launch.pressed.connect(_on_launch_pressed)
	_panel.add_child(_btn_launch)


func _refresh_ui() -> void:
	_btn_left.modulate  = Color(1.0, 1.0, 0.4) if _selected_dir == GameEnums.JungleStartDir.LEFT  else Color(0.7, 0.7, 0.7)
	_btn_right.modulate = Color(1.0, 1.0, 0.4) if _selected_dir == GameEnums.JungleStartDir.RIGHT else Color(0.7, 0.7, 0.7)
	var dir_name := "LEFT" if _selected_dir == GameEnums.JungleStartDir.LEFT else "RIGHT"
	_lbl_status.text = "Selected: %s" % dir_name
	_btn_launch.disabled = (_selected_dir == -1)


func _on_dir_pressed(dir: int) -> void:
	_selected_dir = dir
	_refresh_ui()


func _on_launch_pressed() -> void:
	if _selected_dir == -1: return
	_panel.queue_free()
	_panel = null
	phase_finished.emit({"dir": _selected_dir})


func _mk_label(parent: Control, text: String, font_size: int, color: Color,
		pos: Vector2, sz: Vector2, align: int = HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.position = pos
	l.size     = sz
	l.horizontal_alignment = align as HorizontalAlignment
	parent.add_child(l)
	return l
