@tool
extends RefCounted

## L10n 명령 파사드 — 설계서 §7.1. 에디터 메뉴(`plugin.gd`) · L10n 편집기(sheet/) · 헤드리스
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
const StepJob = preload("res://addons/l10n_tool/core/step_job.gd")

const MODE_DEV := "dev"
const MODE_RELEASE := "release"

const USAGE := """L10n 명령 (godot --headless --path . --script res://addons/l10n_tool/cli.gd -- <명령>)
  new_key <domain> <alias> <text> [context]
  new_keys <json 경로> [--out=<결과 json>]
                                         (일괄 발급: [{"domain","alias","ko","context"?,"max_len"?,"note"?,"en"?}, …]
                                          — 하나라도 틀리면 아무것도 안 바꿈, 같은 alias + 같은 원문은 재사용)
  add_locale <locale>
  sync
  approve <locale> <key|alias>...        (오너 지시 시에만)
  rename_alias <old> <new>
  move_key <key|alias> <new alias>       (다른 도메인 파일로 옮김: key · 번역 유지, 코드 L 상수 치환. 공유 낱말을 term/ui 로 올릴 때)
  scan
  validate [dev|release] [--fix-preview-leak]
  build [dev|release]
  write_l                                (L.gd 만 원본에서 다시 생성 — 검증 관문 없음)
  write_strings [dev|release]            (strings_<loc>.csv 만 다시 생성 — 검증 관문 없음)
  extract data [csv 파일명...]
  extract scenes <domain> <경로...> [--dry]
                                         (씬 · 리소스 고아 값 → key 발급 + 값 치환, 경로 = 파일 또는 폴더)
  extract code [경로...] [--out=<json>]   (코드 고아 리터럴 작업 목록, 기본 generated/extract_code.json)
  set_tr <locale> <json 경로>            (번역 초안 일괄: {"key 또는 alias": "번역", …} → draft)
  edit <json 경로>                       (셀 일괄 수정: [{"key": key 또는 alias, "column": ko|en|context|max_len|note|status, "value"}, …]
                                          원문을 고치면 번역은 stale, 같은 key 의 원문 → 번역 순으로 적으면 번역은 새 해시의 draft.
                                          status = active | deprecated. 하나라도 틀리면 아무것도 안 바꿈)
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

## key = a key issued beforehand (Keygen); "" = issue one.
func cmd_new_key(domain: String, alias: String, text: String, context: String = "", key: String = "") -> Dictionary:
	var res: Dictionary = catalog.add_entry(domain, alias, text, context, "", "", true, key)
	if res["error"] != "":
		info("new_key 실패: " + String(res["error"]))
	else:
		info("new_key %s = %s (%s)" % [alias, res["key"], domain])
	return res


## Columns the sheet editor may write besides the locale texts.
const EDIT_META_COLS := ["context", "max_len", "note"]


## `edit` — the sheet editor's cell writes. edits = [{key, column, value}]; column = the source
## locale (row text; translations go stale by hash), a target locale (→ draft + current source
## hash, cleared text clears status · hash) or EDIT_META_COLS (max_len = "" or a positive int).
## Re-reads the sources first so a write never overwrites other edits on disk, checks every edit
## and Excel lock up front — any failure writes nothing. Returns an error string.
## `status` (active / deprecated) is accepted only from the headless `edit` command.
func cmd_edit(edits: Array, allow_status: bool = false) -> String:
	reload()
	var targets: PackedStringArray = config.target_locales()
	var checked: Array = []
	for ed in edits:
		var key: String = String((ed as Dictionary).get("key", ""))
		var column: String = String(ed.get("column", ""))
		var value: String = String(ed.get("value", ""))
		var e: Dictionary = catalog.entry(key)
		if e.is_empty():
			return "없는 key: %s" % key
		var is_status: bool = allow_status and column == "status"
		if column != config.source_locale and not targets.has(column) and not EDIT_META_COLS.has(column) and not is_status:
			return "편집할 수 없는 컬럼: %s" % column
		if is_status and value != Catalog.STATUS_ACTIVE and value != Catalog.STATUS_DEPRECATED:
			return "status 는 active / deprecated: %s (%s)" % [value, key]
		if column == "max_len" and value != "" and not (value.is_valid_int() and value.to_int() > 0):
			return "max_len 은 비우거나 양의 정수: %s (%s)" % [value, key]
		var lock: String = Catalog.excel_lock_for(String(e["file"]))
		if lock != "":
			return "Excel 잠금 파일이 있다 — 파일을 닫고 다시: %s" % lock
		checked.append([key, column, value])
	var n: int = 0
	for c in checked:
		var key: String = c[0]
		var column: String = c[1]
		var value: String = c[2]
		var err: String = ""
		if targets.has(column):
			# 같은 값이어도 stale 이면 다시 쓴다 (같은 묶음에서 원문을 고친 뒤 번역을 그대로 확인할 때).
			if value == catalog.text(key, column) and not catalog.is_stale(key, column):
				continue
			err = catalog.set_translation(key, column, value)
		else:
			if value == String(catalog.entry(key).get("source" if column == config.source_locale else column, "")):
				continue
			err = catalog.set_field(key, column, value)
		if err != "":
			catalog.reload()
			return err
		n += 1
	var serr: String = catalog.save_all()
	if serr != "":
		catalog.reload()
		return serr
	info("edit: %d칸 저장" % n)
	return ""


## `remove_key`: the sheet editor's row delete. Re-reads the sources, checks the Excel lock,
## removes the key's row and saves. L.gd · strings follow on the next build. Returns an error string.
func cmd_remove_key(key: String) -> String:
	reload()
	var e: Dictionary = catalog.entry(key)
	if e.is_empty():
		return "없는 key: %s" % key
	var lock: String = Catalog.excel_lock_for(String(e["file"]))
	if lock != "":
		return "Excel 잠금 파일이 있다. 파일을 닫고 다시: %s" % lock
	var err: String = catalog.remove_entry(key)
	if err == "":
		err = catalog.save_all()
	catalog.reload()
	if err != "":
		return err
	info("remove_key: %s (%s) 삭제" % [key, String(e["alias"])])
	return ""


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


## L10n 편집기 Sync Data: (write_sources 면) sync → 스캔 + 검증 → index.json · report.md.
## write_sources = false(읽기 전용 모드)는 원본 CSV 를 쓰지 않는다. 돌려주는 값: sync 로 갱신한 셀 수.
func cmd_sync_data(write_sources: bool) -> int:
	return int(sync_data_job(write_sources).run_all())


## cmd_sync_data 를 단계로 나눈 작업 (편집기 진행 창): sync → scan(파일마다) → check(규칙 묶음마다)
## → write(report.md · index.json). 단계 id 가 진행 창 문구가 된다. result = sync 로 갱신한 셀 수.
func sync_data_job(write_sources: bool) -> StepJob:
	var job := StepJob.new()
	job.result = 0
	var st: Dictionary = {}
	if write_sources:
		job.add("sync", 1.0, func(j: StepJob) -> float:
			j.result = cmd_sync()
			return 1.0)
	job.add("scan", 6.0, func(_j: StepJob) -> float:
		if not st.has("ctx"):
			reload()
			st["ctx"] = Scanner.begin(self)
			st["file"] = 0
		var files: PackedStringArray = st["ctx"].files
		var i: int = int(st["file"])
		if i < files.size():
			Scanner.scan_file(st["ctx"], files[i])
			st["file"] = i + 1
			return float(i + 1) / float(files.size() + 1)
		index = Scanner.finish(st["ctx"])
		return 1.0)
	job.add("check", 3.0, func(_j: StepJob) -> float:
		if not st.has("checks"):
			st["checks"] = Validator.checks(self, MODE_DEV)
			st["check"] = 0
		var cs: Array = st["checks"]
		var c: int = int(st["check"])
		(cs[c] as Callable).call()
		st["check"] = c + 1
		return float(c + 1) / float(cs.size()))
	job.add("write", 0.5, func(_j: StepJob) -> float:
		var err: String = Validator.write_report(self, MODE_DEV)
		if err != "":
			info("report.md 쓰기 실패: " + err)
		_print_summary("validate " + MODE_DEV)
		err = Scanner.write_index(self, index)
		if err != "":
			info("index.json 쓰기 실패: " + err)
		return 1.0)
	return job


## `new_keys` — key 일괄 발급 (StatusOps.new_keys). json = 항목 배열. out_path 가 있으면
## 결과 [{alias, key, domain, status}] 를 JSON 으로 쓴다. 돌려주는 값: 오류 문자열.
func cmd_new_keys(json_path: String, out_path: String = "") -> String:
	reload()
	if not FileAccess.file_exists(json_path):
		return "파일 없음: %s" % json_path
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(json_path))
	if typeof(parsed) != TYPE_ARRAY:
		return "JSON 배열이 아님: %s" % json_path
	var res: Dictionary = StatusOps.new_keys(self, parsed)
	if String(res["error"]) != "":
		return String(res["error"])
	var n_new: int = 0
	for r in res["results"]:
		info("%s → %s (%s)" % [r["alias"], r["key"], "신규" if r["status"] == "new" else "재사용"])
		if r["status"] == "new":
			n_new += 1
	if out_path != "":
		DirAccess.make_dir_recursive_absolute(out_path.get_base_dir())
		var f := FileAccess.open(out_path, FileAccess.WRITE)
		if f == null:
			return "결과 쓰기 실패: %s" % out_path
		f.store_string(JSON.stringify(res["results"], "\t", false) + "\n")
		f.close()
	info("new_keys: %d개 (신규 %d · 재사용 %d)" % [(res["results"] as Array).size(), n_new, (res["results"] as Array).size() - n_new])
	return ""


## `write_l` / `write_strings` — 검증 관문 없이 생성물 하나만 다시 쓴다(다른 에이전트의 작업
## 중 Error 가 build 를 막을 때). 원본 읽기 오류(E001 · E002 · E003)가 있으면 상수 · 행이
## 빠진 파일이 되므로 거부한다. 돌려주는 값: 오류 문자열.
func cmd_write_generated(what: String, mode: String = MODE_DEV) -> String:
	reload()
	if catalog.load_issues.error_count() > 0:
		for it in catalog.load_issues.items:
			info("  " + Issues.format_item(it))
		return "원본 읽기 오류 %d개 — 고친 뒤 다시" % catalog.load_issues.error_count()
	if what == "l":
		var err: String = Builder.write_l_gd(self)
		if err == "":
			info("write_l: %s" % config.gen_dir.path_join(Builder.L_GD))
		return err
	return Builder.write_strings(self, mode)


## `extract data [csv…]` (§14 1순위) · `extract scenes <domain> <경로…> [--dry]` (2순위) ·
## `extract code [경로…] [--out=<json>]` (3순위 작업 목록). 돌려주는 값: 오류 문자열.
func cmd_extract(args: PackedStringArray) -> String:
	reload()
	var what: String = args[0] if not args.is_empty() else ""
	var rest := PackedStringArray()
	var dry: bool = false
	var out_path: String = config.gen_dir.path_join("extract_code.json")
	for a in args.slice(1):
		if a == "--dry":
			dry = true
		elif a.begins_with("--out="):
			out_path = resolve_path(a.substr(6))
		else:
			rest.append(a)
	var err: String = ""
	match what:
		"data":
			err = Extractor.extract_data(self, rest)
		"scenes":
			if rest.size() < 2:
				return "사용법: extract scenes <domain> <경로...> [--dry]"
			var paths := PackedStringArray()
			for p in rest.slice(1):
				paths.append(resolve_path(p))
			err = Extractor.extract_scenes(self, rest[0], paths, dry)
		"code":
			var paths := PackedStringArray()
			for p in rest:
				paths.append(resolve_path(p))
			err = Extractor.extract_code(self, paths, out_path)
		_:
			return "지원 대상: extract data [csv...] · extract scenes <domain> <경로...> · extract code [경로...]"
	info(("extract 실패: " + err) if err != "" else "extract %s 완료" % what)
	return err


## 스캔 결과의 orphans(index.json 과 같은 판정)만 — issues · index · index.json 은 건드리지 않는다.
func scan_orphans() -> Array:
	var saved: Issues = issues
	issues = Issues.new()
	var idx: Dictionary = Scanner.scan(self)
	issues = saved
	return idx.get("orphans", [])


## 씬 · 리소스 본문의 scene_text_props 값 목록 (Scanner.parse_scene).
func parse_scene(text: String) -> Array:
	return Scanner.parse_scene(Scanner.scene_regex(config), text)


## 명령 인자 경로 → res:// 경로. 프로젝트 안 절대 경로는 res:// 로, 상대 경로는 res:// 기준.
static func resolve_path(p: String) -> String:
	var s: String = p.replace("\\", "/")
	if s.contains("://"):
		return s
	if s.is_absolute_path():
		return ProjectSettings.localize_path(s)
	return "res://" + s.trim_prefix("./")


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


## 헤드리스 `edit <json>`: [{key(또는 alias), column, value}] 를 key 로 풀어 `cmd_edit`(status 허용).
func cmd_edit_json(json_path: String) -> String:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(json_path))
	if typeof(parsed) != TYPE_ARRAY:
		return "JSON 배열이 아님: %s" % json_path
	reload()
	var edits: Array = []
	for it in parsed:
		if typeof(it) != TYPE_DICTIONARY:
			return "항목이 객체가 아님: %s" % str(it)
		var key: String = resolve_key(String((it as Dictionary).get("key", "")))
		if key == "":
			return "없는 key/alias: %s" % str(it.get("key", ""))
		edits.append({"key": key, "column": String(it.get("column", "")), "value": String(it.get("value", ""))})
	return cmd_edit(edits, true)


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
		"move_key":
			if rest.size() != 2:
				print(USAGE)
				return 2
			var merr: String = StatusOps.move_key(l, rest[0], rest[1])
			if merr != "":
				l.info("move_key 실패: " + merr)
			return 0 if merr == "" else 1
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
		"new_keys":
			var json_path: String = ""
			var nk_out: String = ""
			for a in rest:
				if a.begins_with("--out="):
					nk_out = resolve_path(a.substr(6))
				else:
					json_path = a
			if json_path == "":
				print(USAGE)
				return 2
			var nerr: String = l.cmd_new_keys(resolve_path(json_path), nk_out)
			if nerr != "":
				l.info("new_keys 실패 — 아무것도 바꾸지 않음:\n" + nerr)
			return 0 if nerr == "" else 1
		"write_l", "write_strings":
			var werr: String = l.cmd_write_generated("l" if cmd == "write_l" else "strings", rest[0] if rest.size() > 0 else MODE_DEV)
			if werr != "":
				l.info("%s 실패: %s" % [cmd, werr])
			return 0 if werr == "" else 1
		"extract":
			return 0 if l.cmd_extract(rest) == "" else 1
		"edit":
			if rest.size() != 1:
				print(USAGE)
				return 2
			var eerr: String = l.cmd_edit_json(resolve_path(rest[0]))
			if eerr != "":
				l.info("edit 실패, 아무것도 바꾸지 않음: " + eerr)
			return 0 if eerr == "" else 1
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
