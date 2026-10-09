@tool
extends RefCounted

# ── Draft runtime JSON → mental_events.csv + mental_texts.csv + l10n src/mental.csv ──
# The mental events (interview · outing · incident · press · morning talk) are authored
# in the Draft project `res://narrative/` and exported by Draft as `draft-runtime` JSON
# into `res://data/draft/` (Draft runtime preset, auto-sync on save). This importer turns
# those flows into the game's tables; the game itself never reads the JSON.
#
# Flow convention (one top-level Flow per event — full text in README.md):
#   Start → Dialog*  (opening lines)  → Select (options = answers, option attr `effects`)
#         → per option: Dialog* (replies, Dialog attr `branch` ok / ng) → End
#   Event settings = attrs of the memo (Comment, attached to the first line) with `kind`:
#   kind · manager_type · stage · cond · weight. Flow name = event id. Speaker (wiki entry name) → line marker: 감독 `>`, 파트너 `&`,
#   태그 `@`, no speaker or a `!` stage line `*`, anyone else plain.
#   Translations: Draft `i18n.En` → the l10n `en` column (always written as draft).
#
# Text ids are the csv's (`<event>_L<seq>` · `_C<n>` · `_C<n>_S<seq>`) and their l10n
# aliases the data rule `mental.<event>.<id>` (lower case), so re-importing an unchanged
# event touches nothing. Texts no longer produced are removed from `src/mental.csv`.
# Keys are only issued through the l10n tool (`StatusOps.new_keys`) — never invented here.

const L10n = preload("res://addons/l10n_tool/core/l10n.gd")
const StatusOps = preload("res://addons/l10n_tool/core/status_ops.gd")

const DATA_DIR: String = "res://data/draft"
const EVENTS_CSV: String = "res://data/csv/mental_events.csv"
const TEXTS_CSV: String = "res://data/csv/mental_texts.csv"
const DOMAIN: String = "mental"
const TARGET_LOCALE: String = "en"
const DRAFT_LANG: String = "En"
## Event kinds in table order (rows are sorted by kind, then id).
## `story` / `story_sat` / `story_sun` = the afternoon visit's 이야기 (§15 D, `MentalEvents.STORY_KINDS`).
const KINDS: Array = ["interview", "outing", "incident", "press", "talk", "talk_pair",
		"story", "story_sat", "story_sun", "limit_break"]
## Wiki speaker name → line marker. No speaker = narration `*`; any other name = plain.
const SPEAKER_MARKERS: Dictionary = {"감독": ">", "파트너": "&", "태그": "@"}
const EVENT_HEADER: String = "id,kind,manager_type,stage,cond,effects,weight"
const TEXT_HEADER: String = "id,event_id,slot,choice,branch,seq,text_key"


## Parse every `draft-runtime` document of `data_dir` into events.
## → `{error: String, warnings: [String], events: [event]}`, event =
## `{id, kind, manager_type, stage, cond, weight, effects: [String],
##   texts: [{id, slot, choice, branch, seq, ko, en}]}` (texts carry their marker).
static func read_events(data_dir: String = DATA_DIR) -> Dictionary:
	var warnings: Array = []
	var flows: Dictionary = {}
	var speakers: Dictionary = {}
	var dir := DirAccess.open(data_dir)
	if dir == null:
		return {"error": "데이터 폴더를 열 수 없다: %s" % data_dir, "warnings": warnings, "events": []}
	for f in dir.get_files():
		if not f.ends_with(".json") or f.ends_with(".host-api.json"):
			continue
		var doc: Variant = JSON.parse_string(FileAccess.get_file_as_string(data_dir.path_join(f)))
		if not (doc is Dictionary) or String((doc as Dictionary).get("format", "")) != "draft-runtime":
			continue
		flows.merge((doc as Dictionary).get("flows", {}))
		speakers.merge((doc as Dictionary).get("speakers", {}))
	if flows.is_empty():
		return {"error": "draft-runtime Flow 가 없다: %s" % data_dir, "warnings": warnings, "events": []}
	var events: Array = []
	var seen: Dictionary = {}
	for fid in flows.keys():
		var ev: Dictionary = _flow_event(flows[fid], speakers, warnings)
		if ev.is_empty():
			continue
		if seen.has(ev["id"]):
			warnings.append("%s: 같은 이벤트 id 의 Flow 가 둘 — 뒤의 것을 버린다" % ev["id"])
			continue
		seen[ev["id"]] = true
		events.append(ev)
	events.sort_custom(func(a, b):
		var ka: int = KINDS.find(a["kind"]); var kb: int = KINDS.find(b["kind"])
		return ka < kb if ka != kb else String(a["id"]) < String(b["id"]))
	return {"error": "", "warnings": warnings, "events": events}


