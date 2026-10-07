@tool
extends RefCounted

## `extract data` — 데이터 CSV 텍스트 컬럼 → l10n key (설계서 §14 1순위, §6, D15 · D17).
##
## config.data_columns 항목마다: 대상 컬럼 = `column`(`name_key`), 원문 컬럼 =
## `source_column` 또는 `column` 에서 `_key` 를 뗀 것(`desc_key` → `desc`).
## - 원문 컬럼만 있으면: 행마다 alias 규칙으로 key 를 발급(이미 있는 alias 면 그 key
##   재사용)하고 셀을 key 로, 헤더를 대상 이름으로 바꾼다. 헤더 · 바뀐 셀만 다시 쓴다.
## - 대상 컬럼이 이미 있으면: 추출하지 않고 셀이 alias 규칙에 맞는 key 인지 검사만.
## - CSV · 컬럼이 없으면 보고하고 넘어간다.
## 저장 순서: 도메인 파일(`save_all`) → 데이터 CSV — 중간에 멈춰도 데이터 CSV 에 원본에
## 없는 key 가 남지 않는다. 쓸 파일 중 하나라도 Excel 잠금이면 아무것도 바꾸지 않는다.
## 번역은 비워 둔다. 보고서(중복 텍스트 · E036 후보) = `generated/extract_report.md`.

const Config = preload("res://addons/l10n_tool/core/config.gd")
const Catalog = preload("res://addons/l10n_tool/core/catalog.gd")
const CsvIo = preload("res://addons/l10n_tool/core/csv_io.gd")
const Refs = preload("res://addons/l10n_tool/core/refs.gd")

const REPORT_FILE := "extract_report.md"
const KEY_SUFFIX := "_key"


## csv_names 가 비면 config.data_columns 전체. 오류 문자열 또는 "".
static func extract_data(l, csv_names: PackedStringArray) -> String:
	var cfg: Config = l.config
	var cat: Catalog = l.catalog
	# rep: stats = [줄], warns = [줄], texts = 원문 → [위치]
	var rep: Dictionary = {"stats": [], "warns": [], "texts": {}}
	var by_csv: Dictionary = {}
	var csv_order: PackedStringArray = PackedStringArray()
	for dc in cfg.data_columns:
		var csv: String = String((dc as Dictionary).get("csv", ""))
		if not csv_names.is_empty() and not csv_names.has(csv):
			continue
		if not by_csv.has(csv):
			by_csv[csv] = []
			csv_order.append(csv)
		(by_csv[csv] as Array).append(dc)
	for n in csv_names:
		if not by_csv.has(n):
			(rep["warns"] as Array).append("%s: config.data_columns 에 없는 csv — 건너뜀" % n)
	# 쓸 파일(데이터 CSV · 도메인 파일)의 Excel 잠금 — 하나라도 있으면 거부 (§12.3)
	var locks: PackedStringArray = PackedStringArray()
	var seen_domains: Dictionary = {}
	for csv in csv_order:
		var lk: String = Catalog.excel_lock_for(cfg.data_csv_dir.path_join(csv))
		if lk != "" and not locks.has(lk):
			locks.append(lk)
		for dc in by_csv[csv]:
			var dom: String = String((dc as Dictionary).get("domain", ""))
			if seen_domains.has(dom):
				continue
			seen_domains[dom] = true
			lk = Catalog.excel_lock_for(cfg.domain_path(dom))
			if lk != "" and not locks.has(lk):
				locks.append(lk)
	if not locks.is_empty():
		return "Excel 잠금 파일이 있다 — 파일을 닫고 다시: " + ", ".join(locks)
	# 추출 (메모리에서만) — 실패하면 저장하지 않고 원본을 다시 읽는다
	var tables: Array = []
	for csv in csv_order:
		var p: String = cfg.data_csv_dir.path_join(csv)
		if not FileAccess.file_exists(p):
			(rep["warns"] as Array).append("%s: 파일 없음 — 건너뜀" % csv)
			continue
		var t: CsvIo = CsvIo.load_file(p)
		if not t.ok():
			for e in t.errors:
				(rep["warns"] as Array).append("%s: 읽기 오류 %s — 건너뜀 (%s)" % [csv, e["code"], e["msg"]])
			continue
		for dc in by_csv[csv]:
			var err: String = _process_column(cat, t, csv, dc, rep)
			if err != "":
				cat.reload()
				return err
		tables.append(t)
	var save_err: String = cat.save_all()
	if save_err != "":
		cat.reload()
		return "도메인 파일 저장 실패 — 데이터 CSV 는 그대로: " + save_err
	var changed: PackedStringArray = PackedStringArray()
	for t in tables:
		if not (t as CsvIo).is_dirty():
			continue
		var e2: String = (t as CsvIo).save()
		if e2 != "":
			return "데이터 CSV 저장 실패: " + e2
		changed.append((t as CsvIo).path.get_file())
	var dups: Array = _duplicates(rep["texts"])
	var e036: Array = _e036_candidates(cat)
	var rerr: String = _write_report(cfg, rep, dups, e036, changed)
	for s in rep["stats"]:
		l.info("  " + s)
	for w in rep["warns"]:
		l.info("  경고: " + w)
	l.info("extract data: 바뀐 데이터 CSV %d개 · 경고 %d · 중복 텍스트 %d · E036 후보 %d → %s"
			% [changed.size(), (rep["warns"] as Array).size(), dups.size(), e036.size(), cfg.gen_dir.path_join(REPORT_FILE)])
	if rerr != "":
		l.info("보고서 쓰기 실패: " + rerr)
	return ""


