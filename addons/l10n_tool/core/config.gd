@tool
extends RefCounted

## `data/l10n/config.json` — 설계서 §2.2.
## 경로는 config.json 위치 기준: `<base>/src/` 원본, `<base>/generated/` 생성물.
## 테스트는 fixture 폴더의 config.json 을 넘겨 같은 코드를 돌린다.

const Config = preload("res://addons/l10n_tool/core/config.gd")
const DEFAULT_PATH := "res://data/l10n/config.json"

var path: String = DEFAULT_PATH
var base_dir: String = "res://data/l10n"
var src_dir: String = "res://data/l10n/src"
var gen_dir: String = "res://data/l10n/generated"
## 데이터 테이블 CSV 폴더 (§6). config 의 `data_csv_dir` 로 바꿀 수 있다(테스트용).
var data_csv_dir: String = "res://data/csv"

var source_locale: String = "ko"
var locales: PackedStringArray = PackedStringArray(["ko", "en"])
var fallback_locale: String = "en"
var key_prefix: String = "tx_"
var strict_orphans: String = "warn"
var josa_tags: Array = []
var ref_domains: Array = []
var bbcode_tags: Array = []
## scan 섹션 원본 그대로 (roots, include_ext, exclude_dirs, scene_text_props,
## log_funcs, ignore_paths).
var scan: Dictionary = {}
## [{csv, id, column, domain, alias}] — alias 의 `{col}` 은 그 행의 col 값으로 채운다(§3.2).
var data_columns: Array = []
## 파일 전체 원본 — 저장할 때 모르는 키를 잃지 않도록.
var raw: Dictionary = {}
var error: String = ""


static func load_from(config_path: String = DEFAULT_PATH) -> Config:
	var c: Config = Config.new()
	c.path = config_path
	c.base_dir = config_path.get_base_dir()
	c.src_dir = c.base_dir.path_join("src")
	c.gen_dir = c.base_dir.path_join("generated")
	if not FileAccess.file_exists(config_path):
		c.error = "config.json 없음: %s" % config_path
		return c
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(config_path))
	if typeof(parsed) != TYPE_DICTIONARY:
		c.error = "config.json 파싱 실패: %s" % config_path
		return c
	c.raw = parsed
	c.source_locale = String(parsed.get("source_locale", "ko"))
	c.locales = PackedStringArray(parsed.get("locales", ["ko", "en"]))
	c.fallback_locale = String(parsed.get("fallback_locale", "en"))
	c.key_prefix = String(parsed.get("key_prefix", "tx_"))
	c.strict_orphans = String((parsed.get("strict", {}) as Dictionary).get("orphans", "warn"))
	var tok: Dictionary = parsed.get("tokens", {})
	c.josa_tags = tok.get("josa_tags", [])
	c.ref_domains = tok.get("ref_domains", [])
	c.bbcode_tags = tok.get("bbcode_tags", [])
	c.scan = parsed.get("scan", {})
	c.data_columns = parsed.get("data_columns", [])
	if parsed.has("data_csv_dir"):
		var d: String = String(parsed["data_csv_dir"])
		c.data_csv_dir = d if d.begins_with("res://") else c.base_dir.path_join(d)
	return c


## 원문 외 로케일 — 번역 컬럼 묶음(`<loc>` · `<loc>_status` · `<loc>_hash`)이 있는 것.
func target_locales() -> PackedStringArray:
	var out := PackedStringArray()
	for l in locales:
		if l != source_locale:
			out.append(l)
	return out


## 도메인 파일의 표준 헤더 (§4.2).
func domain_header() -> PackedStringArray:
	var h := PackedStringArray(["key", "alias", "status", "context", "max_len", "note", source_locale])
	for l in target_locales():
		h.append_array([l, l + "_status", l + "_hash"])
	return h


func domain_path(domain: String) -> String:
	return src_dir.path_join(domain + ".csv")


func glossary_path() -> String:
	return src_dir.path_join("glossary.csv")


func scan_list(list_name: String) -> Array:
	return scan.get(list_name, []) as Array


## data_columns alias 규칙을 한 행에 적용 — `{col}` 을 그 행 값으로 바꾸되 소문자로,
## `[a-z0-9_]` 밖의 글자는 `_` 로 (`S01` → `s01`). row 는 {헤더: 값}.
static func expand_alias(template: String, row: Dictionary) -> String:
	var out: String = template
	var re := RegEx.create_from_string("\\{([a-z_][a-z0-9_]*)\\}")
	for m in re.search_all(template):
		var v: String = String(row.get(m.get_string(1), "")).to_lower()
		var clean: String = ""
		for ch in v:
			clean += ch if ("abcdefghijklmnopqrstuvwxyz0123456789_".contains(ch)) else "_"
		out = out.replace(m.get_string(0), clean)
	return out


## config.json 을 다시 쓴다(add_locale 등). 들여쓰기 2칸.
func save() -> String:
	raw["source_locale"] = source_locale
	raw["locales"] = Array(locales)
	raw["fallback_locale"] = fallback_locale
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return "쓰기 실패: %s" % path
	f.store_string(JSON.stringify(raw, "  ", false) + "\n")
	f.close()
	return ""
