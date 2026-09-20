extends Node

## 对战场景：拉取当日用量 → 组一场车轮战 → 逐条事件播动画和战报。
## 所有胜负判定都在 WheelWar / CombatResolver 里，这里只负责演出。
##
## 一场结束或加载失败后等待 60 秒自动再战；结果面板上的按钮同时显示倒计时，
## 玩家也可以随时点击它跳过等待。每轮开始前都会重新读取当天名单。

const MAIN_SCENE := "res://scenes/main.tscn"
## 一场打完之后隔多久自动开下一轮。拉名单失败时也按这个间隔重试。
const NEXT_ROUND_DELAY := 60.0
## 人数不够时的说明，状态栏和结果面板用的是同一句。
const SHORT_ROSTER_MSG := "上榜人数不足，无法开战（需要至少 2 人）"
## 每条战报事件之间的停顿，太快看不清、太慢一场打不完。
const TURN_BEAT := 0.15
## 挥击动画挥到一半的时刻，挨打方在这里结算才像被打中。
## 跟着 FighterView 的出手动画长度走，和上面那条战报节奏是两回事，别合成一个。
const HIT_IMPACT_DELAY := 0.15
## 反弹盾+波播完再进落地判定，比挥击冲击稍长一点。
const REFLECT_BEAT := 0.45

var _war: WheelWar
var _rng: RollSource
## 本场每位挑战者对擂主的输出，用来评 MVP。
var _tally: DamageTally
## 当天的场次和榜一战绩，存在 user:// 里，退出重进接着算。
var _record: RoundRecord
@onready var _champion_view: FighterView = %ChampionView
@onready var _opponent_view: FighterView = %OpponentView
## 演出协程正在跑。测试靠它确认循环能自己收手。
var _busy := false
## 网络加载正在进行。与 _busy 分开，保证倒计时和按钮都不会并发发出请求。
var _loading := false
## 结果面板正在等待自动再战；按钮只负责把 _replay_requested 提前置为 true，
## 真正开始下一轮始终由 _round_loop 这一条路径负责。
var _waiting_for_replay := false
var _replay_requested := false
## 玩家中途点“返回”时场景会立刻被释放，但 _run_loop / _play_event 还挂在 await 上。
## 这个标记让所有等待点都能及时收手，不再去碰已经离开场景树的节点。
var _leaving := false
## 测试用：设成 true 就不自动开打，由测试自己喂名单。
var skip_autoload := false
## 默认写正式战绩；测试会在节点进树前改到独立文件，避免污染真实 user:// 存档。
var record_path := RoundRecord.SAVE_PATH


func _ready() -> void:
	TvRemote.install()
	# 战斗曲只在这个场景；离开时由主菜单/排行/设置把金冠铃接回去。
	MusicManager.play_battle()
	# 观感全在 ui_theme.tres 和 battle.tscn 里：结果面板是不透明的 ResultPanel，
	# 底部战报和战绩榜共用半透明的 GlassLog / GlassPanel，上面的文字带深色描边。
	# 这里只接线和填数据。
	%BackButton.pressed.connect(_on_back_pressed)
	%ReplayButton.pressed.connect(_on_replay_pressed)
	# 先读一次当天战绩。_record 还是 null，所以这一句就是首次加载；
	# 之后跨天再调它，换成新一天的。
	_sync_record_to_today()
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
	# 从后台切回来：空闲或倒计时期间可以把榜对齐到今天；请求或战斗正在进行时
	# 必须保留本轮捕获的日期，不能把一场旧日战斗写进新日记录。
	elif what == NOTIFICATION_APPLICATION_RESUMED and _is_live() and not _loading and not _busy:
		_sync_record_to_today()


func _unhandled_input(event: InputEvent) -> void:
	if TvRemote.consume_back(event, self):
		_on_back_pressed()
	elif TvRemote.is_navigation(event):
		TvRemote.ensure_focus(%ReplayButton if %ResultPanel.visible else %BackButton)


