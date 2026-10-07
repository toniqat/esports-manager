extends RefCounted

## builder 테스트 — strings_<loc>.csv 포함 조건(§7.3) · L.gd · refs.json · 같은 내용 건너뛰기.

const TestKit = preload("res://addons/l10n_tool/tests/test_kit.gd")
const L10n = preload("res://addons/l10n_tool/core/l10n.gd")
const Builder = preload("res://addons/l10n_tool/core/builder.gd")


func _open(t: TestKit) -> L10n:
	var dir: String = t.copy_fixture("builder_basic")
	var l: L10n = L10n.open(dir.path_join("config.json"))
	l.echo = false
	t.ok(l.ok(), "open")
	return l


func _read(l: L10n, fn: String) -> String:
	return FileAccess.get_file_as_string(l.config.gen_dir.path_join(fn))


func test_dev_inclusion(t: TestKit) -> void:
	var l: L10n = _open(t)
	t.eq(Builder.build(l, "dev"), "")
	t.eq(_read(l, "strings_ko.csv"), "keys,ko\n"
		+ "tx_7KQ2M9XA4P,로켓 펀치\n"
		+ "tx_B3PZ8RW1MC,[추적] 후 [로켓 펀치]\n"
		+ "tx_J1KM2N3P4Q,조합 팁\n"
		+ "tx_Q9M2HX7ZK1,추적\n"
		+ "tx_D5MN0P1Q2R,확인\n"
		+ "tx_E6ST3V4W5X,\"{name}{i} 왔다, 반갑다\"\n"
		+ "tx_F7YZ6A7B8C,옛 문구\n"
		+ "tx_G8AB9C0D1E,바뀐 원문\n"
		+ "tx_H9CD0E1F2G,빈 번역\\n둘째 줄\n", "ko dev — deprecated 포함, 도메인 · 행 순서, 따옴표, 리터럴 \\n")
	t.eq(_read(l, "strings_en.csv"), "keys,en\n"
		+ "tx_7KQ2M9XA4P,Rocket Punch\n"
		+ "tx_B3PZ8RW1MC,[추적] 후 [로켓 펀치]\n"
		+ "tx_J1KM2N3P4Q,조합 팁\n"
		+ "tx_Q9M2HX7ZK1,Track\n"
		+ "tx_D5MN0P1Q2R,OK\n"
		+ "tx_E6ST3V4W5X,{name} arrived\n"
		+ "tx_F7YZ6A7B8C,Old\n"
		+ "tx_G8AB9C0D1E,Changed\n"
		+ "tx_H9CD0E1F2G,빈 번역\\n둘째 줄\n", "en dev — 빈 번역은 원문, stale · draft 포함")
	var raw: PackedByteArray = FileAccess.get_file_as_bytes(l.config.gen_dir.path_join("strings_en.csv"))
	t.eq(raw.slice(0, 4), "keys".to_utf8_buffer(), "BOM 없음")
	t.ok(not raw.get_string_from_utf8().contains("\r"), "LF")


func test_release_inclusion(t: TestKit) -> void:
	var l: L10n = _open(t)
	t.ok(not l.catalog.is_stale("tx_7KQ2M9XA4P", "en"), "fixture 해시 일치")
	t.eq(Builder.build(l, "release"), "")
	var ko: String = _read(l, "strings_ko.csv")
	t.ok(not ko.contains("tx_F7YZ6A7B8C"), "release 원문 — deprecated 제외")
	t.ok(ko.contains("tx_H9CD0E1F2G"), "release 원문 — active 포함")
	t.eq(_read(l, "strings_en.csv"), "keys,en\ntx_7KQ2M9XA4P,Rocket Punch\ntx_D5MN0P1Q2R,OK\n",
		"en release — approved · 비-stale 만 (draft · stale · 빈 · 미착수 · deprecated 제외)")


