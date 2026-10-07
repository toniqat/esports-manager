extends RefCounted

## 단언 도우미 — 실패를 모아 두고 러너가 출력한다.

const TMP_ROOT := "user://l10n_test"
const FIXTURES := "res://addons/l10n_tool/tests/fixtures"

var label: String = ""
var failures: PackedStringArray = PackedStringArray()


func ok(cond: bool, msg: String = "") -> void:
	if not cond:
		failures.append("ok 실패: " + msg)


func eq(got: Variant, want: Variant, msg: String = "") -> void:
	if typeof(got) != typeof(want) or got != want:
		failures.append("%s\n           got:  %s\n           want: %s" % [msg, var_to_str(got), var_to_str(want)])


## fixture 폴더를 임시 폴더로 통째 복사하고 그 경로(user://…)를 돌려준다.
func copy_fixture(fixture_name: String) -> String:
	var dst: String = TMP_ROOT.path_join(fixture_name + "_" + str(Time.get_ticks_usec()))
	_copy_dir(FIXTURES.path_join(fixture_name), dst)
	return dst


## 파일을 바이트 그대로 읽는다.
static func read_bytes(path: String) -> PackedByteArray:
	return FileAccess.get_file_as_bytes(path)


static func write_bytes(path: String, data: PackedByteArray) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_buffer(data)
	f.close()


func _copy_dir(src: String, dst: String) -> void:
	DirAccess.make_dir_recursive_absolute(dst)
	for fn in DirAccess.get_files_at(src):
		write_bytes(dst.path_join(fn), read_bytes(src.path_join(fn)))
	for d in DirAccess.get_directories_at(src):
		_copy_dir(src.path_join(d), dst.path_join(d))