func _on_back_pressed() -> void:
	# 已经在走人的路上就别再切一次场景。
	if _leaving:
		return
	_leaving = TvRemote.leave_to(self, MAIN_SCENE)


## 这个场景是否还在演出中。离开场景树之后 get_tree() 会是 null，
## 所以每个 await 前后都要先问一句，不能只靠 is_instance_valid。
func _is_live() -> bool:
	return not _leaving and is_instance_valid(self) and is_inside_tree()


## 带中止检查的等待。返回 false 表示场景已经没了，调用方应当直接收尾。
func _wait(seconds: float) -> bool:
	if not _is_live():
		return false
	await get_tree().create_timer(seconds).timeout
	return _is_live()


## 一轮接一轮地打下去，直到玩家点“返回”把场景换走。
## 按钮和倒计时都只结束等待，不直接拉接口；因此同一轮永远只有这一处会发请求。
func _round_loop() -> void:
	while _is_live():
		_loading = true
		%ReplayButton.disabled = true
		# 这个场景会通宵开着，所以每轮开打前都要确认还是不是同一天。
		_sync_record_to_today()
		var fought := await _load_and_run()
		_loading = false
		if not _is_live():
			return
		%ReplayButton.disabled = false
		%ReplayButton.grab_focus()
		await _countdown(NEXT_ROUND_DELAY, _replay_action(fought))
		if not _is_live():
			return
		%ReplayButton.disabled = true
		_reset_for_replay()


## 玩家可以在 60 秒到点前立即再战。这里只结束当前等待；_round_loop 醒来后
## 才负责清场和拉取，连点按钮也不会产生第二条请求。
func _on_replay_pressed() -> void:
	if _loading or _busy or not _waiting_for_replay or not _is_live():
		return
	_replay_requested = true


## 以真实时间截止点驱动倒计时。应用切到后台时帧会暂停，但系统时钟照走；恢复后的
## 第一帧会直接发现已经到点，不会要求玩家重新等待剩余的 60 秒。
func _countdown(seconds: float, action_text: String) -> void:
	%ResultPanel.visible = true
	_waiting_for_replay = true
	_replay_requested = false
	var deadline := Time.get_unix_time_from_system() + seconds
	var shown_seconds := -1
	while _is_live() and not _replay_requested:
		var remaining := deadline - Time.get_unix_time_from_system()
		if remaining <= 0.0:
			break
		var seconds_left := int(ceil(remaining))
		if seconds_left != shown_seconds:
			shown_seconds = seconds_left
			%ReplayButton.text = "%s（%d 秒）" % [action_text, seconds_left]
		# 每帧检查按钮标记，点击后下一帧就能进入新一轮；显示文字仍只在秒数变化时更新。
		await get_tree().process_frame
	_waiting_for_replay = false
	_replay_requested = false
	if _is_live():
		%ReplayButton.text = action_text


## 到点之后是“再战”还是“重试”：打起来了就是再战，没打起来（拉取失败等）是重试。
## 按钮和结果面板提示都问它，免得同一个词在三处各写一份。
static func _replay_action(fought: bool) -> String:
	return "再战" if fought else "重试"


## 结果面板下面那行等待提示。秒数直接从 NEXT_ROUND_DELAY 算，
## 改间隔不会留下两句对不上的文案。
static func _replay_hint(action_text: String) -> String:
	return "%d 秒后自动%s，也可立即点击按钮" % [int(NEXT_ROUND_DELAY), action_text]


## 跨天之后把当天战绩换成新一天的（场次归零、榜一战绩清空），并刷新右侧榜。
##
## 平常按系统今天同步；请求跨过午夜时，_load_and_run 会再用接口结果里的明确日期校准。
func _sync_record_to_today() -> void:
	_sync_record_to(DayClock.today())


## 把战绩对象固定到一轮名单实际使用的日期。请求可能在午夜前发出、午夜后返回；
## TokenUsageApi 返回的 date 才是这份名单真正按哪一天聚合的权威值。
func _sync_record_to(date: String) -> void:
	if date.is_empty() or (_record != null and _record.date == date):
		return
	# load_for 读到的存档日期对不上就会返回一份空记录，正好是我们要的。
	_record = RoundRecord.load_for(date, record_path)
	_refresh_record_board()


