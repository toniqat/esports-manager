@tool
extends RefCounted

## 검증 · 스캔 결과 모음 — 설계서 §13. 항목 하나 =
## `{code, level("error"|"warn"), msg, file, line, key}`.

const ERROR := "error"
const WARN := "warn"

var items: Array = []


func add(code: String, level: String, msg: String, file: String = "", line: int = 0, key: String = "") -> void:
	items.append({"code": code, "level": level, "msg": msg, "file": file, "line": line, "key": key})


func error(code: String, msg: String, file: String = "", line: int = 0, key: String = "") -> void:
	add(code, ERROR, msg, file, line, key)


func warn(code: String, msg: String, file: String = "", line: int = 0, key: String = "") -> void:
	add(code, WARN, msg, file, line, key)


func error_count() -> int:
	var n: int = 0
	for it in items:
		if it["level"] == ERROR:
			n += 1
	return n


func warn_count() -> int:
	return items.size() - error_count()


func has_code(code: String) -> bool:
	for it in items:
		if it["code"] == code:
			return true
	return false


func count_code(code: String) -> int:
	var n: int = 0
	for it in items:
		if it["code"] == code:
			n += 1
	return n


func merge(other) -> void:
	items.append_array(other.items)


func clear() -> void:
	items.clear()


## 한 줄 요약 — 콘솔 출력용.
static func format_item(it: Dictionary) -> String:
	var where: String = String(it["file"])
	if int(it["line"]) > 0:
		where += ":%d" % int(it["line"])
	var key_part: String = (" [%s]" % it["key"]) if String(it["key"]) != "" else ""
	return "%s %s%s — %s" % [String(it["code"]), where, key_part, String(it["msg"])]