func test_l_gd(t: TestKit) -> void:
	var l: L10n = _open(t)
	t.eq(Builder.build(l, "dev"), "")
	var dev_l: String = _read(l, "L.gd")
	t.eq(dev_l, "# 자동 생성 파일. 직접 수정 금지. (l10n_tool build)\n"
		+ "class_name L\n"
		+ "extends RefCounted\n"
		+ "\n"
		+ "const SOURCE_LOCALE := \"ko\"\n"
		+ "const FALLBACK_LOCALE := \"en\"\n"
		+ "const LOCALES: PackedStringArray = [\"ko\", \"en\"]\n"
		+ "\n"
		+ "const CARD_COMBO_HINT := \"tx_J1KM2N3P4Q\"\n"
		+ "const KEYWORD_TRACK_NAME := \"tx_Q9M2HX7ZK1\"\n"
		+ "const UI_CONFIRM := \"tx_D5MN0P1Q2R\"\n"
		+ "const UI_EMPTY := \"tx_H9CD0E1F2G\"\n"
		+ "const UI_GREET := \"tx_E6ST3V4W5X\"\n"
		+ "## @deprecated\n"
		+ "const UI_OLD := \"tx_F7YZ6A7B8C\"\n"
		+ "const UI_STALE := \"tx_G8AB9C0D1E\"\n", "정렬 · deprecated 주석 · 데이터 alias 제외")
	t.eq(Builder.build(l, "release"), "")
	t.eq(_read(l, "L.gd"), dev_l, "release 도 같은 L.gd")
	# 생성된 L.gd 가 GDScript 로 컴파일되는지 (class_name 은 전역 등록 없이도 파싱만)
	var gd := GDScript.new()
	gd.source_code = dev_l.replace("class_name L\n", "")
	t.eq(gd.reload(), OK, "L.gd 컴파일")


func test_refs_json(t: TestKit) -> void:
	var l: L10n = _open(t)
	t.eq(Builder.build(l, "dev"), "")
	t.eq(_read(l, "refs.json"), "{\n\t\"tx_B3PZ8RW1MC\": [\n\t\t\"tx_Q9M2HX7ZK1\",\n\t\t\"tx_7KQ2M9XA4P\"\n\t]\n}\n",
		"등장 순서 · 탭 들여쓰기 · 끝 줄바꿈")


func test_unchanged_skip(t: TestKit) -> void:
	var l: L10n = _open(t)
	t.eq(Builder.build(l, "dev"), "")
	var marker_path: String = l.config.gen_dir.path_join("L.gd")
	# 같은 내용으로 다시 빌드하면 → 아무것도 쓰지 않는다
	l.output.clear()
	t.eq(Builder.build(l, "dev"), "")
	t.ok(String(l.output[l.output.size() - 1]).contains("생성물 0개"), "같은 내용 → 0개: " + str(l.output))
	# 하나를 망가뜨리면 그것만 다시 쓴다
	var f := FileAccess.open(marker_path, FileAccess.WRITE)
	f.store_string("broken")
	f.close()
	l.output.clear()
	t.eq(Builder.build(l, "dev"), "")
	t.ok(String(l.output[l.output.size() - 1]).contains("생성물 1개"), "망가진 L.gd 만: " + str(l.output))
	t.ok(FileAccess.get_file_as_string(marker_path).begins_with("# 자동 생성"), "L.gd 복구")


func test_bad_mode_and_no_project_settings(t: TestKit) -> void:
	var l: L10n = _open(t)
	t.ok(Builder.build(l, "beta") != "", "모르는 모드 거부")
	var before: Variant = ProjectSettings.get_setting(Builder.SETTING_TRANSLATIONS, PackedStringArray())
	t.eq(Builder.build(l, "dev"), "")
	t.eq(ProjectSettings.get_setting(Builder.SETTING_TRANSLATIONS, PackedStringArray()), before, "fixture 빌드는 프로젝트 설정을 안 건드린다")
	t.eq(Builder.translation_path(l.config, "en"), l.config.gen_dir.path_join("strings_en.en.translation"))