## data_columns 항목 하나. 치명 오류(alias 위반 · 중복 · 발급 실패)만 돌려주고 나머지는 rep 에.
static func _process_column(cat: Catalog, t: CsvIo, csv: String, dc: Dictionary, rep: Dictionary) -> String:
	var target: String = String(dc.get("column", ""))
	var src: String = String(dc.get("source_column", target.trim_suffix(KEY_SUFFIX)))
	var domain: String = String(dc.get("domain", ""))
	var tpl: String = String(dc.get("alias", ""))
	var id_col: String = String(dc.get("id", "id"))
	var warns: Array = rep["warns"]
	if target == "" or src == target:
		return "%s: data_columns 의 column 이 `_key` 로 끝나지 않고 source_column 도 없다: %s" % [csv, target]
	if t.has_column(target):
		if t.has_column(src):
			warns.append("%s: %s 와 %s 가 둘 다 있다 — 추출하지 않음" % [csv, src, target])
		_verify_column(cat, t, csv, target, domain, tpl, id_col, rep)
		return ""
	if not t.has_column(src):
		warns.append("%s: 컬럼 %s · %s 둘 다 없음 — 건너뜀" % [csv, src, target])
		return ""
	var n_new: int = 0
	var n_reuse: int = 0
	var n_empty: int = 0
	var seen: Dictionary = {}
	for r in t.row_count():
		var txt: String = t.get_cell(r, src)
		if txt.strip_edges().is_empty():
			t.set_cell(r, src, "")
			n_empty += 1
			continue
		var row: Dictionary = t.row_dict(r)
		var rid: String = String(row.get(id_col, ""))
		var alias: String = Config.expand_alias(tpl, row)
		if not Catalog.is_valid_alias(alias, domain):
			return "%s:%d: alias 규칙 위반 '%s' (domain=%s, %s=%s)" % [csv, t.row_lines[r], alias, domain, id_col, rid]
		if seen.has(alias):
			return "%s:%d: alias '%s' 가 %d행과 겹친다 — id 중복?" % [csv, t.row_lines[r], alias, int(seen[alias])]
		seen[alias] = t.row_lines[r]
		var key: String = cat.key_of_alias(alias)
		if key != "":
			n_reuse += 1
			var old: String = cat.source_text(key)
			if old != txt:
				warns.append("%s id=%s %s: alias %s 가 이미 있고 원문이 다르다 — 원본 유지 ('%s' ≠ '%s')" % [csv, rid, src, alias, old, txt])
		else:
			var res: Dictionary = cat.add_entry(domain, alias, txt, "%s %s (%s=%s)" % [csv, src, id_col, rid], "", "", false)
			if String(res["error"]) != "":
				return "%s id=%s: %s" % [csv, rid, res["error"]]
			key = res["key"]
			n_new += 1
		_note_text(rep, cat.source_text(key), "%s %s=%s %s (`%s`)" % [csv, id_col, rid, src, alias])
		t.set_cell(r, src, key)
	t.rename_column(src, target)
	(rep["stats"] as Array).append("%s %s → %s: 신규 %d · 재사용 %d · 빈 칸 %d" % [csv, src, target, n_new, n_reuse, n_empty])
	return ""


