@tool
extends RefCounted

## key 발급 — 설계서 §3.1. `<prefix>` + Crockford Base32 대문자 10자(50비트).
## 혼동되는 I · L · O · U 는 쓰지 않는다. 발급된 key 는 삭제 · 재사용하지 않는다.

const ALPHABET := "0123456789ABCDEFGHJKMNPQRSTVWXYZ"
const BODY_LEN := 10

static var _crypto: Crypto = null
static var _re: RegEx = null
static var _re_prefix: String = ""


## existing 에 없는 새 key. existing 은 key → 무엇이든(deprecated 포함 모든 원본의 key).
## 100번 연속 충돌하면(사실상 불가능) "" 를 돌려준다.
static func generate(prefix: String, existing: Dictionary) -> String:
	if _crypto == null:
		_crypto = Crypto.new()
	for _attempt in 100:
		var b: PackedByteArray = _crypto.generate_random_bytes(7)
		var v: int = 0
		for i in 7:
			v = (v << 8) | int(b[i])
		var s: String = prefix
		for i in BODY_LEN:
			s += ALPHABET[(v >> (i * 5)) & 31]
		if not existing.has(s):
			return s
	return ""


## `^<prefix>[0-9A-HJKMNP-TV-Z]{10}$`
static func is_valid(key: String, prefix: String) -> bool:
	if _re == null or _re_prefix != prefix:
		_re = RegEx.create_from_string("^" + _escape(prefix) + "[0-9A-HJKMNP-TV-Z]{10}$")
		_re_prefix = prefix
	return _re.search(key) != null


## 텍스트 안의 key 패턴(스캔용, §9.2 literal). 접두사 뒤 10자.
static func pattern(prefix: String) -> String:
	return _escape(prefix) + "[0-9A-HJKMNP-TV-Z]{10}"


static func _escape(s: String) -> String:
	var out: String = ""
	for ch in s:
		if "\\^$.|?*+()[]{}".contains(ch):
			out += "\\"
		out += ch
	return out
