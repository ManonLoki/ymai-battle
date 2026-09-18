extends Node2D

## 对战场景：拉取当日用量 → 组一场车轮战 → 逐条事件播动画和战报。
## 所有胜负判定都在 WheelWar / CombatResolver 里，这里只负责演出。

const MAIN_SCENE := "res://main.tscn"
const FIGHTER_VIEW := preload("res://scenes/fighter_view.tscn")
## 一场打完之后隔多久自动开下一轮。拉名单失败时也按这个间隔重试。
const NEXT_ROUND_DELAY := 60.0

var _war: WheelWar
var _rng: RollSource
## 本场每位挑战者对擂主的输出，用来评 MVP。
var _tally: DamageTally
## 当天的场次和榜一战绩，存在 user:// 里，退出重进接着算。
var _record: RoundRecord
var _champion_view: FighterView
var _opponent_view: FighterView
var _busy := false
## 玩家中途点“返回”时场景会立刻被释放，但 _run_loop / _play_event 还挂在 await 上。
## 这个标记让所有等待点都能及时收手，不再去碰已经离开场景树的节点。
var _aborted := false
var skip_autoload := false


func _ready() -> void:
	TvRemote.install()
	ThemeHelper.apply(%HUD.get_node("Margin") as Control, 18)
	ThemeHelper.apply(%ResultPanel, 18)
	%Backdrop.color = ThemeHelper.BG
	ThemeHelper.style_button(%BackButton, false)
	%BackButton.custom_minimum_size = Vector2(120, 40)
	%BackButton.pressed.connect(_on_back_pressed)
	%ResultPanel.visible = false
	# 结果面板压在立绘和战报上面，没有底色会糊成一片。
	var result_box := ThemeHelper.make_flat(ThemeHelper.PANEL, 14)
	result_box.content_margin_left = 24
	result_box.content_margin_right = 24
	result_box.content_margin_top = 18
	result_box.content_margin_bottom = 18
	result_box.border_width_left = 2
	result_box.border_width_top = 2
	result_box.border_width_right = 2
	result_box.border_width_bottom = 2
	result_box.border_color = ThemeHelper.CARD
	%ResultPanel.add_theme_stylebox_override("panel", result_box)
	%RecordPanel.add_theme_stylebox_override("panel", ThemeHelper.make_flat(ThemeHelper.PANEL, 10))
	%RecordTitle.add_theme_color_override("font_color", ThemeHelper.MUTED)
	_record = RoundRecord.load_for(Time.get_date_string_from_system())
	_refresh_record_board()
	## 电视上没有鼠标，“返回”必须始终可聚焦，否则演出过程中遥控器按什么都没用。
	%BackButton.focus_mode = Control.FOCUS_ALL
	%BackButton.grab_focus()
	if skip_autoload:
		return
	await _round_loop()


## 电视遥控器 BACK 键。
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		_on_back_pressed()


func _unhandled_input(event: InputEvent) -> void:
	if TvRemote.is_back(event):
		get_viewport().set_input_as_handled()
		_on_back_pressed()
	elif TvRemote.is_navigation(event):
		TvRemote.ensure_focus(%BackButton)


func _on_back_pressed() -> void:
	if _aborted or not is_inside_tree():
		return
	_aborted = true
	get_tree().change_scene_to_file(MAIN_SCENE)


## 这个场景是否还在演出中。离开场景树之后 get_tree() 会是 null，
## 所以每个 await 前后都要先问一句，不能只靠 is_instance_valid。
func _is_live() -> bool:
	return not _aborted and is_instance_valid(self) and is_inside_tree()


## 带中止检查的等待。返回 false 表示场景已经没了，调用方应当直接收尾。
func _wait(seconds: float) -> bool:
	if not _is_live():
		return false
	await get_tree().create_timer(seconds).timeout
	return _is_live()


## 一轮接一轮地打下去，直到玩家点“返回”把场景换走。
## 写成循环而不是在结尾递归调用自己，是为了不让协程一层层套下去。
func _round_loop() -> void:
	while _is_live():
		var fought := await _load_and_run()
		if not _is_live():
			return
		await _countdown(NEXT_ROUND_DELAY, "下一轮" if fought else "重试")
		if not _is_live():
			return
		_reset_for_next_round()


