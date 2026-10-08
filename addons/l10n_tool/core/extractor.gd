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
##
## `extract scenes <domain> <경로…>` — 씬 · 리소스 고아 값 → key + 값 치환 (§14 2순위).
## `extract code [경로…]` — 코드 고아 리터럴 작업 목록 JSON 만 (§14 3순위, key 발급은 `new_keys`).
## 둘 다 고아 판정은 파사드 `l.scan_orphans()`(= scanner)를 그대로 쓴다.

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


# ── extract scenes (§14 2순위) ──────────────────────────────────────────

## paths(파일 · 폴더, 이미 res:// 로 푼 것) 아래 `.tscn` · `.tres` 에서 scanner 가 고아로
## 보는 값(orphan_scene — auto_translate_mode DISABLED · ignore_paths · E057 누수 · key ·
## 글자 없는 값은 제외)마다 key 를 발급하고 그 값 바이트만 key 로 바꾼다. 원문(ko)만 쓴다.
## alias = `<domain>.<scene>.<node>[.<prop>]` (`scene_alias_parts` 참고), context =
## `<파일 이름> <노드 경로> <prop>`. 이미 있는 alias 가 원문 · context 까지 같으면 그 key 를
## 다시 쓴다(씬만 되돌려진 경우). dry 면 계획만 출력. 오류 문자열 또는 "".
static func extract_scenes(l, domain: String, paths: PackedStringArray, dry: bool) -> String:
	var cat: Catalog = l.catalog
	if RegEx.create_from_string("^[a-z][a-z0-9_]*$").search(domain) == null:
		return "domain 형식 위반: %s" % domain
	if paths.is_empty():
		return "경로가 없음"
	var by_file: Dictionary = {}
	for o in l.scan_orphans():
		if o["kind"] != "orphan_scene" or not under_paths(String(o["file"]), paths):
			continue
		if not by_file.has(o["file"]):
			by_file[o["file"]] = []
		(by_file[o["file"]] as Array).append(o)
	var files: Array = by_file.keys()
	files.sort()
	var consts: Dictionary = cat.const_map()
	var planned: Dictionary = {}       # alias → true (이번에 새로 쓸 것)
	var plan: Array = []               # {file, start, end, line, prop, text, alias, context, key, status}
	var texts: Dictionary = {}         # file → [bom, text]
	for f in files:
		var bytes: PackedByteArray = FileAccess.get_file_as_bytes(f)
		var bom: bool = bytes.size() >= 3 and bytes[0] == 0xEF and bytes[1] == 0xBB and bytes[2] == 0xBF
		var text: String = bytes.slice(3 if bom else 0).get_string_from_utf8()
		texts[f] = [bom, text]
		var by_line: Dictionary = {}
		for sv in l.parse_scene(text):
			by_line[int(sv["line"])] = sv
		var scene: String = scene_alias_parts(String(f).get_file())
		for o in by_file[f]:
			var sv: Dictionary = by_line.get(int(o["line"]), {})
			if sv.is_empty() or String(sv["value"]) != String(o["text"]):
				l.info("  건너뜀 (스캔과 파싱 불일치): %s:%d" % [f, int(o["line"])])
				continue
			var src: String = String(sv["value"]).replace("\r\n", "\n")
			var prop: String = sv["prop"]
			var where: String = "resource"
			if sv["section"] == "node":
				where = String(sv["node_name"]) if sv["node_path"] == "." else String(sv["node_path"])
			elif sv["section"] == "sub_resource":
				where = "sub_resource " + String(sv["section_id"])
			var ctx: String = "%s %s %s" % [String(f).get_file(), where, prop]
			var picked: Array = _pick_scene_alias(cat, domain, scene, sv, src, ctx, consts, planned)
			if picked.is_empty():
				return "%s:%d: alias 를 정할 수 없음" % [f, int(sv["line"])]
			plan.append({"file": f, "start": sv["start"], "end": sv["end"], "line": sv["line"], "prop": prop,
				"text": src, "alias": picked[0], "context": ctx, "key": picked[1], "status": picked[2]})
	var n_new: int = 0
	for p in plan:
		if p["status"] == "new":
			n_new += 1
		l.info("  %s:%d %s \"%s\" → %s (%s)" % [String(p["file"]).get_file(), int(p["line"]), p["prop"],
				_clip(String(p["text"])), p["alias"], "신규" if p["status"] == "new" else "재사용 " + String(p["key"])])
	var summary: String = "extract scenes %s: 파일 %d개 · 값 %d개 (신규 %d · 재사용 %d)" % [domain, files.size(), plan.size(), n_new, plan.size() - n_new]
	if dry:
		l.info(summary + " — --dry, 아무것도 쓰지 않음")
		return ""
	if plan.is_empty():
		l.info(summary)
		return ""
	if n_new > 0:
		var lock: String = Catalog.excel_lock_for(l.config.domain_path(domain))
		if lock != "":
			return "Excel 잠금 파일이 있다 — 파일을 닫고 다시: %s" % lock
	# 도메인 파일 먼저 — 중간에 멈춰도 씬에 원본에 없는 key 가 남지 않는다.
	for p in plan:
		if p["status"] != "new":
			continue
		var res: Dictionary = cat.add_entry(domain, String(p["alias"]), String(p["text"]), String(p["context"]), "", "", false)
		if String(res["error"]) != "":
			cat.reload()
			return "%s: %s" % [p["alias"], res["error"]]
		p["key"] = res["key"]
	var serr: String = cat.save_all()
	if serr != "":
		cat.reload()
		return "도메인 파일 저장 실패 — 씬은 그대로: " + serr
	# 씬 — 뒤쪽 값부터 바꿔야 앞쪽 오프셋이 그대로다.
	plan.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return String(a["file"]) < String(b["file"]) if a["file"] != b["file"] else int(a["start"]) > int(b["start"]))
	var errs := PackedStringArray()
	var cur: String = ""
	for i in plan.size():
		var p: Dictionary = plan[i]
		var f: String = p["file"]
		var tx: String = texts[f][1]
		texts[f][1] = tx.substr(0, int(p["start"])) + String(p["key"]) + tx.substr(int(p["end"]))
		if i + 1 < plan.size() and String(plan[i + 1]["file"]) == f:
			continue
		var fa := FileAccess.open(f, FileAccess.WRITE)
		if fa == null:
			errs.append("쓰기 실패: %s" % f)
			continue
		if texts[f][0]:
			fa.store_buffer(PackedByteArray([0xEF, 0xBB, 0xBF]))
		fa.store_buffer(String(texts[f][1]).to_utf8_buffer())
		fa.close()
	l.info(summary)
	return "\n".join(errs)


