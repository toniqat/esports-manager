@tool
extends RefCounted

## 생성물 — strings_<loc>.csv · L.gd · refs.json · 프로젝트 설정 등록 (설계서 §7.2 · §7.3 · §10.3).
##
## 모든 파일은 내용이 같으면 다시 쓰지 않는다(불필요한 재임포트 · diff 방지). 줄바꿈 LF,
## BOM 없음. 행 순서 = 도메인 파일 이름 순 → 파일 행 순(`catalog.all_entries`).
## 프로젝트 설정은 실제 프로젝트 config(`Config.DEFAULT_PATH`)를 빌드할 때만 건드린다 —
## 테스트 fixture 가 project.godot 을 고치지 않도록.

const Config = preload("res://addons/l10n_tool/core/config.gd")
const Catalog = preload("res://addons/l10n_tool/core/catalog.gd")
const CsvIo = preload("res://addons/l10n_tool/core/csv_io.gd")
const KeyRefs = preload("res://addons/l10n_tool/core/key_refs.gd")

const MODE_DEV := "dev"
const MODE_RELEASE := "release"
const L_GD := "L.gd"
const REFS_JSON := "refs.json"
const HEADER_LINE := "# 자동 생성 파일. 직접 수정 금지. (l10n_tool build)"
## L.gd 가 직접 쓰는 상수 이름 — alias 상수와 겹치면 validator 의 E013. 정의는 config.gd
## (scanner 도 E051 판정에 쓴다).
const RESERVED_CONSTS: Array = Config.RESERVED_L_CONSTS
const SETTING_TRANSLATIONS := "internationalization/locale/translations"
const SETTING_FALLBACK := "internationalization/locale/fallback"


## 오류 문자열 또는 "".
static func build(l, mode: String) -> String:
	if mode != MODE_DEV and mode != MODE_RELEASE:
		return "알 수 없는 빌드 모드: %s" % mode
	var cfg: Config = l.config
	if not DirAccess.dir_exists_absolute(cfg.gen_dir):
		var mk: Error = DirAccess.make_dir_recursive_absolute(cfg.gen_dir)
		if mk != OK:
			return "생성 폴더를 만들 수 없음: %s (%s)" % [cfg.gen_dir, error_string(mk)]
	var errs := PackedStringArray()
	var written: int = 0
	for loc in cfg.locales:
		var res: int = _write_if_changed(cfg.gen_dir.path_join(strings_file(loc)), strings_csv(l, loc, mode))
		if res < 0:
			errs.append("쓰기 실패: " + strings_file(loc))
		written += maxi(res, 0)
	var lres: int = _write_l(l)
	if lres < 0:
		errs.append("쓰기 실패: " + L_GD)
	written += maxi(lres, 0)
	var rres: int = _write_if_changed(cfg.gen_dir.path_join(REFS_JSON), refs_json(l))
	if rres < 0:
		errs.append("쓰기 실패: " + REFS_JSON)
	written += maxi(rres, 0)
	if cfg.path == Config.DEFAULT_PATH:
		var perr: String = register_project_settings(cfg)
		if perr != "":
			errs.append(perr)
	if written > 0:
		_rescan_editor()
	l.info("build %s: 생성물 %d개 갱신" % [mode, written])
	return "\n".join(errs)


## L.gd 만 다시 쓴다 (rename_alias · `write_l`). 오류 문자열 또는 "".
static func write_l_gd(l) -> String:
	var cfg: Config = l.config
	if not DirAccess.dir_exists_absolute(cfg.gen_dir):
		DirAccess.make_dir_recursive_absolute(cfg.gen_dir)
	var res: int = _write_l(l)
	if res < 0:
		return "쓰기 실패: " + cfg.gen_dir.path_join(L_GD)
	if res > 0:
		_rescan_editor()
	return ""


## `strings_<loc>.csv` 만 다시 쓴다 (`write_strings` — 검증 관문 없이). 오류 문자열 또는 "".
static func write_strings(l, mode: String) -> String:
	if mode != MODE_DEV and mode != MODE_RELEASE:
		return "알 수 없는 빌드 모드: %s" % mode
	var cfg: Config = l.config
	if not DirAccess.dir_exists_absolute(cfg.gen_dir):
		DirAccess.make_dir_recursive_absolute(cfg.gen_dir)
	var errs := PackedStringArray()
	var written: int = 0
	for loc in cfg.locales:
		var res: int = _write_if_changed(cfg.gen_dir.path_join(strings_file(loc)), strings_csv(l, loc, mode))
		if res < 0:
			errs.append("쓰기 실패: " + strings_file(loc))
		written += maxi(res, 0)
	if written > 0:
		_rescan_editor()
	l.info("write_strings %s: %d개 갱신" % [mode, written])
	return "\n".join(errs)


static func strings_file(loc: String) -> String:
	return "strings_%s.csv" % loc


## Godot CSV 번역 임포터가 만드는 리소스 경로 — `strings_<loc>.<loc>.translation`.
static func translation_path(cfg: Config, loc: String) -> String:
	return cfg.gen_dir.path_join("strings_%s.%s.translation" % [loc, loc])


