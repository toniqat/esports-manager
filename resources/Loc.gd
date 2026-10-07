class_name Loc
extends RefCounted

## 런타임 현지화 헬퍼 — 설계서 §10.2 · §10.3 · D4 · D11. static 만.
## 모든 코드 텍스트는 `Loc.t(L.X)` / `Loc.t(row.xxx_key)` 로 이 경로를 거친다.
## key 상수 클래스 `L` 은 l10n build 가 만든다(`data/l10n/generated/L.gd`).

const REFS_PATH := "res://data/l10n/generated/refs.json"

static var _refs: Dictionary = {}
static var _refs_loaded: bool = false


## key → 현재 로케일 텍스트. 순서: 번역 조회 → `{name}` 자리표시자 치환(params 에 있는
## 이름만, 나머지 `{x}` · 조사 태그는 남긴다) → 리터럴 `\n` 개행 · 조사 처리. 조사는 이름을
## 채운 **뒤에** 처리해야 받침을 본다. 현재 · 폴백 로케일 모두에 없으면 key 그대로.
static func t(key: String, params: Dictionary = {}) -> String:
	var s: String = String(TranslationServer.translate(key))
	if not params.is_empty():
		s = s.format(params)
	return StrategyIcon.resolve_josa(s)


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