## 把上一场的残留清干净，准备自动或手动再战。
func _reset_for_replay() -> void:
	%ResultPanel.visible = false
	%ResultLabel.text = ""
	%MvpLabel.text = ""
	%ReplayHintLabel.text = ""
	%BattleLog.clear()
	%RemainingLabel.text = "右侧剩余 —"
	# 上一轮可能因为报错把状态栏染红了，去掉覆盖回到默认色。
	%MatchupLabel.remove_theme_color_override("font_color")
	# 两个固定视图留在场景树里；各自收掉动画、Tween 和本轮动态内容后隐藏。
	_champion_view.reset_view()
	_opponent_view.reset_view()
	_war = null
	_rng = null
	_tally = null


## 返回值表示这次有没有真的打起来：拉取失败或人数不够时是 false，
## 外层会据此把按钮写成“重试”，一分钟后重新拉取。
func _load_and_run() -> bool:
	%MatchupLabel.text = "正在拉取今日对战名单…"
	var result: Dictionary = await TokenUsageApi.fetch_ranking(self)
	if not _is_live():
		return false
	if not bool(result.get("ok", false)):
		var reason := str(result.get("error", "未知错误"))
		return _fail_round("加载失败：%s" % reason, "拉取今日名单失败：%s" % reason)
	# 名单日期在请求完成后才确定；先把战绩切到同一天，再开战并最终落盘。
	_sync_record_to(str(result.get("date", "")))
	var ranked: Array[RankedUser] = result.get("users", [] as Array[RankedUser])
	# 一个人没法打车轮战。
	if ranked.size() < 2:
		return _fail_round(SHORT_ROSTER_MSG, SHORT_ROSTER_MSG)
	await _start_war(ranked)
	return true


## 这一轮开不起来：顶部状态栏标红，结果面板放一句说明。
## 两个失败出口的文案不同但动作完全一样，所以只留这一份。
## 固定返回 false，调用方可以直接 `return _fail_round(...)`。
func _fail_round(status_text: String, notice_text: String) -> bool:
	%MatchupLabel.text = status_text
	%MatchupLabel.add_theme_color_override("font_color", ThemeHelper.DANGER)
	_show_notice(notice_text)
	return false


## 用一份名单摆开战场并开打。
func _start_war(ranked: Array[RankedUser]) -> void:
	# 只有名单足够、真正要开战时才算新 Round 并换背景。挑图使用 BattleParallax
	# 自己的 RandomNumberGenerator，和下面负责结算的 RollSource 完全隔离。
	%BattleBackground.roll_background()
	_rng = RollSource.new()
	_tally = DamageTally.new()
	_war = WheelWar.new()
	_war.setup(ranked, _rng)
	# 两个 FighterView 是场景内的固定实例；这里只绑定本轮动态角色数据。
	# 擂主固定在左边，face_left=false 表示朝右看着对手。
	_champion_view.bind(_war.champion, false)
	_bind_current_opponent()
	_update_hud()
	_append_log(CombatLog.opening_line(_war.champion, _war.remaining_including_current()))
	_append_log("战力 %s vs 其余合计 %s" % [
		NumberFormat.compact(_war.champion.tokens),
		NumberFormat.compact(_war.others_power),
	])
	await _run_loop()


## 右侧战绩榜：板子本身怎么画归 RecordBoard，这里只管把当天的战绩递过去。
func _refresh_record_board() -> void:
	%RoundLabel.text = RecordBoard.round_text(_record)
	%RecordTitle.text = RecordBoard.title_text(_record)
	RecordBoard.refresh(%RecordList, _record)


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
		%MatchupLabel.text = "%s  VS  %s" % [_war.champion.username, _war.current_opponent.username]
	else:
		%MatchupLabel.text = "战斗结束"
	_champion_view.set_hp(_war.champion.hp, _war.champion.max_hp)
	if _war.current_opponent:
		_opponent_view.set_hp(_war.current_opponent.hp, _war.current_opponent.max_hp)