## 씬 파일 이름 → alias 세그먼트. `UI_View_` · `UI_Comp_` 접두사를 떼고 snake_case
## (`UI_View_BattleHud.tscn` → `battle_hud`, `Lobby.tscn` → `lobby`).
static func scene_alias_parts(file_name: String) -> String:
	var base: String = file_name.get_basename()
	for pre in ["UI_View_", "UI_Comp_"]:
		if base.begins_with(pre):
			base = base.substr(pre.length())
			break
	return alias_segment(base, "scene")


## 이름 → alias 세그먼트 `[a-z0-9_]+` (snake_case, 그 밖 글자는 `_`, 연속 · 양끝 `_` 정리).
static func alias_segment(s: String, fallback: String) -> String:
	var low: String = s.to_snake_case().to_lower()
	var out: String = ""
	for ch in low:
		out += ch if "abcdefghijklmnopqrstuvwxyz0123456789_".contains(ch) else "_"
	while out.contains("__"):
		out = out.replace("__", "_")
	out = out.strip_edges().trim_prefix("_").trim_suffix("_")
	return out if out != "" else fallback


# 노드 값 하나의 alias → [alias, key, "new" | "reused"]. 후보 순서: 노드 이름 → 부모_노드 →
# 노드_2, 노드_3 … 이미 있는 alias 는 원문 · context 가 같을 때만 재사용, 아니면 다음 후보.
static func _pick_scene_alias(cat: Catalog, domain: String, scene: String, sv: Dictionary, src: String, ctx: String, consts: Dictionary, planned: Dictionary) -> Array:
	var node: String
	var parent: String = ""
	match String(sv["section"]):
		"node":
			node = alias_segment(String(sv["node_name"]), "node")
			var np: String = sv["node_path"]
			var cut: int = np.rfind("/")
			if cut > 0:
				parent = alias_segment(np.substr(0, cut).get_file(), "")
		"sub_resource":
			node = "sub_" + alias_segment(String(sv["section_id"]), "res")
		_:
			node = "resource"
	var suffix: String = "" if sv["prop"] == "text" else "." + alias_segment(String(sv["prop"]), "prop")
	var cands: Array = [node]
	if parent != "":
		cands.append(parent + "_" + node)
	for n in range(2, 1000):
		cands.append("%s_%d" % [node, n])
	for c in cands:
		var alias: String = "%s.%s.%s%s" % [domain, scene, c, suffix]
		if planned.has(alias):
			continue
		var old: String = cat.key_of_alias(alias)
		if old != "":
			var e: Dictionary = cat.entry(old)
			if String(e["source"]) == src and String(e["context"]) == ctx and String(e["domain"]) == domain:
				planned[alias] = true
				return [alias, old, "reused"]
			continue
		var cn: String = Config.const_name(alias)
		if consts.has(cn):
			continue
		consts[cn] = alias
		planned[alias] = true
		return [alias, "", "new"]
	return []


