@tool
extends RefCounted

## 텍스트 토큰 문법 — 설계서 §5.
##   값 자리표시자 `{name}` (조사 태그 이름 제외) · 조사 태그 `{eul}` …
##   참조 `[이름]` (괄호 안이 BBCode 태그가 아닌 것) · BBCode `[b]…[/b]`
## 줄바꿈은 리터럴 `\n` 두 글자.

static var _re_brace: RegEx = null
static var _re_bracket: RegEx = null


## 값 자리표시자 이름 — 등장 순서, 중복 제거. 복수 태그 `{plural:name|…}` 의 name 은 넣지 않는다
## (ko 에는 복수 태그가 없고, name 이 카드 전투 값 · 식 · const 이름일 수 있어서).
static func placeholders(text: String, josa_tags: Array) -> PackedStringArray:
	var out := PackedStringArray()
	for m in _brace().search_all(text):
		var nm: String = m.get_string(1)
		if josa_tags.has(nm) or out.has(nm):
			continue
		out.append(nm)
	return out


## 복수 태그 `{plural:name|형태|형태…}` — [{name, forms: PackedStringArray}] 등장 순서.
## 형태 안에 key 참조 `{tx_…}` 가 있어도 된다(한 겹까지). 이름은 식일 수 있다(카드 설명의
## 전투 값 `charge+{attack_base}` · `max(1, chain)`, `CardDescBox` 가 고른다).
static func plurals(text: String) -> Array:
	var out: Array = []
	if text.find("{plural:") < 0:
		return out
	if _re_plural == null:
		_re_plural = RegEx.create_from_string("\\{plural:((?:[^{}|]|\\{[a-z][a-z0-9_]*\\})+)((?:\\|(?:[^{}|]|\\{[^{}]*\\})*)+)\\}")
	for m in _re_plural.search_all(text):
		out.append({"name": m.get_string(1), "forms": m.get_string(2).substr(1).split("|")})
	return out


static var _re_plural: RegEx = null


## 값 자리표시자 집합 비교용 — 정렬된 목록.
static func placeholder_set(text: String, josa_tags: Array) -> PackedStringArray:
	var arr: Array = Array(placeholders(text, josa_tags))
	arr.sort()
	return PackedStringArray(arr)


## 조사 태그 — 등장할 때마다 하나씩(중복 포함).
static func josa(text: String, josa_tags: Array) -> PackedStringArray:
	var out := PackedStringArray()
	for m in _brace().search_all(text):
		if josa_tags.has(m.get_string(1)):
			out.append(m.get_string(1))
	return out


## 참조 `[이름]` 의 이름 — 등장 순서(중복 포함). BBCode 태그(`[b]` · `[/b]` ·
## `[color=red]` · `[img]`)는 뺀다.
static func refs(text: String, bbcode_tags: Array) -> PackedStringArray:
	var out := PackedStringArray()
	for m in _bracket().search_all(text):
		var inner: String = m.get_string(1)
		if is_bbcode(inner, bbcode_tags):
			continue
		out.append(inner.strip_edges())
	return out


## BBCode 태그 — `[b]` 는 "b", `[/b]` 는 "/b", `[color=x]` 는 "color".
static func bbcode(text: String, bbcode_tags: Array) -> PackedStringArray:
	var out := PackedStringArray()
	for m in _bracket().search_all(text):
		var inner: String = m.get_string(1)
		if is_bbcode(inner, bbcode_tags):
			out.append(_bb_name(inner))
	return out


static func is_bbcode(inner: String, bbcode_tags: Array) -> bool:
	var nm: String = _bb_name(inner)
	if nm.begins_with("/"):
		nm = nm.substr(1)
	return bbcode_tags.has(nm)


## 분해된 한글 자모(U+1100–U+11FF) 포함 여부 — W003.
static func has_decomposed_jamo(text: String) -> bool:
	for i in text.length():
		var c: int = text.unicode_at(i)
		if c >= 0x1100 and c <= 0x11FF:
			return true
	return false


## 한글 음절 포함 여부(고아 텍스트 판정 등).
static func has_hangul(text: String) -> bool:
	for i in text.length():
		var c: int = text.unicode_at(i)
		if (c >= 0xAC00 and c <= 0xD7A3) or (c >= 0x3131 and c <= 0x318E):
			return true
	return false


static func _bb_name(inner: String) -> String:
	var s: String = inner.strip_edges()
	var cut: int = s.length()
	for sep in ["=", " "]:
		var p: int = s.find(sep)
		if p >= 0 and p < cut:
			cut = p
	return s.substr(0, cut)


static func _brace() -> RegEx:
	if _re_brace == null:
		_re_brace = RegEx.create_from_string("\\{([a-z][a-z0-9_]*)\\}")
	return _re_brace


static func _bracket() -> RegEx:
	if _re_bracket == null:
		_re_bracket = RegEx.create_from_string("\\[([^\\[\\]]+)\\]")
	return _re_bracket