## Import: read the JSON, sync the l10n source, write both csv tables.
## `dry` = report only. → `{error, warnings, events, new, edited, removed}` (counts).
static func run(data_dir: String = DATA_DIR, dry: bool = false) -> Dictionary:
	var res: Dictionary = read_events(data_dir)
	var report: Dictionary = {"error": String(res["error"]), "warnings": res["warnings"],
			"events": (res["events"] as Array).size(), "new": 0, "edited": 0, "removed": 0}
	if report["error"] != "":
		return report
	var l: L10n = L10n.open()
	if not l.ok():
		report["error"] = "l10n 설정을 읽지 못했다"
		return report
	l.echo = false
	l.reload()
	var cat = l.catalog

	# Texts → aliases.
	var wanted: Dictionary = {}       # alias → {ko, en, id}
	for ev in res["events"]:
		for t in (ev as Dictionary)["texts"]:
			wanted[_alias(String(ev["id"]), String(t["id"]))] = t
	var new_items: Array = []
	var edits: Array = []
	for alias in wanted.keys():
		var t: Dictionary = wanted[alias]
		var key: String = cat.key_of_alias(alias)
		if key == "":
			var item: Dictionary = {"domain": DOMAIN, "alias": alias, "ko": t["ko"],
					"context": "mental_texts.csv text (id=%s)" % t["id"]}
			if String(t["en"]) != "":
				item[TARGET_LOCALE] = t["en"]
			new_items.append(item)
			continue
		if cat.source_text(key) != String(t["ko"]):
			edits.append({"key": key, "column": l.config.source_locale, "value": t["ko"]})
		if String(t["en"]) != "" and cat.text(key, TARGET_LOCALE) != String(t["en"]):
			edits.append({"key": key, "column": TARGET_LOCALE, "value": t["en"]})
	var removed: Array = []
	for alias in cat.by_alias.keys():
		var a: String = String(alias)
		if a.begins_with(DOMAIN + ".") and a.get_slice_count(".") == 3 and l.config.is_data_alias(a) \
				and not wanted.has(a):
			removed.append(cat.key_of_alias(a))
	report["new"] = new_items.size()
	report["edited"] = edits.size()
	report["removed"] = removed.size()
	if dry:
		return report

	if not new_items.is_empty():
		var nk: Dictionary = StatusOps.new_keys(l, new_items)
		if String(nk["error"]) != "":
			report["error"] = "new_keys: " + String(nk["error"])
			return report
	if not edits.is_empty():
		var err: String = l.cmd_edit(edits)
		if err != "":
			report["error"] = "edit: " + err
			return report
	for key in removed:
		var rerr: String = l.cmd_remove_key(String(key))
		if rerr != "":
			report["error"] = "remove_key: " + rerr
			return report
	l.reload()
	cat = l.catalog

	# Tables (text_key = the l10n key of each text).
	var ev_lines: PackedStringArray = PackedStringArray([EVENT_HEADER])
	var tx_lines: PackedStringArray = PackedStringArray([TEXT_HEADER])
	for ev_raw in res["events"]:
		var ev: Dictionary = ev_raw
		ev_lines.append(",".join(PackedStringArray([ev["id"], ev["kind"], str(ev["manager_type"]),
				str(ev["stage"]), _csv(ev["cond"]), _csv("|".join(PackedStringArray(ev["effects"]))),
				str(ev["weight"])])))
		for t_raw in ev["texts"]:
			var t: Dictionary = t_raw
			var key: String = cat.key_of_alias(_alias(String(ev["id"]), String(t["id"])))
			if key == "":
				report["error"] = "key 를 찾지 못했다: %s" % t["id"]
				return report
			tx_lines.append(",".join(PackedStringArray([t["id"], ev["id"], t["slot"],
					"" if t["slot"] == "line" else str(t["choice"]), t["branch"], str(t["seq"]), key])))
	var werr: String = _write(EVENTS_CSV, "\n".join(ev_lines) + "\n")
	if werr == "":
		werr = _write(TEXTS_CSV, "\n".join(tx_lines) + "\n")
	report["error"] = werr
	return report


