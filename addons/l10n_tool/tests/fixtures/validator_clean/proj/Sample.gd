extends Node

func _ready() -> void:
	var a := Loc.t(L.UI_CONFIRM)
	var b := Loc.t(L.UI_GREET, {"name": "x"})
	var c := Loc.t(L.UI_DRAW_HINT)
	var d := Loc.t(L.UI_MVP)
	var e := Loc.t(L.KEYWORD_TRACK_NAME)
