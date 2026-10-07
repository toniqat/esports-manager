@tool
extends RefCounted

## 원본 규칙 검증 + report.md — 설계서 §13 (E05x · W05x 사용처 규칙은 scanner 몫).
## STUB — 에이전트 ① 이 구현한다. 시그니처는 core/l10n.gd 계약대로 유지.

const Issues = preload("res://addons/l10n_tool/core/issues.gd")


## l = core/l10n.gd 인스턴스. l.catalog · l.config 를 읽고 l.issues 에 담는다.
static func validate(_l, _mode: String) -> void:
	pass


## l.config.gen_dir/report.md 를 쓴다. 오류 문자열 또는 "".
static func write_report(_l, _mode: String) -> String:
	return ""
