class_name Loc
extends RefCounted

## 런타임 현지화 헬퍼 — 설계서 §10.2 · §10.3 · D4 · D11. static 만.
## 모든 코드 텍스트는 `Loc.t(L.X)` / `Loc.t(row.xxx_key)` 로 이 경로를 거친다.
## key 상수 클래스 `L` 은 l10n build 가 만든다(`data/l10n/generated/L.gd`).

const REFS_PATH := "res://data/l10n/generated/refs.json"

static var _refs: Dictionary = {}
static var _refs_loaded: bool = false


## key → 현재 로케일 텍스트. 순서: 번역 조회 → 복수 태그(`resolve_plurals`) → `{name}` 자리표시자 치환(params 에 있는
## 이름만) → 남은 이름 중 튜닝 상수는 const.csv 값(`fill_consts`) → 리터럴 `\n` 개행 · 조사 처리. 조사는 이름을
## 채운 **뒤에** 처리해야 받침을 본다. 현재 · 폴백 로케일 모두에 없으면 key 그대로.
## `keep_unknown_plurals`: 값을 모르는 복수 태그를 남긴다 (카드 설명: 전투 값으로 `CardDescBox` 가 고른다).
static func t(key: String, params: Dictionary = {}, keep_unknown_plurals: bool = false) -> String:
	var s: String = String(TranslationServer.translate(key))
	if s.find("{") < 0:
		return StrategyIcon.resolve_josa(s)
	# 복수 태그는 params 치환 전에 고른다(태그 안 이름이 값으로 바뀌기 전에).
	s = resolve_plurals(s, params, keep_unknown_plurals)
	if not params.is_empty():
		s = s.format(params)
	if s.find("{") >= 0:
		s = fill_consts(s)
	return StrategyIcon.resolve_josa(s)


## 복수 태그 `{plural:name|단수|복수}` (설계서 §5). `name` 의 값(params, 없으면 const.csv
## 자리표시자 규칙 `fill_consts` 와 같은 이름)으로 형태를 고른다. 형태 순서는
## `plural_index` 의 규칙표를 따른다(지금은 one · other 두 형태). 값을 모르면 마지막 형태,
## `keep_unknown` 이면 태그를 그대로 둔다. 이름이 식(`charge+1`)인 태그는 여기서 고르지 않는다.
## 형태 안의 낱말은 보통 공유 key 참조(`{tx_…}`)로 적고 build 가 펼친다.
static func resolve_plurals(s: String, params: Dictionary = {}, keep_unknown: bool = false) -> String:
	if s.find("{plural:") < 0:
		return s
	if _re_plural == null:
		_re_plural = RegEx.create_from_string("\\{plural:([a-z][a-z0-9_]*)((?:\\|[^{}|]*)+)\\}")
	var out: String = ""
	var last: int = 0
	var loc: String = TranslationServer.get_locale()
	for m in _re_plural.search_all(s):
		var forms: PackedStringArray = m.get_string(2).substr(1).split("|")
		var nm: String = m.get_string(1)
		var raw: String = str(params[nm]) if params.has(nm) else _const_text(nm)
		if not raw.is_valid_float() and keep_unknown:
			continue
		out += s.substr(last, m.get_start() - last) + pick_plural(forms, raw.to_float() if raw.is_valid_float() else NAN, loc)
		last = m.get_end()
	return out + s.substr(last)


## 값 n 에 맞는 형태 (NAN = 모름 → 마지막 형태).
static func pick_plural(forms: PackedStringArray, n: float, loc: String = "") -> String:
	if forms.is_empty():
		return ""
	if is_nan(n):
		return forms[forms.size() - 1]
	return forms[mini(plural_index(loc if loc != "" else TranslationServer.get_locale(), n), forms.size() - 1)]


## 로케일별 복수 형태 번호: 0 = one, 1 = other. 3형태 이상 언어(ru · pl …)를 더할 때
## 여기에 규칙을 넣고 태그에 형태를 늘린다.
static func plural_index(locale: String, n: float) -> int:
	var lang: String = locale.get_slice("_", 0)
	if lang in ["fr", "pt"]:
		return 0 if absf(n) < 2.0 else 1
	return 0 if is_equal_approx(absf(n), 1.0) else 1