## 一回合一回合推进，把每条事件播完再算下一回合。
func _run_loop() -> void:
	_busy = true
	await _turn_loop()
	_busy = false
	# 中途被打断时 _is_live() 已经是 false，所以结果面板照样不会弹出来。
	if _is_live():
		_show_result()


## 一回合一回合地演，直到分出胜负或者场景被换走。
## 单独拆出来是为了让 _busy 成为严格的“进函数置位、出函数复位”，
## 中途任何一个中止点都只要 return，不用记得先把标记清掉。
func _turn_loop() -> void:
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
				return
			_bind_current_opponent()
			if _war.current_opponent:
				_append_log(CombatLog.next_up_line(_war.current_opponent))
		_update_hud()
		if not await _wait(TURN_BEAT):
			return


## 播一条战报事件：先动画后文字，节奏跟着动画长度走。
## 两条路径没有交集，所以分成两个函数：没有攻击动作的（中毒掉血、被跳过的行动）
## 一帧就演完，挥击那条要等动画。
func _play_event(event: StrikeResult, champion: Fighter, opponent: Fighter) -> void:
	if not _is_live():
		return
	# 五条 one-shot 按事件字段组合；Dummy 驱动测的是点名，不是扬声器。
	CombatSfx.play_event(event)
	# 擂主在左、挑战者在右；自伤时攻守是同一个视图。
	var attacker_view := _champion_view if event.attacker_is_champion else _opponent_view
	var attacker := champion if event.attacker_is_champion else opponent
	var defender_view := _opponent_view if event.attacker_is_champion else _champion_view
	var defender := opponent if event.attacker_is_champion else champion
	if event.self_hit or event.attacker_name == event.defender_name:
		defender_view = attacker_view
		defender = attacker
	if event.poison_tick or event.skip_reason != "":
		_play_tick(event, attacker_view, attacker)
		return
	if event.reflected:
		await _play_reflect(event, defender_view)
		return
	await _play_strike(event, attacker_view, attacker, defender_view, defender)


## 没有攻击动作的一条：中毒掉血、麻痹跳过、治疗跳过。全在出手方自己身上演，
## 不用等动画，所以这条路径里一个 await 也没有。
## 状态粒子只在真正结算到身上时播。
func _play_tick(event: StrikeResult, attacker_view: FighterView, attacker: Fighter) -> void:
	if event.poison_tick:
		attacker_view.play_poison_fx()
		attacker_view.set_hp(event.defender_hp_after, attacker.max_hp)
	elif event.skip_reason == StrikeResult.SKIP_PARALYZE:
		attacker_view.play_paralyze_fx()
	elif event.skip_reason == StrikeResult.SKIP_HEAL:
		attacker_view.play_heal_fx()
		attacker_view.set_hp(event.attacker_hp_after, attacker.max_hp)
	_append_log(_event_text(event))
	if event.revived:
		attacker_view.play_rebirth_fx()
		attacker_view.play_idle()
		attacker_view.set_hp(event.defender_hp_after, attacker.max_hp)
	elif event.defender_died:
		attacker_view.play_death()


## 反弹：反弹方面前出盾，波射向被反弹方。不播挥击。
func _play_reflect(event: StrikeResult, bouncer_view: FighterView) -> void:
	bouncer_view.play_reflect_fx()
	_append_log(_event_text(event))
	await _wait(REFLECT_BEAT)


