extends SceneTree

# 헤드리스 진입점:
#   godot --headless --path . --script res://addons/l10n_tool/cli.gd -- build dev
# 인자는 `--` 뒤(OS.get_cmdline_user_args). 종료 코드 0 = 성공.

const L10n = preload("res://addons/l10n_tool/core/l10n.gd")


func _initialize() -> void:
	quit(L10n.run_cli(OS.get_cmdline_user_args()))