## 설명문 안 튜닝 상수 자리표시자. 수치를 문장에 적지 않고 const.csv 를 가리킨다:
## `{skill_hold_turns}` = `SKILL_HOLD_TURNS` 값. 이름 끝 꾸밈(여러 개 가능, 순서 무관):
##   `_pct` ×100 (비율 → 퍼센트) · `_abs` 절댓값 · `_signed` 양수에 `+` 를 붙인다.
## 예: `{skill_hold_lane_stat_pct}` → "-20", `{skill_hold_growth_rate_signed_pct}` → "+20".
## 상수가 아닌 이름(조사 태그, 호출부가 채울 값)은 그대로 둔다.
static func fill_consts(s: String) -> String:
	if _re_const == null:
		_re_const = RegEx.create_from_string("\\{([a-z][a-z0-9_]*)\\}")
	var out: String = ""
	var last: int = 0
	for m in _re_const.search_all(s):
		var v: String = _const_text(m.get_string(1))
		if v == "":
			continue
		out += s.substr(last, m.get_start() - last) + v
		last = m.get_end()
	return out + s.substr(last) if last > 0 else s


## 설명문용 수 표기. 정수면 소수점 없이, 아니면 소수 둘째 자리까지(끝 0 제거).
static func number_text(v: float, signed: bool = false) -> String:
	var r: float = snappedf(v, 0.01)
	var txt: String = str(int(round(r))) if is_equal_approx(r, round(r)) else String.num(r, 2)
	return "+" + txt if signed and r > 0.0 else txt


static var _re_const: RegEx = null
static var _re_plural: RegEx = null
const _CONST_MODS: Array = ["_pct", "_abs", "_signed"]


# 자리표시자 이름 → 상수 값 글자. 상수가 아니면 "".
static func _const_text(nm: String) -> String:
	var mods: Dictionary = {}
	var base: String = nm
	var stripped: bool = true
	while stripped:
		stripped = false
		for mod in _CONST_MODS:
			if base.ends_with(mod):
				mods[mod] = true
				base = base.left(base.length() - String(mod).length())
				stripped = true
	var ckey: String = base.to_upper()
	if not ConstTable.has(ckey):
		return ""
	var v: float = ConstTable.num(ckey)
	if mods.has("_pct"):
		v *= 100.0
	if mods.has("_abs"):
		v = absf(v)
	return number_text(v, mods.has("_signed"))


## 현재 또는 폴백 로케일에 번역이 있는가.
static func has(key: String) -> bool:
	return String(TranslationServer.translate(key)) != key


## 설명 key 의 `[x]` 참조 key 목록 (등장 순서, D4). 참조가 없으면 빈 배열.
static func refs(key: String) -> PackedStringArray:
	if not _refs_loaded:
		_refs_loaded = true
		if FileAccess.file_exists(REFS_PATH):
			var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(REFS_PATH))
			if typeof(parsed) == TYPE_DICTIONARY:
				_refs = parsed
			else:
				push_error("Loc: refs.json 파싱 실패 — %s" % REFS_PATH)
		else:
			push_error("Loc: refs.json 없음 — %s" % REFS_PATH)
	return PackedStringArray(_refs.get(key, []))


static func set_locale(code: String) -> void:
	TranslationServer.set_locale(code)


## 처음 쓸 로케일 (D11): 저장값이 지원 로케일이면 그것 → 기기 언어(`zh_CN` 같은 전체
## 코드, 그다음 언어만)가 지원되면 그것 → `L.FALLBACK_LOCALE`.
static func pick_initial_locale(saved: String) -> String:
	if saved != "" and L.LOCALES.has(saved):
		return saved
	var full: String = OS.get_locale()
	if L.LOCALES.has(full):
		return full
	var lang: String = OS.get_locale_language()
	if L.LOCALES.has(lang):
		return lang
	return L.FALLBACK_LOCALE
