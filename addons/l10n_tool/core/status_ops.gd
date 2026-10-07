@tool
extends RefCounted

## 원본을 고치는 명령 — sync · approve · add_locale · rename_alias (설계서 §7.1 · §8).
## STUB — 에이전트 ② 가 구현한다. 시그니처는 core/l10n.gd 계약대로 유지.


## 돌려주는 값: 갱신한 번역 수.
static func sync(_l) -> int:
	return 0


static func approve(_l, _locale: String, _keys_or_aliases: PackedStringArray) -> String:
	return "미구현"


static func add_locale(_l, _locale: String) -> String:
	return "미구현"


static func rename_alias(_l, _old_alias: String, _new_alias: String) -> String:
	return "미구현"
