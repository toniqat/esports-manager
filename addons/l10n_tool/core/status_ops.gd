@tool
extends RefCounted

## 원본을 고치는 명령 — sync · approve · add_locale · rename_alias · new_keys (설계서 §7.1 · §8 · §3.2).
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


## `new_keys` — key 일괄 발급. items = [{domain, alias, <원문 로케일>, context?, max_len?, note?,
## <번역 로케일>?…}]. 먼저 전부 검사하고(alias 형식 · 첫 세그먼트 = domain · L 상수 충돌 ·
## 알 수 없는 필드 · 빈 원문 · Excel 잠금) 하나라도 틀리면 아무것도 바꾸지 않는다.
## 이미 있는 alias(원본 또는 같은 묶음 안)는 원문이 같으면 그 key 를 그대로 쓰고("reused",
## 그 행은 건드리지 않는다) 다르면 오류. 새 행은 `<domain>.csv` 끝에(없으면 표준 헤더로 만든다),
## 번역은 draft + 현재 원문 해시(set_tr 와 같다).
## 돌려주는 값 {error, results: [{alias, key, domain, status: "new" | "reused"}]} — 입력 순서.
static func new_keys(l, items: Array) -> Dictionary:
	var cat: Catalog = l.catalog
	var cfg: Config = l.config
	var src_loc: String = cfg.source_locale
	var allowed: Dictionary = {"domain": true, "alias": true, "context": true, "max_len": true, "note": true, src_loc: true}
	for loc in cfg.target_locales():
		allowed[loc] = true
	var re_domain := RegEx.create_from_string("^[a-z][a-z0-9_]*$")
	var consts: Dictionary = cat.const_map()
	var planned: Dictionary = {}     # 새 alias → 원문 (묶음 안)
	var errs := PackedStringArray()
	var domains: Dictionary = {}
	var plan: Array = []             # [item, status]
	for i in items.size():
		var where: String = "#%d" % i
		if typeof(items[i]) != TYPE_DICTIONARY:
			errs.append("%s: 객체가 아님" % where)
			continue
		var it: Dictionary = items[i]
		var domain: String = String(it.get("domain", ""))
		var alias: String = String(it.get("alias", ""))
		var src: String = _field(it, src_loc)
		where = "#%d %s" % [i, alias]
		for k in it.keys():
			if not allowed.has(String(k)):
				errs.append("%s: 알 수 없는 필드 '%s' (원문은 \"%s\")" % [where, k, src_loc])
		if re_domain.search(domain) == null:
			errs.append("%s: domain 형식 위반 '%s'" % [where, domain])
			continue
		if not Catalog.is_valid_alias(alias, domain):
			errs.append("%s: alias 형식 위반 또는 첫 세그먼트 ≠ domain (domain=%s)" % [where, domain])
			continue
		if src.strip_edges().is_empty():
			errs.append("%s: 원문(%s)이 비어 있음" % [where, src_loc])
			continue
		var old_key: String = cat.key_of_alias(alias)
		if old_key != "":
			if cat.source_text(old_key) != src:
				errs.append("%s: 이미 있는 alias 인데 원문이 다름 ('%s' ≠ '%s')" % [where, cat.source_text(old_key), src])
			elif String(cat.entry(old_key)["domain"]) != domain:
				errs.append("%s: 이미 있는 alias 가 다른 도메인 파일에 있음 (%s)" % [where, cat.entry(old_key)["domain"]])
			plan.append([it, "reused"])
			continue
		if planned.has(alias):
			if String(planned[alias]) != src:
				errs.append("%s: 묶음 안에서 같은 alias 의 원문이 다름" % where)
			plan.append([it, "reused"])
			continue
		if not cfg.is_data_alias(alias):
			var cn: String = Config.const_name(alias)
			if consts.has(cn):
				errs.append("%s: L 상수 이름 충돌 %s (%s)" % [where, cn, consts[cn] if consts[cn] != "" else "예약"])
				continue
			consts[cn] = alias
		planned[alias] = src
		domains[domain] = true
		plan.append([it, "new"])
	for d in domains.keys():
		var lock: String = Catalog.excel_lock_for(cfg.domain_path(d))
		if lock != "":
			errs.append("Excel 잠금 파일이 있다 — 파일을 닫고 다시: %s" % lock)
		elif cat.tables.has(d) and not (cat.tables[d] as CsvIo).ok():
			errs.append("읽기 오류가 있는 파일 — 먼저 고친다: %s" % (cat.tables[d] as CsvIo).path)
	if not errs.is_empty():
		return {"error": "\n".join(errs), "results": []}
	var results: Array = []
	for pr in plan:
		var it: Dictionary = pr[0]
		var alias: String = String(it["alias"])
		var key: String = cat.key_of_alias(alias)
		var status: String = pr[1]
		if status == "new":
			var res: Dictionary = cat.add_entry(String(it["domain"]), alias, _field(it, src_loc),
					_field(it, "context"), _field(it, "max_len"), _field(it, "note"), false)
			if String(res["error"]) != "":
				cat.reload()
				return {"error": "%s: %s" % [alias, res["error"]], "results": []}
			key = res["key"]
			for loc in cfg.target_locales():
				var tv: String = _field(it, loc)
				if tv != "":
					var terr: String = cat.set_translation(key, loc, tv)
					if terr != "":
						cat.reload()
						return {"error": "%s: %s" % [alias, terr], "results": []}
		results.append({"alias": alias, "key": key, "domain": String(it["domain"]), "status": status})
	var serr: String = cat.save_all()
	if serr != "":
		cat.reload()
		return {"error": serr, "results": []}
	return {"error": "", "results": results}


# JSON 값 → 문자열 (숫자 max_len 은 정수 표기).
static func _field(it: Dictionary, k: String) -> String:
	var v: Variant = it.get(k, "")
	if typeof(v) == TYPE_FLOAT and is_equal_approx(v, roundf(v)):
		return str(int(v))
	return "" if v == null else String(v) if typeof(v) == TYPE_STRING else str(v)


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