# ── extract code (작업 목록) ────────────────────────────────────────────

## paths 아래(비면 전체) `.gd` 고아 리터럴(orphan_code — scanner 와 같은 판정) 목록을
## out_path(JSON)에 쓴다. key 는 발급하지 않는다 — alias 는 이행하는 쪽이 정해 `new_keys`
## 로 발급한다(§14 3순위). 본문 {generated_at, paths, total, files: [{file, count, items:
## [{line, text}]}]}. 오류 문자열 또는 "".
static func extract_code(l, paths: PackedStringArray, out_path: String) -> String:
	var by_file: Dictionary = {}
	var total: int = 0
	for o in l.scan_orphans():
		if o["kind"] != "orphan_code":
			continue
		if not paths.is_empty() and not under_paths(String(o["file"]), paths):
			continue
		if not by_file.has(o["file"]):
			by_file[o["file"]] = []
		(by_file[o["file"]] as Array).append({"line": int(o["line"]), "text": o["text"]})
		total += 1
	var names: Array = by_file.keys()
	names.sort()
	var files: Array = []
	for f in names:
		var items: Array = by_file[f]
		items.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["line"]) < int(b["line"]))
		files.append({"file": f, "count": items.size(), "items": items})
		l.info("  %s: %d" % [f, items.size()])
	var body: Dictionary = {
		"generated_at": Time.get_datetime_string_from_system(true) + "Z",
		"paths": Array(paths), "total": total, "files": files,
	}
	DirAccess.make_dir_recursive_absolute(out_path.get_base_dir())
	var fa := FileAccess.open(out_path, FileAccess.WRITE)
	if fa == null:
		return "쓰기 실패: %s (%s)" % [out_path, error_string(FileAccess.get_open_error())]
	fa.store_string(JSON.stringify(body, "\t", false) + "\n")
	fa.close()
	l.info("extract code: 파일 %d개 · 고아 리터럴 %d개 → %s" % [files.size(), total, out_path])
	return ""


## file 이 paths(파일 또는 폴더) 중 하나와 같거나 그 아래인가.
static func under_paths(file: String, paths: PackedStringArray) -> bool:
	for p in paths:
		if file == p or file.begins_with(p if p.ends_with("/") else p + "/"):
			return true
	return false


static func _clip(s: String) -> String:
	var one: String = s.replace("\r", "").replace("\n", "⏎")
	return one if one.length() <= 50 else one.substr(0, 50) + "…"


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


## [[이름, [`alias` (key)…]]]: ref_aliases 대상 원문이 같은 key 가 둘 이상 (E036).
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
	md.append("참조 대상(%s)의 원문이 같아 설명문 `[이름]` 참조가 모호하다. 이름을 바꾸거나 오너가 정한다." % ", ".join(cfg.ref_aliases))
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
