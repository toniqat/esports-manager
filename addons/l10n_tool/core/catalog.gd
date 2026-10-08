@tool
extends RefCounted

## 원본 전체(`src/<domain>.csv` + `glossary.csv`)를 읽은 카탈로그 — 모든 명령의 입력.
##
## 엔트리 하나 = 도메인 파일 한 행:
##   {key, alias, status, context, max_len, note, domain, row, line, file,
##    source: String, tr: {loc: {text, status, hash}}}
## `entries` 는 key → 첫 엔트리, `all_entries` 는 파일 순서 전체(중복 key 포함 — E011
## 판정용). 형식 규칙 검사(E010 · E011 · E012 …)는 validator 몫이고, 여기서는 읽기
## 오류(E001 · E002)와 헤더 불일치(E003)만 `load_issues` 에 담는다.

const Catalog = preload("res://addons/l10n_tool/core/catalog.gd")
const Config = preload("res://addons/l10n_tool/core/config.gd")
const CsvIo = preload("res://addons/l10n_tool/core/csv_io.gd")
const Issues = preload("res://addons/l10n_tool/core/issues.gd")
const Keygen = preload("res://addons/l10n_tool/core/keygen.gd")
const Hasher = preload("res://addons/l10n_tool/core/hasher.gd")

const STATUS_ACTIVE := "active"
const STATUS_DEPRECATED := "deprecated"
const TR_DRAFT := "draft"
const TR_APPROVED := "approved"
const REQUIRED_COLS := ["key", "alias", "status"]
const ALIAS_PATTERN := "^[a-z][a-z0-9_]*(\\.[a-z0-9_]+)+$"

var config: Config
## domain → CsvIo
var tables: Dictionary = {}
var entries: Dictionary = {}
var all_entries: Array = []
## alias → key (첫 등장)
var by_alias: Dictionary = {}
var glossary: CsvIo = null
var load_issues: Issues = Issues.new()
# "domain:row" → all_entries 인덱스
var _pos: Dictionary = {}


static func open(cfg: Config) -> Catalog:
	var c: Catalog = Catalog.new()
	c.config = cfg
	c.reload()
	return c


## 원본을 디스크에서 다시 읽는다.
func reload() -> void:
	tables.clear()
	entries.clear()
	all_entries.clear()
	_pos.clear()
	by_alias.clear()
	glossary = null
	load_issues = Issues.new()
	var dir := DirAccess.open(config.src_dir)
	if dir == null:
		load_issues.error("E001", "원본 폴더 없음: %s" % config.src_dir)
		return
	var files: Array = Array(dir.get_files())
	files.sort()
	for fn in files:
		if not String(fn).ends_with(".csv") or String(fn).begins_with("~$"):
			continue
		var full: String = config.src_dir.path_join(fn)
		if fn == "glossary.csv":
			glossary = CsvIo.load_file(full)
			_collect_csv_errors(glossary)
			continue
		var domain: String = String(fn).get_basename()
		var t: CsvIo = CsvIo.load_file(full)
		tables[domain] = t
		_collect_csv_errors(t)
		if not t.ok():
			continue
		_check_header(domain, t)
		for r in t.row_count():
			_index_row(domain, t, r)


func domains() -> PackedStringArray:
	var arr: Array = tables.keys()
	arr.sort()
	return PackedStringArray(arr)


func has_key(key: String) -> bool:
	return entries.has(key)


func entry(key: String) -> Dictionary:
	return entries.get(key, {})


func key_of_alias(alias: String) -> String:
	return String(by_alias.get(alias, ""))


func source_text(key: String) -> String:
	return String(entry(key).get("source", ""))


## 그 로케일 텍스트. 원문 로케일이면 원문. 번역이 없으면 "".
func text(key: String, locale: String) -> String:
	var e: Dictionary = entry(key)
	if e.is_empty():
		return ""
	if locale == config.source_locale:
		return String(e["source"])
	return String((e["tr"] as Dictionary).get(locale, {}).get("text", ""))


## 번역이 stale 인가 — 텍스트가 있고 hash 가 현재 원문 해시와 다르다(§8).
func is_stale(key: String, locale: String) -> bool:
	var e: Dictionary = entry(key)
	if e.is_empty() or locale == config.source_locale:
		return false
	var t: Dictionary = (e["tr"] as Dictionary).get(locale, {})
	if String(t.get("text", "")).is_empty():
		return false
	return String(t.get("hash", "")) != Hasher.hash_text(String(e["source"]))


## 모든 원본의 key 집합(deprecated 포함) — 발급 시 중복 검사용.
func key_set() -> Dictionary:
	var s: Dictionary = {}
	for e in all_entries:
		s[e["key"]] = true
	return s