## 이미 이행된 컬럼 — 비어 있지 않은 셀은 alias 규칙에 맞는 기존 key 여야 한다.
static func _verify_column(cat: Catalog, t: CsvIo, csv: String, target: String, domain: String, tpl: String, id_col: String, rep: Dictionary) -> void:
	var warns: Array = rep["warns"]
	var bad: int = 0
	var good: int = 0
	for r in t.row_count():
		var key: String = t.get_cell(r, target)
		if key.is_empty():
			continue
		var row: Dictionary = t.row_dict(r)
		var rid: String = String(row.get(id_col, ""))
		var want: String = Config.expand_alias(tpl, row)
		if not cat.has_key(key):
			warns.append("%s id=%s %s: 없는 key '%s'" % [csv, rid, target, key])
			bad += 1
			continue
		var e: Dictionary = cat.entry(key)
		if String(e["alias"]) != want or String(e["domain"]) != domain:
			warns.append("%s id=%s %s: key %s 의 alias '%s' ≠ 규칙 '%s'" % [csv, rid, target, key, e["alias"], want])
			bad += 1
			continue
		good += 1
		_note_text(rep, String(e["source"]), "%s %s=%s %s (`%s`)" % [csv, id_col, rid, target, want])
	(rep["stats"] as Array).append("%s %s: 이미 이행됨 — 검사 통과 %d · 불일치 %d" % [csv, target, good, bad])


static func _note_text(rep: Dictionary, txt: String, where: String) -> void:
	var texts: Dictionary = rep["texts"]
	if not texts.has(txt):
		texts[txt] = []
	(texts[txt] as Array).append(where)


## [[원문, [위치…]]] — 두 행 이상에 나온 원문, 많이 나온 순 → 원문 순.
static func _duplicates(texts: Dictionary) -> Array:
	var out: Array = []
	for txt in texts.keys():
		if (texts[txt] as Array).size() > 1:
			out.append([txt, texts[txt]])
	out.sort_custom(func(a: Array, b: Array) -> bool:
		var na: int = (a[1] as Array).size()
		var nb: int = (b[1] as Array).size()
		return na > nb if na != nb else String(a[0]) < String(b[0]))
	return out


## [[이름, [`alias` (key)…]]] — ref_domains 의 `*.name` 원문이 같은 key 가 둘 이상 (E036).
static func _e036_candidates(cat: Catalog) -> Array:
	var idx: Dictionary = Refs.name_index(cat)
	var names: Array = idx.keys()
	names.sort()
	var out: Array = []
	for nm in names:
		var ks: Array = idx[nm]
		if ks.size() < 2:
			continue
		var items: Array = []
		for k in ks:
			items.append("`%s` (%s)" % [cat.entry(k).get("alias", ""), k])
		out.append([nm, items])
	return out


static func _write_report(cfg: Config, rep: Dictionary, dups: Array, e036: Array, changed: PackedStringArray) -> String:
	var md: PackedStringArray = PackedStringArray()
	md.append("# extract data 보고서")
	md.append("")
	md.append("`extract data` 가 매번 다시 쓴다. 설계서 §14 · D15 — 데이터 행마다 key 를 따로 두고, 묶을지는 오너가 정한다.")
	md.append("")
	md.append("## 처리")
	md.append("")
	for s in rep["stats"]:
		md.append("- " + s)
	md.append("- 바뀐 데이터 CSV: " + (", ".join(changed) if not changed.is_empty() else "없음"))
	md.append("")
	md.append("## 경고 (%d)" % (rep["warns"] as Array).size())
	md.append("")
	for w in rep["warns"]:
		md.append("- " + w)
	md.append("")
	md.append("## 중복 텍스트 (%d)" % dups.size())
	md.append("")
	md.append("같은 원문이 두 행 이상에 있다. 문맥이 같으면 하나로 묶을지 검토.")
	md.append("")
	for d in dups:
		md.append("- \"%s\" ×%d" % [d[0], (d[1] as Array).size()])
		for w in d[1]:
			md.append("  - " + String(w))
	md.append("")
	md.append("## E036 후보 (%d)" % e036.size())
	md.append("")
	md.append("참조 도메인(%s)의 `*.name` 원문이 같아 설명문 `[이름]` 참조가 모호하다. 이름을 바꾸거나 오너가 정한다." % ", ".join(PackedStringArray(cfg.ref_domains)))
	md.append("")
	for c in e036:
		md.append("- \"%s\": %s" % [c[0], ", ".join(PackedStringArray(c[1]))])
	md.append("")
	DirAccess.make_dir_recursive_absolute(cfg.gen_dir)
	var f := FileAccess.open(cfg.gen_dir.path_join(REPORT_FILE), FileAccess.WRITE)
	if f == null:
		return error_string(FileAccess.get_open_error())
	f.store_string("\n".join(md))
	f.close()
	return ""
