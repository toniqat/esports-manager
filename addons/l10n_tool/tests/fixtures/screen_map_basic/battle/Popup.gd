class_name Popup
extends Control

static func create() -> Popup:
	return preload("res://battle/UI_View_Popup.tscn").instantiate()

const SIZE := 3
