extends SceneTree

## 启动冒烟测试。跑法：
##   Godot --headless --path . --script tests/run_launch_smoke.gd
##
## 只回答一个问题：四个场景能不能加载出来、关键控件在不在。
## 不碰网络、不打一场仗，所以几秒就跑完，适合做导出前的最后一道关。
## 任何一步不对就 printerr 一个大写标记并 quit(1)，CI 靠这个标记定位。

const TEST_BATTLE_RECORD_PATH := "user://test_launch_smoke_daily_rounds.json"


func _initialize() -> void:
	_remove_test_record()
	# 延到下一帧再跑，让引擎先把 autoload 和 class_name 装好。
	_run.call_deferred()


func _run() -> void:
	WebLaunchConfig.reset()
	# 先把三个场景都加载一遍，任何一个资源坏了在这里就会暴露。
	var packed_main := load("res://scenes/main.tscn") as PackedScene
	var packed_ranking := load("res://scenes/ranking.tscn") as PackedScene
	var packed_battle := load("res://scenes/battle.tscn") as PackedScene
	var packed_settings := load("res://scenes/settings.tscn") as PackedScene
	if packed_main == null or packed_ranking == null or packed_battle == null or packed_settings == null:
		printerr("SCENE_LOAD_FAILED")
		quit(1)
		return

	# 主菜单：四个按钮都得在，少一个电视上就有路走不通。
	var main: Node = packed_main.instantiate()
	root.add_child(main)
	# 等一帧让 _ready 跑完，唯一名节点（%）才查得到。
	await process_frame
	if main.get_node_or_null("%RankingButton") == null or main.get_node_or_null("%BattleButton") == null:
		printerr("MAIN_MENU_CONTROLS_MISSING")
		quit(1)
		return
	if main.get_node_or_null("%QuitButton") == null:
		printerr("QUIT_BUTTON_MISSING")
		quit(1)
		return
	if main.get_node_or_null("%SettingsButton") == null:
		printerr("SETTINGS_BUTTON_MISSING")
		quit(1)
		return
	print("MAIN_MENU_OK")
	main.queue_free()
	# 再等一帧，让上一个场景真的被释放掉再摆下一个。
	await process_frame

	# 排行榜：只查返回按钮。这里不等它拉接口，那是 headless 测试的事。
	var ranking: Node = packed_ranking.instantiate()
	root.add_child(ranking)
	await process_frame
	if ranking.get_node_or_null("%BackButton") == null:
		printerr("RANKING_BACK_MISSING")
		quit(1)
		return
	var ranking_backdrop := ranking.get_node_or_null("%RankingBackdrop") as TextureRect
	if ranking_backdrop == null or ranking_backdrop.texture == null or ranking.get_node_or_null("%RankingScrim") == null or ranking.get_node_or_null("%ContentPanel") == null:
		printerr("RANKING_BACKGROUND_MISSING")
		quit(1)
		return
	print("RANKING_SCENE_OK")
	ranking.queue_free()
	await process_frame

	# 对战场景：返回按钮 + 擂主站位。冒烟测试不碰网络，也不读正式战绩。
	var battle: Node = packed_battle.instantiate()
	battle.skip_autoload = true
	battle.record_path = TEST_BATTLE_RECORD_PATH
	root.add_child(battle)
	await process_frame
	if battle.get_node_or_null("%BackButton") == null or battle.get_node_or_null("%ChampionSlot") == null:
		printerr("BATTLE_CONTROLS_MISSING")
		quit(1)
		return
	var battle_backdrop := battle.get_node_or_null("%BattleBackground") as BattleParallax
	if battle_backdrop == null or battle_backdrop.texture == null or BattleParallax.BACKGROUND_PATHS.size() != 16:
		printerr("BATTLE_BACKGROUNDS_MISSING")
		quit(1)
		return
	print("BATTLE_SCENE_OK")
	battle.queue_free()
	await process_frame

	# 设置页：返回按钮 + 模式列表，少一个就没法切窗口模式了。
	var settings: Node = packed_settings.instantiate()
	root.add_child(settings)
	await process_frame
	if settings.get_node_or_null("%BackButton") == null or settings.get_node_or_null("%ModeList") == null:
		printerr("SETTINGS_CONTROLS_MISSING")
		quit(1)
		return
	# 服务器地址那一栏：下拉、增加输入和增删按钮都得在。
	if settings.get_node_or_null("%ServerSelect") == null or settings.get_node_or_null("%ServerAddInput") == null or settings.get_node_or_null("%ServerAdd") == null or settings.get_node_or_null("%ServerDelete") == null:
		printerr("SETTINGS_SERVER_CONTROLS_MISSING")
		quit(1)
		return
	print("SETTINGS_SCENE_OK")
	print("LAUNCH_SMOKE_PASSED")
	_remove_test_record()
	quit(0)


func _remove_test_record() -> void:
	if FileAccess.file_exists(TEST_BATTLE_RECORD_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_BATTLE_RECORD_PATH))
