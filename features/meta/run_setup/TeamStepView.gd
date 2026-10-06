class_name TeamStepView
extends ChoiceListView

# 런 준비 2단계 — **팀 패키지**(`RunRules.team_packages()`, `teams.csv`) 8장.
# 카드 = 팀명 · 약칭 · 예산(막대) · 시설 레벨 · "직접 해야 하는 일" · 설명.
#
# **예산이 높을수록 쉽다** — 안내 줄과 예산 막대가 그 말을 한다. 막대 길이는
# 표의 최고 예산 대비 비율이라 난이도 문턱 같은 숫자를 코드에 두지 않는다.
# M1 은 표시 · 스냅샷만 한다 — 예산 · 시설 · 직접 영역의 효과는 M3 / M6.

const CARD_H: float = 300.0
const BUDGET_BAR_H: float = 12.0

var _max_budget: int = 1


func _items() -> Array:
	var items: Array = RunRules.team_packages()
	_max_budget = 1
	for raw in items:
		_max_budget = maxi(_max_budget, int((raw as Dictionary).get("budget", 0)))
	return items


func _hint_text() -> String:
	return "예산이 높을수록 쉽습니다 — 스태프가 많아 직접 해야 하는 일이 적습니다."


func _card_h(_item: Dictionary) -> float:
	return CARD_H


func _fill_card(card: Control, item: Dictionary, w: float) -> void:
	var x: float = CARD_PAD
	var y: float = CARD_PAD - 6.0
	add_text(card, String(item.get("name", "?")), 36, OutgameTheme.TEXT,
			Vector2(x, y), Vector2(w - 140.0, 50))
	add_text(card, String(item.get("short_name", "")), 26, OutgameTheme.TEXT_FAINT,
			Vector2(x + w - 140.0, y + 8.0), Vector2(140.0, 36), HORIZONTAL_ALIGNMENT_RIGHT)
	y += 60.0

	# 예산 — 글자 + 최고 예산 대비 막대.
	var budget: int = int(item.get("budget", 0))
	add_text(card, "예산 %d" % budget, 26, OutgameTheme.ACCENT_TEXT,
			Vector2(x, y), Vector2(220.0, 36))
	add_text(card, "시설 Lv %d" % int(item.get("facility_level", 0)), 26,
			OutgameTheme.TEXT, Vector2(x + w - 200.0, y), Vector2(200.0, 36),
			HORIZONTAL_ALIGNMENT_RIGHT)
	var bar_x: float = x + 230.0
	var bar_w: float = w - 230.0 - 220.0
	var track := ColorRect.new()
	track.color = OutgameTheme.SURFACE_SUNK
	track.position = Vector2(bar_x, y + 12.0)
	track.size = Vector2(bar_w, BUDGET_BAR_H)
	track.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(track)
	var fill := ColorRect.new()
	fill.color = OutgameTheme.ACCENT
	fill.size = Vector2(bar_w * clampf(float(budget) / float(_max_budget), 0.0, 1.0),
			BUDGET_BAR_H)
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	track.add_child(fill)
	y += 48.0

	# 직접 해야 하는 일 — 비어 있으면 "없음".
	var labels: Array = []
	for area in item.get("manual_areas", []):
		labels.append(RunRules.area_label(String(area)))
	var manual: String = "없음" if labels.is_empty() else " · ".join(PackedStringArray(labels))
	add_text(card, "직접 해야 하는 일", 22, OutgameTheme.TEXT_SUB,
			Vector2(x, y), Vector2(w, 30))
	y += 32.0
	add_text(card, manual, 26,
			OutgameTheme.POSITIVE if labels.is_empty() else OutgameTheme.TEXT,
			Vector2(x, y), Vector2(w, 36))
	y += 46.0

	add_para(card, String(item.get("desc", "")), 22, OutgameTheme.TEXT_SUB,
			Vector2(x, y), Vector2(w, CARD_H - y - CARD_PAD * 0.5))
