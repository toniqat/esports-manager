@tool
extends RefCounted

## L10n 명령 파사드 — 설계서 §7.1. 에디터 메뉴(`plugin.gd`) · 조회 도크 · 헤드리스
## (`cli.gd`) · 테스트가 모두 이 객체를 통해 같은 코드를 부른다.
##
## 상태: `config` · `catalog`(원본) · `issues`(이번 명령의 검증 결과) · `index`(스캔
## 결과 = index.json 본문). 모듈(validator · scanner · builder · status_ops ·
## extractor)은 이 객체를 첫 인자로 받는 static 함수만 갖는다 — 모듈끼리는 서로
## 부르지 않고 항상 여기를 거친다.

const L10n = preload("res://addons/l10n_tool/core/l10n.gd")
const Config = preload("res://addons/l10n_tool/core/config.gd")
const Catalog = preload("res://addons/l10n_tool/core/catalog.gd")
const Issues = preload("res://addons/l10n_tool/core/issues.gd")
const Refs = preload("res://addons/l10n_tool/core/refs.gd")
const Validator = preload("res://addons/l10n_tool/core/validator.gd")
const Scanner = preload("res://addons/l10n_tool/core/scanner.gd")
const Builder = preload("res://addons/l10n_tool/core/builder.gd")
const StatusOps = preload("res://addons/l10n_tool/core/status_ops.gd")
const Extractor = preload("res://addons/l10n_tool/core/extractor.gd")

const MODE_DEV := "dev"
const MODE_RELEASE := "release"

const USAGE := """L10n 명령 (godot --headless --path . --script res://addons/l10n_tool/cli.gd -- <명령>)
  new_key <domain> <alias> <text> [context]
  add_locale <locale>
  sync
  approve <locale> <key|alias>...        (오너 지시 시에만)
  rename_alias <old> <new>
  scan
  validate [dev|release] [--fix-preview-leak]
  build [dev|release]
  extract data [csv 파일명...]
  set_tr <locale> <json 경로>            (번역 초안 일괄: {"key 또는 alias": "번역", …} → draft)
옵션: --config=<res://…/config.json> (기본 res://data/l10n/config.json)"""

var config: Config
var catalog: Catalog
var issues: Issues = Issues.new()
## 스캔 결과 — index.json 본문(§9.4). scan 전에는 {}.
var index: Dictionary = {}
## 이번 명령 동안의 출력 줄 (도크가 보여 준다).
var output: PackedStringArray = PackedStringArray()
## false 면 print 하지 않는다(테스트).
var echo: bool = true


static func open(config_path: String = Config.DEFAULT_PATH) -> L10n:
	var l: L10n = L10n.new()
	l.config = Config.load_from(config_path)
	if l.config.error != "":
		l.info("오류: " + l.config.error)
		return l
	l.catalog = Catalog.open(l.config)
	return l


func ok() -> bool:
	return config != null and config.error == "" and catalog != null


func info(msg: String) -> void:
	output.append(msg)
	if echo:
		print(msg)


## 원본을 다시 읽고 issues 를 비운다 — 명령마다 처음에 부른다.
func reload() -> void:
	catalog.reload()
	issues = Issues.new()
	issues.merge(catalog.load_issues)


# ── 명령 ────────────────────────────────────────────────────────────────

func cmd_new_key(domain: String, alias: String, text: String, context: String = "") -> Dictionary:
	var res: Dictionary = catalog.add_entry(domain, alias, text, context)
	if res["error"] != "":
		info("new_key 실패: " + String(res["error"]))
	else:
		info("new_key %s = %s (%s)" % [alias, res["key"], domain])
	return res


func cmd_add_locale(locale: String) -> String:
	var err: String = StatusOps.add_locale(self, locale)
	info(("add_locale 실패: " + err) if err != "" else "add_locale %s 완료" % locale)
	return err


## 돌려주는 값: 갱신한 셀 수.
func cmd_sync() -> int:
	reload()
	var n: int = StatusOps.sync(self)
	info("sync: %d개 번역에 해시 · draft 기록" % n)
	return n


func cmd_approve(locale: String, keys_or_aliases: PackedStringArray) -> String:
	reload()
	var err: String = StatusOps.approve(self, locale, keys_or_aliases)
	info(("approve 실패: " + err) if err != "" else "approve %s: %d개" % [locale, keys_or_aliases.size()])
	return err


func cmd_rename_alias(old_alias: String, new_alias: String) -> String:
	reload()
	var err: String = StatusOps.rename_alias(self, old_alias, new_alias)
	info(("rename_alias 실패: " + err) if err != "" else "rename_alias %s → %s" % [old_alias, new_alias])
	return err


## 사용처 스캔 → index.json. 사용처 검증(E05x · W05x)은 issues 에 담긴다.
func cmd_scan(write: bool = true) -> Dictionary:
	reload()
	index = Scanner.scan(self)
	if write:
		var err: String = Scanner.write_index(self, index)
		if err != "":
			info("index.json 쓰기 실패: " + err)
	info("scan: key %d개, 고아 %d개" % [(index.get("keys", {}) as Dictionary).size(), (index.get("orphans", []) as Array).size()])
	return index


## 검증만 — 스캔(사용처 규칙) + 원본 규칙. report.md 를 쓴다. 돌려주는 값: issues.
func cmd_validate(mode: String = MODE_DEV, write_report: bool = true) -> Issues:
	reload()
	index = Scanner.scan(self)
	Validator.validate(self, mode)
	if write_report:
		var err: String = Validator.write_report(self, mode)
		if err != "":
			info("report.md 쓰기 실패: " + err)
	_print_summary("validate " + mode)
	return issues