# ── Flow → event ─────────────────────────────────────────────────────────────
static func _flow_event(flow: Dictionary, speakers: Dictionary, warnings: Array) -> Dictionary:
	var id: String = String(flow.get("name", "")).strip_edges()
	var nodes: Dictionary = flow.get("nodes", {})
	var where: String = id if id != "" else String(flow.get("id", "?"))
	# Event settings = the attrs of the memo (Comment) carrying `kind`, attached to the first line.
	var meta: Dictionary = {}
	for n in nodes.values():
		if String((n as Dictionary).get("type", "")) == "Comment" \
				and ((n as Dictionary).get("attrs", {}) as Dictionary).has("kind"):
			meta = (n as Dictionary)["attrs"]
			break
	if meta.is_empty():
		warnings.append("%s: kind 속성을 가진 메모(Comment)가 없다 — 이벤트가 아닌 Flow 로 보고 건너뛴다" % where)
		return {}
	var cur: Dictionary = nodes.get(String(flow.get("start", "")), {})
	if RegEx.create_from_string("^[A-Za-z0-9_]+$").search(id) == null:
		warnings.append("%s: Flow 이름(= 이벤트 id)은 영문 · 숫자 · _ 만 — 건너뛴다" % where)
		return {}
	var kind: String = String(meta.get("kind", ""))
	if not KINDS.has(kind):
		warnings.append("%s: 알 수 없는 kind '%s' — 건너뛴다" % [id, kind])
		return {}
	var ev: Dictionary = {"id": id, "kind": kind, "manager_type": int(meta.get("manager_type", -1)),
			"stage": int(meta.get("stage", 0)), "cond": String(meta.get("cond", "")),
			"weight": int(meta.get("weight", 1)), "effects": [], "texts": []}
	var texts: Array = ev["texts"]
	var seq: int = 0
	cur = nodes.get(String(cur.get("next", "")), {})
	while String(cur.get("type", "")) == "Dialog":
		for ln in _dialog_lines(cur, speakers, id, warnings):
			texts.append({"id": "%s_L%d" % [id, seq], "slot": "line", "choice": 0, "branch": "",
					"seq": seq, "ko": ln[0], "en": ln[1]})
			seq += 1
		cur = nodes.get(String(cur.get("next", "")), {})
	if String(cur.get("type", "")) != "Select":
		warnings.append("%s: 대사 다음에 Select(선택지)가 없다 — 건너뛴다" % id)
		return {}
	if seq == 0:
		warnings.append("%s: 첫 대사가 없다" % id)
	var options: Array = cur.get("options", [])
	for ci in options.size():
		var opt: Dictionary = options[ci]
		var en: String = String(((opt.get("i18n", {}) as Dictionary).get(DRAFT_LANG, {}) as Dictionary).get("text", ""))
		texts.append({"id": "%s_C%d" % [id, ci], "slot": "choice", "choice": ci, "branch": "",
				"seq": 0, "ko": String(opt.get("text", "")), "en": en})
		(ev["effects"] as Array).append(String((opt.get("attrs", {}) as Dictionary).get("effects", "")))
		var sseq: int = 0
		var n: Dictionary = nodes.get(String(opt.get("next", "")), {})
		while String(n.get("type", "")) == "Dialog":
			var branch: String = String((n.get("attrs", {}) as Dictionary).get("branch", ""))
			for ln in _dialog_lines(n, speakers, id, warnings):
				texts.append({"id": "%s_C%d_S%d" % [id, ci, sseq], "slot": "say", "choice": ci,
						"branch": branch, "seq": sseq, "ko": ln[0], "en": ln[1]})
				sseq += 1
			n = nodes.get(String(n.get("next", "")), {})
		if String(n.get("type", "")) != "End":
			warnings.append("%s: 선택지 %d 의 답 대사가 End 로 끝나지 않는다 (%s) — 그 뒤는 버린다" % [
					id, ci, String(n.get("type", "?"))])
	return ev


## `[[ko, en]]` per shown line of one Dialog, each with the speaker's marker.
static func _dialog_lines(node: Dictionary, speakers: Dictionary, id: String, warnings: Array) -> Array:
	var sp: Variant = node.get("speaker", null)
	var marker: String = "*"
	if sp != null and String(sp) != "":
		var who: String = String((speakers.get(String(sp), {}) as Dictionary).get("name", ""))
		marker = String(SPEAKER_MARKERS.get(who, ""))
	var ko: Array = _flat(node.get("lines", []), marker, id, warnings)
	var en_lines: Variant = ((node.get("i18n", {}) as Dictionary).get(DRAFT_LANG, {}) as Dictionary).get("lines", null)
	var en: Array = _flat(en_lines, marker, id, warnings) if en_lines is Array else []
	var out: Array = []
	for i in ko.size():
		out.append([ko[i], en[i] if i < en.size() and en.size() == ko.size() else ""])
	if not en.is_empty() and en.size() != ko.size():
		warnings.append("%s: 번역 줄 수가 원문과 다르다 — 그 대사의 en 은 비운다" % id)
	return out


static func _flat(lines: Array, marker: String, id: String, warnings: Array) -> Array:
	var out: Array = []
	for raw in lines:
		var ln: Dictionary = raw
		match String(ln.get("kind", "")):
			"text":
				out.append(marker + String(ln.get("text", "")).strip_edges())
			"stage":
				out.append("*" + String(ln.get("text", "")).strip_edges())
			_:
				warnings.append("%s: '#' 스크립트 줄은 게임이 쓰지 않는다 — 버린다" % id)
	return out


static func _alias(event_id: String, text_id: String) -> String:
	return "%s.%s.%s" % [DOMAIN, event_id.to_lower(), text_id.to_lower()]


static func _csv(v: Variant) -> String:
	var s: String = String(v)
	if s.contains(",") or s.contains("\"") or s.contains("\n"):
		return "\"%s\"" % s.replace("\"", "\"\"")
	return s


static func _write(path: String, text: String) -> String:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return "쓰기 실패: %s" % path
	f.store_string(text)
	f.close()
	return ""
