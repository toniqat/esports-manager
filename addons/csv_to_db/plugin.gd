@tool
extends EditorPlugin

# Project → Tools → Rebuild game.db 메뉴 항목만 담당하는 껍데기.
#
# 변환 로직과 스키마 정의는 전부 `csv_to_db.gd`(순수 RefCounted)에 있다 —
# EditorPlugin 은 에디터 밖에서 인스턴스화할 수 없어서, 로직이 여기 있으면
# 헤드리스(CLI)로 DB 를 다시 만들 수 없기 때문이다. 테이블/컬럼을 추가할 때는
# 이 파일이 아니라 csv_to_db.gd 의 SCHEMAS / TABLE_DEFS 를 고친다.

const CsvToDb = preload("res://addons/csv_to_db/csv_to_db.gd")


func _enter_tree() -> void:
	add_tool_menu_item("Rebuild game.db", _rebuild_db)


func _exit_tree() -> void:
	remove_tool_menu_item("Rebuild game.db")


func _rebuild_db() -> void:
	var err: String = CsvToDb.new().rebuild()
	if err != "":
		push_error(err)
