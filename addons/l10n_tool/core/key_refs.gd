@tool
extends RefCounted

## 문장 안 key 참조 `{tx_XXXXXXXXXX}` (설계서 §5): 다른 key 의 같은 로케일 텍스트를
## build 가 그 자리에 펼쳐 넣는다. 런타임(`Loc.t`)은 펼친 문장만 본다.
##
## - 언어마다 선택 사항이다. ko 는 `{tx_적}{tx_또는}{tx_아군}` 처럼 조합하고, 관사 · 성 · 대소문자가
##   맞지 않는 언어는 참조 없이 문장을 직접 쓴다. 그래서 원문과 번역의 참조 짝은 검사하지 않는다.
## - 참조 대상은 active key 여야 한다(E037 없는 key · E038 deprecated). 순환은 E039.
## - 값 자리표시자 · 조사 태그는 펼친 뒤의 문장으로 판정한다(validator E033).
## - 펼치는 텍스트: dev = 그 로케일 번역(없으면 원문), release = approved · 비-stale 번역만
##   (하나라도 없으면 그 행 전체를 빼서 Godot 폴백에 맡긴다. 한 문장에 두 언어가 섞이지 않게).

const Catalog = preload("res://addons/l10n_tool/core/catalog.gd")
const Issues = preload("res://addons/l10n_tool/core/issues.gd")

const MODE_RELEASE := "release"
## 펼치기 깊이 상한. 순환은 따로 잡지만 비정상 데이터에서 멈추게.
const MAX_DEPTH := 8

static var _re: RegEx = null


## 텍스트 안 참조 key: 등장 순서, 중복 포함.
static func keys_in(text: String) -> PackedStringArray:
	var out := PackedStringArray()
	if text.find("{") < 0:
		return out
	for m in _regex().search_all(text):
		out.append(m.get_string(1))
	return out


static func has_refs(text: String) -> bool:
	return text.find("{") >= 0 and _regex().search(text) != null


## 그 로케일에서 key 가 내보낼 원래 텍스트 (펼치기 전). dev 는 번역 없으면 원문,
## release 는 approved · 비-stale 번역만(없으면 ""). 원문 로케일은 원문.
static func raw_text(cat: Catalog, key: String, loc: String, mode: String) -> String:
	var e: Dictionary = cat.entry(key)
	if e.is_empty():
		return ""
	if loc == cat.config.source_locale:
		return String(e["source"])
	var t: Dictionary = (e["tr"] as Dictionary).get(loc, {})
	var tr_text: String = String(t.get("text", ""))
	if mode != MODE_RELEASE:
		return tr_text if not tr_text.is_empty() else String(e["source"])
	if String(t.get("status", "")) == Catalog.TR_APPROVED and not cat.is_stale(key, loc):
		return tr_text
	return ""


## text 안의 참조를 그 로케일 텍스트로 펼친다. 펼칠 수 없는 참조(없는 key · 순환 ·
## release 에서 승인 번역 없음)가 있으면 "" 를 돌려준다.
static func expand(cat: Catalog, text: String, loc: String, mode: String, _stack: Array = []) -> String:
	if not has_refs(text):
		return text
	if _stack.size() >= MAX_DEPTH:
		return ""
	var out: String = ""
	var pos: int = 0
	for m in _regex().search_all(text):
		var k: String = m.get_string(1)
		if _stack.has(k):
			return ""
		var e: Dictionary = cat.entry(k)
		if e.is_empty():
			return ""
		var inner: String = raw_text(cat, k, loc, mode)
		if inner.is_empty():
			return ""
		var st: Array = _stack.duplicate()
		st.append(k)
		inner = expand(cat, inner, loc, mode, st)
		if inner.is_empty():
			return ""
		out += text.substr(pos, m.get_start() - pos) + inner
		pos = m.get_end()
	return out + text.substr(pos)


## E037 · E038 · E039: 원문과 모든 번역문의 참조를 검사한다. 이름 key 도 참조를 쓸 수 있다
## (어느 key 가 이름인지 도구는 모른다. 이름에 태그를 넣지 않는 것은 LLM 작업 규칙, 설계서 §5).
static func check(cat: Catalog, iss: Issues) -> void:
	for e in cat.all_entries:
		var key: String = String(e["key"])
		var texts: Array = [[cat.config.source_locale, String(e["source"])]]
		for loc in cat.config.target_locales():
			texts.append([loc, String((e["tr"] as Dictionary).get(loc, {}).get("text", ""))])
		for pair in texts:
			for k in keys_in(String(pair[1])):
				var target: Dictionary = cat.entry(k)
				if target.is_empty():
					iss.error("E037", "%s 텍스트의 참조 {%s} 가 없는 key" % [pair[0], k], String(e["file"]), int(e["line"]), key)
				elif target["status"] != Catalog.STATUS_ACTIVE and e["status"] == Catalog.STATUS_ACTIVE:
					iss.error("E038", "%s 텍스트의 참조 {%s} (%s) 가 deprecated" % [pair[0], k, target["alias"]], String(e["file"]), int(e["line"]), key)
		if _in_cycle(cat, key, [key]):
			iss.error("E039", "참조 순환 (%s)" % e["alias"], String(e["file"]), int(e["line"]), key)


# key 에서 출발한 참조(모든 로케일 텍스트)가 출발점으로 돌아오는가.
static func _in_cycle(cat: Catalog, key: String, path: Array) -> bool:
	if path.size() > MAX_DEPTH:
		return true
	var e: Dictionary = cat.entry(key)
	if e.is_empty():
		return false
	var nexts: Dictionary = {}
	for k in keys_in(String(e["source"])):
		nexts[k] = true
	for loc in cat.config.target_locales():
		for k in keys_in(String((e["tr"] as Dictionary).get(loc, {}).get("text", ""))):
			nexts[k] = true
	for k in nexts.keys():
		if k == path[0]:
			return true
		if path.has(k):
			continue
		var p2: Array = path.duplicate()
		p2.append(k)
		if _in_cycle(cat, k, p2):
			return true
	return false


static func _regex() -> RegEx:
	if _re == null:
		_re = RegEx.create_from_string("\\{(tx_[0-9A-HJKMNP-TV-Z]{10})\\}")
	return _re
