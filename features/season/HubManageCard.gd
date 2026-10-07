class_name HubManageCard
extends Panel

# One small card of `HubView`'s manage row (staff · mech research · finance).
#
# **Layout lives in `HubManageCard.tscn`** (176 tall, width from the row's HBox; `Card` variation,
# title / value / sub / owner labels, red alert dot top-right, a flat `%Hit` button over the whole
# card). The content belongs to each feature's panel — `<Panel>.hub_summary(state)` →
# `{title, value, sub, owner, alert}` — and this script only puts it in.

signal pressed

const SCENE_PATH: String = "res://features/season/HubManageCard.tscn"


static func create() -> HubManageCard:
	return (load(SCENE_PATH) as PackedScene).instantiate() as HubManageCard


func _ready() -> void:
	%Hit.pressed.connect(pressed.emit)


## `sm` = `<Panel>.hub_summary(state)`.
func show_summary(sm: Dictionary) -> void:
	%Title.text = String(sm.get("title", ""))
	%Value.text = String(sm.get("value", ""))
	%Sub.text = String(sm.get("sub", ""))
	var who: String = String(sm.get("owner", ""))
	%Owner.text = ("담당: " + who) if who != "" else ""
	%Alert.visible = bool(sm.get("alert", false))