## alias 형식(§3.2): 정규식 + 첫 세그먼트 = domain.
static func is_valid_alias(alias: String, domain: String) -> bool:
	var re := RegEx.create_from_string(ALIAS_PATTERN)
	return re.search(alias) != null and alias.get_slice(".", 0) == domain


## L 상수 이름 → alias (데이터 alias 제외, 예약 상수는 alias "") — 일괄 발급(new_keys ·
## extract scenes)이 E013 충돌을 미리 막는 데 쓴다. 새로 정한 alias 는 호출자가 더한다.
func const_map() -> Dictionary:
	var m: Dictionary = {}
	for c in Config.RESERVED_L_CONSTS:
		m[c] = ""
	for a in by_alias.keys():
		if not config.is_data_alias(a):
			var cn: String = Config.const_name(a)
			if not m.has(cn):
				m[cn] = a
	return m


## `new_key` (§7.1): key 발급 → `<domain>.csv` 끝에 active 행 추가 → 저장.
## 돌려주는 값 {key, error}. 같은 alias 가 있으면 오류. do_save = false 면 저장을 미루고
## (일괄 추출) 나중에 `save_all()`.
## preset_key = a key issued beforehand (the sheet shows it in its add-row dialog); "" = issue one now.
func add_entry(domain: String, alias: String, source: String, context: String = "", max_len: String = "", note: String = "", do_save: bool = true, preset_key: String = "") -> Dictionary:
	if not is_valid_alias(alias, domain):
		return {"key": "", "error": "alias 형식 위반 또는 첫 세그먼트 ≠ domain: %s (domain=%s)" % [alias, domain]}
	if by_alias.has(alias):
		return {"key": "", "error": "이미 있는 alias: %s (%s)" % [alias, by_alias[alias]]}
	var lock: String = excel_lock_for(config.domain_path(domain))
	if lock != "":
		return {"key": "", "error": "Excel 잠금 파일이 있다 — 파일을 닫고 다시: %s" % lock}
	var key: String = preset_key
	if key != "" and (not Keygen.is_valid(key, config.key_prefix) or key_set().has(key)):
		return {"key": "", "error": "쓸 수 없는 key: %s (형식 위반 또는 이미 있음)" % key}
	if key == "":
		key = Keygen.generate(config.key_prefix, key_set())
	if key == "":
		return {"key": "", "error": "key 발급 실패"}
	var t: CsvIo = tables.get(domain, null)
	if t == null:
		t = CsvIo.create(config.domain_path(domain), config.domain_header())
		tables[domain] = t
	var vals: Dictionary = {"key": key, "alias": alias, "status": STATUS_ACTIVE,
		"context": context, "max_len": max_len, "note": note, config.source_locale: source}
	var r: int = t.append_row(vals)
	if do_save:
		var err: String = t.save()
		if err != "":
			return {"key": "", "error": err}
	_index_row(domain, t, r)
	return {"key": key, "error": ""}


## 번역 텍스트를 쓴다 — LLM 은 항상 draft(§0.5). hash 는 현재 원문 해시.
## 저장은 하지 않는다 — 여러 행을 고친 뒤 `save_all()`.
func set_translation(key: String, locale: String, value: String, status: String = TR_DRAFT) -> String:
	var e: Dictionary = entry(key)
	if e.is_empty():
		return "없는 key: %s" % key
	if locale == config.source_locale or not config.target_locales().has(locale):
		return "번역 로케일이 아님: %s" % locale
	var t: CsvIo = tables[e["domain"]]
	var r: int = int(e["row"])
	t.set_cell(r, locale, value)
	t.set_cell(r, locale + "_status", status if value != "" else "")
	t.set_cell(r, locale + "_hash", Hasher.hash_text(String(e["source"])) if value != "" else "")
	_index_row(String(e["domain"]), t, r)
	return ""


## 셀 하나를 쓴다(원문 · context · status 등). 저장은 `save_all()`.
func set_field(key: String, column: String, value: String) -> String:
	var e: Dictionary = entry(key)
	if e.is_empty():
		return "없는 key: %s" % key
	var t: CsvIo = tables[e["domain"]]
	if not t.set_cell(int(e["row"]), column, value):
		return "없는 컬럼: %s" % column
	_index_row(String(e["domain"]), t, int(e["row"]))
	return ""


