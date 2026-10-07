class_name BattleScreen
extends Node

const CARD := preload("res://scenes/Card.tscn")

func open() -> void:
	var v := Viewer.new()
	add_child(v)
	add_child(Popup.create())