## 真正挥一下的那条：出招 → 等挥到一半 → 挨打方的反应 → 文字 → 等动画收尾。
func _play_strike(
	event: StrikeResult,
	attacker_view: FighterView,
	attacker: Fighter,
	defender_view: FighterView,
	defender: Fighter,
) -> void:
	if event.self_hit:
		attacker_view.play_confuse_fx()
	attacker_view.play_attack()
	# 等挥击动画挥到一半再结算挨打方，看起来才像打中了。
	if not await _wait(HIT_IMPACT_DELAY):
		return
	if event.hit:
		defender_view.set_hp(event.defender_hp_after, defender.max_hp)
		if event.assassinated:
			defender_view.play_assassinate_fx()
		if event.crit:
			defender_view.play_crit_fx()
		# 复活 / 倒下 / 挡下 / 普通挨打，四种反应互斥。
		if event.revived:
			defender_view.play_hurt()
			defender_view.play_rebirth_fx()
			defender_view.play_idle()
		elif event.defender_died:
			defender_view.play_death()
		elif event.guarded:
			defender_view.play_guard_fx()
			defender_view.play_idle()
		else:
			defender_view.play_hurt()
	elif event.dodged:
		# 普通闪避和凌波微步共用后退 + 重影；凌波的还击是随后那条反击事件上的斩击。
		defender_view.play_dodge()
	else:
		defender_view.play_idle()
	# 潜能激发先扣自己的血；吸血和治疗再回。攻击方血条都要跟着动。
	if event.awakened or event.heal_amount > 0:
		attacker_view.set_hp(event.attacker_hp_after, attacker.max_hp)
	if event.heal_amount > 0:
		attacker_view.play_heal_fx()
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


## 记一场并立刻落盘，中途关掉 app 也不丢，然后把右侧榜刷新到最新。
func _commit_record(champion_won: bool) -> void:
	_record.record_round(_war.champion.username, champion_won)
	_record.save(record_path)
	_refresh_record_board()


## 事件的战报文字。单独包一层是为了让测试能直接调。
func _event_text(event: StrikeResult) -> String:
	return CombatLog.line_for(event)


## 战报按时间正序往下排：新的一条追加到末尾。
## %BattleLog 开了 scroll_following，追加后会自动滚到最下方，始终停在最新一条上。
##
## 用 add_text 而不是 `%BattleLog.text += ...`：赋值 text 会把整条战报推倒重排，
## 一场十几个挑战者能攒上千行，越打到后面越卡（每行都要重新排版全部中文字形）。
## add_text 只追加这一段。代价是 text 属性不再跟着变，要读内容得用 get_parsed_text()。
func _append_log(text: String) -> void:
	if _log_text().is_empty():
		%BattleLog.add_text(text)
	else:
		%BattleLog.add_text("\n" + text)


## 当前战报全文。add_text 追加的内容不进 text 属性，统一从这里读。
func _log_text() -> String:
	return %BattleLog.get_parsed_text()


## 拉取失败之类没打起来的情况，也用结果面板说明一下，
## 不然屏幕上只有一行小字，电视上离得远根本看不清。
func _show_notice(text: String) -> void:
	%ResultPanel.visible = true
	%ResultLabel.text = text
	%ResultLabel.add_theme_color_override("font_color", ThemeHelper.DANGER)
	%MvpLabel.text = ""
	%ReplayHintLabel.text = _replay_hint(_replay_action(false))


## 一场打完：亮结果、记战绩、评 MVP。
func _show_result() -> void:
	%ResultPanel.visible = true
	var won := _war.champion_won()
	# 擂主倒下时场上那位就是终结者；万一是空的（不该发生）就写个通称。
	var killer := "挑战者"
	if _war.current_opponent != null:
		killer = _war.current_opponent.username
	%ResultLabel.text = CombatLog.outcome_line(_war.champion.username, killer, won)
	%ResultLabel.add_theme_color_override("font_color", ThemeHelper.OK_GREEN if won else ThemeHelper.DANGER)
	_commit_record(won)
	# MVP 只看挑战者对擂主的输出，跟这一场谁赢了没关系。
	var mvp_line := CombatLog.mvp_line(_tally.best())
	%MvpLabel.text = mvp_line
	%MvpLabel.add_theme_color_override("font_color", ThemeHelper.GOLD)
	%ReplayHintLabel.text = _replay_hint(_replay_action(true))
	_append_log(mvp_line)
	_update_hud()