## key 행을 다른 도메인 파일 끝으로 옮기고 alias 를 바꾼다 (key · 번역 · 상태 · 해시는 그대로).
## 저장은 `save_all()`, 그 뒤 `reload()` 로 행 번호를 다시 맞춘다.
func move_entry(key: String, new_alias: String) -> String:
	var e: Dictionary = entry(key)
	if e.is_empty():
		return "없는 key: %s" % key
	var src_domain: String = String(e["domain"])
	var dst_domain: String = new_alias.get_slice(".", 0)
	var src: CsvIo = tables[src_domain]
	var r: int = int(e["row"])
	var vals: Dictionary = src.row_dict(r)
	vals["alias"] = new_alias
	var dst: CsvIo = tables.get(dst_domain, null)
	if dst == null:
		dst = CsvIo.create(config.domain_path(dst_domain), config.domain_header())
		tables[dst_domain] = dst
	dst.append_row(vals)
	if dst_domain != src_domain:
		src.remove_row(r)
	else:
		return "같은 도메인 안에서는 rename_alias 를 쓴다"
	return ""


## key 행을 원본에서 지운다 (L10n 편집기의 행 제거). 저장은 `save_all()`, 그 뒤 `reload()`.
func remove_entry(key: String) -> String:
	var e: Dictionary = entry(key)
	if e.is_empty():
		return "없는 key: %s" % key
	var t: CsvIo = tables.get(String(e["domain"]), null)
	if t == null or not t.remove_row(int(e["row"])):
		return "행을 지우지 못함: %s" % key
	return ""


## 바뀐 도메인 파일을 모두 저장. 오류들을 이어 붙여 돌려준다.
func save_all() -> String:
	var errs: PackedStringArray = PackedStringArray()
	for d in tables.keys():
		var t: CsvIo = tables[d]
		if not t.is_dirty():
			continue
		var lock: String = excel_lock_for(t.path)
		if lock != "":
			errs.append("Excel 잠금 파일 — 저장 안 함: %s" % lock)
			continue
		var e: String = t.save()
		if e != "":
			errs.append(e)
	return "\n".join(errs)


## 같은 폴더의 Excel 잠금 파일(`~$<이름>`) 경로. 없으면 "" (§12.3).
static func excel_lock_for(file_path: String) -> String:
	var dir: String = file_path.get_base_dir()
	var fn: String = file_path.get_file()
	for cand in ["~$" + fn, "~$" + fn.substr(2) if fn.length() > 2 else ""]:
		if cand != "" and FileAccess.file_exists(dir.path_join(cand)):
			return dir.path_join(cand)
	return ""


## 용어집 행 목록 — [{term_id, key, <loc>…, forbidden_<loc>…, dnt, note, match_<loc>…, line}].
func glossary_rows() -> Array:
	var out: Array = []
	if glossary == null or not glossary.ok():
		return out
	for r in glossary.row_count():
		var d: Dictionary = glossary.row_dict(r)
		d["line"] = glossary.row_lines[r]
		out.append(d)
	return out


func _collect_csv_errors(t: CsvIo) -> void:
	for e in t.errors:
		load_issues.error(String(e["code"]), String(e["msg"]), t.path, int(e["line"]))


func _check_header(domain: String, t: CsvIo) -> void:
	for c in REQUIRED_COLS + [config.source_locale]:
		if not t.has_column(c):
			load_issues.error("E003", "필수 컬럼 없음: %s (%s)" % [c, domain], t.path, 1)
	for l in config.target_locales():
		for c in [l, l + "_status", l + "_hash"]:
			if not t.has_column(c):
				load_issues.error("E003", "config.locales 와 컬럼 불일치 — %s 없음 (%s)" % [c, domain], t.path, 1)


func _index_row(domain: String, t: CsvIo, r: int) -> void:
	var trs: Dictionary = {}
	for l in config.target_locales():
		trs[l] = {"text": t.get_cell(r, l), "status": t.get_cell(r, l + "_status"), "hash": t.get_cell(r, l + "_hash")}
	var e: Dictionary = {
		"key": t.get_cell(r, "key"), "alias": t.get_cell(r, "alias"), "status": t.get_cell(r, "status"),
		"context": t.get_cell(r, "context"), "max_len": t.get_cell(r, "max_len"), "note": t.get_cell(r, "note"),
		"domain": domain, "row": r, "line": t.row_lines[r], "file": t.path,
		"source": t.get_cell(r, config.source_locale), "tr": trs,
	}
	# 같은 행을 다시 색인하면(set_translation 등) 기존 엔트리를 갈아 끼운다.
	var pos_key: String = "%s:%d" % [domain, r]
	if _pos.has(pos_key):
		all_entries[int(_pos[pos_key])] = e
	else:
		_pos[pos_key] = all_entries.size()
		all_entries.append(e)
	var key: String = e["key"]
	if not entries.has(key) or (entries[key]["domain"] == domain and int(entries[key]["row"]) == r):
		entries[key] = e
	var alias: String = e["alias"]
	if alias != "" and (not by_alias.has(alias) or by_alias[alias] == key):
		by_alias[alias] = key