## 倒计时。期间玩家随时可以按返回走人，_wait 会替我们收手。
func _countdown(seconds: float, what: String) -> void:
	%ResultPanel.visible = true
	var remaining := seconds
	while remaining > 0.0:
		%NextRoundLabel.text = "%s %d 秒后开始" % [what, int(ceil(remaining))]
		if not await _wait(1.0):
			return
		remaining -= 1.0
	%NextRoundLabel.text = ""


## 把上一场的残留清干净，准备重新拉名单。
func _reset_for_next_round() -> void:
	%ResultPanel.visible = false
	%ResultLabel.text = ""
	%MvpLabel.text = ""
	%NextRoundLabel.text = ""
	%Log.text = ""
	%RemainingLabel.text = "右侧剩余 —"
	%Status.remove_theme_color_override("font_color")
	for slot in [%ChampionSlot, %OpponentSlot]:
		for child in slot.get_children():
			slot.remove_child(child)
			child.queue_free()
	_champion_view = null
	_opponent_view = null
	_war = null
	_rng = null
	_tally = null


## 返回值表示这一轮有没有真的打起来：拉取失败或人数不够时是 false，
## 此时结果面板只放一句错误说明，外层照样等一分钟再试。
func _load_and_run() -> bool:
	%Status.text = "正在拉取今日对战名单…"
	var api := TokenUsageApi.new()
	add_child(api)
	var result: Dictionary = await api.fetch_usage()
	if is_instance_valid(api):
		api.queue_free()
	if not _is_live():
		return false
	if not bool(result.get("ok", false)):
		var reason := str(result.get("error", "未知错误"))
		%Status.text = "加载失败：%s" % reason
		%Status.add_theme_color_override("font_color", ThemeHelper.DANGER)
		_show_notice("拉取今日名单失败：%s" % reason)
		return false
	var data: Dictionary = result.get("data", {})
	var usage: Array = data.get("channelUsage", [])
	var today := Time.get_date_string_from_system()
	var ranked: Array[RankedUser] = RankingAggregator.rank_users(usage, today)
	if ranked.size() < 2:
		%Status.text = "上榜人数不足，无法开战（需要至少 2 人）"
		%Status.add_theme_color_override("font_color", ThemeHelper.DANGER)
		_show_notice("上榜人数不足，无法开战（需要至少 2 人）")
		return false
	await _start_war(ranked)
	return true


func _start_war(ranked: Array[RankedUser]) -> void:
	_rng = RollSource.new()
	_tally = DamageTally.new()
	_war = WheelWar.new()
	_war.setup(ranked, _rng)
	_champion_view = FIGHTER_VIEW.instantiate()
	%ChampionSlot.add_child(_champion_view)
	_opponent_view = FIGHTER_VIEW.instantiate()
	%OpponentSlot.add_child(_opponent_view)
	_champion_view.bind(_war.champion, false)
	_bind_current_opponent()
	_update_hud()
	_append_log("车轮战开始：%s（%s · %d 技能）迎战其余 %d 人" % [
		_war.champion.username,
		_war.champion.agent_buff_text(),
		_war.champion.skills.size(),
		_war.remaining_including_current(),
	])
	_append_log("战力 %s vs 其余合计 %s" % [
		ThemeHelper.compact(_war.champion.tokens),
		ThemeHelper.compact(_war.others_total_power),
	])
	await _run_loop()


## 右侧战绩榜：今天打了几场，以及每位上过榜一的玩家各赢了几场。
## 前三名挂金银铜牌，没赢过的也留在榜上（0 场），因为他确实当过榜一。
func _refresh_record_board() -> void:
	%RoundLabel.text = "今日第 %d 场" % maxi(1, _record.rounds + 1)
	%RecordTitle.text = "今日榜一战绩 · 共 %d 场" % _record.rounds
	for child in %RecordList.get_children():
		%RecordList.remove_child(child)
		child.free()
	var rows := _record.standings()
	if rows.is_empty():
		var empty := Label.new()
		empty.text = "还没有人打完一场"
		empty.add_theme_color_override("font_color", ThemeHelper.MUTED)
		empty.add_theme_font_size_override("font_size", 15)
		%RecordList.add_child(empty)
		return
	for i in range(rows.size()):
		%RecordList.add_child(_record_row(i + 1, rows[i]))


