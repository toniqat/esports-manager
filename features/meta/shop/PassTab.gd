class_name PassTab
extends Control

# 로비 탭 — 주간패스. 탭 계약은 `features/meta/lobby/LobbyScreen.gd` 머리말,
# 기능 범위는 계획서 §12 (작업 E). **기반 커밋의 자리표시** — 기능 작업이 채운다.

var _host: LobbyScreen


func bar_specs() -> Array:
	return []


func setup(host: LobbyScreen) -> void:
	_host = host
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	UiHelpers.mk_label(self, "주간패스 — 준비 중", 32, OutgameTheme.TEXT_SUB,
			Vector2(0, 200), Vector2(size.x, 48), HORIZONTAL_ALIGNMENT_CENTER)


func on_shown() -> void:
	pass


func on_bar_pressed(_i: int) -> void:
	pass
