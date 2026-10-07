class_name HubManageCard
extends Panel

# One small card of `HubView`'s manage row (staff · mech research · finance).
#
# **Layout lives in `UI_Comp_HubManageCard.tscn`** (176 tall, width from the row's HBox; `Card` variation,
# title / value / sub / owner labels, red alert dot top-right, a flat `%Hit` button over the whole
# card). The content belongs to each feature's panel — `<Panel>.hub_summary(state)` →
# `{title, value, sub, owner, alert}` — and this script only puts it in.

signal pressed

const SCENE_PATH: String = "res://features/season/UI_Comp_HubManageCard.tscn"


static func create() -> HubManageCard:
	return (load(SCENE_PATH) as PackedScene).instantiate() as HubManageCard


func _ready() -> void:
	%Hit.pressed.connect(pressed.emit)
	if UiPreview.is_standalone(self):
		_fill_preview()


## `sm` = `<Panel>.hub_summary(state)`.
func show_summary(sm: Dictionary) -> void:
	%Title.text = String(sm.get("title", ""))
	%Value.text = String(sm.get("value", ""))
	%Sub.text = String(sm.get("sub", ""))
	var who: String = String(sm.get("owner", ""))
	%Owner.text = Loc.t(L.SEASON_HUB_CARD_OWNER, {"name": who}) if who != "" else ""
	%Alert.visible = bool(sm.get("alert", false))


## F6 단독 실행 미리보기 — 경고 점이 켜진 재무 카드 (`resources/UiPreview.gd`).
func _fill_preview() -> void:  # l10n-ignore
	UiPreview.stage(self)
	UiPreview.trace(pressed)
	# 행 HBox 가 주는 폭이 없어 단독으로는 카드 폭을 직접 준다.
	custom_minimum_size.x = 320.0
	show_summary({
		"title": "재무",
		"value": "1,240 G",
		"sub": "이번 주 수지 -85",
		"owner": "한서윤",
		"alert": true,
	})
