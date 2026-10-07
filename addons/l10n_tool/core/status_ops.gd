@tool
extends RefCounted

## 원본을 고치는 명령 — sync · approve · add_locale · rename_alias (설계서 §7.1 · §8 · §3.2).
## 원본 수정은 catalog(→ csv_io)만 거친다. rename_alias 는 L.gd 를 다시 쓰려고
## builder 의 `write_l_gd` 를 부른다 — 모듈 사이 호출의 유일한 예외.

const Config = preload("res://addons/l10n_tool/core/config.gd")
const Catalog = preload("res://addons/l10n_tool/core/catalog.gd")
const CsvIo = preload("res://addons/l10n_tool/core/csv_io.gd")
const Hasher = preload("res://addons/l10n_tool/core/hasher.gd")
const Builder = preload("res://addons/l10n_tool/core/builder.gd")

const LOCALE_PATTERN := "^[a-z]{2,3}(_[A-Za-z0-9]{2,8})*$"
const IDENT_CHARS := "[A-Za-z0-9_]"


## 텍스트가 있는데 `<loc>_hash` 가 빈 번역에 현재 원문 해시를 쓰고, status 가 비었으면
## draft 로 둔다. approved 인데 해시가 빈 것(수동 승인)은 건드리지 않는다 — E031 로 남겨
## `approve` 를 거치게 한다. 돌려주는 값: 갱신한 번역 수.
static func sync(l) -> int:
	var cat: Catalog = l.catalog
	var n: int = 0
	for e in cat.all_entries:
		var t: CsvIo = cat.tables.get(e["domain"], null)
		if t == null:
			continue
		var r: int = int(e["row"])
		for loc in cat.config.target_locales():
			var tr_d: Dictionary = (e["tr"] as Dictionary).get(loc, {})
			if String(tr_d.get("text", "")).is_empty() or not String(tr_d.get("hash", "")).is_empty():
				continue
			var st: String = String(tr_d.get("status", ""))
			if st == Catalog.TR_APPROVED:
				continue
			t.set_cell(r, loc + "_hash", Hasher.hash_text(String(e["source"])))
			if st.is_empty():
				t.set_cell(r, loc + "_status", Catalog.TR_DRAFT)
			n += 1
	if n > 0:
		var err: String = cat.save_all()
		if err != "":
			l.info("sync 저장 실패: " + err)
		cat.reload()
	return n


## `<loc>_status=approved`, `<loc>_hash=hash(현재 원문)`. 하나라도 문제가 있으면 아무것도
## 바꾸지 않는다. **오너 지시 시에만** (CLI 정책).
static func approve(l, locale: String, keys_or_aliases: PackedStringArray) -> String:
	var cat: Catalog = l.catalog
	if not cat.config.target_locales().has(locale):
		return "번역 로케일이 아님: %s" % locale
	if keys_or_aliases.is_empty():
		return "대상 key 가 없음"
	var keys := PackedStringArray()
	var errs := PackedStringArray()
	for ka in keys_or_aliases:
		var key: String = l.resolve_key(ka)
		if key.is_empty():
			errs.append("없는 key/alias: %s" % ka)
		elif cat.text(key, locale).is_empty():
			errs.append("%s 번역이 비어 있음: %s" % [locale, ka])
		elif not keys.has(key):
			keys.append(key)
	if not errs.is_empty():
		return "; ".join(errs)
	for key in keys:
		cat.set_field(key, locale + "_status", Catalog.TR_APPROVED)
		cat.set_field(key, locale + "_hash", Hasher.hash_text(cat.source_text(key)))
	return cat.save_all()


## 모든 도메인 파일 끝에 `<loc>` · `<loc>_status` · `<loc>_hash` 컬럼을 붙이고 config 에 추가.
static func add_locale(l, locale: String) -> String:
	var cat: Catalog = l.catalog
	var cfg: Config = l.config
	if RegEx.create_from_string(LOCALE_PATTERN).search(locale) == null:
		return "로케일 코드 형식 위반: %s" % locale
	if cfg.locales.has(locale):
		return "이미 있는 로케일: %s" % locale
	var domains: PackedStringArray = cat.domains()
	for d in domains:
		var lock: String = Catalog.excel_lock_for((cat.tables[d] as CsvIo).path)
		if lock != "":
			return "Excel 잠금 파일이 있다 — 파일을 닫고 다시: %s" % lock
		if not (cat.tables[d] as CsvIo).ok():
			return "읽기 오류가 있는 파일 — 먼저 고친다: %s" % (cat.tables[d] as CsvIo).path
	for d in domains:
		var t: CsvIo = cat.tables[d]
		for c in [locale, locale + "_status", locale + "_hash"]:
			t.add_column(c)
		var err: String = t.save()
		if err != "":
			return err
	var locs: PackedStringArray = cfg.locales.duplicate()
	locs.append(locale)
	cfg.locales = locs
	var cerr: String = cfg.save()
	cat.reload()
	return cerr


