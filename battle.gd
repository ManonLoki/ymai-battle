extends Node2D

## 对战场景：拉取当日用量 → 组一场车轮战 → 逐条事件播动画和战报。
## 所有胜负判定都在 WheelWar / CombatResolver 里，这里只负责演出。
##
## 这个场景会一直开着自动打下去，所以任何“当天”的东西都不能只在 _ready 里算一次，
## 每轮开打前都要重新取一次系统日期（见 _sync_record_to_today）。

const MAIN_SCENE := "res://main.tscn"
const FIGHTER_VIEW := preload("res://scenes/fighter_view.tscn")
## 一场打完之后隔多久自动开下一轮。拉名单失败时也按这个间隔重试。
const NEXT_ROUND_DELAY := 60.0
## 每条战报事件之间的停顿，太快看不清、太慢一场打不完。
const EVENT_BEAT := 0.12
## 返回按钮的尺寸，比主菜单的小一圈。
const BACK_BUTTON_SIZE := Vector2(120, 40)
## 战绩榜上挂奖牌的名次上限。
const MEDAL_RANKS := 3

var _war: WheelWar
var _rng: RollSource
## 本场每位挑战者对擂主的输出，用来评 MVP。
var _tally: DamageTally
## 当天的场次和榜一战绩，存在 user:// 里，退出重进接着算。
var _record: RoundRecord
var _champion_view: FighterView
var _opponent_view: FighterView
## 演出协程正在跑。测试靠它确认循环能自己收手。
var _busy := false
## 玩家中途点“返回”时场景会立刻被释放，但 _run_loop / _play_event 还挂在 await 上。
## 这个标记让所有等待点都能及时收手，不再去碰已经离开场景树的节点。
var _aborted := false
## 测试用：设成 true 就不自动开打，由测试自己喂名单。
var skip_autoload := false


func _ready() -> void:
	TvRemote.install()
	# HUD 和结果面板各自是一棵子树，字体要分别套。
	ThemeHelper.apply(%HUD.get_node("Margin") as Control, 18)
	ThemeHelper.apply(%ResultPanel, 18)
	%Backdrop.color = ThemeHelper.BG
	ThemeHelper.style_button(%BackButton, false)
	%BackButton.custom_minimum_size = BACK_BUTTON_SIZE
	%BackButton.pressed.connect(_on_back_pressed)
	%ResultPanel.visible = false
	# 结果面板压在立绘和战报上面，没有底色会糊成一片。
	var result_box := ThemeHelper.make_flat(ThemeHelper.PANEL, 14)
	result_box.content_margin_left = 24
	result_box.content_margin_right = 24
	result_box.content_margin_top = 18
	result_box.content_margin_bottom = 18
	result_box.set_border_width_all(2)
	result_box.border_color = ThemeHelper.CARD
	%ResultPanel.add_theme_stylebox_override("panel", result_box)
	%RecordPanel.add_theme_stylebox_override("panel", ThemeHelper.make_flat(ThemeHelper.PANEL, 10))
	%RecordTitle.add_theme_color_override("font_color", ThemeHelper.MUTED)
	# 先读一次当天战绩；跨天之后由 _sync_record_to_today 换成新一天的。
	_record = RoundRecord.load_for(Time.get_date_string_from_system())
	_refresh_record_board()
	# 电视上没有鼠标，“返回”必须始终可聚焦，否则演出过程中遥控器按什么都没用。
	%BackButton.focus_mode = Control.FOCUS_ALL
	%BackButton.grab_focus()
	if skip_autoload:
		return
	await _round_loop()


func _notification(what: int) -> void:
	# 电视遥控器 BACK 键。
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		_on_back_pressed()
	# 从后台切回来：可能已经跨天了。这里先把右侧战绩榜对齐到今天，
	# 否则玩家会先看到昨天的场次，要等下一轮开打才刷新。
	elif what == NOTIFICATION_APPLICATION_RESUMED and _is_live():
		_sync_record_to_today()


