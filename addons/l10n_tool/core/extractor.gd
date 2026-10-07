@tool
extends RefCounted

## `extract data` — 데이터 CSV 텍스트 컬럼 → l10n key (설계서 §14 1순위, §6).
## STUB — 에이전트 ⑥ 이 구현한다. 시그니처는 core/l10n.gd 계약대로 유지.


## csv_names 가 비면 config.data_columns 전체. 오류 문자열 또는 "".
static func extract_data(_l, _csv_names: PackedStringArray) -> String:
	return "미구현"