func _record_row(rank: int, row: Dictionary) -> Control:
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 8)
	line.add_child(_medal(rank))
	var name_label := Label.new()
	name_label.text = "【%s】" % str(row.get("username", ""))
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.add_theme_color_override("font_color", ThemeHelper.medal_color(rank) if rank <= 3 else ThemeHelper.TEXT)
	name_label.add_theme_font_size_override("font_size", 16)
	line.add_child(name_label)
	var wins_label := Label.new()
	wins_label.text = "%d 场" % int(row.get("wins", 0))
	wins_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	wins_label.add_theme_color_override("font_color", ThemeHelper.TEXT)
	wins_label.add_theme_font_size_override("font_size", 16)
	line.add_child(wins_label)
	return line


## 前三名的金银铜牌。用一个圆底 + 名次数字，不依赖字体里有没有奖牌字符。
func _medal(rank: int) -> Control:
	var badge := Panel.new()
	badge.custom_minimum_size = Vector2(22, 22)
	var box := StyleBoxFlat.new()
	box.corner_radius_top_left = 11
	box.corner_radius_top_right = 11
	box.corner_radius_bottom_left = 11
	box.corner_radius_bottom_right = 11
	if rank <= 3:
		box.bg_color = ThemeHelper.medal_color(rank)
	else:
		box.bg_color = ThemeHelper.CARD
	badge.add_theme_stylebox_override("panel", box)
	var number := Label.new()
	number.text = str(rank)
	number.set_anchors_preset(Control.PRESET_FULL_RECT)
	number.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	number.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	number.add_theme_font_size_override("font_size", 13)
	number.add_theme_color_override("font_color", ThemeHelper.BG if rank <= 3 else ThemeHelper.MUTED)
	badge.add_child(number)
	return badge


func _bind_current_opponent() -> void:
	if _war.current_opponent == null:
		_opponent_view.visible = false
		return
	_opponent_view.modulate = Color.WHITE
	_opponent_view.bind(_war.current_opponent, true)


func _update_hud() -> void:
	if _war == null or _war.champion == null:
		return
	%RemainingLabel.text = "右侧剩余 %d 人" % _war.remaining_including_current()
	if _war.current_opponent:
		%Status.text = "%s  VS  %s" % [_war.champion.username, _war.current_opponent.username]
	else:
		%Status.text = "战斗结束"
	if _champion_view:
		_champion_view.set_hp(_war.champion.hp, _war.champion.max_hp)
	if _opponent_view and _war.current_opponent:
		_opponent_view.set_hp(_war.current_opponent.hp, _war.current_opponent.max_hp)


func _run_loop() -> void:
	_busy = true
	while _is_live() and _war.outcome == WheelWar.Outcome.ONGOING:
		var previous_opponent: Fighter = _war.current_opponent
		var events: Array[StrikeResult] = _war.simulate_turn(_rng)
		_tally.add_events(events)
		CombatLog.annotate(events)
		for event in events:
			await _play_event(event, _war.champion, previous_opponent)
		if previous_opponent != null and not previous_opponent.is_alive():
			if is_instance_valid(_opponent_view):
				await _await_oneshot(_opponent_view.anim_player)
			if not _is_live():
				_busy = false
				return
			_bind_current_opponent()
			if _war.current_opponent:
				_append_log("下一位：%s（%s · %d 技能）" % [
					_war.current_opponent.username,
					_war.current_opponent.agent_buff_text(),
					_war.current_opponent.skills.size(),
				])
		_update_hud()
		if not await _wait(0.12):
			_busy = false
			return
	_busy = false
	if _is_live():
		_show_result()