func _unhandled_input(event: InputEvent) -> void:
	if TvRemote.is_back(event):
		get_viewport().set_input_as_handled()
		_on_back_pressed()
	elif TvRemote.is_navigation(event):
		TvRemote.ensure_focus(%BackButton)


func _on_back_pressed() -> void:
	# 已经在走人的路上就别再切一次场景。
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
		# 这个场景会通宵开着，所以每轮开打前都要确认还是不是同一天。
		_sync_record_to_today()
		var fought := await _load_and_run()
		if not _is_live():
			return
		await _countdown(NEXT_ROUND_DELAY, "下一轮" if fought else "重试")
		if not _is_live():
			return
		_reset_for_next_round()


## 跨天之后把当天战绩换成新一天的（场次归零、榜一战绩清空），并刷新右侧榜。
##
## 名单本身不用在这里处理：_load_and_run 每轮都会重新取一次系统日期去拉接口，
## 所以榜单天然就是当天的；会“卡在昨天”的只有 _record，因为它只在 _ready 里读过一次。
func _sync_record_to_today() -> void:
	var today := Time.get_date_string_from_system()
	if _record != null and not _record.is_stale(today):
		return
	# load_for 读到的存档日期对不上就会返回一份空记录，正好是我们要的。
	_record = RoundRecord.load_for(today)
	_refresh_record_board()


## 倒计时。期间玩家随时可以按返回走人，_wait 会替我们收手。
##
## 剩余秒数按真实时钟算，而不是每跳一次减 1：应用切到后台时整个进程会被
## 系统挂起，帧不再推进，计时器跟着停摆。减法式倒计时在那种情况下会从
## 中断的地方接着走，玩家切回来还得把剩下的秒数重新等一遍。
## 盯着一个真实时间的截止点就没这问题——后台期间时间照走，切回来立刻开下一场。
func _countdown(seconds: float, what: String) -> void:
	%ResultPanel.visible = true
	var deadline := Time.get_unix_time_from_system() + seconds
	while true:
		var remaining := deadline - Time.get_unix_time_from_system()
		if remaining <= 0.0:
			break
		%NextRoundLabel.text = "%s %d 秒后开始" % [what, int(ceil(remaining))]
		# 最多睡一秒；睡过头也没关系，上面会重新按真实时间算剩余。
		if not await _wait(minf(1.0, remaining)):
			return
	%NextRoundLabel.text = ""


## 把上一场的残留清干净，准备重新拉名单。
func _reset_for_next_round() -> void:
	%ResultPanel.visible = false
	%ResultLabel.text = ""
	%MvpLabel.text = ""
	%NextRoundLabel.text = ""
	%Log.text = ""
	%RemainingLabel.text = "右侧剩余 —"
	# 上一轮可能因为报错把状态栏染红了，去掉覆盖回到默认色。
	%Status.remove_theme_color_override("font_color")
	# 两位角色的视图整个丢掉重建，省得逐项复位。
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
	# 日期每轮现取，跨天之后自动换成新一天的榜单。
	var today := Time.get_date_string_from_system()
	var ranked: Array[RankedUser] = RankingAggregator.rank_users(usage, today)
	# 一个人没法打车轮战。
	if ranked.size() < 2:
		%Status.text = "上榜人数不足，无法开战（需要至少 2 人）"
		%Status.add_theme_color_override("font_color", ThemeHelper.DANGER)
		_show_notice("上榜人数不足，无法开战（需要至少 2 人）")
		return false
	await _start_war(ranked)
	return true