## alias 를 바꾸고(key 는 그대로) L.gd 를 다시 쓴 뒤, 스캔 루트의 `.gd` 에서
## `L.<OLD>` 를 `L.<NEW>` 로 바꾼다(단어 단위). 데이터 alias 는 바꿀 수 없다.
static func rename_alias(l, old_alias: String, new_alias: String) -> String:
	var cat: Catalog = l.catalog
	var cfg: Config = l.config
	var key: String = cat.key_of_alias(old_alias)
	if key.is_empty():
		return "없는 alias: %s" % old_alias
	if old_alias == new_alias:
		return "같은 alias"
	if cfg.is_data_alias(old_alias) or cfg.is_data_alias(new_alias):
		return "데이터 테이블 alias 는 바꿀 수 없음 (data_columns 규칙이 정한다): %s → %s" % [old_alias, new_alias]
	var domain: String = String(cat.entry(key)["domain"])
	if not Catalog.is_valid_alias(new_alias, domain):
		return "alias 형식 위반 또는 첫 세그먼트 ≠ domain: %s (domain=%s)" % [new_alias, domain]
	if cat.by_alias.has(new_alias):
		return "이미 있는 alias: %s (%s)" % [new_alias, cat.by_alias[new_alias]]
	var new_const: String = Config.const_name(new_alias)
	if Builder.RESERVED_CONSTS.has(new_const):
		return "예약된 L 상수 이름: %s" % new_const
	for a in cat.by_alias.keys():
		if a != old_alias and Config.const_name(a) == new_const and not cfg.is_data_alias(a):
			return "L 상수 이름 충돌: %s (%s)" % [new_const, a]
	var lock: String = Catalog.excel_lock_for(cfg.domain_path(domain))
	if lock != "":
		return "Excel 잠금 파일이 있다 — 파일을 닫고 다시: %s" % lock
	var err: String = cat.set_field(key, "alias", new_alias)
	if err == "":
		err = cat.save_all()
	if err != "":
		return err
	cat.reload()
	err = Builder.write_l_gd(l)
	if err != "":
		return err
	var res: Dictionary = replace_const_in_code(cfg, Config.const_name(old_alias), new_const)
	l.info("rename_alias: 코드 %d개 파일 · %d곳 치환" % [int(res["files"]), int(res["count"])])
	return String(res["error"])


## 스캔 루트의 `.gd` 에서 `L.<old>` → `L.<new>` (앞뒤가 식별자 글자가 아닐 때만).
## 돌려주는 값 {files, count, error}.
static func replace_const_in_code(cfg: Config, old_const: String, new_const: String) -> Dictionary:
	var re := RegEx.create_from_string("(?<!%s)L\\.%s(?!%s)" % [IDENT_CHARS, old_const, IDENT_CHARS])
	var excludes := PackedStringArray([_dir_slash(cfg.gen_dir)])
	for x in cfg.scan_list("exclude_dirs"):
		excludes.append(_dir_slash(_resolve(cfg, String(x))))
	var files := PackedStringArray()
	for root in cfg.scan_list("roots"):
		_collect_gd(_resolve(cfg, String(root)), excludes, files)
	var out: Dictionary = {"files": 0, "count": 0, "error": ""}
	var errs := PackedStringArray()
	for p in files:
		var src: String = FileAccess.get_file_as_string(p)
		var hits: int = re.search_all(src).size()
		if hits == 0:
			continue
		var f := FileAccess.open(p, FileAccess.WRITE)
		if f == null:
			errs.append("쓰기 실패: %s" % p)
			continue
		f.store_string(re.sub(src, "L." + new_const, true))
		f.close()
		out["files"] = int(out["files"]) + 1
		out["count"] = int(out["count"]) + hits
	out["error"] = "\n".join(errs)
	return out


static func _resolve(cfg: Config, p: String) -> String:
	return p if p.contains("://") else cfg.base_dir.path_join(p)


static func _dir_slash(p: String) -> String:
	return p if p.ends_with("/") else p + "/"


static func _collect_gd(dir_path: String, excludes: PackedStringArray, into: PackedStringArray) -> void:
	var d: String = _dir_slash(dir_path)
	for x in excludes:
		if d.begins_with(x):
			return
	if not DirAccess.dir_exists_absolute(dir_path):
		return
	for fn in DirAccess.get_files_at(dir_path):
		if fn.ends_with(".gd"):
			into.append(d + fn)
	for sub in DirAccess.get_directories_at(dir_path):
		if sub.begins_with("."):
			continue
		_collect_gd(d + sub, excludes, into)
