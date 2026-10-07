@tool
extends RefCounted

## Glossary term matcher for one locale (§4.5 · §13). A `match_<loc>` regex in glossary.csv
## replaces the default rule — substring of the standard form, case-insensitive — for that
## locale, so word-internal hits (`어시스턴트` ⊃ `턴`, `손가락` ⊃ `손`) can be excluded.
## Shared by validator (W071/W072 presence), scanner (index.json `glossary`) and the dock.

## Matcher = {word, re (RegEx or null), error}. `error` != "" = the pattern did not compile;
## the matcher then falls back to the substring rule so the caller can still report E074.
static func make(word: String, pattern: String) -> Dictionary:
	var m: Dictionary = {"word": word, "re": null, "error": ""}
	if pattern.strip_edges() == "":
		return m
	var re := RegEx.new()
	var src: String = pattern if pattern.begins_with("(?i)") else "(?i)" + pattern
	if re.compile(src, false) != OK or not re.is_valid():
		m["error"] = "정규식 컴파일 실패: %s" % pattern
		return m
	m["re"] = re
	return m


## Matcher for glossary row `g` in `loc` with standard form `word`.
static func for_row(g: Dictionary, loc: String, word: String) -> Dictionary:
	return make(word, String(g.get("match_" + loc, "")))


static func found(m: Dictionary, text: String) -> bool:
	if text.is_empty():
		return false
	var re: RegEx = m.get("re") as RegEx
	if re != null:
		return re.search(text) != null
	var word: String = String(m.get("word", ""))
	return word != "" and text.findn(word) >= 0
