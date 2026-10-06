class_name ScenarioStepView
extends ChoiceListView

# 런 준비 1단계 — **시나리오**(`RunRules.scenarios()`, `scenarios.csv`).
# 카드 = 이름 · 샐러리캡 · 설명. 샐러리캡은 편성 단계의 게이지가 그대로 읽는다.

const CARD_H: float = 220.0


func _items() -> Array:
	return RunRules.scenarios()


func _hint_text() -> String:
	return "시나리오가 샐러리캡을 정합니다 — 다섯 선수의 샐러리 합이 캡을 넘으면 시작할 수 없습니다."


func _card_h(_item: Dictionary) -> float:
	return CARD_H


func _fill_card(card: Control, item: Dictionary, w: float) -> void:
	var x: float = CARD_PAD
	add_text(card, String(item.get("name", "?")), 38, OutgameTheme.TEXT,
			Vector2(x, CARD_PAD - 6.0), Vector2(w * 0.6, 52))
	var chip_w: float = 260.0
	OutgameTheme.add_chip(card, "샐러리캡 %d" % int(item.get("salary_cap", 0)),
			Vector2(x + w - chip_w, CARD_PAD), Vector2(chip_w, 44),
			OutgameTheme.ACCENT_DIM, OutgameTheme.ACCENT_TEXT, 24)
	add_para(card, String(item.get("desc", "")), 26, OutgameTheme.TEXT_SUB,
			Vector2(x, CARD_PAD + 66.0), Vector2(w, CARD_H - CARD_PAD * 2.0 - 66.0))