## `strings_<loc>.csv` 본문 (§4.4 · §7.3). 빈 셀은 만들지 않는다.
static func strings_csv(l, loc: String, mode: String) -> String:
	var cat: Catalog = l.catalog
	var lines := PackedStringArray(["keys," + CsvIo.quote_cell(loc)])
	var seen: Dictionary = {}
	for e in cat.all_entries:
		var key: String = String(e["key"])
		if key.is_empty() or seen.has(key):
			continue
		seen[key] = true
		var active: bool = e["status"] == Catalog.STATUS_ACTIVE
		if mode == MODE_RELEASE and not active:
			continue
		# key 참조 `{tx_…}` 는 여기서 그 로케일 텍스트로 펼친다 (KeyRefs). 펼칠 수 없으면 행을 뺀다.
		var value: String = KeyRefs.expand(cat, KeyRefs.raw_text(cat, key, loc, mode), loc, mode)
		if value.is_empty():
			continue
		lines.append(CsvIo.quote_cell(key) + "," + CsvIo.quote_cell(value))
	return "\n".join(lines) + "\n"


## `L.gd` 본문 (§7.2) — 모드와 무관하게 같다(deprecated 도 남겨 코드가 컴파일되게).
static func l_gd(l) -> String:
	var cfg: Config = l.config
	var by_alias: Dictionary = {}
	for e in l.catalog.all_entries:
		var alias: String = String(e["alias"])
		if alias.is_empty() or by_alias.has(alias) or cfg.is_data_alias(alias):
			continue
		by_alias[alias] = e
	var aliases: Array = by_alias.keys()
	aliases.sort()
	var quoted_locales := PackedStringArray()
	for loc in cfg.locales:
		quoted_locales.append("\"%s\"" % loc.c_escape())
	var out := PackedStringArray([
		HEADER_LINE,
		"class_name L",
		"extends RefCounted",
		"",
		"const SOURCE_LOCALE := \"%s\"" % cfg.source_locale.c_escape(),
		"const FALLBACK_LOCALE := \"%s\"" % cfg.fallback_locale.c_escape(),
		"const LOCALES: PackedStringArray = [%s]" % ", ".join(quoted_locales),
		"",
	])
	var used: Dictionary = {}
	for c in RESERVED_CONSTS:
		used[c] = true
	for alias in aliases:
		var cname: String = Config.const_name(alias)
		# 이름 충돌은 validator 의 E013 — 여기서는 첫 것만 남기고 넘어간다.
		if used.has(cname):
			continue
		used[cname] = true
		var e: Dictionary = by_alias[alias]
		if e["status"] == Catalog.STATUS_DEPRECATED:
			out.append("## @deprecated")
		out.append("const %s := \"%s\"" % [cname, String(e["key"]).c_escape()])
	return "\n".join(out) + "\n"


## `refs.json` 본문 (D4) — key 정렬, 탭 들여쓰기, 끝 줄바꿈.
static func refs_json(l) -> String:
	var refs: Dictionary = l.resolve_refs()
	if refs.is_empty():
		return "{}\n"
	return JSON.stringify(refs, "\t", true) + "\n"


## `internationalization/locale/translations` 에 생성 번역 리소스를 등록하고 fallback 을
## 맞춘다. 다른 항목은 그대로 두고, gen 폴더의 `strings_*.translation` 중 지금 로케일에
## 없는 것은 뺀다. 바뀐 것이 있을 때만 저장한다.
static func register_project_settings(cfg: Config) -> String:
	var cur := PackedStringArray()
	if ProjectSettings.has_setting(SETTING_TRANSLATIONS):
		cur = PackedStringArray(ProjectSettings.get_setting(SETTING_TRANSLATIONS))
	var want := PackedStringArray()
	for loc in cfg.locales:
		want.append(translation_path(cfg, loc))
	var gen_prefix: String = cfg.gen_dir.path_join("strings_")
	var next := PackedStringArray()
	for p in cur:
		if p.begins_with(gen_prefix) and p.ends_with(".translation") and not want.has(p):
			continue
		next.append(p)
	for p in want:
		if not next.has(p):
			next.append(p)
	var changed: bool = false
	if next != cur:
		ProjectSettings.set_setting(SETTING_TRANSLATIONS, next)
		changed = true
	var cur_fb: String = String(ProjectSettings.get_setting(SETTING_FALLBACK, "en"))
	if not ProjectSettings.has_setting(SETTING_FALLBACK) or cur_fb != cfg.fallback_locale:
		ProjectSettings.set_setting(SETTING_FALLBACK, cfg.fallback_locale)
		changed = true
	if not changed:
		return ""
	var err: Error = ProjectSettings.save()
	return "" if err == OK else "project.godot 저장 실패 (%s)" % error_string(err)


# 돌려주는 값: 1 = 썼다, 0 = 내용이 같아 건너뜀, -1 = 실패.
static func _write_l(l) -> int:
	return _write_if_changed(l.config.gen_dir.path_join(L_GD), l_gd(l))


static func _write_if_changed(file_path: String, text: String) -> int:
	var data: PackedByteArray = text.to_utf8_buffer()
	if FileAccess.file_exists(file_path) and FileAccess.get_file_as_bytes(file_path) == data:
		return 0
	var f := FileAccess.open(file_path, FileAccess.WRITE)
	if f == null:
		return -1
	f.store_buffer(data)
	f.close()
	return 1


# 에디터 안이면 파일 시스템을 다시 훑게 한다 — 새 CSV 임포트 · `L` 클래스 등록.
static func _rescan_editor() -> void:
	if not Engine.is_editor_hint() or not Engine.has_singleton("EditorInterface"):
		return
	var ei: Object = Engine.get_singleton("EditorInterface")
	var efs: Object = ei.call("get_resource_filesystem")
	if efs != null:
		efs.call("scan")