## sync → 검증 → (Error 0 이면) 생성물 → index.json · report.md. 돌려주는 값: Error 수.
func cmd_build(mode: String = MODE_DEV) -> int:
	cmd_sync()
	cmd_validate(mode, false)
	var errors: int = issues.error_count()
	if errors == 0:
		var err: String = Builder.build(self, mode)
		if err != "":
			issues.error("E000", "생성 실패: " + err)
			info("생성 실패: " + err)
			errors += 1
	else:
		info("Error %d개 — 생성물을 쓰지 않는다 (report.md 확인)" % errors)
	var werr: String = Scanner.write_index(self, index)
	if werr != "":
		info("index.json 쓰기 실패: " + werr)
	werr = Validator.write_report(self, mode)
	if werr != "":
		info("report.md 쓰기 실패: " + werr)
	info("build %s: %s" % [mode, "완료" if errors == 0 else "실패"])
	return errors


## `extract data [csv…]` (§14 1순위). 돌려주는 값: 오류 문자열.
func cmd_extract(args: PackedStringArray) -> String:
	reload()
	if args.is_empty() or args[0] != "data":
		return "지원 대상: extract data [csv 파일명...]"
	var err: String = Extractor.extract_data(self, args.slice(1))
	info(("extract 실패: " + err) if err != "" else "extract data 완료")
	return err


## 번역 초안 일괄 쓰기 — json 은 {key 또는 alias: 번역문}. 모두 draft + 현재 원문 해시
## (LLM 번역은 draft 까지, §0.5). 없는 key 가 하나라도 있으면 아무것도 쓰지 않는다.
func cmd_set_translations(locale: String, json_path: String) -> String:
	reload()
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(json_path))
	if typeof(parsed) != TYPE_DICTIONARY:
		return "JSON 객체가 아님: %s" % json_path
	var pairs: Array = []
	for k in (parsed as Dictionary).keys():
		var key: String = resolve_key(String(k))
		if key == "":
			return "없는 key/alias: %s" % k
		pairs.append([key, String(parsed[k])])
	for pr in pairs:
		var err: String = catalog.set_translation(pr[0], locale, pr[1])
		if err != "":
			catalog.reload()
			return err
	var serr: String = catalog.save_all()
	if serr != "":
		return serr
	info("set_tr %s: %d개 draft" % [locale, pairs.size()])
	return ""


## refs.json 본문 — 설명 key → [참조 key…] (D4). builder 가 쓴다.
func resolve_refs(into: Issues = null) -> Dictionary:
	return Refs.resolve(catalog, into)


## alias 또는 key → key. 없으면 "".
func resolve_key(key_or_alias: String) -> String:
	if catalog.has_key(key_or_alias):
		return key_or_alias
	return catalog.key_of_alias(key_or_alias)


# ── 헤드리스 ────────────────────────────────────────────────────────────

## cli.gd 가 부른다. 돌려주는 값 = 프로세스 종료 코드(0 성공).
static func run_cli(raw_args: PackedStringArray) -> int:
	var cfg_path: String = Config.DEFAULT_PATH
	var args := PackedStringArray()
	for a in raw_args:
		if a.begins_with("--config="):
			cfg_path = a.substr(9)
		else:
			args.append(a)
	if args.is_empty():
		print(USAGE)
		return 2
	var l: L10n = L10n.open(cfg_path)
	if not l.ok():
		return 1
	var cmd: String = args[0]
	var rest: PackedStringArray = args.slice(1)
	match cmd:
		"new_key":
			if rest.size() < 3:
				print(USAGE)
				return 2
			return 0 if l.cmd_new_key(rest[0], rest[1], rest[2], rest[3] if rest.size() > 3 else "")["error"] == "" else 1
		"add_locale":
			return 0 if rest.size() == 1 and l.cmd_add_locale(rest[0]) == "" else 1
		"sync":
			l.cmd_sync()
			return 0
		"approve":
			if rest.size() < 2:
				print(USAGE)
				return 2
			return 0 if l.cmd_approve(rest[0], rest.slice(1)) == "" else 1
		"rename_alias":
			return 0 if rest.size() == 2 and l.cmd_rename_alias(rest[0], rest[1]) == "" else 1
		"scan":
			l.cmd_scan()
			return 0
		"validate":
			var vargs := PackedStringArray()
			for a in rest:
				if a == "--fix-preview-leak":
					l.reload()
					l.info("fix-preview-leak: %d개 씬 값을 key 로 되돌림" % Scanner.fix_preview_leak(l))
				else:
					vargs.append(a)
			return 0 if l.cmd_validate(vargs[0] if vargs.size() > 0 else MODE_DEV).error_count() == 0 else 1
		"build":
			return 0 if l.cmd_build(rest[0] if rest.size() > 0 else MODE_DEV) == 0 else 1
		"extract":
			return 0 if l.cmd_extract(rest) == "" else 1
		"set_tr":
			if rest.size() != 2:
				print(USAGE)
				return 2
			var serr: String = l.cmd_set_translations(rest[0], rest[1])
			if serr != "":
				l.info("set_tr 실패: " + serr)
			return 0 if serr == "" else 1
	print(USAGE)
	return 2


func _print_summary(title: String) -> void:
	info("%s: Error %d · Warn %d" % [title, issues.error_count(), issues.warn_count()])
	var shown: int = 0
	for it in issues.items:
		if it["level"] != Issues.ERROR:
			continue
		info("  " + Issues.format_item(it))
		shown += 1
		if shown >= 30:
			info("  … (report.md 참고)")
			break
