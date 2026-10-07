extends Node


func _ready() -> void:
	var a := Loc.t(L.UI_CONFIRM)
	var b := Loc.t(L.UI_CONFIRM_EXTRA)
	var c := XL.UI_CONFIRM
	print(a, b, c, L.UI_CONFIRM)
