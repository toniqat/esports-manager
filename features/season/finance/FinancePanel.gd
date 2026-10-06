class_name FinancePanel
extends RefCounted

# 허브 관리 카드 「재무」 — STUB. 계약: 계획서 §11.2 (`hub_summary` / `open`).
# `HubView` 의 관리 카드 줄이 요약을 그리고, 누르면 `open(host)` 이 `HubSheet` 를 띄운다.


## 카드 요약 — `{title, value, sub, owner, alert}`.
## owner = 담당 배지("감독" / 스태프 이름 / ""), alert = 처리할 일이 있으면 true.
static func hub_summary(_state: Dictionary) -> Dictionary:
	return {"title": "재무", "value": "—", "sub": "준비 중", "owner": "", "alert": false}


static func open(host: Node) -> void:
	var sheet := HubSheet.open_on(host, "재무")
	UiHelpers.mk_label(sheet.body, "준비 중", 28, OutgameTheme.TEXT_SUB,
			Vector2(0, 0), Vector2(sheet.body_w(), 40))
	sheet.set_body_height(60)