func _play_event(event: StrikeResult, champion: Fighter, opponent: Fighter) -> void:
	if not _is_live():
		return
	var attacker_view := _champion_view if event.attacker_is_champion else _opponent_view
	var defender_view := _opponent_view if event.attacker_is_champion else _champion_view
	if event.self_hit:
		defender_view = attacker_view
	var defender := opponent if event.attacker_is_champion else champion
	if event.self_hit:
		defender = champion if event.attacker_is_champion else opponent
	if event.poison_tick or event.skipped != "":
		if event.poison_tick:
			attacker_view.play_poison_fx()
			attacker_view.set_hp(event.defender_hp_after, (champion if event.attacker_is_champion else opponent).max_hp)
		_append_log(_event_text(event))
		if event.revived:
			attacker_view.play_idle()
			attacker_view.set_hp(event.defender_hp_after, (champion if event.attacker_is_champion else opponent).max_hp)
		elif event.defender_died:
			attacker_view.play_death()
		return
	attacker_view.play_attack()
	if not await _wait(0.12):
		return
	if event.hit:
		defender_view.set_hp(event.defender_hp_after, defender.max_hp)
		if event.crit:
			defender_view.play_crit_fx()
		if event.poisoned:
			defender_view.play_poison_fx()
		if event.revived:
			defender_view.play_hurt()
			defender_view.play_idle()
		elif event.defender_died:
			defender_view.play_death()
		elif event.guarded:
			defender_view.play_idle()
		else:
			defender_view.play_hurt()
	elif event.dodged:
		defender_view.play_dodge()
	else:
		defender_view.play_idle()
	if event.heal_amount > 0:
		attacker_view.play_heal_fx()
		var attacker := champion if event.attacker_is_champion else opponent
		attacker_view.set_hp(event.attacker_hp_after, attacker.max_hp)
	_append_log(_event_text(event))
	if is_instance_valid(attacker_view):
		await _await_oneshot(attacker_view.anim_player)
	if not _is_live():
		return
	if not event.defender_died and is_instance_valid(attacker_view):
		attacker_view.play_idle()


## 等一个一次性动画播完。
##
## 这里刻意不 await animation_finished：玩家中途点“返回”时节点会离开场景树，
## AnimationPlayer 不再推进，那个信号就永远不会来，协程会一直挂着不放。
## 改成按动画剩余时长走 _wait()，既能正常等完，也能在场景没了的时候立刻收手。
func _await_oneshot(player: AnimationPlayer) -> void:
	if not is_instance_valid(player) or not player.is_playing():
		return
	var anim_name := player.current_animation
	if anim_name.is_empty() or not player.has_animation(anim_name):
		return
	var anim := player.get_animation(anim_name)
	if anim == null or anim.loop_mode != Animation.LOOP_NONE:
		return
	var remaining := maxf(0.0, anim.length - player.current_animation_position)
	await _wait(remaining / maxf(0.01, absf(player.speed_scale)))


func _event_text(event: StrikeResult) -> String:
	return CombatLog.line_for(event)


## 战报按时间正序往下排：新的一条追加到末尾。
## %Log 开了 scroll_following，追加后会自动滚到最下方，始终停在最新一条上。
func _append_log(text: String) -> void:
	if %Log.text.is_empty():
		%Log.text = text
	else:
		%Log.text += "\n" + text


## 拉取失败之类没打起来的情况，也用结果面板说明一下，
## 不然屏幕上只有一行小字，电视上离得远根本看不清。
func _show_notice(text: String) -> void:
	%ResultPanel.visible = true
	%ResultLabel.text = text
	%ResultLabel.add_theme_color_override("font_color", ThemeHelper.DANGER)
	%MvpLabel.text = ""
	%BackButton.grab_focus()


func _show_result() -> void:
	%ResultPanel.visible = true
	%BackButton.grab_focus()
	if _war.outcome == WheelWar.Outcome.CHAMPION_DOWN:
		var killer := "挑战者"
		if _war.current_opponent != null:
			killer = _war.current_opponent.username
		%ResultLabel.text = "%s在经过多轮鏖战，惜败于%s" % [_war.champion.username, killer]
		%ResultLabel.add_theme_color_override("font_color", ThemeHelper.DANGER)
	else:
		%ResultLabel.text = "%s经过艰难的鏖战，终于干掉了所有的挑战者，成为了唯一神" % _war.champion.username
		%ResultLabel.add_theme_color_override("font_color", ThemeHelper.OK_GREEN)
	_record.record_round(_war.champion.username, _war.outcome == WheelWar.Outcome.ALL_OPPONENTS_DOWN)
	_record.save()
	_refresh_record_board()
	# MVP 只看挑战者对擂主的输出，跟这一场谁赢了没关系。
	var mvp_line := _tally.mvp_line()
	%MvpLabel.text = mvp_line
	%MvpLabel.add_theme_color_override("font_color", ThemeHelper.GOLD)
	_append_log(mvp_line)
	_update_hud()