## 用一份名单摆开战场并开打。
func _start_war(ranked: Array[RankedUser]) -> void:
	_rng = RollSource.new()
	_tally = DamageTally.new()
	_war = WheelWar.new()
	_war.setup(ranked, _rng)
	# 擂主固定在左边，face_left=false 表示朝右看着对手。
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
	# 正在打的这一场还没记进去，所以显示 rounds + 1。
	%RoundLabel.text = "今日第 %d 场" % maxi(1, _record.rounds + 1)
	%RecordTitle.text = "今日榜一战绩 · 共 %d 场" % _record.rounds
	for child in %RecordList.get_children():
		%RecordList.remove_child(child)
		child.free()
	var rows := _record.standings()
	# 当天第一场（或者刚跨天）时榜是空的，放一句占位。
	if rows.is_empty():
		var empty := Label.new()
		empty.text = "还没有人打完一场"
		empty.add_theme_color_override("font_color", ThemeHelper.MUTED)
		empty.add_theme_font_size_override("font_size", 15)
		%RecordList.add_child(empty)
		return
	for i in range(rows.size()):
		%RecordList.add_child(_record_row(i + 1, rows[i]))


## 战绩榜的一行：奖牌 + 名字 + 胜场。
func _record_row(rank: int, row: Dictionary) -> Control:
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 8)
	line.add_child(_medal(rank))
	var name_label := Label.new()
	name_label.text = "【%s】" % str(row.get("username", ""))
	# 名字占满中间，把胜场推到最右。
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.add_theme_color_override("font_color", _rank_color(rank))
	name_label.add_theme_font_size_override("font_size", 16)
	line.add_child(name_label)
	var wins_label := Label.new()
	wins_label.text = "%d 场" % int(row.get("wins", 0))
	wins_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	wins_label.add_theme_color_override("font_color", ThemeHelper.TEXT)
	wins_label.add_theme_font_size_override("font_size", 16)
	line.add_child(wins_label)
	return line


## 前三名用奖牌色，之后的用普通文字色。
func _rank_color(rank: int) -> Color:
	return ThemeHelper.medal_color(rank) if rank <= MEDAL_RANKS else ThemeHelper.TEXT


## 前三名的金银铜牌。用一个圆底 + 名次数字，不依赖字体里有没有奖牌字符。
func _medal(rank: int) -> Control:
	var badge := Panel.new()
	badge.custom_minimum_size = Vector2(22, 22)
	var box := StyleBoxFlat.new()
	# 圆角开到边长的一半就是正圆。
	box.set_corner_radius_all(11)
	box.bg_color = ThemeHelper.medal_color(rank) if rank <= MEDAL_RANKS else ThemeHelper.CARD
	badge.add_theme_stylebox_override("panel", box)
	# 名次数字铺满整个圆，居中显示。
	var number := Label.new()
	number.text = str(rank)
	number.set_anchors_preset(Control.PRESET_FULL_RECT)
	number.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	number.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	number.add_theme_font_size_override("font_size", 13)
	# 亮底上用深色字，暗底上用浅灰字。
	number.add_theme_color_override("font_color", ThemeHelper.BG if rank <= MEDAL_RANKS else ThemeHelper.MUTED)
	badge.add_child(number)
	return badge


## 把当前挑战者绑到右侧视图；人打完了就把右侧藏起来。
func _bind_current_opponent() -> void:
	if _war.current_opponent == null:
		_opponent_view.visible = false
		return
	# 上一位是淡出退场的，modulate 要先调回来。
	_opponent_view.modulate = Color.WHITE
	_opponent_view.bind(_war.current_opponent, true)


## 刷新剩余人数、对阵文字和两条血条。
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


## 一回合一回合推进，把每条事件播完再算下一回合。
func _run_loop() -> void:
	_busy = true
	while _is_live() and _war.outcome == WheelWar.Outcome.ONGOING:
		# simulate_turn 里可能已经换人了，先记住这回合打的是谁。
		var previous_opponent: Fighter = _war.current_opponent
		var events: Array[StrikeResult] = _war.simulate_turn(_rng)
		_tally.add_events(events)
		# 先标好连击次数，逐条播的时候文案才对。
		CombatLog.annotate(events)
		for event in events:
			await _play_event(event, _war.champion, previous_opponent)
		# 这位挑战者倒下了：等死亡动画播完再换下一位上场。
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
		if not await _wait(EVENT_BEAT):
			_busy = false
			return
	_busy = false
	if _is_live():
		_show_result()


