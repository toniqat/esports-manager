@tool
extends RefCounted

## 사용처 스캔 → index.json — 설계서 §9 (+ E051 · W052/E052 · W053/E053 · W054 · E055 · W056 · E057).
## STUB — 에이전트 ③ 이 구현한다. 시그니처는 core/l10n.gd 계약대로 유지.


## index.json 본문(§9.4)을 돌려주고, 사용처 규칙 위반은 l.issues 에 담는다.
static func scan(_l) -> Dictionary:
	return {"keys": {}, "orphans": [], "dynamic_bare": []}


static func write_index(_l, _index: Dictionary) -> String:
	return ""
