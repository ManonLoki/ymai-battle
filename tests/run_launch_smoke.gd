extends SceneTree

func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var packed_main := load("res://main.tscn") as PackedScene
	var packed_ranking := load("res://ranking.tscn") as PackedScene
	var packed_battle := load("res://battle.tscn") as PackedScene
	if packed_main == null or packed_ranking == null or packed_battle == null:
		printerr("SCENE_LOAD_FAILED")
		quit(1)
		return
	var main: Node = packed_main.instantiate()
	root.add_child(main)
	await process_frame
	if main.get_node_or_null("%RankingButton") == null or main.get_node_or_null("%BattleButton") == null:
		printerr("MAIN_MENU_CONTROLS_MISSING")
		quit(1)
		return
	if main.get_node_or_null("%QuitButton") == null:
		printerr("QUIT_BUTTON_MISSING")
		quit(1)
		return
	print("MAIN_MENU_OK")
	main.queue_free()
	await process_frame

	var ranking: Node = packed_ranking.instantiate()
	root.add_child(ranking)
	await process_frame
	if ranking.get_node_or_null("%BackButton") == null:
		printerr("RANKING_BACK_MISSING")
		quit(1)
		return
	print("RANKING_SCENE_OK")
	ranking.queue_free()
	await process_frame

	var battle: Node = packed_battle.instantiate()
	root.add_child(battle)
	await process_frame
	if battle.get_node_or_null("%BackButton") == null or battle.get_node_or_null("%ChampionSlot") == null:
		printerr("BATTLE_CONTROLS_MISSING")
		quit(1)
		return
	print("BATTLE_SCENE_OK")
	print("LAUNCH_SMOKE_PASSED")
	quit(0)