## 播一条战报事件：先动画后文字，节奏跟着动画长度走。
func _play_event(event: StrikeResult, champion: Fighter, opponent: Fighter) -> void:
	if not _is_live():
		return
	# 擂主在左、挑战者在右；自伤时攻守是同一个视图。
	var attacker_view := _champion_view if event.attacker_is_champion else _opponent_view
	var attacker := champion if event.attacker_is_champion else opponent
	var defender_view := _opponent_view if event.attacker_is_champion else _champion_view
	var defender := opponent if event.attacker_is_champion else champion
	if event.self_hit:
		defender_view = attacker_view
		defender = attacker
	# 中毒掉血和被跳过的行动没有攻击动作，单独走一条短路径。
	if event.poison_tick or event.skipped != "":
		if event.poison_tick:
			attacker_view.play_poison_fx()
			attacker_view.set_hp(event.defender_hp_after, attacker.max_hp)
		_append_log(_event_text(event))
		if event.revived:
			attacker_view.play_idle()
			attacker_view.set_hp(event.defender_hp_after, attacker.max_hp)
		elif event.defender_died:
			attacker_view.play_death()
		return
	attacker_view.play_attack()
	# 等挥击动画挥到一半再结算挨打方，看起来才像打中了。
	if not await _wait(EVENT_BEAT):
		return
	if event.hit:
		defender_view.set_hp(event.defender_hp_after, defender.max_hp)
		if event.crit:
			defender_view.play_crit_fx()
		if event.poisoned:
			defender_view.play_poison_fx()
		# 复活 / 倒下 / 挡下 / 普通挨打，四种反应互斥。
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
	# 吸血和治疗都会回血，攻击方这边也要更新血条。
	if event.heal_amount > 0:
		attacker_view.play_heal_fx()
		attacker_view.set_hp(event.attacker_hp_after, attacker.max_hp)
	_append_log(_event_text(event))
	if is_instance_valid(attacker_view):
		await _await_oneshot(attacker_view.anim_player)
	if not _is_live():
		return
	# 打死人的那一下不要回站立，留着死亡画面。
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
	# 循环动画（待机）永远播不完，直接返回，别在这里挂死。
	if anim == null or anim.loop_mode != Animation.LOOP_NONE:
		return
	var remaining := maxf(0.0, anim.length - player.current_animation_position)
	# 除以播放速度换算成真实秒数；speed_scale 可能是 0 或负数，兜一下底。
	await _wait(remaining / maxf(0.01, absf(player.speed_scale)))


## 事件的战报文字。单独包一层是为了让测试能直接调。
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


## 一场打完：亮结果、记战绩、评 MVP。
func _show_result() -> void:
	%ResultPanel.visible = true
	%BackButton.grab_focus()
	if _war.outcome == WheelWar.Outcome.CHAMPION_DOWN:
		# 擂主倒下时场上那位就是终结者；万一是空的（不该发生）就写个通称。
		var killer := "挑战者"
		if _war.current_opponent != null:
			killer = _war.current_opponent.username
		%ResultLabel.text = "%s在经过多轮鏖战，惜败于%s" % [_war.champion.username, killer]
		%ResultLabel.add_theme_color_override("font_color", ThemeHelper.DANGER)
	else:
		%ResultLabel.text = "%s经过艰难的鏖战，终于干掉了所有的挑战者，成为了唯一神" % _war.champion.username
		%ResultLabel.add_theme_color_override("font_color", ThemeHelper.OK_GREEN)
	# 记一场并立刻落盘，中途关掉 app 也不丢。
	_record.record_round(_war.champion.username, _war.outcome == WheelWar.Outcome.ALL_OPPONENTS_DOWN)
	_record.save()
	_refresh_record_board()
	# MVP 只看挑战者对擂主的输出，跟这一场谁赢了没关系。
	var mvp_line := _tally.mvp_line()
	%MvpLabel.text = mvp_line
	%MvpLabel.add_theme_color_override("font_color", ThemeHelper.GOLD)
	_append_log(mvp_line)
	_update_hud()
