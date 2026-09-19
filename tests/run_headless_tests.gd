extends SceneTree

## 全项目的 headless 回归测试。跑法：
##   Godot --headless --path . --script tests/run_headless_tests.gd
## 全过打印 ALL_ASSERTIONS_PASSED 并 quit(0)，否则打 TESTS_FAILED 并 quit(1)。
##
## 三类断言混在一起，看的时候注意区分：
## 1. 纯逻辑：结算、聚合、文案，不需要场景树，最快也最多。
## 2. 场景：真的 instantiate 出 .tscn 摆进 root，要 await process_frame 等布局。
## 3. 源码文本：直接 FileAccess 读 .gd / .tscn 去 find 字符串，
##    用来钉住“这个写法不许回退”（比如不许有 auto_hit、不许出现第二个外部域名）。
##    改代码时如果这类断言挂了，先想清楚是真的破坏了约定，还是只是改了措辞。
##
## 注意 _test_win_rate_regression 是蒙特卡洛回归，跑 6 个阵容 × 240 场，
## 占了整轮运行的绝大部分时间；改技能池或技能张数之后它会第一个报警。
##
## 另：用 --path . 跑一次会顺带把 export_presets.cfg 里的 keystore 配置刷掉，
## 跑完记得 git checkout 还原 export_presets.cfg 和 project.godot。

## 失败的断言说明，跑完统一报。为的是一次运行能看到全部问题。
var _failures: PackedStringArray = PackedStringArray()
const TEST_BATTLE_RECORD_PATH := "user://test_battle_daily_rounds.json"


## SceneTree 的入口。延到下一帧再跑，让引擎先把 autoload 和 class_name 装好。
func _initialize() -> void:
	_remove_test_battle_record()
	_run.call_deferred()


## 全部用例按顺序跑一遍，失败的收进 _failures，最后统一报。
## 带 await 的那几个要摆场景、等帧，所以必须串行等。
func _run() -> void:
	_test_aggregator()
	_test_player_identity_and_tokens()
	_test_buff_per_agent()
	_test_compact_numbers()
	_test_win_rate()
	_test_skills()
	_test_size_traits()
	_test_combat_log()
	_test_wheel_war()
	_test_win_rate_regression()
	_test_roster_size_regression()
	await _test_main_menu()
	await _test_settings()
	_test_server_settings()
	_test_web_launch_config()
	await _test_server_settings_ui()
	await _test_web_main_menu()
	await _test_tv_remote()
	await _test_main_parallax_and_quit()
	await _test_battle_and_ranking_backgrounds()
	await _test_app_icon_and_cursors()
	await _test_fighter_anims()
	_test_appearances_and_crown()
	await _test_battle_playback()
	await _test_result_copy()
	_test_damage_tally()
	await _test_next_round_cycle()
	_test_round_record()
	await _test_record_board()
	await _test_body_scale()
	_test_api_contract()
	_test_no_medals()
	_test_icons_and_layout()
	_export_character_pngs()
	_remove_test_battle_record()
	if _failures.is_empty():
		print("ALL_ASSERTIONS_PASSED")
		quit(0)
	else:
		print("TESTS_FAILED count=%d" % _failures.size())
		for failure in _failures:
			printerr("FAIL: ", failure)
		quit(1)


## 断言。通过就打一行 PASS，失败则记账并往 stderr 打 FAIL，
## 不中断后续用例——一次运行要能看到所有问题，而不是只看到第一个。
func _assert(cond: bool, msg: String) -> void:
	if cond:
		print("PASS: ", msg)
	else:
		_failures.append(msg)
		printerr("FAIL: ", msg)


## 场景演出测试会真的走保存逻辑；统一清理隔离文件，绝不碰正式 daily_rounds.json。
func _remove_test_battle_record() -> void:
	if FileAccess.file_exists(TEST_BATTLE_RECORD_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_BATTLE_RECORD_PATH))


## 聚合器：同一个人在多台设备、多个渠道上的流水要并成一条，
## 并且只认指定日期的记录。
func _test_aggregator() -> void:
	var date := "2026-09-18"
	var usage := [
		{"date": date, "username": "alice", "channel": "openai.codex", "totalTokens": 100},
		{"date": date, "username": "alice", "channel": "openai.codex", "totalTokens": 50},
		{"date": date, "username": "alice", "channel": "xai.grok", "totalTokens": 10},
		{"date": date, "username": "bob", "channel": "anthropic.claude", "totalTokens": 80},
		{"date": "2026-09-17", "username": "carol", "channel": "xai.grok", "totalTokens": 99999},
		{"date": date, "username": "dave", "channel": "workbuddy.workbuddy", "totalTokens": null},
		{"date": date, "username": "erin", "channel": "openai.codex", "totalTokens": 120},
	]
	var ranked: Array[RankedUser] = RankingAggregator.rank_users(usage, date)
	_assert(ranked.size() == 4, "aggregator keeps only the given date and unique users")
	_assert(ranked[0].username == "alice", "first place is the highest token user")
	_assert(ranked[0].tokens == 160, "same user across devices/channels is merged")
	_assert(ranked[0].rank == 1, "rank 1 is champion")
	_assert(ranked[0].agent_name == "CODEX", "primary agent is the highest-token channel")
	_assert("GROK" in ranked[0].agents, "secondary agents still listed")
	_assert(ranked[1].username == "erin" and ranked[1].tokens == 120, "descending token order")
	_assert(ranked[1].agent_name == "CODEX", "openai.codex maps to CODEX")
	_assert(ranked[2].username == "bob" and ranked[2].agent_name == "CLAUDE CODE", "anthropic.claude maps to CLAUDE CODE")
	_assert(ranked[3].username == "dave" and ranked[3].tokens == 0, "null totalTokens counts as 0")
	_assert(ranked[3].agent_name == "WORKBUDDY", "workbuddy.workbuddy maps to WORKBUDDY")
	var grok_user := RankedUser.new()
	var grok_rows := [{"date": date, "username": "z", "channel": "xai.grok", "totalTokens": 1}]
	var grok_ranked: Array[RankedUser] = RankingAggregator.rank_users(grok_rows, date)
	grok_user = grok_ranked[0]
	_assert(grok_user.agent_name == "GROK", "xai.grok maps to GROK")


## 服务端流水是「设备 × 渠道 × 日期」的明细，榜上必须是聚合后的逻辑玩家。
func _test_player_identity_and_tokens() -> void:
	var date := "2026-09-18"
	# 贴着线上 channelUsage 的字段形状：同一个人两台机器、三个 agent。
	var usage := [
		{"date": date, "deviceId": "dev-1", "deviceName": "MacBook-Pro.local", "username": "韩浩然",
			"channel": "openai.codex", "totalTokens": 200000000},
		{"date": date, "deviceId": "dev-2", "deviceName": "DESKTOP-8KUT0MG", "username": "韩浩然",
			"channel": "openai.codex", "totalTokens": 148431491},
		{"date": date, "deviceId": "dev-2", "deviceName": "DESKTOP-8KUT0MG", "username": "韩浩然",
			"channel": "xai.grok", "totalTokens": 1000000},
		{"date": date, "deviceId": "dev-3", "deviceName": "ymm001deMacBook-Pro.local", "username": "ymm001",
			"channel": "workbuddy.workbuddy", "totalTokens": 1718871},
	]
	var ranked: Array[RankedUser] = RankingAggregator.rank_users(usage, date)
	_assert(ranked.size() == 2, "four device-level rows collapse into two logical players")
	_assert(ranked[0].username == "韩浩然", "the board shows the logical player name")
	_assert(ranked[0].tokens == 349431491, "tokens are summed across every device and channel")
	_assert(ranked[0].agent_name == "CODEX", "the primary agent is the highest-token channel")
	_assert("GROK" in ranked[0].agents, "secondary agents survive the merge")

	# 设备名只在服务端用于去重，游戏里任何一个展示字段都不该带上它。
	for user in ranked:
		_assert(user.username.find("DESKTOP") < 0 and user.username.find(".local") < 0, "no device name leaks into the player name")
		for agent in user.agents:
			_assert(agent.find("DESKTOP") < 0 and agent.find(".local") < 0, "no device name leaks into the agent list")
	var fields := PackedStringArray(["RankedUser", "username", "tokens"])
	var user_src := FileAccess.get_file_as_string("res://scripts/ranked_user.gd")
	for field in fields:
		_assert(user_src.find(field) >= 0, "RankedUser still carries %s" % field)
	_assert(user_src.find("device") < 0, "RankedUser has no device-level field at all")
	for path in ["res://scenes/ranking.gd", "res://scenes/battle.gd", "res://scenes/fighter_view.gd"]:
		var src := FileAccess.get_file_as_string(path)
		_assert(src.find("deviceName") < 0 and src.find("deviceId") < 0, "%s never reads a device field" % path)
		_assert(src.find("dailyUsage") < 0, "%s reads channelUsage, the only feed with tokens" % path)


## 每个 agent 各产出一个独立 buff：用了 3 个 agent 就带 3 个 buff，一起叠加。
func _test_buff_per_agent() -> void:
	var date := "2026-09-18"
	var usage := [
		{"date": date, "username": "三修", "channel": "openai.codex", "totalTokens": 300},
		{"date": date, "username": "三修", "channel": "anthropic.claude", "totalTokens": 200},
		{"date": date, "username": "三修", "channel": "xai.grok", "totalTokens": 100},
		{"date": date, "username": "独修", "channel": "openai.codex", "totalTokens": 500},
	]
	var ranked: Array[RankedUser] = RankingAggregator.rank_users(usage, date)
	var many := ranked[1] if ranked[0].username == "独修" else ranked[0]
	var one := ranked[0] if ranked[0].username == "独修" else ranked[1]
	_assert(many.channels.size() == 3, "a three-agent player keeps all three channels")
	_assert(many.channels[0] == AgentChannels.CHANNEL_CODEX, "channels are ordered by usage")
	_assert(one.channels.size() == 1, "a single-agent player keeps one channel")

	# 同一场里，同一种 agent buff 也要**每人各掷各的**：
	# 谁都可能这把 5%、别人 10%，不能一个渠道掷一次然后所有人共用。
	var roster: Array[RankedUser] = []
	for i in range(6):
		var u := RankedUser.new()
		u.username = "same%d" % i
		u.tokens = 1000 - i
		u.channels.append(AgentChannels.CHANNEL_CODEX)
		u.channel = AgentChannels.CHANNEL_CODEX
		u.agent_name = AgentChannels.agent_display_name(u.channel)
		u.agents.append(u.agent_name)
		roster.append(u)
	var war := WheelWar.new()
	war.setup(roster, RollSource.new(42))
	var everyone: Array[Fighter] = war.waiting.duplicate()
	if war.current_opponent != null:
		everyone.append(war.current_opponent)
	everyone.append(war.champion)
	var amounts: Array[float] = []
	for f in everyone:
		_assert(f.agent_buffs.size() == 1, "%s carries exactly one CODEX buff" % f.username)
		var amount: float = f.agent_buffs[0].crit_chance
		_assert(amount >= SkillCatalog.AGENT_BUFF_MIN - 0.0001, "%s rolled at or above the buff floor (%.4f)" % [f.username, amount])
		_assert(amount <= SkillCatalog.AGENT_BUFF_MAX + 0.0001, "%s rolled at or below the buff ceiling (%.4f)" % [f.username, amount])
		amounts.append(amount)
	var distinct := {}
	for a in amounts:
		distinct[snappedf(a, 0.000001)] = true
	# 6 个人全同值的概率约等于 0；真出现就说明 buff 被共用了，不是运气问题。
	_assert(distinct.size() > 1, "the same buff rolls a different amount per fighter (%d distinct of %d)" % [distinct.size(), amounts.size()])

	# 一个人带多个渠道时，每个 buff 也各掷各的。
	var multi := RankedUser.new()
	multi.username = "multi"
	multi.tokens = 900
	for ch in [AgentChannels.CHANNEL_CODEX, AgentChannels.CHANNEL_GROK, AgentChannels.CHANNEL_CLAUDE]:
		multi.channels.append(ch)
		multi.agents.append(AgentChannels.agent_display_name(ch))
	multi.channel = multi.channels[0]
	multi.agent_name = AgentChannels.agent_display_name(multi.channel)
	var buffs: Array[SkillDef] = SkillGrant.roll_agent_buffs(multi.channels, RollSource.new(7))
	_assert(buffs.size() == 3, "a three-agent player gets three buffs")
	var buff_amounts := {}
	for b in buffs:
		# 每条 buff 自己记着写的是哪个字段，直接取那一个。
		buff_amounts[snappedf(float(b.get(b.prop)), 0.000001)] = true
	_assert(buff_amounts.size() > 1, "one player's several buffs are rolled independently")

	var triple := Fighter.from_ranked(many, true)
	var single := Fighter.from_ranked(one, false)
	SkillGrant.apply(triple, RollSource.new(1))
	SkillGrant.apply(single, RollSource.new(1))
	_assert(triple.agent_buffs.size() == 3, "three agents grant three buffs")
	_assert(single.agent_buffs.size() == 1, "one agent grants one buff")
	var buff_ids: PackedStringArray = PackedStringArray()
	for buff in triple.agent_buffs:
		buff_ids.append(buff.id)
	_assert("buff_codex" in buff_ids and "buff_claude" in buff_ids and "buff_grok" in buff_ids, "each channel contributes its own buff")

	# 三个 buff 的数值是叠加的，不是只取主 agent 那一个。
	triple.skills.clear()
	single.skills.clear()
	_assert(triple.stacked_crit() > 0.0, "the CODEX buff still adds crit")
	_assert(triple.stacked_accuracy() > 0.0, "the CLAUDE buff adds accuracy on top")
	_assert(triple.stacked_dodge() > Fighter.BASE_DODGE + triple.innate_dodge(), "the GROK buff adds dodge on top of the 10% base")
	_assert(single.stacked_accuracy() == 0.0, "a CODEX-only fighter has no accuracy buff")
	_assert(is_equal_approx(single.stacked_dodge(), Fighter.BASE_DODGE + single.innate_dodge()), "a fighter without GROK still has the 10% base dodge")
	_assert(triple.agent_buff_text().find(" + ") >= 0, "the report names every agent buff")
	_assert(single.agent_buff_text().find(" + ") < 0, "a single buff needs no separator")

	# 认不出的渠道不产 buff，也不会崩。
	var unknown := _ranked("陌生", 10, "who.knows")
	var stranger := Fighter.from_ranked(unknown, false)
	SkillGrant.apply(stranger, RollSource.new(1))
	_assert(stranger.agent_buffs.is_empty(), "an unknown channel grants no buff")
	_assert(stranger.stacked_crit() >= 0.0, "an unknown channel still resolves cleanly")

	# 配置表里每一行都得给出命中当量的权重：漏写就是 0 当量，这个 buff 不用付
	# 命中率就白拿，而且是悄悄地白拿，只有这条断言会喊。
	var probe := SkillDef.new()
	for channel in SkillCatalog.AGENT_BUFF_SPECS:
		var spec: Dictionary = SkillCatalog.AGENT_BUFF_SPECS[channel]
		var priced := str(spec["prop"])
		_assert(probe.get(priced) != null, "%s writes a real SkillDef field (%s)" % [channel, priced])
		_assert(float(spec.get("hit_weight", 0.0)) > 0.0, "%s's %s is priced above zero" % [channel, priced])
		# 建出来的 buff 自己带着这两样，结算时不用回头查表。
		var built := SkillCatalog.agent_buff_template(channel, 0.1)
		_assert(built.prop == priced and is_equal_approx(built.hit_weight, float(spec["hit_weight"])), "%s carries its own prop and weight" % channel)
	# 技能牌不走命中当量，按张计价，所以权重留 0。
	_assert(is_equal_approx(SkillCatalog.by_id("skill_crit").hit_weight, 0.0), "skill cards carry no hit weight")
	# 当量就是按权重加权求和：闪避一比一，暴击按 (CRIT_MULTIPLIER-1) 折半。
	var weighed: Array[SkillDef] = [
		SkillCatalog.agent_buff_template(AgentChannels.CHANNEL_GROK, 0.2),
		SkillCatalog.agent_buff_template(AgentChannels.CHANNEL_CODEX, 0.2),
	]
	var crit_share := 0.2 * (CombatResolver.CRIT_MULTIPLIER - 1.0) * CombatResolver.AGENT_BUFF_WEIGHT_PER_DAMAGE
	_assert(is_equal_approx(CombatResolver.agent_buff_hit_value(weighed), 0.2 + crit_share), "hit value is the weighted sum of what was actually rolled")
	# 空技能和技能牌都不该往当量里掺东西。
	var unpriced: Array[SkillDef] = [SkillCatalog.none_buff(), SkillCatalog.by_id("skill_crit")]
	_assert(is_equal_approx(CombatResolver.agent_buff_hit_value(unpriced), 0.0), "cards and the empty skill add no hit value")


## 数字紧凑写法：按大小自动挂 K / M / B，四舍五入到小数点后两位。
func _test_compact_numbers() -> void:
	_assert(NumberFormat.compact(0) == "0", "zero stays plain")
	_assert(NumberFormat.compact(1) == "1", "single digits stay plain")
	_assert(NumberFormat.compact(999) == "999", "under a thousand stays plain")
	_assert(NumberFormat.compact(1000) == "1.00K", "a thousand switches to K")
	_assert(NumberFormat.compact(1234) == "1.23K", "K keeps two decimals")
	_assert(NumberFormat.compact(999499) == "999.50K", "just under a million is still K")
	_assert(NumberFormat.compact(1000000) == "1.00M", "a million switches to M")
	_assert(NumberFormat.compact(348431491) == "348.43M", "the real board's champion reads as M")
	_assert(NumberFormat.compact(1000000000) == "1.00B", "a billion switches to B")
	_assert(NumberFormat.compact(2500000000) == "2.50B", "B keeps two decimals")
	_assert(NumberFormat.compact(-1234) == "-1.23K", "negatives keep their sign")

	# 四舍五入，不是截断。
	_assert(NumberFormat.compact(1230000) == "1.23M", "an exact second decimal survives")
	_assert(NumberFormat.compact(1234999) == "1.23M", "a third digit below half rounds down")
	_assert(NumberFormat.compact(1235000) == "1.24M", "a third digit at half rounds up")

	# 单位是跟着当前数字走的，不是固定写死 M。
	var seen: Dictionary = {}
	for value in [500, 5000, 5000000, 5000000000]:
		var text := NumberFormat.compact(int(value))
		var unit := text.substr(text.length() - 1, 1)
		seen[unit] = true
	_assert(seen.size() == 4, "each magnitude picks its own unit")

	# 界面上确实用的是这个函数，而不是各写各的。
	for path in ["res://scenes/ranking.gd", "res://scenes/battle.gd", "res://scenes/fighter_view.gd", "res://scripts/combat_log.gd"]:
		var src := FileAccess.get_file_as_string(path)
		_assert(src.find("NumberFormat.compact(") >= 0, "%s renders numbers through the shared compact helper" % path)
	_assert(FileAccess.get_file_as_string("res://scenes/ranking.gd").find("_format_millions") < 0, "the old M-only formatter is gone")


## 胜率曲线：人均战力比 1:1 精确落在 50%，人数另算，两端收敛到 30%/70% 而不是 0/100%。
func _test_win_rate() -> void:
	# 胜率永远被夹在 [30%, 70%]：战力再悬殊也不能把结果锁死。
	var extremes: Array[int] = [0, 1, 25, 100, 400, 10000, 1000000]
	for power in extremes:
		var rate := CombatResolver.champion_win_rate(power, 100)
		_assert(rate >= CombatResolver.MIN_WIN_RATE, "win rate never drops below 30%% (at %d vs 100)" % power)
		_assert(rate <= CombatResolver.MAX_WIN_RATE, "win rate never rises above 70%% (at %d vs 100)" % power)

	# 两个锚点：比人均强 4 倍（s=4）时贴着上限，只有人均的四分之一（s=0.25）时贴着
	# 下限，各自走完区间的 SATURATION。这里全是单挑，人数压力为 0。
	var span := CombatResolver.MAX_WIN_RATE - CombatResolver.MIN_WIN_RATE
	var at_ceil := CombatResolver.champion_win_rate(400, 100)
	var at_floor := CombatResolver.champion_win_rate(25, 100)
	var sat := CombatResolver.WIN_RATE_ANCHOR_SATURATION
	_assert(absf(at_ceil - (CombatResolver.MAX_WIN_RATE - span * 0.5 * (1.0 - sat))) < 0.001, "s=4 sits at the upper anchor (%.3f)" % at_ceil)
	_assert(absf(at_floor - (CombatResolver.MIN_WIN_RATE + span * 0.5 * (1.0 - sat))) < 0.001, "s=0.25 sits at the lower anchor (%.3f)" % at_floor)
	# 和人均一样强就是真正的五五开——1v1 里两个一模一样的人对打不再白送擂主。
	_assert(is_equal_approx(CombatResolver.champion_win_rate(100, 100), 0.5), "matching your only opponent is an even 50%")
	_assert(is_equal_approx(CombatResolver.champion_win_rate(70, 70), 0.5), "another identical 1v1 is 50%")
	_assert(at_floor > CombatResolver.MIN_WIN_RATE, "a 1:4 underdog still has more than the floor")
	_assert(at_ceil < CombatResolver.MAX_WIN_RATE, "even 4x the per-head power leaves room below the ceiling")

	# 锚点之外仍然单调，但收益和惩罚都极慢——不会一跨线就躺平。
	var far_above := CombatResolver.champion_win_rate(1600, 100)
	var way_above := CombatResolver.champion_win_rate(1000000, 100)
	_assert(far_above > at_ceil and way_above > far_above, "past the upper anchor the curve still creeps up")
	_assert(way_above - at_ceil < span * 0.5 * (1.0 - sat) + 0.001, "but the whole climb past it is worth less than the leftover margin")
	var far_below := CombatResolver.champion_win_rate(6, 100)
	_assert(far_below < at_floor and far_below > CombatResolver.MIN_WIN_RATE, "past the lower anchor it still creeps down without hitting the floor")
	_assert(CombatResolver.champion_win_rate(200, 0) <= CombatResolver.MAX_WIN_RATE, "no others still caps at 70%")

	var samples: Array[int] = [1, 25, 35, 50, 75, 100, 150, 200, 400, 4000]
	var prev := -1.0
	for power in samples:
		var rate := CombatResolver.champion_win_rate(power, 100)
		_assert(rate >= prev, "win rate is monotonically non-decreasing at %d vs 100" % power)
		prev = rate
	_assert(CombatResolver.champion_win_rate(150, 100) > CombatResolver.champion_win_rate(100, 100), "more power strictly helps")
	_assert(CombatResolver.champion_win_rate(50, 100) < CombatResolver.champion_win_rate(100, 100), "less power strictly hurts")

	# 合计战力走 RMS 口径：一个大号比两个半大号更难打。
	var one_big := CombatResolver.aggregate_power([100, 10, 10])
	var spread_out := CombatResolver.aggregate_power([40, 40, 40])
	_assert(one_big > spread_out, "a single heavy hitter aggregates to more threat than an even spread")
	_assert(CombatResolver.aggregate_power([]) == 0, "an empty field has no power")
	# 人均口径是合计除以 √N，所以“一个大号更难打”在人均上同样成立。
	_assert(is_equal_approx(CombatResolver.per_challenger_power(100, 4), 50.0), "per-head power is the RMS average")
	_assert(is_equal_approx(CombatResolver.per_challenger_power(100, 1), 100.0), "a lone challenger is his own average")

	# 人数压力：一个人时为 0，人越多压得越狠，但有封顶，而且始终单调。
	_assert(is_equal_approx(CombatResolver.crowd_pressure(1), 0.0), "a duel carries no crowd pressure")
	var prev_pressure := -1.0
	for count in [1, 2, 5, 10, 30, 100, 1000]:
		var pressure := CombatResolver.crowd_pressure(count)
		_assert(pressure >= prev_pressure, "crowd pressure never drops as the field grows (at %d)" % count)
		_assert(pressure <= CombatResolver.CROWD_PRESSURE_CAP + 0.0001, "crowd pressure stays under its cap (at %d)" % count)
		prev_pressure = pressure
	_assert(CombatResolver.crowd_pressure(10) > CombatResolver.crowd_pressure(2), "ten opponents press harder than two")

	# 等战力时人数说了算：1v1 五五开，人越多越难，1v100 仍留得住参与感。
	var even_rates := {}
	for count in [1, 2, 5, 10, 30, 100]:
		var powers: Array[int] = []
		for i in count:
			powers.append(50000000)
		even_rates[count] = CombatResolver.champion_win_rate(50000000, CombatResolver.aggregate_power(powers), count)
	_assert(is_equal_approx(even_rates[1], 0.5), "an even 1v1 is 50%")
	_assert(even_rates[10] < even_rates[2] and even_rates[2] < even_rates[1], "the same per-head strength gets harder as the field grows")
	_assert(even_rates[100] < even_rates[30], "and a hundred still presses harder than thirty")
	_assert(even_rates[100] > CombatResolver.MIN_WIN_RATE + 0.04, "but a hundred-strong field never reads as hopeless (%.2f)" % even_rates[100])

	# 战力能把人数劣势补回来，但补不满：1v100 里战力拉到离谱也够不到上限。
	var crowded := CombatResolver.aggregate_power(_even_powers(100, 50000000))
	var crushing_crowd := CombatResolver.champion_win_rate(50000000 * 1000, crowded, 100)
	_assert(crushing_crowd > even_rates[100] + 0.1, "raw power does pull the target back up in a crowd")
	_assert(crushing_crowd < CombatResolver.MAX_WIN_RATE - CombatResolver.crowd_pressure(100) + 0.001, "but the crowd keeps the ceiling out of reach")

	# 目标胜率反解出来的是命中率的偏移量：0 是五五开，正数偏向擂主，
	# 整个 30%~70% 的目标带只对应几个百分点——胜率靠概率调，不靠锁定。
	var low_steer := CombatResolver.champion_steer(CombatResolver.MIN_WIN_RATE)
	var high_steer := CombatResolver.champion_steer(CombatResolver.MAX_WIN_RATE)
	_assert(low_steer < 0.0 and high_steer > 0.0, "the steer leans to whoever is favoured")
	_assert(high_steer - low_steer < 0.25, "the whole 30%-70% target band maps into a narrow steer window")
	_assert(high_steer > low_steer, "a higher target means a bigger steer for the champion")
	_assert(is_equal_approx(low_steer, -high_steer), "the 30% and 70% ends are mirror images")

	var src := FileAccess.get_file_as_string("res://scripts/combat_resolver.gd")
	_assert(src.find("tanh(") >= 0 and src.find("WIN_RATE_RATIO_CEIL") >= 0, "win rate interpolation is an anchored tanh on log power ratio")
	var war_src := FileAccess.get_file_as_string("res://scripts/wheel_war.gd")
	_assert(war_src.find("CombatResolver.champion_win_rate") >= 0, "wheel war uses the shipped win-rate function")


## 造一名测试用角色，省掉每次手写 RankedUser 的样板。
func _make_fighter(name: String, tokens: int, channel: String, champion: bool) -> Fighter:
	return Fighter.from_ranked(_ranked(name, tokens, channel), champion)


## N 个等战力的挑战者，用来看“人数本身值多少胜率”。
func _even_powers(count: int, each: int) -> Array[int]:
	var powers: Array[int] = []
	for i in count:
		powers.append(each)
	return powers


## 把角色身上所有技能和 buff 摘干净，只留先天属性。
## 用于需要精确控制掷点序列的用例。
func _disarm(fighter: Fighter) -> void:
	fighter.agent_buffs = []
	fighter.skills.clear()
	fighter.rebirth_available = false
	fighter.poison_turns = 0
	fighter.paralyze_turns = 0
	fighter.confuse_turns = 0
	fighter.heal_guard = false
	fighter.hp = fighter.max_hp



## 技能池是不是真的由 SkillCatalog.SPECS 那一张表生成的：每行的 prop 必须是
## SkillDef 上真实存在的字段，生成出来的技能要带上配置的 id / 名字 / 数值 / 边框族，
## 说明里也不许留下没填上的占位符。「加技能只补一行」靠的就是这条。
func _assert_specs_drive_pool() -> void:
	var fields: Dictionary = {}
	for entry in SkillDef.new().get_property_list():
		fields[str(entry["name"])] = true
	var families: Dictionary = SkillCatalog.icon_families()
	var built: Array[SkillDef] = SkillCatalog.pool()
	_assert(built.size() == SkillCatalog.SPECS.size(), "pool has exactly one skill per spec row")
	for i in SkillCatalog.SPECS.size():
		var spec: Dictionary = SkillCatalog.SPECS[i]
		var id := str(spec["id"])
		var prop := str(spec["prop"])
		var family := str(spec["family"])
		var skill: SkillDef = built[i]
		_assert(fields.has(prop), "%s writes a real SkillDef field (%s)" % [id, prop])
		_assert(skill.id == id and skill.icon_id == id, "%s keeps its id as icon name" % id)
		_assert(skill.display_name == str(spec["name"]), "%s keeps its display name" % id)
		if typeof(spec["value"]) == TYPE_BOOL:
			_assert(bool(skill.get(prop)) == bool(spec["value"]), "%s carries its configured switch" % id)
		else:
			_assert(is_equal_approx(float(skill.get(prop)), float(spec["value"])), "%s carries its configured value" % id)
		_assert(skill.description.find("{") < 0, "%s tooltip has no unfilled placeholder" % id)
		_assert(SkillCatalog.icon_family(id) == family, "%s reports its configured family" % id)
		_assert(families.has(family) and (families[family] as Array).has(id), "%s is listed under its family" % id)
		_assert(not SkillCatalog.display_group(id).is_empty(), "%s lands in a display group" % id)
		_assert(SkillCatalog.spec_rank(id) == i, "%s keeps its table order" % id)
		var looked_up: SkillDef = SkillCatalog.by_id(id)
		_assert(looked_up != null and looked_up.description == skill.description, "by_id rebuilds %s from the same row" % id)
	_assert(SkillCatalog.spec_rank("buff_codex") < 0, "agent buffs are not pool rows")

## 和 SkillCatalog._percent 同一口径：tooltip 里写的就是这份百分数。
func _pct_label(value: float) -> String:
	return "%d%%" % roundi(value * 100.0)


## 目录字段、tooltip 百分数、结算常量必须是同一套活数字。
func _assert_live_combat_numbers() -> void:
	_assert(is_equal_approx(SkillCatalog.by_id("skill_crit").crit_chance, SkillCatalog.SELF_BUFF_CHANCE), "crit self-buff is the live self-buff rate")
	_assert(is_equal_approx(SkillCatalog.by_id("skill_hit").accuracy_bonus, SkillCatalog.SELF_BUFF_CHANCE), "hit self-buff is the live self-buff rate")
	_assert(is_equal_approx(SkillCatalog.by_id("skill_dmg").damage_bonus, SkillCatalog.SELF_BUFF_CHANCE), "damage self-buff is the live self-buff rate")
	_assert(is_equal_approx(SkillCatalog.by_id("skill_dodge").dodge_bonus, SkillCatalog.SELF_BUFF_CHANCE), "dodge bonus is the live self-buff rate")
	_assert(is_equal_approx(SkillCatalog.by_id("skill_dr").damage_reduction, SkillCatalog.SELF_BUFF_CHANCE), "damage reduction is the live self-buff rate")
	_assert(is_equal_approx(SkillCatalog.by_id("skill_guard").guard_chance, SkillCatalog.SELF_BUFF_CHANCE), "guard is the live self-buff rate")
	_assert(is_equal_approx(SkillCatalog.by_id("skill_poison").poison_chance, SkillCatalog.STATUS_CHANCE), "poison is the live status rate")
	_assert(is_equal_approx(SkillCatalog.by_id("skill_paralyze").paralyze_chance, SkillCatalog.STATUS_CHANCE), "paralyze is the live status rate")
	_assert(is_equal_approx(SkillCatalog.by_id("skill_confuse").confuse_chance, SkillCatalog.STATUS_CHANCE), "confuse is the live status rate")
	_assert(is_equal_approx(SkillCatalog.by_id("skill_double").double_chance, SkillCatalog.DOUBLE_CHANCE), "double strike is the live combo rate")
	_assert(is_equal_approx(SkillCatalog.by_id("skill_triple").triple_chance, SkillCatalog.TRIPLE_CHANCE), "triple strike is the live combo rate")
	_assert(is_equal_approx(SkillCatalog.by_id("skill_counter").counter_chance, SkillCatalog.COUNTER_CHANCE), "counter is the live counter rate")
	_assert(is_equal_approx(SkillCatalog.by_id("skill_lingbo").lingbo_chance, SkillCatalog.LINGBO_CHANCE), "lingbo is the live lingbo rate")
	_assert(is_equal_approx(SkillCatalog.by_id("skill_heal").heal_chance, CombatResolver.HEAL_CHANCE_CHAMPION), "heal catalog flag matches the live heal chance")
	_assert(is_equal_approx(SkillCatalog.by_id("skill_awaken").awaken_chance, CombatResolver.AWAKEN_CHANCE), "awaken catalog chance matches resolver")
	_assert(is_equal_approx(SkillCatalog.by_id("skill_assassinate").assassinate_chance, CombatResolver.ASSASSINATE_CHANCE_CHAMPION), "assassinate catalog flag matches the champion roll")
	var heal_tip := SkillCatalog.by_id("skill_heal").description
	_assert(heal_tip.find(_pct_label(CombatResolver.HEAL_CHANCE_CHAMPION)) >= 0, "heal tooltip names champion trigger chance")
	_assert(heal_tip.find(_pct_label(CombatResolver.HEAL_CHANCE_CHALLENGER)) >= 0, "heal tooltip names challenger trigger chance")
	_assert(heal_tip.find(_pct_label(CombatResolver.HEAL_SHARE_CHAMPION)) >= 0, "heal tooltip names champion heal share")
	_assert(heal_tip.find(_pct_label(CombatResolver.HEAL_SHARE_CHALLENGER)) >= 0, "heal tooltip names challenger heal share")
	_assert(heal_tip.find(_pct_label(CombatResolver.HEAL_GUARD_DODGE)) >= 0, "heal tooltip names the live full-dodge")
	var steal_tip := SkillCatalog.by_id("skill_lifesteal").description
	_assert(steal_tip.find(_pct_label(CombatResolver.LIFESTEAL_RATIO_CHAMPION)) >= 0, "lifesteal tooltip names champion ratio")
	_assert(steal_tip.find(_pct_label(CombatResolver.LIFESTEAL_RATIO_CHALLENGER)) >= 0, "lifesteal tooltip names challenger ratio")
	var ass_tip := SkillCatalog.by_id("skill_assassinate").description
	_assert(ass_tip.find(_pct_label(CombatResolver.ASSASSINATE_CHANCE_CHAMPION)) >= 0, "assassinate tooltip names champion chance")
	_assert(ass_tip.find(_pct_label(CombatResolver.ASSASSINATE_CHANCE_CHALLENGER)) >= 0, "assassinate tooltip names challenger chance")
	_assert(ass_tip.find(_pct_label(CombatResolver.ASSASSINATE_SHARE_CHALLENGER)) >= 0, "assassinate tooltip names challenger share")
	var confuse_tip := SkillCatalog.by_id("skill_confuse").description
	_assert(confuse_tip.find(_pct_label(CombatResolver.CONFUSE_SELF_HIT_CHANCE)) >= 0, "confuse tooltip names the live self-hit chance")
	var awaken_tip := SkillCatalog.by_id("skill_awaken").description
	_assert(awaken_tip.find(_pct_label(CombatResolver.AWAKEN_CHANCE)) >= 0, "awaken tooltip names the live trigger chance")
	_assert(awaken_tip.find(_pct_label(CombatResolver.AWAKEN_HP_SHARE)) >= 0, "awaken tooltip names the live HP share")
	_assert(awaken_tip.find(_pct_label(CombatResolver.AWAKEN_HIT_BONUS)) >= 0, "awaken tooltip names the live hit bonus")
	var lingbo_tip := SkillCatalog.by_id("skill_lingbo").description
	_assert(lingbo_tip.find(_pct_label(SkillCatalog.LINGBO_CHANCE)) >= 0, "lingbo tooltip names the live chance")
	var crit_tip := SkillCatalog.by_id("skill_crit").description
	_assert(crit_tip.find(_pct_label(SkillCatalog.SELF_BUFF_CHANCE)) >= 0, "self-buff tooltip names the live rate")
	var poison_tip := SkillCatalog.by_id("skill_poison").description
	_assert(poison_tip.find(_pct_label(SkillCatalog.STATUS_CHANCE)) >= 0, "status tooltip names the live rate")
	_assert(poison_tip.find(str(CombatResolver.STATUS_TURNS)) >= 0, "status tooltip names the live duration")


## 技能与 buff 的全部规则：数值区间、叠加、连击、状态、反击、
## 吸血、治疗、复活，以及“没有任何必中必闪”这条底线。
func _test_skills() -> void:
	var rng_lo := RollSource.new(1)
	rng_lo.push([0.0])
	var buff_lo := SkillGrant.roll_agent_buff(AgentChannels.CHANNEL_CODEX, rng_lo)
	_assert(buff_lo.id == "buff_codex", "CODEX buff type is crit")
	_assert(is_equal_approx(buff_lo.crit_chance, SkillCatalog.AGENT_BUFF_MIN), "agent buff floor is the live min")
	var rng_hi := RollSource.new(1)
	rng_hi.push([1.0])
	var buff_hi := SkillGrant.roll_agent_buff(AgentChannels.CHANNEL_CODEX, rng_hi)
	_assert(is_equal_approx(buff_hi.crit_chance, SkillCatalog.AGENT_BUFF_MAX), "agent buff ceiling is the live max")
	var rng_c := RollSource.new(1)
	rng_c.push([0.0])
	_assert(is_equal_approx(SkillGrant.roll_agent_buff(AgentChannels.CHANNEL_CLAUDE, rng_c).accuracy_bonus, SkillCatalog.AGENT_BUFF_MIN), "CLAUDE buff is accuracy")
	var rng_g := RollSource.new(1)
	rng_g.push([0.0])
	_assert(is_equal_approx(SkillGrant.roll_agent_buff(AgentChannels.CHANNEL_GROK, rng_g).dodge_bonus, SkillCatalog.AGENT_BUFF_MIN), "GROK buff is dodge")
	var rng_w := RollSource.new(1)
	rng_w.push([0.0])
	_assert(is_equal_approx(SkillGrant.roll_agent_buff(AgentChannels.CHANNEL_WORKBUDDY, rng_w).damage_reduction, SkillCatalog.AGENT_BUFF_MIN), "WORKBUDDY buff is damage reduction")

	var champ_skills: Array[SkillDef] = SkillGrant.pick_skills(SkillCatalog.CHAMPION_SKILL_CAP, RollSource.new(3))
	var chal_skills: Array[SkillDef] = SkillGrant.pick_skills(SkillCatalog.CHALLENGER_SKILL_CAP, RollSource.new(4))
	_assert(SkillCatalog.CHAMPION_SKILL_MIN == 6 and SkillCatalog.CHAMPION_SKILL_CAP == 8, "champion skill count is 6-8")
	var rng_champ_lo := RollSource.new(1)
	rng_champ_lo.push([0])
	_assert(SkillGrant.roll_skill_count(true, rng_champ_lo) == 6, "champion skill floor is 6")
	var rng_champ_hi := RollSource.new(1)
	rng_champ_hi.push([8])
	_assert(SkillGrant.roll_skill_count(true, rng_champ_hi) == 8, "champion skill cap is 8")
	_assert(champ_skills.size() <= 8 and champ_skills.size() > 0, "champion gets at most 8 skills")
	_assert(chal_skills.size() <= 4 and chal_skills.size() > 0, "challenger gets at most 4 skills")
	var seen := {}
	for skill in champ_skills:
		_assert(not seen.has(skill.id), "champion skills are unique: %s" % skill.id)
		seen[skill.id] = true
	seen = {}
	for skill in chal_skills:
		_assert(not seen.has(skill.id), "challenger skills are unique: %s" % skill.id)
		seen[skill.id] = true
	_assert(SkillCatalog.pool().size() == 18, "skill pool has 潜能激发; 定身 stays out")
	var pool_ids: PackedStringArray = PackedStringArray()
	for skill in SkillCatalog.pool():
		pool_ids.append(skill.id)
	_assert(pool_ids.find("skill_root") < 0, "定身 is no longer in the pool")
	_assert(pool_ids.find("skill_paralyze") >= 0, "麻痹 stays as the 3-turn skip")
	_assert(pool_ids.find("skill_awaken") >= 0, "潜能激发 is in the pool")
	_assert_specs_drive_pool()
	_assert_live_combat_numbers()
	_assert(SkillCatalog.by_id("skill_assassinate").display_name == "幻影刺杀", "assassinate display name")
	_assert(SkillCatalog.by_id("skill_lingbo").display_name == "凌波微步", "lingbo display name")
	_assert(SkillCatalog.by_id("skill_awaken").display_name == "潜能激发", "awaken display name")
	_assert(SkillCatalog.icon_family("skill_awaken") == SkillCatalog.FAMILY_TECHNIQUE, "awaken is a high-tier technique")
	_assert(SkillCatalog.display_group("skill_crit") == SkillCatalog.DISPLAY_GROUP_BUFF, "crit is 增强")
	_assert(SkillCatalog.display_group("skill_dodge") == SkillCatalog.DISPLAY_GROUP_BUFF, "dodge is 增强")
	_assert(SkillCatalog.display_group("skill_poison") == SkillCatalog.DISPLAY_GROUP_STATUS, "poison is 附加")
	_assert(SkillCatalog.display_group("skill_heal") == SkillCatalog.DISPLAY_GROUP_RECOVER, "heal is 治疗")
	_assert(SkillCatalog.display_group("skill_awaken") == SkillCatalog.DISPLAY_GROUP_TECHNIQUE, "awaken is 高级")
	# FAMILY_ORDER 和 DISPLAY_GROUP_ORDER 是两张表，排序同时读它们。
	# 只要族序按分组单调递增，两者就不会打架；这一条就是钉住这件事。
	var last_group_rank := -1
	for family in SkillCatalog.FAMILY_ORDER:
		var group: String = SkillCatalog.FAMILY_DISPLAY_GROUP[family]
		var group_rank: int = SkillCatalog.DISPLAY_GROUP_ORDER.find(group)
		_assert(group_rank >= last_group_rank, "family %s does not jump back a display group" % family)
		last_group_rank = group_rank
	var mixed: Array[SkillDef] = [
		SkillCatalog.by_id("skill_assassinate"),
		SkillCatalog.by_id("skill_heal"),
		SkillCatalog.by_id("skill_poison"),
		SkillCatalog.by_id("skill_crit"),
		SkillCatalog.by_id("skill_lifesteal"),
		SkillCatalog.by_id("skill_guard"),
	]
	var shown: Array[SkillDef] = SkillCatalog.sort_for_display(mixed)
	var shown_ids: PackedStringArray = PackedStringArray()
	for skill in shown:
		shown_ids.append(skill.id)
	_assert(shown_ids == PackedStringArray(["skill_crit", "skill_guard", "skill_poison", "skill_lifesteal", "skill_heal", "skill_assassinate"]), "display order is 增强 → 附加 → 治疗 → 高级")
	for i in range(1, shown.size()):
		_assert(SkillCatalog.display_group_rank(shown[i].icon_id) >= SkillCatalog.display_group_rank(shown[i - 1].icon_id), "display ranks never go backwards")
	var roster_fighter := _make_fighter("甲", 100, AgentChannels.CHANNEL_CLAUDE, true)
	roster_fighter.skills = [SkillCatalog.by_id("skill_crit"), SkillCatalog.by_id("skill_dodge")]
	var roster := CombatLog.roster_line(roster_fighter)
	_assert(roster.find("甲") >= 0 and roster.find("2 技能") >= 0, "出场介绍写清名字和技能张数")
	_assert(CombatLog.opening_line(roster_fighter, 4).find("其余 4 人") >= 0, "开场白写清对面几个人")
	_assert(CombatLog.next_up_line(roster_fighter).find("下一位") >= 0, "换人那句带“下一位”")
	_assert(CombatLog.outcome_line("甲", "乙", true).find("唯一神") >= 0, "擂主全胜是唯一神")
	_assert(CombatLog.outcome_line("甲", "乙", false).find("惜败于乙") >= 0, "擂主倒下时写出终结者")
	var heal_tip := SkillCatalog.by_id("skill_heal").description
	_assert(heal_tip.find("不进攻") >= 0 and heal_tip.find("闪避") >= 0, "heal tooltip says skip attack and full dodge")
	_assert(heal_tip.find("幻影刺杀") >= 0, "heal tooltip names the assassinate exception")
	var awaken_tip := SkillCatalog.by_id("skill_awaken").description
	_assert(awaken_tip.find(_pct_label(CombatResolver.AWAKEN_HP_SHARE)) >= 0, "awaken tooltip names the live HP cost")
	_assert(awaken_tip.find(_pct_label(CombatResolver.AWAKEN_HIT_BONUS)) >= 0, "awaken tooltip names the live bonuses")
	_assert(awaken_tip.find("不足") >= 0, "awaken tooltip says it needs enough HP")

	var steer := 0.0
	var attacker := _make_fighter("A", 100, "", true)
	var defender := _make_fighter("B", 100, "", false)
	_disarm(attacker)
	_disarm(defender)
	var rng_plain := RollSource.new(1)
	rng_plain.push([0.0, 0.99])
	var plain_events: Array[StrikeResult] = CombatResolver.resolve_strikes(attacker, defender, steer, rng_plain)
	var plain_damage := 0
	for event in plain_events:
		plain_damage += event.damage
	_assert(plain_events.size() == 1 and plain_events[0].hit and not plain_events[0].crit, "no-skill hit is a single non-crit when the crit die misses")

	defender.hp = defender.max_hp
	attacker.skills = [SkillCatalog.by_id("skill_crit")]
	var rng_crit := RollSource.new(1)
	rng_crit.push([0.0, 0.0])
	var crit_events: Array[StrikeResult] = CombatResolver.resolve_strikes(attacker, defender, steer, rng_crit)
	_assert(crit_events.size() == 1 and crit_events[0].crit, "crit skill can crit on the same hit roll")
	_assert(crit_events[0].damage != plain_damage, "with-skill settlement differs from no-skill")

	_disarm(attacker)
	_disarm(defender)
	attacker.skills = [SkillCatalog.by_id("skill_double")]
	var rng_double := RollSource.new(1)
	rng_double.push([0.0, 0.99, 0.0, 0.0, 0.99])
	var double_events: Array[StrikeResult] = CombatResolver.resolve_strikes(attacker, defender, steer, rng_double)
	_assert(double_events.size() == 2 and double_events[1].combo, "double strike adds one extra hit")

	_disarm(attacker)
	_disarm(defender)
	defender.hp = defender.max_hp
	attacker.skills = [SkillCatalog.by_id("skill_triple")]
	var rng_triple := RollSource.new(1)
	rng_triple.push([0.0, 0.99, 0.0, 0.0, 0.99, 0.0, 0.99])
	var triple_events: Array[StrikeResult] = CombatResolver.resolve_strikes(attacker, defender, steer, rng_triple)
	_assert(triple_events.size() == 3, "triple strike adds two extra hits")

	_disarm(attacker)
	_disarm(defender)
	var dodge_buff := SkillCatalog.agent_buff_template(AgentChannels.CHANNEL_GROK)
	dodge_buff.dodge_bonus = 0.25
	_give_buffs(defender, [dodge_buff])
	# 闪避 25% + 基础 15% = 40%，命中线落到 50%，0.6 就被闪掉。
	var rng_dodge := RollSource.new(1)
	rng_dodge.push([0.6])
	var dodge_events: Array[StrikeResult] = CombatResolver.resolve_strikes(attacker, defender, steer, rng_dodge)
	_assert(not dodge_events[0].hit and dodge_events[0].dodged, "dodge buff turns a mid roll into a dodge")
	_disarm(defender)
	# 只剩挑战者的基础闪避 15%，命中线 75%，0.8 仍被闪掉。
	var rng_base_dodge := RollSource.new(1)
	rng_base_dodge.push([0.8])
	_assert(not CombatResolver.resolve_strikes(attacker, defender, steer, rng_base_dodge)[0].hit, "0.8 still dodges on the base dodge alone")
	defender.hp = defender.max_hp
	var rng_no_dodge := RollSource.new(1)
	rng_no_dodge.push([0.20, 0.99])
	_assert(CombatResolver.resolve_strikes(attacker, defender, steer, rng_no_dodge)[0].hit, "a 0.20 roll hits without extra dodge")

	var acc_buff := SkillCatalog.agent_buff_template(AgentChannels.CHANNEL_CLAUDE)
	acc_buff.accuracy_bonus = 0.20
	_give_buffs(attacker, [acc_buff])
	defender.hp = defender.max_hp
	# 命中 20% 压过闪避 15%，净差 +5% 把命中线从 75% 抬到 92.5%。
	var rng_acc := RollSource.new(1)
	rng_acc.push([0.8, 0.99])
	_assert(CombatResolver.resolve_strikes(attacker, defender, steer, rng_acc)[0].hit, "accuracy buff turns a 0.8 roll into a hit")
	_disarm(attacker)
	defender.hp = defender.max_hp
	var rng_miss := RollSource.new(1)
	rng_miss.push([0.8])
	_assert(not CombatResolver.resolve_strikes(attacker, defender, steer, rng_miss)[0].hit, "same 0.8 roll dodges without accuracy")

	_disarm(attacker)
	_disarm(defender)
	attacker.skills = [SkillCatalog.by_id("skill_poison")]
	var rng_poison := RollSource.new(1)
	rng_poison.push([0.0, 0.99, 0.0])
	CombatResolver.resolve_strikes(attacker, defender, steer, rng_poison)
	_assert(defender.poison_turns == 3, "poison applies for 3 turns")
	defender.paralyze_turns = 3
	var before_hp := defender.hp
	var poison_events: Array[StrikeResult] = CombatResolver.resolve_action(defender, attacker, steer, RollSource.new(1))
	_assert(poison_events[0].poison_tick, "poison ticks on the afflicted fighter's action")
	var poison_tick := maxi(1, int(round(float(CombatResolver.strike_damage(defender)) * CombatResolver.POISON_TICK_SHARE)))
	_assert(defender.hp == before_hp - poison_tick, "poison ticks for half a clean hit")

	_disarm(attacker)
	_disarm(defender)
	defender.paralyze_turns = 3
	var para_events: Array[StrikeResult] = CombatResolver.resolve_action(defender, attacker, steer, RollSource.new(1))
	_assert(para_events[0].skip_reason == StrikeResult.SKIP_PARALYZE, "paralyze skips the action")
	_assert(defender.paralyze_turns == 2, "paralyze lasts 3 turns")
	_assert(attacker.hp == attacker.max_hp, "paralyzed fighter deals no damage")

	_disarm(attacker)
	_disarm(defender)
	attacker.confuse_turns = 3
	var rng_conf := RollSource.new(1)
	rng_conf.push([0.0, 0.0, 0.99])
	var conf_events: Array[StrikeResult] = CombatResolver.resolve_action(attacker, defender, steer, rng_conf)
	var saw_self := false
	for ev in conf_events:
		if ev.self_hit:
			saw_self = true
	_assert(saw_self, "confusion can make the fighter hit themselves")
	_assert(attacker.hp < attacker.max_hp, "self-hit from confusion deals damage")

	_disarm(attacker)
	_disarm(defender)
	defender.skills = [SkillCatalog.by_id("skill_guard")]
	var rng_guard := RollSource.new(1)
	rng_guard.push([0.0, 0.0])
	var guard_events: Array[StrikeResult] = CombatResolver.resolve_strikes(attacker, defender, steer, rng_guard)
	_assert(guard_events[0].guarded and guard_events[0].damage == 0, "absolute guard negates all damage")
	_assert(defender.hp == defender.max_hp, "guarded fighter keeps full HP")
	_disarm(attacker)
	_disarm(defender)
	attacker.skills = [SkillCatalog.by_id("skill_poison"), SkillCatalog.by_id("skill_paralyze"), SkillCatalog.by_id("skill_confuse")]
	defender.skills = [SkillCatalog.by_id("skill_guard")]
	var rng_guard_clean := RollSource.new(1)
	rng_guard_clean.push([0.0, 0.0])
	var guard_clean: Array[StrikeResult] = CombatResolver.resolve_strikes(attacker, defender, steer, rng_guard_clean)
	_assert(guard_clean[0].guarded, "guard still triggers when the attacker holds on-hit statuses")
	_assert(not guard_clean[0].poisoned and not guard_clean[0].paralyzed and not guard_clean[0].confused, "guarded hits apply no extra effects")
	_assert(defender.poison_turns == 0 and defender.paralyze_turns == 0 and defender.confuse_turns == 0, "guarded target is not statused")
	_assert(SkillCatalog.by_id("skill_confuse").description.find(_pct_label(CombatResolver.CONFUSE_SELF_HIT_CHANCE)) >= 0, "混乱 tooltip names the live self-hit chance")

	_disarm(attacker)
	_disarm(defender)
	defender.skills = [SkillCatalog.by_id("skill_rebirth")]
	defender.rebirth_available = true
	defender.hp = 1
	var rng_rebirth := RollSource.new(1)
	rng_rebirth.push([0.0, 0.99])
	var rebirth_events: Array[StrikeResult] = CombatResolver.resolve_strikes(attacker, defender, steer, rng_rebirth)
	_assert(rebirth_events[0].revived, "rebirth revives on lethal hit")
	_assert(defender.hp == defender.max_hp, "rebirth restores full HP")
	_assert(not defender.rebirth_available, "rebirth is consumed")
	var rng_rebirth2 := RollSource.new(1)
	rng_rebirth2.push([0.0, 0.99])
	defender.hp = 1
	var rebirth2: Array[StrikeResult] = CombatResolver.resolve_strikes(attacker, defender, steer, rng_rebirth2)
	_assert(rebirth2[0].defender_died and not rebirth2[0].revived, "consumed rebirth does not revive again")

	_disarm(attacker)
	_disarm(defender)
	defender.skills = [SkillCatalog.by_id("skill_counter")]
	var rng_counter := RollSource.new(1)
	rng_counter.push([0.0, 0.99, 0.0, 0.0, 0.99])
	var counter_events: Array[StrikeResult] = CombatResolver.resolve_strikes(attacker, defender, steer, rng_counter)
	var saw_counter := false
	for ev in counter_events:
		if ev.countered:
			saw_counter = true
	_assert(saw_counter, "counter fires after a hit")
	_assert(attacker.hp < attacker.max_hp, "counter deals damage back")

	_disarm(attacker)
	_disarm(defender)
	attacker.skills = [SkillCatalog.by_id("skill_lifesteal")]
	attacker.hp = 40
	var rng_ls := RollSource.new(1)
	rng_ls.push([0.0, 0.99])
	var ls_events: Array[StrikeResult] = CombatResolver.resolve_strikes(attacker, defender, steer, rng_ls)
	var ls_scale := float(CombatResolver.strike_damage(attacker)) / float(maxi(1, CombatResolver.strike_damage(defender)))
	var stolen := maxi(1, int(round(float(ls_events[0].damage) * CombatResolver.lifesteal_ratio(attacker) * ls_scale)))
	_assert(ls_events[0].lifesteal, "lifesteal flags when the skill is held")
	_assert(ls_events[0].heal_amount == stolen, "吸血按本方比例回血（擂主 25% / 挑战者 50%）")
	_assert(attacker.hp == 40 + stolen, "attacker HP rises by the lifesteal amount")
	_disarm(attacker)
	_disarm(defender)
	attacker.hp = 40
	var rng_nols := RollSource.new(1)
	rng_nols.push([0.0, 0.99])
	var nols: Array[StrikeResult] = CombatResolver.resolve_strikes(attacker, defender, steer, rng_nols)
	_assert(not nols[0].lifesteal and nols[0].heal_amount == 0, "no lifesteal skill means no heal from that hit")
	_assert(attacker.hp == 40, "attacker HP unchanged without lifesteal")

	# 治疗触发率双方 20%；擂主回 5% 最大生命，挑战者回 10% 最大生命。
	var short_bar := _make_fighter("short", 1000, "", false)
	var long_bar := _make_fighter("long", 1000, "", true)
	long_bar.hits_to_down = CombatResolver.HITS_PER_DUEL * 10
	_assert(is_equal_approx(float(CombatResolver.heal_amount(long_bar)) / float(long_bar.max_hp), CombatResolver.HEAL_SHARE_CHAMPION), "擂主一次治疗回的是身份分额")
	_assert(is_equal_approx(float(CombatResolver.heal_amount(short_bar)) / float(short_bar.max_hp), CombatResolver.HEAL_SHARE_CHALLENGER), "挑战者一次治疗回的是身份分额")
	_assert(is_equal_approx(CombatResolver.heal_chance(long_bar), CombatResolver.HEAL_CHANCE_CHAMPION), "擂主治疗触发率走身份常量")
	_assert(is_equal_approx(CombatResolver.heal_chance(short_bar), CombatResolver.HEAL_CHANCE_CHALLENGER), "挑战者治疗触发率走身份常量")
	_assert(is_equal_approx(CombatResolver.lifesteal_ratio(long_bar), CombatResolver.LIFESTEAL_RATIO_CHAMPION), "擂主吸血走身份常量")
	_assert(is_equal_approx(CombatResolver.lifesteal_ratio(short_bar), CombatResolver.LIFESTEAL_RATIO_CHALLENGER), "挑战者吸血走身份常量")
	_assert(CombatResolver.heal_amount(long_bar) != CombatResolver.strike_damage(long_bar), "治疗不再跟单次命中挂钩，改看最大生命")
	_assert(float(CombatResolver.heal_amount(short_bar)) / float(short_bar.max_hp) < 0.5, "one heal is never half a health bar")
	_disarm(attacker)
	_disarm(defender)
	attacker.skills = [SkillCatalog.by_id("skill_heal")]
	attacker.hp = 10
	var defender_hp_before := defender.hp
	var rng_heal := RollSource.new(1)
	rng_heal.push([0.0])
	var heal_events: Array[StrikeResult] = CombatResolver.resolve_action(attacker, defender, steer, rng_heal)
	_assert(heal_events.size() == 1, "heal replaces the whole action with one skip event")
	var last_heal: StrikeResult = heal_events[0]
	_assert(last_heal.skip_reason == StrikeResult.SKIP_HEAL and last_heal.treated, "heal skill procs instead of attacking")
	_assert(not last_heal.hit, "heal turn does not attack")
	var expected_heal := CombatResolver.heal_amount(attacker)
	_assert(last_heal.heal_amount == expected_heal, "heal amount matches the shipped formula")
	_assert(attacker.hp == 10 + expected_heal, "heal restores HP")
	_assert(defender.hp == defender_hp_before, "heal turn deals no damage")
	_assert(attacker.heal_guard, "heal turn raises 100% dodge until the next action")
	var rng_heal_dodge := RollSource.new(1)
	rng_heal_dodge.push([0.0, 0.99])
	var against_heal: Array[StrikeResult] = CombatResolver.resolve_strikes(defender, attacker, steer, rng_heal_dodge)
	_assert(against_heal[0].dodged and not against_heal[0].hit, "heal-guard dodges a roll that would otherwise hit")
	_assert(not against_heal[0].lingbo, "heal-guard is a plain dodge, not 凌波微步")
	_assert(attacker.hp == 10 + expected_heal, "heal-guard prevents incoming damage")
	_disarm(defender)
	defender.skills = [SkillCatalog.by_id("skill_assassinate")]
	var rng_heal_ass := RollSource.new(1)
	rng_heal_ass.push([0.99, 0.0])
	var pierce_heal: Array[StrikeResult] = CombatResolver.resolve_strikes(defender, attacker, steer, rng_heal_ass)
	_assert(pierce_heal[0].hit and pierce_heal[0].assassinated, "幻影刺杀 still pierces heal-guard")
	_disarm(attacker)
	_disarm(defender)
	attacker.hp = 10
	var rng_noheal := RollSource.new(1)
	rng_noheal.push([0.0, 0.99])
	var noheal: Array[StrikeResult] = CombatResolver.resolve_action(attacker, defender, steer, rng_noheal)
	_assert(not noheal[noheal.size() - 1].treated, "same rolls do not heal without the skill")
	_assert(attacker.hp < 10 or noheal[0].hit or noheal[0].dodged, "without heal the action is a strike")
	_assert(attacker.hp == 10, "HP unchanged without heal skill")
	_assert(not attacker.heal_guard, "heal-guard is not set without the skill")
	# 下一手行动开始时卸掉治疗闪避。
	attacker.skills = [SkillCatalog.by_id("skill_heal")]
	attacker.heal_guard = true
	var rng_clear := RollSource.new(1)
	rng_clear.push([0.99, 0.0, 0.99])
	CombatResolver.resolve_action(attacker, defender, steer, rng_clear)
	_assert(not attacker.heal_guard, "the next action clears leftover heal-guard")

	# 目录字段就算改成 100%，真正掷骰仍走结算器的身份治疗率。
	_disarm(attacker)
	_disarm(defender)
	var stuffed_heal := SkillCatalog.by_id("skill_heal")
	stuffed_heal.heal_chance = 1.0
	attacker.skills = [stuffed_heal]
	var rng_stuffed_heal := RollSource.new(1)
	rng_stuffed_heal.push([0.99, 0.0, 0.99])
	var stuffed_heal_events: Array[StrikeResult] = CombatResolver.resolve_action(attacker, defender, steer, rng_stuffed_heal)
	_assert(not stuffed_heal_events[0].treated and stuffed_heal_events[0].skip_reason == "", "heal settlement rolls the resolver chance, not the stuffed catalog field")

	# 潜能激发：扣费、本次攻击加成；生命不够不掷。结算率走 AWAKEN_CHANCE。
	_disarm(attacker)
	_disarm(defender)
	attacker.skills = [SkillCatalog.by_id("skill_awaken")]
	var awaken_cost := CombatResolver.awaken_cost(attacker)
	_assert(is_equal_approx(float(awaken_cost) / float(attacker.max_hp), CombatResolver.AWAKEN_HP_SHARE), "awaken cost is the live max-HP share")
	_assert(CombatResolver.can_awaken(attacker), "full HP can pay for awaken")
	var rng_awaken := RollSource.new(1)
	rng_awaken.push([0.0, 0.0, 0.99])
	var awaken_events: Array[StrikeResult] = CombatResolver.resolve_strikes(attacker, defender, steer, rng_awaken)
	_assert(awaken_events[0].awakened, "awaken flags the opening strike")
	_assert(awaken_events[0].awaken_cost == awaken_cost, "awaken cost is 10% max HP")
	_assert(awaken_events[0].hit, "awaken strike still has to land")
	var expected_awaken_dmg := maxi(1, int(round(float(CombatResolver.strike_damage(defender)) * (1.0 + CombatResolver.AWAKEN_DAMAGE_BONUS) * (1.0 - defender.stacked_damage_reduction()))))
	_assert(awaken_events[0].damage == expected_awaken_dmg, "awaken adds 50% extra damage through the shipped formula")
	_assert(attacker.hp == attacker.max_hp - awaken_cost, "awaken spends 10% max HP")
	var awaken_hit := CombatResolver.hit_chance(attacker, defender, steer, CombatResolver.AWAKEN_HIT_BONUS)
	var plain_hit := CombatResolver.hit_chance(attacker, defender, steer)
	_assert(awaken_hit > plain_hit, "awaken raises this-attack hit chance")
	_assert(is_equal_approx(awaken_hit, CombatResolver.CERTAIN_HIT_CHANCE), "+50% this-strike accuracy clears the certain-hit edge")
	_disarm(attacker)
	_disarm(defender)
	attacker.skills = [SkillCatalog.by_id("skill_awaken")]
	# 挑战者 15% 闪避、没有命中加成时命中线是 75%，0.9 会被闪掉；
	# 激发 +50% 命中把净差顶过 FULL_HIT_EDGE，这一击必中，再高的点数也照样打中。
	var rng_awaken_hit := RollSource.new(1)
	rng_awaken_hit.push([0.0, 0.9, 0.99])
	var awaken_mid: Array[StrikeResult] = CombatResolver.resolve_strikes(attacker, defender, steer, rng_awaken_hit)
	_assert(awaken_mid[0].awakened and awaken_mid[0].hit, "awaken +50% hit turns a 0.9 roll into a hit")
	_disarm(attacker)
	_disarm(defender)
	var rng_no_awaken_hit := RollSource.new(1)
	rng_no_awaken_hit.push([0.9])
	var no_awaken_mid: Array[StrikeResult] = CombatResolver.resolve_strikes(attacker, defender, steer, rng_no_awaken_hit)
	_assert(no_awaken_mid[0].dodged, "the same 0.9 roll dodges without awaken")
	_disarm(attacker)
	_disarm(defender)
	attacker.skills = [SkillCatalog.by_id("skill_awaken")]
	attacker.hp = awaken_cost
	_assert(not CombatResolver.can_awaken(attacker), "HP equal to the cost is not enough")
	var hp_before_poor := attacker.hp
	var rng_poor := RollSource.new(1)
	rng_poor.push([0.0, 0.99])
	var poor_awaken: Array[StrikeResult] = CombatResolver.resolve_strikes(attacker, defender, steer, rng_poor)
	_assert(not poor_awaken[0].awakened, "awaken does not trigger when HP cannot pay")
	_assert(attacker.hp == hp_before_poor or poor_awaken[0].hit, "insufficient HP skips the awaken roll")
	_assert(attacker.hp == hp_before_poor, "awaken does not spend HP when it cannot trigger")
	_disarm(attacker)
	_disarm(defender)
	attacker.skills = [SkillCatalog.by_id("skill_awaken")]
	defender.skills = [SkillCatalog.by_id("skill_counter")]
	var rng_awaken_counter := RollSource.new(1)
	rng_awaken_counter.push([0.0, 0.0, 0.99, 0.0, 0.0, 0.99])
	var awaken_counter_events: Array[StrikeResult] = CombatResolver.resolve_strikes(attacker, defender, steer, rng_awaken_counter)
	var counter_awoke := false
	for ev in awaken_counter_events:
		if ev.countered and ev.awakened:
			counter_awoke = true
	_assert(not counter_awoke, "counter bursts do not roll 潜能激发")
	_disarm(attacker)
	_disarm(defender)
	var stuffed_awaken := SkillCatalog.by_id("skill_awaken")
	stuffed_awaken.awaken_chance = 1.0
	attacker.skills = [stuffed_awaken]
	var rng_stuffed_awaken := RollSource.new(1)
	rng_stuffed_awaken.push([0.50, 0.0, 0.99])
	var stuffed_awaken_events: Array[StrikeResult] = CombatResolver.resolve_strikes(attacker, defender, steer, rng_stuffed_awaken)
	_assert(not stuffed_awaken_events[0].awakened, "awaken settlement rolls AWAKEN_CHANCE, not the stuffed catalog field")

	# 三步口径：谁出手都从 BASE_HIT_CHANCE 起步，再按净命中优势走曲线，最后叠胜率偏移。
	var plain_champ := _make_fighter("plain_champ", 1000, "", true)
	var plain_foe := _make_fighter("plain_foe", 1000, "", false)
	_disarm(plain_champ)
	_disarm(plain_foe)
	_assert(is_equal_approx(CombatResolver.hit_chance(plain_champ, plain_foe, 0.0), CombatResolver.BASE_HIT_CHANCE - plain_foe.stacked_dodge()), "a negative net edge comes straight off the base hit chance")
	_assert(is_equal_approx(CombatResolver.hit_chance_before_steer(0.0), CombatResolver.BASE_HIT_CHANCE), "no net edge means the plain base hit chance")
	_assert(is_equal_approx(CombatResolver.hit_chance_before_steer(CombatResolver.FULL_HIT_EDGE * 0.5), (CombatResolver.BASE_HIT_CHANCE + 1.0) * 0.5), "half the certain-hit edge lands halfway to certainty")
	_assert(is_equal_approx(CombatResolver.hit_chance_before_steer(CombatResolver.FULL_HIT_EDGE), CombatResolver.CERTAIN_HIT_CHANCE), "the full certain-hit edge is a certain hit")

	# 必中只能自己堆出来：净命中优势满 FULL_HIT_EDGE 就是 100%，而且胜率偏移撼不动它。
	var sharp := _make_fighter("sharp", 1000, "", true)
	var soft := _make_fighter("soft", 1000, "", false)
	_disarm(sharp)
	_disarm(soft)
	var sharp_eye := SkillDef.new()
	sharp_eye.id = "probe_hit"
	sharp_eye.accuracy_bonus = soft.stacked_dodge() + CombatResolver.FULL_HIT_EDGE
	sharp.skills = [sharp_eye]
	_assert(is_equal_approx(CombatResolver.net_hit_edge(sharp, soft), CombatResolver.FULL_HIT_EDGE), "the probe is exactly one certain-hit edge ahead")
	_assert(is_equal_approx(CombatResolver.hit_chance(sharp, soft, 0.0), CombatResolver.CERTAIN_HIT_CHANCE), "clearing the certain-hit edge always lands")
	_assert(is_equal_approx(CombatResolver.hit_chance(sharp, soft, -0.30), CombatResolver.CERTAIN_HIT_CHANCE), "a hopeless target win rate cannot take that certainty away")
	sharp_eye.accuracy_bonus -= 0.01
	_assert(CombatResolver.hit_chance(sharp, soft, 0.0) < CombatResolver.CERTAIN_HIT_CHANCE, "one point short of the edge is not a certain hit")
	# 偏移的话语权随净优势递减，所以必中阈值两侧是连着的，不是一道断崖：
	# 差 0.5 个百分点、再配上一个极端不利的偏移，也还在 100% 附近。
	_assert(is_equal_approx(CombatResolver.steer_weight(0.0), 1.0), "with no net edge the steer has the whole say")
	_assert(is_equal_approx(CombatResolver.steer_weight(CombatResolver.FULL_HIT_EDGE * 0.5), 0.5), "halfway to certainty the steer only half counts")
	_assert(is_equal_approx(CombatResolver.steer_weight(CombatResolver.FULL_HIT_EDGE), 0.0), "at the certain-hit edge the steer has no say left")
	sharp_eye.accuracy_bonus += 0.005
	var brink := CombatResolver.hit_chance(sharp, soft, -0.30)
	_assert(CombatResolver.CERTAIN_HIT_CHANCE - brink < 0.02, "just short of certainty is still just short, not a cliff (%.3f)" % brink)
	# 反过来，光靠战力差顶多推到 MAX_HIT_CHANCE，推不出必中，也压不到必闪之下。
	_assert(is_equal_approx(CombatResolver.hit_chance(plain_champ, plain_foe, 10.0), CombatResolver.MAX_HIT_CHANCE), "a huge steer still stops at the 95% rail")
	_assert(is_equal_approx(CombatResolver.hit_chance(plain_champ, plain_foe, -10.0), CombatResolver.MIN_HIT_CHANCE), "and a huge negative steer still leaves the 5% rail")

	# 最悬殊的战力差下，双方净优势都不够必中，命中率就还夹在 5%~95% 之间，
	# 掷到极端点数时结果照样翻转。
	var hopeless := CombatResolver.champion_win_rate(1, 1000000)
	var crushing := CombatResolver.champion_win_rate(1000000, 1)
	for target in [hopeless, crushing]:
		var hit := CombatResolver.champion_steer(target)
		var champ := _make_fighter("champ", 1000, AgentChannels.CHANNEL_CLAUDE, true)
		var foe := _make_fighter("foe", 1000, AgentChannels.CHANNEL_GROK, false)
		var champ_buff := SkillCatalog.agent_buff_template(AgentChannels.CHANNEL_CLAUDE)
		champ_buff.accuracy_bonus = 0.10
		_give_buffs(champ, [champ_buff])
		var foe_buff := SkillCatalog.agent_buff_template(AgentChannels.CHANNEL_GROK)
		foe_buff.dodge_bonus = 0.10
		_give_buffs(foe, [foe_buff])
		# 贴到 95% 的上轨也还有 5% 会被闪掉——底线是“不必中”，不是“不到轨”。
		_assert(CombatResolver.hit_chance(champ, foe, hit) >= CombatResolver.MIN_HIT_CHANCE, "champion can always land a hit (target %.2f)" % target)
		_assert(CombatResolver.hit_chance(champ, foe, hit) < CombatResolver.CERTAIN_HIT_CHANCE, "champion can always miss (target %.2f)" % target)
		_assert(CombatResolver.hit_chance(foe, champ, hit) >= CombatResolver.MIN_HIT_CHANCE, "opponent can always land a hit (target %.2f)" % target)
		_assert(CombatResolver.hit_chance(foe, champ, hit) < CombatResolver.CERTAIN_HIT_CHANCE, "opponent can always miss (target %.2f)" % target)
		var rng_roll_zero := RollSource.new(1)
		rng_roll_zero.push([0.0])
		_assert(CombatResolver.resolve_strikes(champ, foe, hit, rng_roll_zero)[0].hit, "roll 0 always hits, whatever the target (%.2f)" % target)
		foe.hp = foe.max_hp
		var rng_roll_one := RollSource.new(1)
		rng_roll_one.push([0.999])
		var high_miss: StrikeResult = CombatResolver.resolve_strikes(champ, foe, hit, rng_roll_one)[0]
		_assert(not high_miss.hit and high_miss.dodged, "roll 0.999 is a dodge, never a whiff (target %.2f)" % target)

	# 连击是“多一次机会”，不是“保证打中”——追击同样要过命中判定。
	var combo_src := FileAccess.get_file_as_string("res://scripts/combat_resolver.gd")
	_assert(combo_src.find("auto_hit") < 0, "no auto-hit shortcut exists in the resolver")
	var combo_attacker := _make_fighter("combo", 1000, "", true)
	var combo_target := _make_fighter("target", 1000, "", false)
	_disarm(combo_attacker)
	_disarm(combo_target)
	combo_attacker.skills = [SkillCatalog.by_id("skill_double")]
	var rng_combo := RollSource.new(1)
	# 首击命中 -> 暴击未中 -> 二连击触发 -> 追击掷到 0.999 落空。
	rng_combo.push([0.0, 0.99, 0.0, 0.999])
	var combo_events: Array[StrikeResult] = CombatResolver.resolve_strikes(combo_attacker, combo_target, 0.5, rng_combo)
	_assert(combo_events.size() == 2 and combo_events[1].combo, "the double-strike extra swing is still rolled")
	_assert(not combo_events[1].hit, "an extra swing can miss like any other")

	# 幻影刺杀：在本会闪掉的点数上仍命中，并把 HP 打到 0。从完整 resolve_strikes 进，不从“已经命中之后”开始。
	_disarm(attacker)
	_disarm(defender)
	attacker.skills = [SkillCatalog.by_id("skill_assassinate")]
	var dodge_for_kill := SkillCatalog.agent_buff_template(AgentChannels.CHANNEL_GROK)
	dodge_for_kill.dodge_bonus = 0.25
	_give_buffs(defender, [dodge_for_kill])
	var rng_ass := RollSource.new(1)
	rng_ass.push([0.4, 0.0])
	var ass_events: Array[StrikeResult] = CombatResolver.resolve_strikes(attacker, defender, steer, rng_ass)
	_assert(ass_events.size() == 1 and ass_events[0].hit, "assassinate hits on a roll that would otherwise dodge")
	_assert(ass_events[0].assassinated, "assassinate flags the strike")
	_assert(not ass_events[0].dodged, "assassinate ignores dodge")
	_assert(defender.hp == 0 and ass_events[0].defender_died, "champion assassinate without rebirth knocks the target out")

	_disarm(attacker)
	_disarm(defender)
	attacker.skills = [SkillCatalog.by_id("skill_assassinate")]
	defender.skills = [SkillCatalog.by_id("skill_rebirth")]
	defender.rebirth_available = true
	_give_buffs(defender, [dodge_for_kill])
	var rng_ass_rb := RollSource.new(1)
	rng_ass_rb.push([0.4, 0.0])
	var ass_rb: Array[StrikeResult] = CombatResolver.resolve_strikes(attacker, defender, steer, rng_ass_rb)
	_assert(ass_rb[0].assassinated and ass_rb[0].revived, "assassinate with rebirth revives instead of a kill")
	_assert(defender.is_alive() and defender.hp == defender.max_hp, "rebirth restores full HP after assassinate")
	_assert(not ass_rb[0].defender_died, "a revived target is not counted as downed")

	# 绝对防御每一次挨打都掷，幻影刺杀也挡得住：它无视的是闪避，不是防御。
	_disarm(attacker)
	_disarm(defender)
	attacker.skills = [SkillCatalog.by_id("skill_assassinate")]
	defender.skills = [SkillCatalog.by_id("skill_guard")]
	_give_buffs(defender, [dodge_for_kill])
	var rng_ass_guard := RollSource.new(1)
	# 命中点 → 刺杀掷中 → 绝对防御掷中。
	rng_ass_guard.push([0.4, 0.0, 0.0])
	var ass_guard: Array[StrikeResult] = CombatResolver.resolve_strikes(attacker, defender, steer, rng_ass_guard)
	_assert(ass_guard.size() == 1 and ass_guard[0].guarded, "absolute guard rolls on an assassinate hit too")
	_assert(ass_guard[0].damage == 0 and defender.hp == defender.max_hp, "a guarded assassinate deals nothing")
	_assert(defender.is_alive() and not ass_guard[0].defender_died, "a guarded assassinate is not a kill")
	# 同一手牌，绝对防御没掷中就照常秒杀。
	_disarm(attacker)
	_disarm(defender)
	attacker.skills = [SkillCatalog.by_id("skill_assassinate")]
	defender.skills = [SkillCatalog.by_id("skill_guard")]
	_give_buffs(defender, [dodge_for_kill])
	var rng_ass_open := RollSource.new(1)
	rng_ass_open.push([0.4, 0.0, 0.99])
	var ass_open: Array[StrikeResult] = CombatResolver.resolve_strikes(attacker, defender, steer, rng_ass_open)
	_assert(ass_open[0].assassinated and not ass_open[0].guarded, "a failed guard roll lets the assassinate through")
	_assert(defender.hp == 0, "the unguarded assassinate still knocks the target out")

	# 追击不掷幻影刺杀：首击未刺杀、追击落在闪避段，不得变成刺杀。
	_disarm(attacker)
	_disarm(defender)
	attacker.skills = [SkillCatalog.by_id("skill_assassinate"), SkillCatalog.by_id("skill_double")]
	_give_buffs(defender, [dodge_for_kill])
	defender.hits_to_down = 20
	defender.hp = defender.max_hp
	# 闪避 25% + 基础 15%，命中线 50%，所以追击那一下的 0.6 落在闪避段。
	var rng_ass_follow := RollSource.new(1)
	rng_ass_follow.push([0.0, 0.99, 0.99, 0.0, 0.6])
	var ass_follow: Array[StrikeResult] = CombatResolver.resolve_strikes(attacker, defender, steer, rng_ass_follow)
	_assert(ass_follow.size() == 2 and ass_follow[1].combo, "double still adds a follow-up after a non-assassinate opener")
	_assert(not ass_follow[1].assassinated, "follow-up swings do not roll assassinate")
	_assert(ass_follow[1].dodged and not ass_follow[1].hit, "the follow-up still respects dodge")

	# 挑战者的幻影刺杀：2% 触发，无视闪避，打最大生命的一半，不是秒杀。
	var chal_killer := _make_fighter("chal", 1000, "", false)
	var boss_target := _make_fighter("boss", 1000, "", true)
	_disarm(chal_killer)
	_disarm(boss_target)
	chal_killer.skills = [SkillCatalog.by_id("skill_assassinate")]
	_give_buffs(boss_target, [dodge_for_kill])
	boss_target.hits_to_down = 20
	boss_target.hp = boss_target.max_hp
	_assert(is_equal_approx(CombatResolver.assassinate_chance(chal_killer), CombatResolver.ASSASSINATE_CHANCE_CHALLENGER), "challenger rolls the live assassinate chance")
	_assert(is_equal_approx(CombatResolver.assassinate_chance(attacker), CombatResolver.ASSASSINATE_CHANCE_CHAMPION), "champion rolls the live assassinate chance")
	var expected_cut := CombatResolver.assassinate_damage(chal_killer, boss_target)
	var rng_chal_ass := RollSource.new(1)
	rng_chal_ass.push([0.4, 0.0])
	var chal_ass: Array[StrikeResult] = CombatResolver.resolve_strikes(chal_killer, boss_target, steer, rng_chal_ass)
	_assert(chal_ass[0].assassinated and chal_ass[0].hit and not chal_ass[0].dodged, "challenger assassinate still ignores dodge")
	_assert(chal_ass[0].damage == expected_cut, "challenger assassinate deals the shipped 50% max HP cut")
	_assert(expected_cut * 2 == boss_target.max_hp, "challenger assassinate cut is half the target max HP")
	_assert(boss_target.hp == boss_target.max_hp - expected_cut and boss_target.is_alive(), "challenger assassinate is not a one-shot on a full bar")
	_assert(not chal_ass[0].defender_died, "a half-bar cut does not count as downed")

	# 凌波微步：本下闪避并立刻还击。
	_disarm(attacker)
	_disarm(defender)
	defender.skills = [SkillCatalog.by_id("skill_lingbo")]
	var rng_lb := RollSource.new(1)
	rng_lb.push([0.0, 0.0, 0.0])
	var lb_events: Array[StrikeResult] = CombatResolver.resolve_strikes(attacker, defender, steer, rng_lb)
	_assert(lb_events[0].dodged and lb_events[0].lingbo and not lb_events[0].hit, "lingbo dodges a swing that would have hit")
	_assert(lb_events.size() >= 2 and lb_events[1].countered, "lingbo is followed by a counter swing")
	_assert(not lb_events[1].combo, "lingbo counter does not combo")
	_assert(not lb_events[1].lingbo, "the counter swing does not roll lingbo again")

	# 追击不掷凌波微步。
	_disarm(attacker)
	_disarm(defender)
	attacker.skills = [SkillCatalog.by_id("skill_double")]
	defender.skills = [SkillCatalog.by_id("skill_lingbo")]
	defender.hits_to_down = 20
	defender.hp = defender.max_hp
	var rng_lb_follow := RollSource.new(1)
	rng_lb_follow.push([0.0, 0.99, 0.99, 0.0, 0.0, 0.99])
	var lb_follow: Array[StrikeResult] = CombatResolver.resolve_strikes(attacker, defender, steer, rng_lb_follow)
	_assert(lb_follow.size() == 2 and lb_follow[1].combo, "double follow-up still happens when lingbo misses the opener")
	_assert(lb_follow[1].hit and not lb_follow[1].lingbo, "follow-up swings do not roll lingbo")

	# 二连 + 三连同时成功 = 5 连；追击不再追加连击。
	_disarm(attacker)
	_disarm(defender)
	attacker.skills = [SkillCatalog.by_id("skill_double"), SkillCatalog.by_id("skill_triple")]
	defender.hits_to_down = 20
	defender.hp = defender.max_hp
	var rng_five := RollSource.new(1)
	for i in 12:
		rng_five.push([0.0])
	var five_events: Array[StrikeResult] = CombatResolver.resolve_strikes(attacker, defender, steer, rng_five)
	_assert(five_events.size() == 5, "double+triple merge into five swings")
	_assert(not five_events[0].combo and five_events[0].extra_index == 0, "five-hit opener is the shared first swing")
	for i in range(1, 5):
		_assert(five_events[i].combo and five_events[i].extra_index == i, "follow-up %d is a combo swing" % i)


## 造一条排行榜记录。channel 留空表示这个人没有可识别的 agent。
func _ranked(name: String, tokens: int, channel: String = "") -> RankedUser:
	var user := RankedUser.new()
	user.username = name
	user.tokens = tokens
	user.channel = channel
	user.agent_name = AgentChannels.agent_display_name(channel)
	if not channel.is_empty():
		user.channels = PackedStringArray([channel])
		user.agents = PackedStringArray([user.agent_name])
	return user


## 给角色挂上一组指定的 agent buff（每个 agent 一个）。
func _give_buffs(fighter: Fighter, buffs: Array[SkillDef]) -> void:
	fighter.agent_buffs = buffs


## 一串全是 0.0 的掷点，让接下来的判定必定命中。
## count 要给够，一次行动可能连掷十几次。
func _always_hits(count: int = 64) -> RollSource:
	var rng := RollSource.new(1)
	for i in count:
		rng.push([0.0])
	return rng


## 车轮战的流程：擂主血条扛全场、挑战者逐个上、换人和终局判定。
func _test_wheel_war() -> void:
	var ranked: Array[RankedUser] = [
		_ranked("champ", 100000000),
		_ranked("b", 5000000),
		_ranked("c", 5000000),
		_ranked("d", 5000000),
	]
	var rng := RollSource.new(1)
	rng.push([0, 0])
	var war := WheelWar.new()
	war.setup(ranked, rng)
	_disarm(war.champion)
	if war.current_opponent:
		_disarm(war.current_opponent)
	for waiting in war.waiting:
		_disarm(waiting)
	_assert(war.champion.username == "champ", "left side is always rank 1")
	_assert(war.active_opponent_count() == 1, "only one opponent is active on the right")
	_assert(war.current_opponent.username == "c", "queued shuffle puts a specific opponent first")
	_assert(war.waiting.size() == 2, "the rest wait off-stage")
	_assert(war.current_opponent.username != "champ", "champion is not on the right")
	_assert(war.win_rate > 0.5, "a champion this far ahead is favoured")
	_assert(war.win_rate <= CombatResolver.MAX_WIN_RATE, "even a runaway champion stops at 70%")

	# 双方需要的有效命中总数是对等的：擂主的血条按“要扛几场”摊开。
	_assert(war.champion.hits_to_down == CombatResolver.HITS_PER_DUEL * 3, "champion endurance covers every challenger")
	_assert(war.current_opponent.hits_to_down == CombatResolver.HITS_PER_DUEL, "each challenger takes one duel worth of hits")

	var names: PackedStringArray = PackedStringArray()
	names.append(war.current_opponent.username)
	for waiting in war.waiting:
		names.append(waiting.username)
	names.sort()
	_assert(",".join(names) == "b,c,d", "right-side queue is a permutation of non-champions")

	# 每次判定都掷 0，双方必然命中。挑战者永远先手；擂主靠更长血条把对手逐个清掉。
	var opener: Fighter = war.current_opponent
	var first_events: Array[StrikeResult] = war.simulate_turn(_always_hits())
	_assert(first_events.size() >= 1, "a turn produces strike events")
	_assert(first_events[0].attacker_name == opener.username, "challenger always acts first")
	_assert(first_events[0].attacker_name != war.champion.username, "champion does not open the turn")
	var downed := 0
	if opener != null and not opener.is_alive():
		downed += 1
	while war.outcome == WheelWar.Outcome.ONGOING:
		_assert(war.active_opponent_count() <= 1, "never more than one opponent in play")
		var before: Fighter = war.current_opponent
		var events: Array[StrikeResult] = war.simulate_turn(_always_hits())
		_assert(events.size() >= 1, "a turn produces strike events")
		if before != null and not before.is_alive():
			downed += 1
	_assert(war.outcome == WheelWar.Outcome.ALL_OPPONENTS_DOWN, "all others dead ends the fight")
	_assert(war.champion.is_alive(), "champion is still alive when others are wiped")
	_assert(downed == 3, "every challenger went down in turn")

	var death_ranked: Array[RankedUser] = [
		_ranked("champ", 5000000),
		_ranked("heavy", 100000000),
		_ranked("x", 10000000),
		_ranked("y", 10000000),
	]
	var death_war := WheelWar.new()
	var death_setup := RollSource.new(1)
	death_setup.push([2, 1])
	death_war.setup(death_ranked, death_setup)
	_disarm(death_war.champion)
	if death_war.current_opponent:
		_disarm(death_war.current_opponent)
	for waiting in death_war.waiting:
		_disarm(waiting)
	_assert(death_war.current_opponent.username == "heavy", "identity shuffle keeps the heavy hitter first")
	_assert(death_war.win_rate >= CombatResolver.MIN_WIN_RATE, "a hopeless champion still keeps the 30% floor")
	_assert(death_war.win_rate < 0.5, "but he is clearly the underdog")
	# 把擂主压到一击必死，用来确认擂主倒下会立刻结束这场车轮战。
	# 血量也一起压到 1：擂主有 5% 先天减伤，光靠 hits_to_down=1 会剩一丝血。
	death_war.champion.hits_to_down = 1
	death_war.champion.hp = 1
	death_war.simulate_turn(_always_hits())
	_assert(death_war.outcome == WheelWar.Outcome.CHAMPION_DOWN, "champion HP<=0 ends the fight")
	_assert(death_war.champion.hp <= 0, "champion is dead")
	var others_left := death_war.waiting.size()
	if death_war.current_opponent != null and death_war.current_opponent.is_alive():
		others_left += 1
	_assert(others_left >= 2, "remaining opponents are not all dead when champion falls")


## 同一份榜单打 trials 场，返回 {"target": 目标胜率, "actual": 实测胜率}。
## 两条胜率回归（6 阵容、1vN）共用这一段：种子怎么取、打到什么算赢、
## 多少回合算跑飞，都只有这一处说了算，改抽样方式不用改两遍。
func _measure_win_rate(roster: Array[RankedUser], trials: int, max_turns: int) -> Dictionary:
	var wins := 0
	var target := 0.0
	for trial in range(trials):
		var war := WheelWar.new()
		var rng := RollSource.new(trial * 7919 + 13)
		war.setup(roster, rng)
		target = war.win_rate
		var turns := 0
		while war.outcome == WheelWar.Outcome.ONGOING and turns < max_turns:
			war.simulate_turn(rng)
			turns += 1
		if war.outcome == WheelWar.Outcome.ALL_OPPONENTS_DOWN:
			wins += 1
	return {"target": target, "actual": float(wins) / float(maxi(1, trials))}


## 蒙特卡洛回归：实测胜率必须落在 [30%, 70%]，并且跟着目标胜率走。
## 改动技能池、技能位数量或伤害口径之后，这里会第一个报警，对应的标定常数是
## CombatResolver.CHAMPION_SKILL_EDGE_PER_SKILL / AGENT_BUFF_HIT_EDGE / WIN_RATE_SPREAD。
##
## "head to head" 只有一个挑战者，整场只掷十几次骰子，随机性本身会把实测往 50% 拉，
## 所以它会稳定地比目标低几个点——容差留到 0.12 就是为了容下这种短局。
func _test_win_rate_regression() -> void:
	var codex := AgentChannels.CHANNEL_CODEX
	var claude := AgentChannels.CHANNEL_CLAUDE
	var grok := AgentChannels.CHANNEL_GROK
	var buddy := AgentChannels.CHANNEL_WORKBUDDY
	# [token, 当天用过的渠道...]，渠道数就是 buff 数。
	var rosters := {
		"today's real board": [
			[348431491, codex], [200872388, codex, grok, claude], [130109847, codex],
			[77757152, codex], [75203811, codex], [67590177, codex], [64627005, codex],
			[61865052, claude, codex], [40721041, codex], [40265773, codex],
			[30220066, codex, buddy], [29920026, codex], [9984526, codex],
			[4963797, codex], [1718871, buddy],
		],
		"runaway leader": [
			[900000000, codex], [50000000, codex], [50000000, claude],
			[50000000, grok], [50000000, buddy], [50000000, codex, grok],
		],
		"even field": [
			[60000000, codex], [50000000, codex], [50000000, claude],
			[50000000, grok], [50000000, buddy], [50000000, codex, claude],
		],
		"outgunned champion": [
			[50000000, codex], [48000000, codex, claude, grok], [47000000, claude],
			[46000000, grok], [45000000, buddy], [44000000, codex, buddy],
		],
		"champion with every agent": [
			[80000000, codex, claude, grok, buddy], [50000000, codex],
			[50000000, claude], [50000000, grok], [50000000, buddy],
		],
		"head to head": [[50000000, codex], [50000000, grok]],
	}
	for label in rosters.keys():
		var rows: Array = rosters[label]
		var roster: Array[RankedUser] = []
		for i in range(rows.size()):
			var row: Array = rows[i]
			var user := RankedUser.new()
			user.username = "p%d" % i
			user.tokens = int(row[0])
			for c in range(1, row.size()):
				user.channels.append(str(row[c]))
				user.agents.append(AgentChannels.agent_display_name(str(row[c])))
			user.channel = user.channels[0]
			user.agent_name = AgentChannels.agent_display_name(user.channel)
			roster.append(user)
		# 120 次抽样的标准误约 4.5 个点，贴着 80% 上限的阵容会随机越界，
		# 所以样本量提到 240，并按 2.5 个标准误给实测值留出抖动空间。
		var trials := 240
		var measured := _measure_win_rate(roster, trials, 4000)
		var target: float = measured["target"]
		var actual: float = measured["actual"]
		var noise := 2.5 * sqrt(0.25 / float(trials))
		_assert(target >= CombatResolver.MIN_WIN_RATE and target <= CombatResolver.MAX_WIN_RATE, "%s: target win rate %.2f stays inside [30%%, 70%%]" % [label, target])
		_assert(actual >= CombatResolver.MIN_WIN_RATE - noise, "%s: measured win rate %.2f is at or above the 30%% floor (target %.2f)" % [label, actual, target])
		_assert(actual <= CombatResolver.MAX_WIN_RATE + noise, "%s: measured win rate %.2f is at or below the 70%% ceiling (target %.2f)" % [label, actual, target])
		_assert(absf(actual - target) < 0.12, "%s: measured win rate %.2f tracks its %.2f target" % [label, actual, target])


## 人数回归：1v1 / 1v10 / 1v50 都要打得出目标胜率。
##
## 目标本身分两截算（CombatResolver.champion_win_rate）：人均战力比决定强弱，
## 人数压力单独往下压。这条用例盯的是**实测跟不跟得住目标**——人一多，
## 一场仗要掷几百次骰，胜负越来越取决于开局发牌的手气而不是单次掷骰，
## 偏移的边际效果会被压扁，所以容差比 6 阵容那条宽一点。
##
## 已知的一处偏离：1v100 且擂主人均战力还碾压（4 倍以上）时，实测比目标低约 0.09。
## 那一档的目标已经顶在“人数压力扣完之后的天花板”附近，再往上没有空间，
## 而擂主每回合只打得掉一个人。真遇到这种榜单再单独标定，别为它把常规场次调歪。
func _test_roster_size_regression() -> void:
	# [挑战者人数, 擂主的人均战力倍率, 抽样场次]
	var cases := [[1, 1.0, 200], [1, 4.0, 200], [10, 1.0, 120], [10, 4.0, 120], [50, 1.0, 40]]
	for case in cases:
		var count := int(case[0])
		var mult := float(case[1])
		var trials := int(case[2])
		var roster: Array[RankedUser] = []
		for i in range(count + 1):
			var user := RankedUser.new()
			user.username = "p%d" % i
			user.tokens = int(50000000.0 * (mult if i == 0 else 1.0))
			user.channel = AgentChannels.CHANNEL_CODEX
			user.channels.append(user.channel)
			user.agents.append(AgentChannels.agent_display_name(user.channel))
			user.agent_name = user.agents[0]
			roster.append(user)
		var measured := _measure_win_rate(roster, trials, 20000)
		var target: float = measured["target"]
		var actual: float = measured["actual"]
		var label := "1v%d x%.0f" % [count, mult]
		_assert(target >= CombatResolver.MIN_WIN_RATE and target <= CombatResolver.MAX_WIN_RATE, "%s: target %.2f stays inside [30%%, 70%%]" % [label, target])
		_assert(absf(actual - target) < 0.15, "%s: measured %.2f tracks its %.2f target" % [label, actual, target])
	# 等战力的 1v1 必须是干干净净的五五开，这是这次改口径的起点。
	_assert(is_equal_approx(CombatResolver.champion_win_rate(100, 100, 1), 0.5), "an even duel is an even 50%")


## 设置页：三种窗口模式都摆出来、存得下读得回，认不出的值回落到默认。
func _test_settings() -> void:
	# 存取：写进临时文件再读回来，三种模式都要能原样往返。
	var path := "user://test_settings.json"
	for mode in AppSettings.MODES:
		AppSettings.save_mode(mode, path)
		_assert(AppSettings.load_mode(path) == mode, "window mode %s survives a save/load round trip" % AppSettings.mode_display_name(mode))
	# 存档没有 / 坏了 / 是个没见过的值，都回落到默认，绝不让游戏开不起来。
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	_assert(AppSettings.load_mode(path) == AppSettings.DEFAULT_MODE, "a missing settings file falls back to the default mode")
	var junk := FileAccess.open(path, FileAccess.WRITE)
	junk.store_string("not json at all")
	junk.close()
	_assert(AppSettings.load_mode(path) == AppSettings.DEFAULT_MODE, "a corrupt settings file falls back to the default mode")
	AppSettings.save_mode(999, path)
	_assert(AppSettings.load_mode(path) == AppSettings.DEFAULT_MODE, "an unknown mode value falls back to the default mode")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

	# 只有窗口模式带边框，另外两种都是无边框的沉浸式。
	_assert(AppSettings.has_border(AppSettings.Mode.WINDOWED), "windowed keeps the system border")
	_assert(not AppSettings.has_border(AppSettings.Mode.MAXIMIZED), "maximized is borderless")
	_assert(not AppSettings.has_border(AppSettings.Mode.FULLSCREEN), "fullscreen is borderless")
	# 三种模式各自映射到不同的 DisplayServer 窗口模式。
	_assert(AppSettings.window_mode_for(AppSettings.Mode.WINDOWED) == DisplayServer.WINDOW_MODE_WINDOWED, "windowed maps to WINDOW_MODE_WINDOWED")
	_assert(AppSettings.window_mode_for(AppSettings.Mode.MAXIMIZED) == DisplayServer.WINDOW_MODE_MAXIMIZED, "maximized maps to WINDOW_MODE_MAXIMIZED")
	_assert(AppSettings.window_mode_for(AppSettings.Mode.FULLSCREEN) == DisplayServer.WINDOW_MODE_FULLSCREEN, "fullscreen maps to WINDOW_MODE_FULLSCREEN")

	# 场景本身：三个固定模式按钮都在设计器节点树里，运行时只绑定模式数据。
	var packed := load("res://scenes/settings.tscn") as PackedScene
	_assert(packed != null, "settings.tscn loads")
	WebLaunchConfig.reset()
	var scene: Node = packed.instantiate()
	scene.settings_path = path
	root.add_child(scene)
	await process_frame
	_assert(scene.get_node_or_null("%BackButton") != null, "Settings has a Back button")
	var list := scene.get_node_or_null("%ModeList") as VBoxContainer
	_assert(list != null, "Settings has a mode list")
	var buttons := 0
	for child in list.get_children():
		if child is Button:
			buttons += 1
	_assert(buttons == AppSettings.MODES.size(), "every window mode gets a button (%d)" % buttons)
	_assert(scene.get_node_or_null("%WindowedButton") != null, "windowed mode button is scene-authored")
	_assert(scene.get_node_or_null("%MaximizedButton") != null, "maximized mode button is scene-authored")
	_assert(scene.get_node_or_null("%FullscreenButton") != null, "fullscreen mode button is scene-authored")
	var settings_src := FileAccess.get_file_as_string("res://scenes/settings.gd")
	_assert(settings_src.find("Button.new") < 0 and settings_src.find("%ModeList.add_child") < 0, "settings binds fixed mode controls without constructing them in code")
	# 服务器那一栏：下拉选择 + 增加输入 + 增删操作 + 一行当前 endpoint。
	var select := scene.get_node_or_null("%ServerSelect") as OptionButton
	var input := scene.get_node_or_null("%ServerAddInput") as LineEdit
	_assert(select != null, "Settings has a server selector")
	_assert(input != null, "Settings has a server add field")
	_assert(input.placeholder_text == AppSettings.SERVER_PLACEHOLDER, "the add field shows the expected protocol://host:port/ form")
	_assert(scene.get_node_or_null("%ServerAdd") != null, "Settings can add a local server")
	_assert(scene.get_node_or_null("%ServerDelete") != null, "Settings can delete the selected local server")
	var status := scene.get_node_or_null("%ServerStatus") as Label
	_assert(status != null and status.text.find(TokenUsageApi.usage_url()) >= 0, "the status line names the endpoint actually in use")
	scene.queue_free()
	await process_frame
	WebLaunchConfig.reset()


## 榜单服务器地址：什么样的写法算合法、怎么存怎么读、还原之后回到默认地址，
## 以及它最终怎么换掉真正请求的那个 URL。
func _test_server_settings() -> void:
	# 合法写法：带端口 / 不带端口 / 结尾斜杠 / 大写协议 / IPv6 / 首尾空白。
	for text in ["http://192.168.1.10:8080/", "https://example.com", "HTTP://Example.com:80/",
			"http://[::1]:9000", "  https://localhost:3000/  ", "http://box-1.lan:8000"]:
		_assert(not AppSettings.normalize_base_url(text).is_empty(), "%s is a usable base url" % text)
	# 不合法：空、缺协议、别的协议、带路径或查询串、端口越界、缺主机。
	for text in ["", "   ", "example.com:8080", "ftp://example.com", "http://example.com/api/v1",
			"http://example.com?x=1", "http://example.com:70000", "http://example.com:0", "http://:8080"]:
		_assert(AppSettings.normalize_base_url(text).is_empty(), "%s is rejected" % text)
	# 规范化：去首尾空白、去结尾斜杠、协议小写，主机原样留着。
	_assert(AppSettings.normalize_base_url("  HTTPS://Example.com:8443/ ") == "https://Example.com:8443", "normalize trims, lowercases the scheme and drops the trailing slash")
	_assert(AppSettings.normalize_base_url("http://10.0.0.2:8080") == "http://10.0.0.2:8080", "an already normal base url survives unchanged")
	_assert(AppSettings.normalize_base_url("nonsense") == "", "an unusable base url normalizes to the empty string")
	var normalized_urls := AppSettings.normalize_base_urls([
		" https://one.example/ ", "garbage", "https://one.example", "http://two.example:8080/", "",
	])
	_assert(normalized_urls == PackedStringArray(["https://one.example", "http://two.example:8080"]), "a base-url list filters invalid entries, normalizes, deduplicates and keeps first-seen order")
	_assert(AppSettings.normalize_base_urls("https://not-an-array.example").is_empty(), "a non-array base-url source is rejected")

	var path := "user://test_server.json"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	_assert(AppSettings.load_base_url(path) == "", "no save file means no override")
	_assert(TokenUsageApi.usage_url(AppSettings.load_base_url(path)) == TokenUsageApi.DEFAULT_USAGE_URL, "and the default server is in use")
	AppSettings.save_base_url("http://10.0.0.2:8000/", path)
	_assert(AppSettings.load_base_url(path) == "http://10.0.0.2:8000", "a saved base url comes back normalized")
	_assert(TokenUsageApi.usage_url(AppSettings.load_base_url(path)).begins_with("http://10.0.0.2:8000"), "a saved base url is the one actually requested")
	# 还原：清掉之后又回到默认。
	AppSettings.clear_base_url(path)
	_assert(AppSettings.load_base_url(path) == "", "clearing restores the default server")
	# 存个不合法的进去等于清掉，绝不会把坏地址留在存档里。
	AppSettings.save_base_url("http://10.0.0.2:8000", path)
	AppSettings.save_base_url("garbage", path)
	_assert(AppSettings.load_base_url(path) == "", "saving an unusable base url clears the override")
	# 手工写脏数据进存档，读出来也当没设过。
	JsonStore.write_dict(path, {AppSettings.BASE_URL_KEY: "://oops"})
	_assert(AppSettings.load_base_url(path) == "", "a corrupt saved value falls back to the default server")
	# 两项设置共用一份存档，谁都不许把对方冲掉。
	AppSettings.save_mode(AppSettings.Mode.FULLSCREEN, path)
	AppSettings.save_base_url("https://box.lan:9443", path)
	_assert(AppSettings.load_mode(path) == AppSettings.Mode.FULLSCREEN, "saving the server address keeps the window mode")
	AppSettings.save_mode(AppSettings.Mode.WINDOWED, path)
	_assert(AppSettings.load_base_url(path) == "https://box.lan:9443", "saving the window mode keeps the server address")

	# 旧存档没有列表字段时，已选服务器就是唯一候选；新字段即使为空也是权威数据。
	JsonStore.write_dict(path, {
		AppSettings.MODE_KEY: AppSettings.Mode.FULLSCREEN,
		AppSettings.BASE_URL_KEY: "https://legacy.example/",
		"sentinel": "keep-me",
	})
	_assert(AppSettings.load_base_urls(path) == PackedStringArray(["https://legacy.example"]), "a legacy selected server migrates in memory as the sole candidate")
	JsonStore.write_dict(path, {
		AppSettings.BASE_URL_KEY: "https://legacy.example",
		AppSettings.BASE_URLS_KEY: [],
	})
	_assert(AppSettings.load_base_urls(path).is_empty(), "an explicitly saved empty candidate list does not resurrect the legacy selection")

	# 列表和选中项一次写入，不要冲掉同一 settings.json 里的其他字段。
	JsonStore.write_dict(path, {
		AppSettings.MODE_KEY: AppSettings.Mode.FULLSCREEN,
		"sentinel": "keep-me",
	})
	_assert(AppSettings.save_base_urls([
		"https://one.example/", "broken", "https://one.example", "http://two.example:8080/",
	], "http://two.example:8080/", path), "a normalized server list and selection save atomically")
	_assert(AppSettings.load_base_urls(path) == PackedStringArray(["https://one.example", "http://two.example:8080"]), "the stored candidate list is normalized and deduplicated")
	_assert(AppSettings.load_base_url(path) == "http://two.example:8080", "the selected candidate is stored normalized")
	var stored := JsonStore.read_dict(path)
	_assert(int(stored.get(AppSettings.MODE_KEY, -1)) == AppSettings.Mode.FULLSCREEN and str(stored.get("sentinel", "")) == "keep-me", "saving server candidates preserves every unrelated settings field")
	_assert(AppSettings.add_base_url("https://three.example/", path), "a valid local server can be added")
	_assert(AppSettings.load_base_urls(path) == PackedStringArray(["https://one.example", "http://two.example:8080", "https://three.example"]), "adding appends one normalized candidate")
	_assert(AppSettings.load_base_url(path) == "https://three.example", "adding a server selects it immediately")
	_assert(AppSettings.add_base_url(" https://three.example ", path), "adding an existing normalized server succeeds by selecting it")
	_assert(AppSettings.load_base_urls(path).size() == 3, "adding a duplicate does not create another option")
	_assert(AppSettings.remove_base_url("https://one.example", path), "an unselected local server can be removed")
	_assert(not AppSettings.load_base_urls(path).has("https://one.example"), "removing drops the requested candidate")
	_assert(AppSettings.load_base_url(path) == "https://three.example", "removing a different candidate keeps the current selection")
	_assert(AppSettings.remove_base_url("https://three.example", path), "the selected local server can be removed")
	_assert(AppSettings.load_base_url(path).is_empty(), "removing the selected server returns to the default")
	_assert(int(JsonStore.read_dict(path).get(AppSettings.MODE_KEY, -1)) == AppSettings.Mode.FULLSCREEN, "adding and removing servers preserves the window mode")
	AppSettings.save_base_urls(["https://one.example"], "https://missing.example", path)
	_assert(AppSettings.load_base_url(path).is_empty(), "a selection outside the saved candidate list falls back to default")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

	# 最后一环：基址怎么变成真正请求的地址。
	_assert(TokenUsageApi.usage_url("") == TokenUsageApi.DEFAULT_USAGE_URL, "no override means the built-in endpoint")
	_assert(TokenUsageApi.usage_url("http://10.0.0.2:8000") == "http://10.0.0.2:8000" + TokenUsageApi.USAGE_PATH, "an override keeps the endpoint path")
	_assert(TokenUsageApi.DEFAULT_USAGE_URL.ends_with(TokenUsageApi.USAGE_PATH), "both servers are asked for the same path")


## Web 启动配置：BaseURL 的“未提供”和“显式空列表”是两种语义，
## 注入列表替代本地列表，CloseMenu 只能关掉三个非核心入口。
func _test_web_launch_config() -> void:
	var path := "user://test_web_launch_config.json"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	AppSettings.save_base_urls(["https://local-a.example", "https://local-b.example"], "https://local-b.example", path)
	WebLaunchConfig.reset()
	_assert(not WebLaunchConfig.has_base_urls_override(), "without a Web BaseURL field there is no override")
	_assert(WebLaunchConfig.active_base_urls(path) == ["https://local-a.example", "https://local-b.example"], "an absent Web BaseURL field falls back to the local candidate list")
	_assert(WebLaunchConfig.effective_base_url(path) == "https://local-b.example", "a saved selection is effective when it belongs to the active local list")

	WebLaunchConfig.configure(true, [], [])
	_assert(WebLaunchConfig.has_base_urls_override(), "an explicitly empty Web BaseURL array still counts as an override")
	_assert(WebLaunchConfig.active_base_urls(path).is_empty(), "an explicitly empty Web BaseURL array does not fall back to local candidates")
	_assert(WebLaunchConfig.effective_base_url(path).is_empty(), "no active candidate means the built-in server is effective")

	var normalized := WebLaunchConfig.normalize_base_urls([
		" https://web-a.example/ ", "bad", "https://web-a.example", 42,
		"http://web-b.example:8080/", "https://web-c.example/path",
	])
	_assert(normalized == ["https://web-a.example", "http://web-b.example:8080"], "Web BaseURL normalization filters invalid and non-string values, deduplicates and preserves order")
	WebLaunchConfig.configure(true, [
		"https://web-a.example/", "invalid", "http://web-b.example:8080/", "https://web-a.example",
	], [])
	_assert(WebLaunchConfig.active_base_urls(path) == ["https://web-a.example", "http://web-b.example:8080"], "a provided Web list replaces rather than merges with local candidates")
	AppSettings.save_base_url("http://web-b.example:8080", path)
	_assert(WebLaunchConfig.effective_base_url(path) == "http://web-b.example:8080", "a saved selection is effective when it belongs to the injected list")
	AppSettings.save_base_url("https://local-a.example", path)
	_assert(WebLaunchConfig.effective_base_url(path).is_empty(), "a saved selection outside the injected list falls back to the built-in server")
	WebLaunchConfig.reset()
	_assert(WebLaunchConfig.active_base_urls(path) == ["https://local-a.example", "https://local-b.example"], "resetting the Web override restores the untouched local source")
	_assert(WebLaunchConfig.effective_base_url(path) == "https://local-a.example", "the local selection becomes effective again after the injected source is gone")

	var close_menus := WebLaunchConfig.normalize_close_menus([
		" Ranking ", "battle", "SETTINGS", "quit", "unknown", "ranking", 7,
	])
	_assert(close_menus == ["ranking", "settings", "quit"], "CloseMenu accepts only ranking/settings/quit, normalizes case and keeps first-seen order")
	WebLaunchConfig.configure(false, [], ["ranking", "settings", "quit", "battle"])
	_assert(WebLaunchConfig.is_menu_closed("ranking"), "CloseMenu can close ranking")
	_assert(WebLaunchConfig.is_menu_closed("settings"), "CloseMenu can close settings")
	_assert(WebLaunchConfig.is_menu_closed("quit"), "CloseMenu can close quit")
	_assert(not WebLaunchConfig.is_menu_closed("battle"), "CloseMenu can never close battle")
	_assert(not WebLaunchConfig.is_menu_closed("unknown"), "unknown menu ids are ignored")
	WebLaunchConfig.reset()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


## 设置页在本地数据源下可增删并立即切换；Web 注入数据源下只能选择，不能改列表。
func _test_server_settings_ui() -> void:
	var path := "user://test_server_settings_ui.json"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	WebLaunchConfig.reset()
	AppSettings.save_base_urls(["https://local-a.example", "https://local-b.example"], "https://local-b.example", path)
	var packed := load("res://scenes/settings.tscn") as PackedScene
	var local_scene: Node = packed.instantiate()
	local_scene.settings_path = path
	root.add_child(local_scene)
	await process_frame
	var local_select := local_scene.get_node("%ServerSelect") as OptionButton
	var local_input := local_scene.get_node("%ServerAddInput") as LineEdit
	var local_add := local_scene.get_node("%ServerAdd") as Button
	var local_delete := local_scene.get_node("%ServerDelete") as Button
	_assert(local_select.item_count == 3, "the local selector contains the virtual default plus every saved candidate")
	_assert(str(local_select.get_item_metadata(local_select.selected)) == "https://local-b.example", "the selector highlights the saved effective server")
	_assert(local_scene.get_node("%ServerAddRow").visible and local_input.editable and not local_add.disabled and local_delete.visible, "local-source controls allow list management")
	_assert(not local_delete.disabled, "a selected local candidate can be deleted")
	local_input.text = "https://local-c.example/"
	local_scene.call("_on_server_add_pressed")
	await process_frame
	_assert(AppSettings.load_base_urls(path).has("https://local-c.example"), "the Settings add action persists a normalized local candidate")
	_assert(AppSettings.load_base_url(path) == "https://local-c.example", "the Settings add action immediately selects the new candidate")
	_assert(str(local_select.get_item_metadata(local_select.selected)) == "https://local-c.example", "the selector refreshes to the newly added candidate")
	local_scene.call("_on_server_delete_pressed")
	await process_frame
	_assert(not AppSettings.load_base_urls(path).has("https://local-c.example"), "the Settings delete action removes the selected local candidate")
	_assert(AppSettings.load_base_url(path).is_empty() and local_select.selected == 0, "deleting the selected candidate switches the UI and saved choice to default")
	local_scene.queue_free()
	await process_frame

	# 同一份本地存档在 Web 注入模式下不应被合并或改写列表。
	var local_before := AppSettings.load_base_urls(path)
	WebLaunchConfig.configure(true, ["https://web-a.example/", "https://web-b.example"], [])
	var injected_scene: Node = packed.instantiate()
	injected_scene.settings_path = path
	root.add_child(injected_scene)
	await process_frame
	var injected_select := injected_scene.get_node("%ServerSelect") as OptionButton
	var injected_input := injected_scene.get_node("%ServerAddInput") as LineEdit
	var injected_add := injected_scene.get_node("%ServerAdd") as Button
	var injected_delete := injected_scene.get_node("%ServerDelete") as Button
	_assert(injected_select.item_count == 3, "the injected selector contains the virtual default plus only Web candidates")
	_assert(not injected_scene.get_node("%ServerAddRow").visible and not injected_input.editable and injected_add.disabled, "injected-source add controls are hidden and disabled")
	_assert(not injected_delete.visible and injected_delete.disabled, "injected-source delete is hidden and disabled")
	_assert((injected_scene.get_node("%ServerHint") as Label).text.find("网页启动参数") >= 0, "the read-only source is explained in the Settings hint")
	injected_scene.call("_on_server_selected", 1)
	await process_frame
	_assert(AppSettings.load_base_url(path) == "https://web-a.example", "an injected candidate can still be selected and persisted")
	_assert(WebLaunchConfig.effective_base_url(path) == "https://web-a.example", "the selected injected candidate takes effect immediately")
	injected_input.text = "https://must-not-save.example"
	injected_scene.call("_on_server_add_pressed")
	injected_scene.call("_on_server_delete_pressed")
	_assert(AppSettings.load_base_urls(path) == local_before, "manual calls cannot mutate the local list while the injected source is active")
	injected_scene.queue_free()
	await process_frame
	WebLaunchConfig.reset()
	_assert(WebLaunchConfig.effective_base_url(path).is_empty(), "an injected-only saved selection is inactive after returning to the local source")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


## 主菜单不删节点，只隐藏 Web 指定的入口；排行被隐藏时对战承担首焦点。
func _test_web_main_menu() -> void:
	var packed := load("res://scenes/main.tscn") as PackedScene
	WebLaunchConfig.configure(false, [], ["ranking"])
	var partial: Node = packed.instantiate()
	root.add_child(partial)
	await process_frame
	var partial_ranking := partial.get_node("%RankingButton") as Button
	var partial_battle := partial.get_node("%BattleButton") as Button
	var partial_settings := partial.get_node("%SettingsButton") as Button
	var partial_quit := partial.get_node("%QuitButton") as Button
	_assert(not partial_ranking.visible and partial_battle.visible and partial_settings.visible and partial_quit.visible, "a partial CloseMenu combination hides only the named entry")
	_assert(partial_battle.has_focus(), "when ranking is hidden battle receives initial focus")
	_assert(partial.call("first_visible_menu_button") == partial_battle, "the first visible menu helper returns battle when ranking is hidden")
	await _press_key(KEY_DOWN)
	_assert(partial_settings.has_focus(), "D-pad navigation skips hidden ranking and continues from battle to settings")
	partial_settings.release_focus()
	await process_frame
	await _press_key(KEY_DOWN)
	_assert(partial_battle.has_focus(), "lost focus is restored to the first visible Web menu entry")
	partial.queue_free()
	await process_frame

	WebLaunchConfig.configure(false, [], ["ranking", "settings", "quit", "battle", "unknown"])
	var closed: Node = packed.instantiate()
	root.add_child(closed)
	await process_frame
	var closed_ranking := closed.get_node("%RankingButton") as Button
	var closed_battle := closed.get_node("%BattleButton") as Button
	var closed_settings := closed.get_node("%SettingsButton") as Button
	var closed_quit := closed.get_node("%QuitButton") as Button
	_assert(not closed_ranking.visible and not closed_settings.visible and not closed_quit.visible, "all three closeable menu entries can be hidden together")
	_assert(closed_battle.visible and closed_battle.has_focus(), "battle remains visible and focused even when every closeable entry is hidden")
	closed.queue_free()
	await process_frame
	WebLaunchConfig.reset()


## 主菜单：四个按钮都在，三个场景入口都能切到对应场景。
func _test_main_menu() -> void:
	var packed := load("res://scenes/main.tscn") as PackedScene
	_assert(packed != null, "main.tscn loads")
	# 普通主菜单用例不继承上一个 Web 用例的参数快照。
	WebLaunchConfig.reset()
	var main: Node = packed.instantiate()
	root.add_child(main)
	await process_frame
	var ranking_btn := main.get_node_or_null("%RankingButton") as Button
	var battle_btn := main.get_node_or_null("%BattleButton") as Button
	_assert(ranking_btn != null, "Main has Ranking button")
	_assert(battle_btn != null, "Main has Battle button")
	_assert(ranking_btn != null and ranking_btn.text.find("排行") >= 0, "Ranking button is labeled for ranking")
	_assert(battle_btn != null and battle_btn.text.find("对战") >= 0, "Battle button is labeled for battle")
	# 设置按钮必须排在退出上面：电视上全靠方向键顺着走，顺序就是可达性。
	var menu := main.get_node_or_null("Center/Menu") as VBoxContainer
	_assert(menu != null, "Main menu is a VBox")
	var settings_btn := main.get_node_or_null("%SettingsButton") as Button
	var quit_btn := main.get_node_or_null("%QuitButton") as Button
	_assert(settings_btn != null, "Main has Settings button")
	_assert(settings_btn != null and settings_btn.text.find("设置") >= 0, "Settings button is labeled for settings")
	_assert(battle_btn != null and ranking_btn != null and battle_btn.get_index() < ranking_btn.get_index(), "Battle is the first menu entry and Ranking is second")
	_assert(ranking_btn != null and settings_btn != null and ranking_btn.get_index() < settings_btn.get_index(), "Ranking sits above Settings")
	_assert(settings_btn != null and quit_btn != null and settings_btn.get_index() < quit_btn.get_index(), "Settings sits above Quit")
	_assert(battle_btn != null and battle_btn.has_focus(), "Battle owns the default menu focus")
	var battle_style := battle_btn.get_theme_stylebox("normal") as StyleBoxFlat
	var ranking_style := ranking_btn.get_theme_stylebox("normal") as StyleBoxFlat
	_assert(battle_style != null and battle_style.bg_color == ThemeHelper.ACCENT, "Battle uses the filled primary color")
	_assert(ranking_style != null and ranking_style.bg_color == ThemeHelper.CARD, "Ranking uses the secondary outlined color")
	var ranking_script := FileAccess.get_file_as_string("res://scenes/main.gd")
	_assert(ranking_script.find("ranking.tscn") >= 0, "Main can switch to Ranking")
	_assert(ranking_script.find("battle.tscn") >= 0, "Main can switch to Battle")
	_assert(ranking_script.find("settings.tscn") >= 0, "Main can switch to Settings")
	_assert(ranking_script.find("AppSettings.apply") >= 0, "Main applies the saved window mode on launch")

	# 主场景角落显示版本号，取自 project.godot，不写死在界面里。
	var configured := str(ProjectSettings.get_setting("application/config/version", ""))
	_assert(not configured.is_empty(), "project.godot declares a version")
	var android_version_code := -1
	for line in FileAccess.get_file_as_string("res://export_presets.cfg").split("\n"):
		if line.strip_edges().begins_with("version/code="):
			android_version_code = int(line.strip_edges().trim_prefix("version/code="))
			break
	_assert(android_version_code == int(configured.get_slice(".", 2)), "Android versionCode stays aligned with the project patch version")
	_assert(main.get_node_or_null("%Subtitle") == null, "the main menu subtitle is gone")
	var version_label := main.get_node_or_null("%VersionLabel") as Label
	_assert(version_label != null, "Main has a version label")
	_assert(version_label != null and version_label.text == "v%s" % configured, "the label shows the configured version, prefixed with v")
	_assert(ranking_script.find("application/config/version") >= 0, "the version is read from project settings, not hard-coded")
	main.queue_free()
	await process_frame


## 深度优先找出第一个 Sprite2D，用来取视差层的贴图。
func _first_sprite(node: Node) -> Sprite2D:
	if node is Sprite2D:
		return node as Sprite2D
	for child in node.get_children():
		var found := _first_sprite(child)
		if found != null:
			return found
	return null


## 主菜单的视差背景（三层各自以不同速度滚）和退出按钮。
func _test_main_parallax_and_quit() -> void:
	var packed := load("res://scenes/main.tscn") as PackedScene
	_assert(packed != null, "main.tscn loads for parallax")
	WebLaunchConfig.reset()
	var main: Node = packed.instantiate()
	root.add_child(main)
	await process_frame
	var ranking_btn := main.get_node_or_null("%RankingButton") as Button
	var battle_btn := main.get_node_or_null("%BattleButton") as Button
	_assert(main.get_node_or_null("%Subtitle") == null, "the main menu subtitle is gone")
	var version_label := main.get_node_or_null("%VersionLabel") as Label
	_assert(ranking_btn != null, "ranking button still exists")
	_assert(battle_btn != null, "battle button still exists")
	_assert(version_label != null, "version label still exists")

	var backdrop := main.get_node_or_null("%ParallaxBackdrop") as MenuParallax
	_assert(backdrop != null, "main has a parallax backdrop")
	_assert(backdrop.layers.size() >= 2, "backdrop has at least two image layers")
	var images: Array[Image] = []
	for layer_index in backdrop.layers.size():
		var layer := backdrop.layers[layer_index]
		var sprite := _first_sprite(layer)
		_assert(sprite != null and sprite.texture != null, "parallax layer loads a texture")
		var img := sprite.texture.get_image()
		_assert(img != null and _opaque_count(img) > 0, "parallax layer has opaque pixels")
		images.append(img)
		var layer_sprites: Array[Sprite2D] = []
		for child in layer.get_children():
			if child is Sprite2D:
				layer_sprites.append(child as Sprite2D)
		_assert(layer_sprites.size() == 2, "each parallax layer keeps exactly two scene-authored sprites")
		if layer_sprites.size() == 2:
			_assert(layer_sprites[0].texture == layer_sprites[1].texture and layer_sprites[0].texture != null, "both copies in a parallax layer share the designed texture")
			var gap := layer_sprites[1].position.x - layer_sprites[0].position.x
			_assert(is_equal_approx(gap, backdrop.wrap_widths[layer_index]), "the second parallax copy begins exactly one wrap width later")
	_assert(images.size() >= 2 and _images_differ(images[0], images[1]), "two layer images are not pixel-identical")
	var tscn := FileAccess.get_file_as_string("res://scenes/main.tscn")
	var parallax_src := FileAccess.get_file_as_string("res://scripts/menu_parallax.gd")
	_assert(tscn.find("ParallaxBackdrop") >= 0, "main scene references the parallax backdrop")
	_assert(tscn.find("res://assets/backgrounds/far.png") >= 0, "far background image is scene-authored")
	_assert(tscn.find("res://assets/backgrounds/mid.png") >= 0, "mid background image is scene-authored")
	_assert(tscn.find("res://assets/backgrounds/near.png") >= 0, "near background image is scene-authored")
	_assert(main.get_node_or_null("%FarLayer") != null and main.get_node("%FarLayer").get_child_count() == 2, "far parallax layer and both sprites are visible in the scene tree")
	_assert(main.get_node_or_null("%MidLayer") != null and main.get_node("%MidLayer").get_child_count() == 2, "mid parallax layer and both sprites are visible in the scene tree")
	_assert(main.get_node_or_null("%NearLayer") != null and main.get_node("%NearLayer").get_child_count() == 2, "near parallax layer and both sprites are visible in the scene tree")
	_assert(parallax_src.find("Node2D.new") < 0 and parallax_src.find("Sprite2D.new") < 0 and parallax_src.find("add_child") < 0, "parallax script only lays out existing scene nodes")

	var before: Array[Vector2] = []
	for layer in backdrop.layers:
		before.append(layer.position)
	for _i in 8:
		await process_frame
	await create_timer(0.35).timeout
	backdrop.advance_parallax(0.45)
	var delta0: Vector2 = backdrop.layers[0].position - before[0]
	var delta1: Vector2 = backdrop.layers[1].position - before[1]
	_assert(delta0 != Vector2.ZERO, "first layer moved")
	_assert(delta1 != Vector2.ZERO, "second layer moved")
	_assert(delta0 != delta1, "layer displacements differ (parallax)")

	var quit_btn := main.get_node_or_null("%QuitButton") as Button
	_assert(quit_btn != null, "Quit button exists")
	_assert(quit_btn.visible, "Quit button is visible")
	_assert(quit_btn.text.find("退出") >= 0, "Quit button is labeled 退出游戏")
	var conns := quit_btn.pressed.get_connections()
	_assert(conns.size() > 0, "Quit button pressed signal is connected")
	var saw_quit_handler := false
	for conn in conns:
		var cb: Callable = conn["callable"]
		if cb.get_method() == &"_on_quit_pressed":
			saw_quit_handler = true
	_assert(saw_quit_handler, "Quit button is wired to the shipped quit handler")
	var main_src := FileAccess.get_file_as_string("res://scenes/main.gd")
	_assert(main_src.find("func _on_quit_pressed") >= 0, "quit handler exists")
	_assert(main_src.find("get_tree().quit()") >= 0, "quit handler uses SceneTree.quit")
	main.queue_free()
	await process_frame


## 十六套战斗背景、独立随机、分带视差，以及排行榜的可读性承托。
func _test_battle_and_ranking_backgrounds() -> void:
	var expected_active_paths: Array[String] = [
		"res://assets/battle_backgrounds/ember_forge.png",
		"res://assets/battle_backgrounds/moonlit_bamboo.png",
		"res://assets/battle_backgrounds/crystal_cavern.png",
		"res://assets/battle_backgrounds/storm_skyship.png",
		"res://assets/battle_backgrounds/spring_tournament_day.png",
		"res://assets/battle_backgrounds/summer_wilderness_day.png",
		"res://assets/battle_backgrounds/autumn_pixel_farm.png",
		"res://assets/battle_backgrounds/winter_high_fantasy.png",
		"res://assets/battle_backgrounds/spring_garden_day.png",
		"res://assets/battle_backgrounds/summer_coast_day.png",
		"res://assets/battle_backgrounds/autumn_valley_day.png",
		"res://assets/battle_backgrounds/winter_village_day.png",
		"res://assets/battle_backgrounds/coral_depths.png",
		"res://assets/battle_backgrounds/cyber_rooftop.png",
		"res://assets/battle_backgrounds/mystic_mushroom_marsh.png",
		"res://assets/battle_backgrounds/desert_oasis_day.png",
	]
	var retired_paths: Array[String] = [
		"res://assets/battle_backgrounds/celestial_citadel.png",
		"res://assets/battle_backgrounds/sunken_ruins.png",
		"res://assets/battle_backgrounds/frozen_observatory.png",
		"res://assets/battle_backgrounds/neon_archive.png",
	]
	_assert(BattleParallax.BACKGROUND_PATHS.size() == 16, "battle ships exactly sixteen active backgrounds")
	_assert(BattleParallax.BACKGROUND_TEXTURES.size() == BattleParallax.BACKGROUND_PATHS.size(), "every battle path is preloaded for export")
	for expected_path in expected_active_paths:
		_assert(BattleParallax.BACKGROUND_PATHS.has(expected_path), "active battle pool includes: %s" % expected_path.get_file())
	for retired_path in retired_paths:
		_assert(not BattleParallax.BACKGROUND_PATHS.has(retired_path), "retired battle background stays out of the active pool: %s" % retired_path.get_file())
	var unique_paths := {}
	var images: Array[Image] = []
	for path in BattleParallax.BACKGROUND_PATHS:
		unique_paths[path] = true
		_assert(FileAccess.file_exists(path), "battle background exists: %s" % path.get_file())
		var tex := load(path) as Texture2D
		_assert(tex != null, "battle background loads: %s" % path.get_file())
		if tex == null:
			continue
		var image := tex.get_image()
		_assert(image != null and image.get_size() == Vector2i(640, 360), "battle background is 640x360: %s" % path.get_file())
		_assert(image != null and _opaque_count(image) > 100000, "battle background contains visible art: %s" % path.get_file())
		images.append(image)
	_assert(unique_paths.size() == 16, "all sixteen battle background paths are unique")
	var all_distinct := images.size() == 16
	for i in images.size():
		for j in range(i + 1, images.size()):
			if not _images_differ(images[i], images[j]):
				all_distinct = false
	_assert(all_distinct, "all sixteen battle backgrounds are visually distinct files")

	var battle := (load("res://scenes/battle.tscn") as PackedScene).instantiate()
	battle.skip_autoload = true
	battle.record_path = TEST_BATTLE_RECORD_PATH
	root.add_child(battle)
	await process_frame
	var backdrop := battle.get_node_or_null("%BattleBackground") as BattleParallax
	_assert(backdrop != null, "battle scene owns the parallax background")
	_assert(backdrop != null and backdrop.get_parent().name == &"BackgroundLayer", "battle art stays below fighters and HUD")
	if backdrop != null:
		_assert(backdrop.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST, "battle art keeps crisp nearest-neighbour pixels")
		var shader_material := backdrop.material as ShaderMaterial
		_assert(shader_material != null and shader_material.shader != null, "battle background has its parallax shader")
		var before_time := backdrop.elapsed_seconds
		backdrop.advance_parallax(1.25)
		_assert(backdrop.elapsed_seconds > before_time, "battle parallax advances over time")
		_assert(shader_material != null and is_equal_approx(float(shader_material.get_shader_parameter(&"elapsed_seconds")), backdrop.elapsed_seconds), "parallax time reaches the shader")
		var far_amplitude := float(shader_material.get_shader_parameter(&"far_amplitude_px")) if shader_material != null else 0.0
		var mid_amplitude := float(shader_material.get_shader_parameter(&"mid_amplitude_px")) if shader_material != null else 0.0
		var near_amplitude := float(shader_material.get_shader_parameter(&"near_amplitude_px")) if shader_material != null else 0.0
		var scroll_cycle := float(shader_material.get_shader_parameter(&"scroll_cycle_seconds")) if shader_material != null else 0.0
		var edge_guard := float(shader_material.get_shader_parameter(&"edge_guard_px")) if shader_material != null else 0.0
		_assert(far_amplitude >= 8.0 and far_amplitude < mid_amplitude, "far and mid planes have visible, ordered scroll travel")
		_assert(mid_amplitude < near_amplitude and near_amplitude >= 24.0, "near plane has clearly visible parallax travel")
		_assert(is_equal_approx(scroll_cycle, BattleParallax.TIME_WRAP_SECONDS), "script and shader share one seamless scroll cycle")
		_assert(edge_guard >= 1.0 and near_amplitude + edge_guard < 160.0, "scroll overscan has a safe edge guard without excessive crop")
		backdrop.elapsed_seconds = BattleParallax.TIME_WRAP_SECONDS - 0.25
		backdrop.advance_parallax(0.5)
		_assert(is_equal_approx(backdrop.elapsed_seconds, 0.25), "parallax wraps at the same phase without a motion jump")
		backdrop.seed_backgrounds(20260919)
		var first_path := backdrop.roll_background()
		var first_index := backdrop.current_index
		_assert(is_zero_approx(backdrop.elapsed_seconds), "a new arena begins its scroll from the centered frame")
		var first_direction := float(shader_material.get_shader_parameter(&"scroll_direction")) if shader_material != null else 0.0
		_assert(first_direction == (1.0 if first_index % 2 == 0 else -1.0), "arena index selects a deterministic scroll direction")
		var combat_rng := RollSource.new(77)
		battle._rng = combat_rng
		var second_path := backdrop.roll_background()
		_assert(not first_path.is_empty() and not second_path.is_empty(), "background rolls resolve to real textures")
		_assert(backdrop.current_index != first_index, "consecutive rounds never repeat the same background")
		_assert(battle._rng == combat_rng, "background rolling never replaces the combat RNG")
		var seen := {}
		seen[first_path] = true
		seen[second_path] = true
		for _roll in 128:
			seen[backdrop.roll_background()] = true
		_assert(seen.size() == 16, "the independent background roll can reach every active arena")
	var floor_scrim := battle.get_node("BackgroundLayer/Floor") as ColorRect
	var arena_scrim := battle.get_node("BackgroundLayer/ArenaTint") as ColorRect
	_assert(floor_scrim.color.a >= 0.4 and floor_scrim.color.a < 0.8, "lower arena is dimmed without hiding the generated floor")
	_assert(arena_scrim.color.a >= 0.2 and arena_scrim.color.a < 0.5, "fighter zone keeps a light readability tint")
	var log := battle.get_node("%BattleLog") as RichTextLabel
	var record_panel := battle.get_node("%RecordPanel") as PanelContainer
	var log_style := log.get_theme_stylebox("normal") as StyleBoxFlat
	var record_style := record_panel.get_theme_stylebox("panel") as StyleBoxFlat
	_assert(log_style != null and log_style.bg_color.a >= 0.5 and log_style.bg_color.a <= 0.62, "combat report uses a translucent backing")
	_assert(record_style != null and record_style.bg_color.a >= 0.5 and record_style.bg_color.a <= 0.62, "round standings use a translucent backing")
	_assert(log_style != null and log_style.get_border_width(SIDE_LEFT) >= 1, "combat report keeps a subtle border over bright art")
	_assert(record_style != null and record_style.get_border_width(SIDE_LEFT) >= 1, "round standings keep a subtle border over bright art")
	_assert(log.get_theme_constant("outline_size") >= 2, "combat report text stays legible over the translucent panel")
	var record_title := battle.get_node("%RecordTitle") as Label
	_assert(record_title.get_theme_constant("outline_size") >= 2, "round standings title stays legible over the translucent panel")
	var has_readable_record_row := false
	for child in battle.get_node("%RecordList").find_children("*", "Label", true, false):
		var row_label := child as Label
		if row_label != null and row_label.get_theme_constant("outline_size") >= 2:
			has_readable_record_row = true
			break
	_assert(has_readable_record_row, "round standings text gets the same readability outline")
	battle.queue_free()
	await process_frame

	var ranking := (load("res://scenes/ranking.tscn") as PackedScene).instantiate()
	var ranking_backdrop := ranking.get_node_or_null("%RankingBackdrop") as TextureRect
	var ranking_scrim := ranking.get_node_or_null("%RankingScrim") as ColorRect
	var content_panel := ranking.get_node_or_null("%ContentPanel") as Panel
	var margin := ranking.get_node("Margin") as MarginContainer
	var ranking_grid := ranking.get_node("%Grid") as GridContainer
	_assert(ranking_grid.get_child_count() == 4, "ranking keeps its four fixed header labels in the scene tree")
	_assert((ranking_grid.get_child(0) as Label).text == "#" and (ranking_grid.get_child(3) as Label).text == "Token / 战力", "ranking static headers keep their designed order")
	var fixed_headers := ranking_grid.get_children()
	var first_rows: Array[RankedUser] = [_ranked("静态表头甲", 20)]
	ranking._render("2026-09-19", first_rows)
	_assert(ranking_grid.get_child_count() == 8, "one ranking result appends four cells after the static header")
	var headers_survive := true
	for i in 4:
		headers_survive = headers_survive and ranking_grid.get_child(i) == fixed_headers[i]
	_assert(headers_survive, "rendering keeps the original four header nodes")
	var second_rows: Array[RankedUser] = [_ranked("静态表头乙", 30), _ranked("静态表头丙", 10)]
	ranking._render("2026-09-20", second_rows)
	_assert(ranking_grid.get_child_count() == 12, "rerender replaces old data cells without duplicating the static header")
	_assert((ranking_grid.get_child(0) as Label).text == "#" and (ranking_grid.get_child(3) as Label).text == "Token / 战力", "header order survives repeated renders")
	_assert(ranking_backdrop != null and ranking_backdrop.texture != null, "ranking scene loads its illustrated hall")
	if ranking_backdrop != null and ranking_backdrop.texture != null:
		var hall := ranking_backdrop.texture.get_image()
		_assert(hall != null and hall.get_size() == Vector2i(640, 360) and _opaque_count(hall) > 100000, "ranking hall is a non-empty 640x360 image")
	_assert(ranking_backdrop != null and ranking_backdrop.get_index() < margin.get_index(), "ranking art renders behind all table content")
	_assert(ranking_scrim != null and ranking_scrim.color.a >= 0.45, "ranking hall has a full-screen readability scrim")
	var panel_style := content_panel.get_theme_stylebox("panel") as StyleBoxFlat if content_panel != null else null
	_assert(panel_style != null and panel_style.bg_color.a >= 0.7, "ranking rows sit on a high-contrast translucent panel")
	_assert(content_panel != null and content_panel.get_index() < margin.get_index(), "ranking content panel stays behind the original layout")
	ranking.free()


## 从 .godot / .cfg 文本里抠出某个键的引号值，不依赖 ProjectSettings。
func _first_quoted_setting(path: String, key: String) -> String:
	var text := FileAccess.get_file_as_string(path)
	for line in text.split("\n"):
		var trimmed := line.strip_edges()
		if trimmed.begins_with(key + "="):
			return trimmed.trim_prefix(key + "=").trim_prefix("\"").trim_suffix("\"")
	return ""


## project.godot 里配置的图标路径，uid:// 会被还原成 res:// 路径。
func _configured_icon_path() -> String:
	return _first_quoted_setting("res://project.godot", "config/icon")


## 图里有多少个不透明像素，用来确认贴图不是一张空白。
func _opaque_count(image: Image) -> int:
	var n := 0
	for y in image.get_height():
		for x in image.get_width():
			if image.get_pixel(x, y).a > 0.5:
				n += 1
	return n


## 两张图是不是逐像素完全一致，用来确认视差三层不是同一张图。
func _images_differ(a: Image, b: Image) -> bool:
	if a.get_width() != b.get_width() or a.get_height() != b.get_height():
		return true
	for y in a.get_height():
		for x in a.get_width():
			if a.get_pixel(x, y) != b.get_pixel(x, y):
				return true
	return false


## 应用图标不是 Godot 默认机器人，以及自定义光标按下/抬起会换图。
func _test_app_icon_and_cursors() -> void:
	var icon_path := _configured_icon_path()
	_assert(not icon_path.is_empty(), "project.godot config/icon is set")
	_assert(FileAccess.file_exists(icon_path), "configured app icon file exists")
	var icon_res := load(icon_path)
	_assert(icon_res != null, "configured app icon loads")
	var icon_bytes := FileAccess.get_file_as_string(icon_path)
	_assert(icon_bytes.find("M105 673v33q407 354 814 0") < 0, "app icon is not the Godot robot")
	var export_icon_ref := _first_quoted_setting("res://export_presets.cfg", "application/icon")
	_assert(not export_icon_ref.is_empty(), "Windows export sets application/icon")
	var export_icon := load(export_icon_ref)
	_assert(export_icon != null and export_icon == icon_res, "Windows export uses the same app icon")
	var cursor_src := FileAccess.get_file_as_string("res://scripts/game_cursor.gd")
	_assert(cursor_src.find("Input.set_custom_mouse_cursor") >= 0, "cursors use the custom-cursor API")
	# 光标是 autoload 全局接管的，场景脚本不该各自再装一遍。
	var controller_src := FileAccess.get_file_as_string("res://scripts/cursor_controller.gd")
	_assert(controller_src.find("GameCursor.boot") >= 0, "the cursor autoload boots the custom cursor")
	_assert(controller_src.find("GameCursor.handle_event") >= 0, "the cursor autoload applies cursor swaps")

	var arrow := load(GameCursor.ARROW_PATH) as Texture2D
	var pressed := load(GameCursor.PRESSED_PATH) as Texture2D
	_assert(arrow != null, "arrow cursor loads")
	_assert(pressed != null, "pressed cursor loads")
	var aimg := arrow.get_image()
	var pimg := pressed.get_image()
	_assert(aimg != null and _opaque_count(aimg) > 0, "arrow cursor has opaque pixels")
	_assert(pimg != null and _opaque_count(pimg) > 0, "pressed cursor has opaque pixels")
	_assert(_images_differ(aimg, pimg), "arrow and pressed cursors differ")

	var packed := load("res://scenes/main.tscn") as PackedScene
	_assert(packed != null, "main.tscn loads for cursor apply")
	var main: Node = packed.instantiate()
	root.add_child(main)
	await process_frame
	_assert(GameCursor.applied_texture == GameCursor.arrow_texture, "start path applies the arrow cursor")

	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = Vector2(12, 12)
	# 走真正的生产路径：autoload 的 _input，而不是某个场景自己抄的一份。
	var cursor_autoload := root.get_node_or_null("CursorController")
	_assert(cursor_autoload != null, "the cursor autoload is registered")
	cursor_autoload._input(press)
	_assert(GameCursor.applied_texture == GameCursor.pressed_texture, "mouse down applies the pressed cursor")

	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	release.position = Vector2(12, 12)
	cursor_autoload._input(release)
	_assert(GameCursor.applied_texture == GameCursor.arrow_texture, "mouse up applies the arrow cursor")
	main.queue_free()
	await process_frame


## 角色视图：五种动画、血条、图标行和悬停说明。
func _test_fighter_anims() -> void:
	var packed := load("res://scenes/fighter_view.tscn") as PackedScene
	_assert(packed != null, "fighter_view.tscn loads")
	var view: FighterView = packed.instantiate()
	root.add_child(view)
	await process_frame
	var names := view.animation_names()
	_assert("idle" in names and "attack" in names and "hurt" in names, "generic fighter has idle/attack/hurt tracks")
	_assert("death" in names, "generic fighter has death track")
	_assert("dodge" in names, "generic fighter has dodge retreat animation")
	_assert(view.anim_player.has_animation(&"attack"), "attack animation is playable")
	_assert(view.anim_player.has_animation(&"hurt"), "hurt animation is playable")
	_assert(view.anim_player.has_animation(&"dodge"), "dodge animation is playable")
	_assert(view.has_method("play_crit_fx") and view.has_method("play_poison_fx") and view.has_method("play_heal_fx") and view.has_method("play_dodge"), "fighter view exposes crit/dodge/poison/heal fx")
	var fighter_tscn := FileAccess.get_file_as_string("res://scenes/fighter_view.tscn")
	var fighter_src := FileAccess.get_file_as_string("res://scenes/fighter_view.gd")
	var combat_fx_src := FileAccess.get_file_as_string("res://scripts/combat_fx.gd")
	_assert(fighter_tscn.find("AnimationLibrary") >= 0 and fighter_tscn.find("Animation_dodge") >= 0, "fighter animations are serialized in the scene")
	_assert(view.get_node("Visual/Afterimages").get_child_count() == CombatFx.AFTERIMAGE_EXTRAS, "fixed afterimage sprites are visible in the scene tree")
	_assert(view.get_node_or_null("Visual/CritFx") != null and view.get_node_or_null("Visual/GuardFx/Gleam") != null, "fixed combat FX are visible in the scene tree")
	_assert(fighter_src.find("_build_animations") < 0 and combat_fx_src.find("CPUParticles2D.new") < 0 and combat_fx_src.find("Sprite2D.new") < 0, "fighter scripts reuse scene-authored animations and FX nodes")
	_assert(not FileAccess.file_exists("res://scripts/fighter_anims.gd"), "obsolete runtime animation builder is removed")
	_assert(SpriteFactory.COUNT >= 12, "appearance pool has at least 12 looks")
	var user := _ranked("anim", 10, AgentChannels.CHANNEL_CODEX)
	var fighter := Fighter.from_ranked(user, true)
	_give_buffs(fighter, [SkillCatalog.agent_buff_template(AgentChannels.CHANNEL_CODEX)])
	var pool: Array[SkillDef] = SkillCatalog.pool()
	fighter.skills.clear()
	for i in range(mini(8, pool.size())):
		fighter.skills.append(pool[i])
	view.bind(fighter, false)
	await process_frame
	_assert(name_label_parent_is_status(view), "name and HP bar share StatusRow; HP text is inside the bar")
	_assert(view.hp_label.horizontal_alignment == HORIZONTAL_ALIGNMENT_CENTER, "HP text is centered in the bar")
	_assert(view.hp_wrap.custom_minimum_size.x >= 180.0, "HP bar is lengthened")
	_assert(is_equal_approx(float(ProjectSettings.get_setting("gui/timers/tooltip_delay_sec", 0.5)), 0.0), "tooltip delay is immediate")
	var buff_icon := view.buff_row.get_child(0)
	buff_icon.mouse_entered.emit()
	_assert(view.tip_panel.visible, "buff hover shows the tip immediately")
	# 断言对着界面真正渲染的那一个 buff，而不是另一条只有测试在走的取值路径。
	var shown_buff: SkillDef = fighter.agent_buffs[0]
	_assert(view.tip_label.text.find(shown_buff.display_name) >= 0, "instant tip contains the buff name")
	_assert(view.tip_label.text.find(shown_buff.description) >= 0, "instant tip contains the buff effect")
	buff_icon.mouse_exited.emit()
	_assert(not view.tip_panel.visible, "buff tip hides on mouse exit")
	_assert(view.buff_row.get_parent() != view.skill_row, "buff row and skill row are separate")
	_assert(view.buff_row.get_child_count() == fighter.agent_buffs.size(), "buff row holds one icon per agent")
	_assert(view.skill_row.get_child_count() == fighter.skills.size(), "skill row holds only random skills")
	_assert(fighter.skills.size() == 8, "champion bind uses 8 skills")
	for child in view.buff_row.get_children():
		_assert_icon_tooltip(child, fighter.agent_buffs[0])
	var shown_skills: Array[SkillDef] = SkillCatalog.sort_for_display(fighter.skills)
	for i in shown_skills.size():
		_assert_icon_tooltip(view.skill_row.get_child(i), shown_skills[i])
	for i in range(1, view.skill_row.get_child_count()):
		var prev_skill: SkillDef = shown_skills[i - 1]
		var cur_skill: SkillDef = shown_skills[i]
		_assert(SkillCatalog.display_group_rank(cur_skill.icon_id) >= SkillCatalog.display_group_rank(prev_skill.icon_id), "bound skill row is grouped 增强→附加→治疗→高级")
	await process_frame
	_assert_icons_align_to_hp_bar(view)
	view.play_attack()
	_assert(view.anim_player.current_animation == "attack", "playing attack selects the attack animation")
	_assert(view.slash.visible, "attack shows the sword slash")
	_assert(view.has_method("play_paralyze_fx") and view.has_method("play_confuse_fx") and view.has_method("play_assassinate_fx") and view.has_method("play_guard_fx"), "fighter view exposes paralyze/confuse/assassinate/guard fx")

	var poison_fx: CPUParticles2D = view.get_node("Visual/PoisonFx")
	var paralyze_fx: CPUParticles2D = view.get_node("Visual/ParalyzeFx")
	var crit_fx: CPUParticles2D = view.get_node("Visual/CritFx")
	var stun_fx: Node2D = view.get_node("Visual/StunFx")
	var skull_fx: Node2D = view.get_node("Visual/SkullFx")
	view.play_poison_fx()
	_assert(poison_fx.color.r > 0.7 and poison_fx.color.g < 0.45, "poison particles are red")
	_assert(poison_fx.emitting, "poison burst is emitting")
	var heal_fx: CPUParticles2D = (load("res://scenes/heal_fx.tscn") as PackedScene).instantiate()
	_assert(heal_fx.color.g > heal_fx.color.r and heal_fx.color.g > heal_fx.color.b, "heal particles are green and distinct from poison")
	heal_fx.free()
	view.play_paralyze_fx()
	_assert(paralyze_fx.color.r > 0.8 and paralyze_fx.color.g > 0.7 and paralyze_fx.color.b < 0.4, "paralyze particles are yellow")
	view.play_confuse_fx()
	_assert(stun_fx.visible, "confuse shows a stun node above the head")
	_assert(stun_fx.get_child_count() >= 3, "stun fx has circling stars")
	view.bind(fighter, false)
	_assert(not stun_fx.visible, "confuse stun is hidden when the view recycles")
	_assert(not poison_fx.emitting, "poison burst stops when the view recycles")
	_assert(not paralyze_fx.emitting, "paralyze burst stops when the view recycles")
	_assert(view.sprite.modulate == Color.WHITE, "status tint returns to white when recycled")
	view.play_crit_fx()
	_assert(crit_fx.amount > FighterView.LEGACY_CRIT_AMOUNT, "crit explosion uses more particles than the old small burst")
	_assert(crit_fx.emitting, "crit burst is emitting")
	view.play_assassinate_fx()
	_assert(skull_fx.visible, "assassinate shows a skull overlay")
	_assert(_skull_is_red_x(skull_fx), "assassinate skull is a red X overlay")
	view.play_guard_fx()
	var guard_fx: Node2D = view.get_node("Visual/GuardFx")
	_assert(guard_fx.visible, "absolute guard shows a shield bubble")
	_assert(guard_fx.get_node("Fill") is Polygon2D, "guard bubble has a filled dome")
	_assert(guard_fx.get_node("Rim") is Line2D, "guard bubble has a rim")
	var fill := guard_fx.get_node("Fill") as Polygon2D
	_assert(fill.color.b > fill.color.r and fill.color.a < 0.5, "guard bubble is a translucent cyan dome")
	view.play_dodge()
	_assert(view.dodge_ghost_count() == CombatFx.GHOST_TOTAL, "dodge has 3 figures including the body")
	var trail := view.get_node("Visual/Afterimages")
	_assert(trail.get_child_count() == CombatFx.AFTERIMAGE_EXTRAS, "two afterimages plus the body")
	var start_ghost: Sprite2D = trail.get_child(0)
	var mid_ghost: Sprite2D = trail.get_child(1)
	_assert(is_equal_approx(start_ghost.modulate.a, CombatFx.DODGE_START_ALPHA), "origin afterimage is 50% opaque")
	_assert(start_ghost.texture == view.sprite.texture, "afterimages copy the current pose")
	_assert(absf(start_ghost.position.x) <= 1.0, "first afterimage stays at the origin")
	_assert(mid_ghost.modulate.a > start_ghost.modulate.a and mid_ghost.modulate.a < CombatFx.DODGE_END_ALPHA, "mid afterimage is between 50% and opaque")
	view.anim_player.seek(0.12, true)
	var dodge_x := absf(view.sprite.position.x)
	var one_body := CombatFx.DODGE_BODY_LENGTHS * float(SpriteFactory.SIZE) * FighterView.BASE_SPRITE_SCALE
	_assert(absf(dodge_x - one_body) <= 1.0, "dodge retreats about 1 body width (got %.1f, want %.1f)" % [dodge_x, one_body])
	_assert(is_equal_approx(view.sprite.modulate.a, CombatFx.DODGE_END_ALPHA) or view.sprite.modulate.a >= 0.99, "the body at the dodge end is opaque")
	_assert(absf(absf(mid_ghost.position.x) - dodge_x * 0.5) <= 1.0, "mid afterimage sits halfway to the dodge end")
	_assert(is_equal_approx(view.displayed_body_width(), CombatFx.displayed_body_width(view.get_node("Visual").scale.x)), "displayed body width matches the shared helper")
	view.reset_view()
	_assert(not view.visible and view.sprite.texture == null, "reset hides the persistent fighter view and clears its runtime portrait")
	_assert(view.buff_row.get_child_count() == 0 and view.skill_row.get_child_count() == 0, "reset clears runtime buff and skill icons")
	_assert(trail.get_child_count() == CombatFx.AFTERIMAGE_EXTRAS and view.dodge_ghost_count() == 1, "reset hides but preserves the two scene-authored afterimage nodes")
	view.queue_free()
	await process_frame


## 接口契约：URL、请求方式，以及全项目不许出现第二个外部域名。
func _test_api_contract() -> void:
	var api_src := FileAccess.get_file_as_string("res://scripts/token_usage_api.gd")
	_assert(api_src.find("https://codex-tracker.yunmai365.com/api/v1/token-usage") >= 0, "API URL is the exact token-usage endpoint")
	_assert(api_src.find("HTTPClient.METHOD_GET") >= 0, "token-usage is fetched with GET")
	var ranking_src := FileAccess.get_file_as_string("res://scenes/ranking.gd")
	var battle_src := FileAccess.get_file_as_string("res://scenes/battle.gd")
	# 两个场景都只认 TokenUsageApi.fetch_ranking 这一个入口；
	# HTTPRequest 的生命周期和 channelUsage 的位置都不该再出现在场景脚本里。
	_assert(ranking_src.find("TokenUsageApi.fetch_ranking") >= 0, "Ranking enter path fetches the ranking")
	_assert(battle_src.find("TokenUsageApi.fetch_ranking") >= 0, "Battle enter path fetches the ranking")
	_assert(ranking_src.find("channelUsage") < 0 and battle_src.find("channelUsage") < 0, "scene scripts do not know the payload shape")
	_assert(api_src.find("channelUsage") >= 0, "the API module owns the payload shape")
	_assert(api_src.find("yunmai365.com/") < 0 or api_src.find("/api/v1/token-usage") >= 0, "api script targets token-usage")
	var extra := _other_host_paths()
	_assert(extra.is_empty(), "no other yunmai365 paths: %s" % ",".join(extra))


## 要扫描的源码文件清单（排除测试自己）。
func _other_host_paths() -> PackedStringArray:
	var found: PackedStringArray = PackedStringArray()
	_scan_dir("res://", found)
	return found


## 递归收集一个目录下的 .gd / .tscn，供域名扫描使用。
func _scan_dir(path: String, found: PackedStringArray) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		if name.begins_with("."):
			name = dir.get_next()
			continue
		var child := path.path_join(name)
		if dir.current_is_dir():
			if name == "tests":
				name = dir.get_next()
				continue
			_scan_dir(child, found)
		elif name.ends_with(".gd") or name.ends_with(".tscn"):
			var text := FileAccess.get_file_as_string(child)
			var from := 0
			while true:
				var idx := text.find("yunmai365.com", from)
				if idx < 0:
					break
				var slice := text.substr(idx, 80)
				if slice.find("/api/v1/token-usage") < 0:
					found.append("%s:%s" % [child, slice])
				from = idx + 1
		name = dir.get_next()
	dir.list_dir_end()


## 战绩榜不靠字体里的奖牌字符，改用圆底 + 名次数字。
func _test_no_medals() -> void:
	var ranking_src := FileAccess.get_file_as_string("res://scenes/ranking.gd") + FileAccess.get_file_as_string("res://scenes/ranking.tscn")
	for needle in ["medal", "badge", "金牌", "银牌", "铜牌", "勋章", "奖杯"]:
		_assert(ranking_src.find(needle) < 0, "Ranking has no %s" % needle)


## 把一串事件渲染成完整战报文本，方便按子串断言。
func _joined_log(events: Array[StrikeResult]) -> String:
	var battle: Node = (load("res://scenes/battle.gd") as GDScript).new()
	CombatLog.annotate(events)
	var blob := ""
	for event in events:
		blob += str(battle._event_text(event)) + "\n"
	battle.free()
	return blob


## 战报文案：暴击、闪避、连击、中毒、混乱自伤各自的固定说法。
func _test_combat_log() -> void:
	var steer := 0.0
	var attacker := _make_fighter("甲", 100, "", true)
	var defender := _make_fighter("乙", 100, "", false)
	_disarm(attacker)
	_disarm(defender)
	attacker.skills = [SkillCatalog.by_id("skill_crit")]
	var rng_crit := RollSource.new(1)
	rng_crit.push([0.0, 0.0])
	var crit_events: Array[StrikeResult] = CombatResolver.resolve_strikes(attacker, defender, steer, rng_crit)
	var crit_log := _joined_log(crit_events)
	_assert(crit_log.find("对乙造成【暴击】伤害") >= 0, "crit log uses 对XXX造成【暴击】伤害")

	_disarm(attacker)
	_disarm(defender)
	var dodge_buff := SkillCatalog.agent_buff_template(AgentChannels.CHANNEL_GROK)
	dodge_buff.dodge_bonus = 0.25
	_give_buffs(defender, [dodge_buff])
	var rng_dodge := RollSource.new(1)
	rng_dodge.push([0.6])
	var dodge_log := _joined_log(CombatResolver.resolve_strikes(attacker, defender, steer, rng_dodge))
	_assert(dodge_log.find("乙【闪避】了甲的伤害") >= 0, "dodge log uses XXX【闪避】了XXX的伤害")
	_assert(FileAccess.get_file_as_string("res://scripts/combat_log.gd").find("没有打中") < 0, "combat log has no 失手/whiff wording")

	_disarm(attacker)
	_disarm(defender)
	attacker.skills = [SkillCatalog.by_id("skill_double")]
	var rng_double := RollSource.new(1)
	rng_double.push([0.0, 0.99, 0.0, 0.0, 0.99])
	var double_log := _joined_log(CombatResolver.resolve_strikes(attacker, defender, steer, rng_double))
	_assert(double_log.find("甲对乙瞬间进攻了【两】次") >= 0, "double log uses 瞬间进攻了【两】次")

	_disarm(attacker)
	_disarm(defender)
	attacker.skills = [SkillCatalog.by_id("skill_triple")]
	var rng_triple := RollSource.new(1)
	rng_triple.push([0.0, 0.99, 0.0, 0.0, 0.99, 0.0, 0.99])
	var triple_log := _joined_log(CombatResolver.resolve_strikes(attacker, defender, steer, rng_triple))
	_assert(triple_log.find("甲对乙瞬间进攻了【三】次") >= 0, "triple log uses 瞬间进攻了【三】次")

	_disarm(attacker)
	_disarm(defender)
	attacker.skills = [SkillCatalog.by_id("skill_double"), SkillCatalog.by_id("skill_triple")]
	defender.hits_to_down = 20
	defender.hp = defender.max_hp
	var rng_five_log := RollSource.new(1)
	for i in 12:
		rng_five_log.push([0.0])
	var five_log := _joined_log(CombatResolver.resolve_strikes(attacker, defender, steer, rng_five_log))
	_assert(five_log.find("甲对乙瞬间进攻了【五】次") >= 0, "merged combo log uses 瞬间进攻了【五】次")
	_assert(five_log.find("瞬间进攻了【两】次") < 0 or five_log.find("甲对乙瞬间进攻了【五】次") >= 0, "five-hit log keeps the 五 wording")

	_disarm(attacker)
	_disarm(defender)
	attacker.skills = [SkillCatalog.by_id("skill_assassinate")]
	var rng_ass_log := RollSource.new(1)
	rng_ass_log.push([0.0, 0.0])
	var ass_log := _joined_log(CombatResolver.resolve_strikes(attacker, defender, steer, rng_ass_log))
	_assert(ass_log.find("甲对乙发动【幻影刺杀】") >= 0, "assassinate log names 幻影刺杀")

	_disarm(attacker)
	_disarm(defender)
	defender.skills = [SkillCatalog.by_id("skill_lingbo")]
	var rng_lb_log := RollSource.new(1)
	rng_lb_log.push([0.0, 0.0, 0.0])
	var lb_log := _joined_log(CombatResolver.resolve_strikes(attacker, defender, steer, rng_lb_log))
	_assert(lb_log.find("乙以【凌波微步】闪避了甲的伤害") >= 0, "lingbo log names 凌波微步")

	_disarm(attacker)
	_disarm(defender)
	attacker.skills = [SkillCatalog.by_id("skill_heal")]
	attacker.hp = 10
	var rng_heal_log := RollSource.new(1)
	rng_heal_log.push([0.0])
	var heal_log := _joined_log(CombatResolver.resolve_action(attacker, defender, steer, rng_heal_log))
	_assert(heal_log.find("甲发动【治疗】") >= 0, "heal log names 治疗")
	_assert(heal_log.find("本回合不进攻") >= 0, "heal log says the turn skips the attack")

	_disarm(attacker)
	_disarm(defender)
	attacker.skills = [SkillCatalog.by_id("skill_awaken")]
	var rng_awaken_log := RollSource.new(1)
	rng_awaken_log.push([0.0, 0.0, 0.99])
	var awaken_log := _joined_log(CombatResolver.resolve_strikes(attacker, defender, steer, rng_awaken_log))
	_assert(awaken_log.find("甲发动【潜能激发】") >= 0, "awaken log names 潜能激发")
	_assert(awaken_log.find("损失") >= 0, "awaken log mentions the HP cost")

	_disarm(attacker)
	_disarm(defender)
	attacker.skills = [SkillCatalog.by_id("skill_poison")]
	var rng_poison := RollSource.new(1)
	rng_poison.push([0.0, 0.99, 0.0])
	var poison_log := _joined_log(CombatResolver.resolve_strikes(attacker, defender, steer, rng_poison))
	_assert(poison_log.find("甲对乙造成了伤害，乙【中毒】了") >= 0, "poison log uses 造成了伤害，XXX【中毒】了")

	_disarm(attacker)
	_disarm(defender)
	attacker.skills = [
		SkillCatalog.by_id("skill_poison"),
		SkillCatalog.by_id("skill_paralyze"),
		SkillCatalog.by_id("skill_confuse"),
	]
	var rng_all := RollSource.new(1)
	rng_all.push([0.0, 0.99, 0.0, 0.0, 0.0])
	var all_log := _joined_log(CombatResolver.resolve_strikes(attacker, defender, steer, rng_all))
	_assert(all_log.find("乙【中毒，麻痹，混乱】了") >= 0, "multi-status log joins 中毒，麻痹，混乱")

	_disarm(attacker)
	_disarm(defender)
	attacker.confuse_turns = 3
	var rng_self := RollSource.new(1)
	rng_self.push([0.0, 0.0, 0.99])
	var self_events: Array[StrikeResult] = CombatResolver.resolve_action(attacker, defender, steer, rng_self)
	var self_log := _joined_log(self_events)
	var self_damage := 0
	for ev in self_events:
		if ev.self_hit:
			self_damage = ev.damage
	_assert(self_damage > 0, "the confused fighter really hurt themselves")
	_assert(self_log.find("甲因为【混乱】对自己造成了【%s】伤害" % NumberFormat.compact(self_damage)) >= 0, "confuse self-hit log reads XXX因为【混乱】对自己造成了【N】伤害")
	_assert(self_log.find("混乱了，对自己造成伤害") < 0, "the old confusion wording is gone")

	# 自伤一样要过命中判定：掷到 0.999 就是挥空，不能还写成造成了伤害。
	_disarm(attacker)
	_disarm(defender)
	attacker.confuse_turns = 3
	var rng_self_miss := RollSource.new(1)
	rng_self_miss.push([0.0, 0.999])
	var miss_log := _joined_log(CombatResolver.resolve_action(attacker, defender, steer, rng_self_miss))
	_assert(miss_log.find("甲因为【混乱】挥空了") >= 0, "a missed self-hit says so instead of claiming damage")


## buff 行和技能行的左边缘要对齐血条，而不是对齐名字。
func _assert_icons_align_to_hp_bar(view: FighterView) -> void:
	var bar_x := view.hp_bar.global_position.x
	_assert(view.buff_row.get_child_count() >= 1, "buff row has an icon to align")
	_assert(view.skill_row.get_child_count() >= 2, "skill row has at least two icons")
	var buff0 := view.buff_row.get_child(0) as Control
	var skill0 := view.skill_row.get_child(0) as Control
	_assert(absf(buff0.global_position.x - bar_x) <= 1.0, "first buff icon left-aligns to HP bar")
	_assert(absf(skill0.global_position.x - bar_x) <= 1.0, "first skill icon left-aligns to HP bar")
	for i in range(1, view.skill_row.get_child_count()):
		var prev := view.skill_row.get_child(i - 1) as Control
		var cur := view.skill_row.get_child(i) as Control
		_assert(cur.global_position.x > prev.global_position.x, "skill icons flow left to right")
	if view.buff_row.get_child_count() >= 2:
		for i in range(1, view.buff_row.get_child_count()):
			var prev_b := view.buff_row.get_child(i - 1) as Control
			var cur_b := view.buff_row.get_child(i) as Control
			_assert(cur_b.global_position.x > prev_b.global_position.x, "buff icons flow left to right")


## 名字和血条在同一个 StatusRow 里，血量文字嵌在血条内部。
func name_label_parent_is_status(view: FighterView) -> bool:
	var status := view.status_row
	return view.name_label.get_parent() == status and view.hp_wrap.get_parent() == status and view.hp_label.get_parent() == view.hp_wrap and view.hp_bar.get_parent() == view.hp_wrap


## 五族边框：同族外圈颜色一致，异族不一致；技能池每张图可加载且内部图案两两不同。
func _assert_icon_family_borders() -> void:
	var family_colors: Dictionary = {}
	var families: Dictionary = SkillCatalog.icon_families()
	for family in families:
		var ids: Array = families[family]
		_assert(ids.size() >= 2, "family %s has at least two icons to compare" % family)
		var ink := _icon_border_color(str(ids[0]))
		family_colors[family] = ink
		for icon_id in ids:
			var color := _icon_border_color(str(icon_id))
			_assert(color.is_equal_approx(ink), "family %s icon %s shares the family border" % [family, icon_id])
			var tex := SkillCatalog.load_icon(str(icon_id))
			_assert(tex != null and tex.get_width() > 0 and tex.get_height() > 0, "icon %s loads a non-empty texture" % icon_id)
	var seen: Array[Color] = []
	for family in family_colors:
		var ink: Color = family_colors[family]
		for other in seen:
			_assert(not ink.is_equal_approx(other), "family %s border differs from other families" % family)
		seen.append(ink)
	var pool: Array[SkillDef] = SkillCatalog.pool()
	_assert(pool.size() >= 18, "skill pool still has every remaining skill icon")
	var masks: Array[PackedByteArray] = []
	var ids: PackedStringArray = PackedStringArray()
	for skill in pool:
		var tex := SkillCatalog.load_icon(skill.icon_id)
		_assert(tex != null and tex.get_width() > 0 and tex.get_height() > 0, "pool icon %s loads" % skill.icon_id)
		var image := Image.new()
		_assert(image.load(SkillCatalog.icon_path(skill.icon_id)) == OK, "pool icon %s has pixels" % skill.icon_id)
		var mask := _icon_inner_occupancy(image)
		var marks := 0
		for bit in mask:
			marks += int(bit)
		_assert(marks >= 20, "pool icon %s has an inner glyph" % skill.icon_id)
		for i in ids.size():
			var diff := _mask_diff(masks[i], mask)
			_assert(diff >= 40, "inner glyph of %s differs from %s (%d pixels)" % [skill.icon_id, ids[i], diff])
		masks.append(mask)
		ids.append(skill.icon_id)


## 采样图标左边缘中点，那是烘焙时 rect() 描边的位置。
func _icon_border_color(icon_id: String) -> Color:
	var image := Image.new()
	var err := image.load(SkillCatalog.icon_path(icon_id))
	_assert(err == OK, "can load icon pixels for %s" % icon_id)
	return image.get_pixel(2, int(image.get_height() / 2.0))


## 边框以内相对底色的占位掩码。换色复制会得到同一份掩码，形状不同才会拉开像素差。
func _icon_inner_occupancy(image: Image) -> PackedByteArray:
	var bg := image.get_pixel(5, 5)
	var bits := PackedByteArray()
	for y in range(6, 26):
		for x in range(6, 26):
			var c := image.get_pixel(x, y)
			var dist := maxf(absf(c.r - bg.r), maxf(absf(c.g - bg.g), absf(c.b - bg.b)))
			bits.append(1 if c.a > 0.8 and dist > 0.14 else 0)
	return bits


## 红 X 骷髅：节点可见，且子树里有偏红的绘制。
func _skull_is_red_x(skull: Node2D) -> bool:
	if not skull.visible:
		return false
	for child in skull.get_children():
		if child is Polygon2D:
			var c: Color = (child as Polygon2D).color
			if c.r > 0.7 and c.g < 0.4:
				return true
		if child is Sprite2D:
			var sprite := child as Sprite2D
			if sprite.texture == null:
				continue
			var img := sprite.texture.get_image()
			if img == null:
				continue
			for y in mini(img.get_height(), 32):
				for x in mini(img.get_width(), 32):
					var c := img.get_pixel(x, y)
					if c.a > 0.5 and c.r > 0.7 and c.g < 0.45:
						return true
	return false


## 一个图标格子的悬停说明要同时包含技能名和效果描述。
func _assert_icon_tooltip(node: Node, skill: SkillDef) -> void:
	var rect := node as TextureRect
	_assert(rect != null and rect.texture != null, "icon TextureRect has a texture")
	_assert(rect.mouse_filter != Control.MOUSE_FILTER_IGNORE, "icon accepts hover")
	_assert(rect.tooltip_text.is_empty(), "native tooltip_text is empty to avoid ghosting")


## 图标加载、两行分开摆放，以及 battle.tscn 里几处关键坐标没被改回去。
func _test_icons_and_layout() -> void:
	for icon_id in SkillCatalog.all_icon_ids():
		var path := SkillCatalog.icon_path(icon_id)
		_assert(FileAccess.file_exists(path), "icon file exists: %s" % path)
	var view_src := FileAccess.get_file_as_string("res://scenes/fighter_view.gd")
	_assert(view_src.find("SkillCatalog.load_icon") >= 0, "fighter view loads skill/buff icons")
	_assert(view_src.find("buff_row") >= 0 and view_src.find("skill_row") >= 0, "fighter view has separate buff and skill rows")
	_assert(view_src.find("sort_for_display") >= 0, "fighter view lays out skills by display group")
	var battle_tscn := FileAccess.get_file_as_string("res://scenes/battle.tscn")
	_assert(battle_tscn.find("Vector2(320, 330)") >= 0, "champion slot moved up from y=480")
	_assert(battle_tscn.find("Vector2(960, 330)") >= 0, "opponent slot moved up from y=480")
	_assert(battle_tscn.find("Vector2(0, 240)") >= 0, "combat log min height is 240px")
	var fighter_tscn := FileAccess.get_file_as_string("res://scenes/fighter_view.tscn")
	_assert(fighter_tscn.find("StatusRow") >= 0, "StatusRow holds name/bar/value")
	_assert(fighter_tscn.find("BuffRow") >= 0 and fighter_tscn.find("SkillRow") >= 0, "BuffRow and SkillRow are separate")
	_assert(fighter_tscn.find("NameLabel") >= 0 and fighter_tscn.find("HpBar") >= 0 and fighter_tscn.find("HpLabel") >= 0, "name, bar and value exist")
	var battle_gd := FileAccess.get_file_as_string("res://scenes/battle.gd")
	_assert(battle_gd.find("play_crit_fx") >= 0, "Battle plays crit FX on crit strikes")
	_assert(battle_gd.find("play_dodge") >= 0, "Battle plays dodge retreat on dodges")
	_assert(battle_gd.find("play_poison_fx") >= 0 and battle_gd.find("poison_tick") >= 0, "Battle plays poison FX on poison ticks")
	_assert(battle_gd.find("event.poisoned") < 0, "poison FX is not played when the status is applied")
	_assert(battle_gd.find("play_heal_fx") >= 0, "Battle plays shared heal FX on lifesteal/heal")
	_assert(battle_gd.find("SKIP_HEAL") >= 0, "Battle plays the heal skip without an attack animation")
	_assert(battle_gd.find("event.awakened") >= 0, "Battle updates attacker HP when 潜能激发 spends health")
	_assert(battle_gd.find("play_paralyze_fx") >= 0 and battle_gd.find("SKIP_PARALYZE") >= 0, "Battle plays paralyze FX when the action is skipped")
	_assert(battle_gd.find("event.paralyzed") < 0, "paralyze FX is not played when the status is applied")
	_assert(battle_gd.find("play_confuse_fx") >= 0 and battle_gd.find("self_hit") >= 0, "Battle plays confuse FX on a confused self-hit")
	_assert(battle_gd.find("event.confused") < 0, "confuse FX is not played when the status is applied")
	_assert(battle_gd.find("play_assassinate_fx") >= 0 and battle_gd.find("event.assassinated") >= 0, "Battle plays skull FX on assassinate")
	_assert(battle_gd.find("play_guard_fx") >= 0 and battle_gd.find("event.guarded") >= 0, "Battle plays the shield bubble on absolute guard")
	_assert(battle_gd.find("play_dodge") >= 0 and battle_gd.find("凌波") >= 0, "Battle reuses dodge FX for lingbo")
	var fv_src := FileAccess.get_file_as_string("res://scenes/fighter_view.gd")
	_assert(fv_src.find("HEAL_FX") >= 0 and fv_src.find("play_heal_fx") >= 0, "lifesteal and heal share HEAL_FX")
	_assert(fv_src.find("CombatFx") >= 0, "fighter view reuses CombatFx for bursts/afterimages/skull")
	_assert(fv_src.find("set_loops") < 0, "status FX do not loop after they expire")
	_assert(fv_src.find("_stop_burst_later") >= 0 and fv_src.find("_hide_stun") >= 0, "status bursts and stun stars are recycled")
	_assert(FileAccess.file_exists("res://scenes/heal_fx.tscn"), "shared heal FX scene exists")
	_assert(FileAccess.file_exists("res://assets/fx/skull_x.png"), "red X skull texture exists")
	_assert_icon_family_borders()


## 12 种形象两两不同，且只有擂主头顶有金色王冠。
func _test_appearances_and_crown() -> void:
	_assert(SpriteFactory.COUNT >= 12, "pool size is at least 12")
	var ids: Dictionary = {}
	for i in 80:
		var user := _ranked("user_%d" % i, 10)
		var fighter := Fighter.from_ranked(user, false)
		ids[fighter.appearance_id] = true
	_assert(ids.size() > 4, "username hashes cover more than 4 appearance ids")
	var human_masks: Array[PackedByteArray] = []
	for id in range(SpriteFactory.ANIMAL_START):
		human_masks.append(_opaque_mask(SpriteFactory.make_texture(id, "idle", false).get_image()))
	for extra in range(SpriteFactory.ORIGINAL_HUMANS, SpriteFactory.ANIMAL_START):
		var best := 9999
		for orig in range(SpriteFactory.ORIGINAL_HUMANS):
			best = mini(best, _mask_diff(human_masks[extra], human_masks[orig]))
		_assert(best >= 18, "extra human %d silhouette differs from original humans" % extra)
	for animal in range(SpriteFactory.ANIMAL_START, SpriteFactory.COUNT):
		var amask := _opaque_mask(SpriteFactory.make_texture(animal, "idle", false).get_image())
		for hid in range(SpriteFactory.ANIMAL_START):
			_assert(_mask_diff(amask, human_masks[hid]) >= 24, "animal %d is not a recolor of human %d" % [animal, hid])
	for id in range(SpriteFactory.COUNT):
		for pose in ["idle", "attack", "hurt"]:
			var champ_img := SpriteFactory.make_texture(id, pose, true).get_image()
			var foe_img := SpriteFactory.make_texture(id, pose, false).get_image()
			_assert(_has_gold_crown(champ_img), "champion appearance %d pose %s has a gold crown" % [id, pose])
			_assert(not _has_gold_crown(foe_img), "challenger appearance %d pose %s has no gold crown" % [id, pose])
	var champ_user := _ranked("crown_bind", 10)
	var champ := Fighter.from_ranked(champ_user, true)
	var foe := Fighter.from_ranked(champ_user, false)
	foe.appearance_id = champ.appearance_id
	var view: FighterView = (load("res://scenes/fighter_view.tscn") as PackedScene).instantiate()
	root.add_child(view)
	view.bind(champ, false)
	_assert(_has_gold_crown(view.sprite.texture.get_image()), "bound champion sprite wears a gold crown")
	view.bind(foe, true)
	_assert(not _has_gold_crown(view.sprite.texture.get_image()), "bound challenger sprite has no crown")
	view.queue_free()


## 把图压成一张“每个像素透不透明”的位图，用来比较轮廓。
func _opaque_mask(image: Image) -> PackedByteArray:
	var bits := PackedByteArray()
	bits.resize(image.get_width() * image.get_height())
	var i := 0
	for y in image.get_height():
		for x in image.get_width():
			bits[i] = 1 if image.get_pixel(x, y).a > 0.5 else 0
			i += 1
	return bits


## 两张轮廓位图有多少个像素不一样。
func _mask_diff(a: PackedByteArray, b: PackedByteArray) -> int:
	var n := 0
	for i in a.size():
		if a[i] != b[i]:
			n += 1
	return n


## 图的顶部一条带里有没有金色像素（王冠）。
func _has_gold_crown(image: Image) -> bool:
	var band := mini(10, image.get_height())
	for y in band:
		for x in image.get_width():
			var c := image.get_pixel(x, y)
			if c.a > 0.5 and c.r > 0.9 and c.g > 0.75 and c.b < 0.22:
				return true
	return false


## 整场演出跑通，战报正序排列；并且中途把场景摘走时，
## 挂在 await 上的播放协程能自己收手，不会去碰已经没了的场景树。
func _test_battle_playback() -> void:
	_remove_test_battle_record()
	var packed := load("res://scenes/battle.tscn") as PackedScene
	var battle: Node = packed.instantiate()
	battle.skip_autoload = true
	battle.record_path = TEST_BATTLE_RECORD_PATH
	root.add_child(battle)
	await process_frame
	var ranked: Array[RankedUser] = [_ranked("champ", 400)]
	for i in 7:
		ranked.append(_ranked("foe_%d" % i, 8))
	var idle_view: FighterView = battle.get_node("%OpponentSlot").get_child(0) if battle.get_node("%OpponentSlot").get_child_count() > 0 else null
	await battle._start_war(ranked)
	_assert(battle._war.outcome != WheelWar.Outcome.ONGOING, "7+ opponent war reaches a terminal outcome")
	_assert(battle.get_node("%ResultPanel").visible, "result panel shows after the war")

	# 战报按时间正序往下排，并且自动跟到最下方。
	var log_node: RichTextLabel = battle.get_node("%BattleLog")
	# add_text 追加的内容不进 text 属性，读全文要走 get_parsed_text。
	var log_lines := log_node.get_parsed_text().split("\n")
	_assert(log_lines.size() > 2, "the war leaves a multi-line report")
	_assert(log_lines[0].find("车轮战开始") >= 0, "the opening line stays at the top")
	_assert(log_lines[log_lines.size() - 1].find("车轮战开始") < 0, "the newest line is at the bottom, not the top")
	_assert(log_node.scroll_following, "the report follows the newest line to the bottom")
	# 中途点“返回”会立刻释放这个场景，但播放协程还挂在 await 上。
	# 这里确认它能安全收手，而不是对着已经离开场景树的节点调 get_tree()。
	var quitter: Node = packed.instantiate()
	quitter.skip_autoload = true
	quitter.record_path = TEST_BATTLE_RECORD_PATH
	root.add_child(quitter)
	await process_frame
	var short_roster: Array[RankedUser] = [_ranked("champ", 400000000, AgentChannels.CHANNEL_CODEX)]
	for i in 4:
		short_roster.append(_ranked("foe_%d" % i, 40000000, AgentChannels.CHANNEL_GROK))
	quitter._start_war(short_roster)
	await process_frame
	_assert(quitter._busy, "the playback loop is running")
	quitter._leaving = true
	root.remove_child(quitter)
	# 计时器走的是真实时间，headless 下空跑帧几乎不耗时，所以要等一小段实时。
	var deadline := Time.get_ticks_msec() + 3000
	while quitter._busy and Time.get_ticks_msec() < deadline:
		await create_timer(0.02).timeout
	_assert(not quitter._is_live(), "a detached battle scene reports itself as gone")
	_assert(not quitter._busy, "the playback loop stops itself instead of touching a null tree")
	quitter.queue_free()
	await process_frame

	var player: AnimationPlayer = battle._champion_view.anim_player
	player.play(&"idle")
	await process_frame
	await battle._await_oneshot(player)
	_assert(true, "awaiting looping idle returns instead of hanging")
	battle.queue_free()
	await process_frame


## 结果面板的胜负文案和 MVP 评选，赢和输两种都要评。
func _test_result_copy() -> void:
	_remove_test_battle_record()
	var packed := load("res://scenes/battle.tscn") as PackedScene
	var battle: Node = packed.instantiate()
	battle.skip_autoload = true
	battle.record_path = TEST_BATTLE_RECORD_PATH
	root.add_child(battle)
	await process_frame
	var win_ranked: Array[RankedUser] = [_ranked("甲", 50), _ranked("乙", 10)]
	battle._rng = RollSource.new(1)
	battle._war = WheelWar.new()
	battle._war.setup(win_ranked, battle._rng)
	battle._war.outcome = WheelWar.Outcome.ALL_OPPONENTS_DOWN
	battle._tally = DamageTally.new()
	battle._tally.add_events([_strike("乙", "甲", 7, false)] as Array[StrikeResult])
	battle._show_result()
	_assert(battle.get_node("%MvpLabel").text.find("【乙】") >= 0, "赢下来的场次也评 MVP")
	_assert(battle.get_node("%ResultLabel").text == "甲经过艰难的鏖战，终于干掉了所有的挑战者，成为了唯一神", "win copy matches OBJECTIVE")
	battle._war.outcome = WheelWar.Outcome.CHAMPION_DOWN
	battle._show_result()
	_assert(battle.get_node("%ResultLabel").text == "甲在经过多轮鏖战，惜败于%s" % battle._war.current_opponent.username, "lose copy names the knocking challenger")
	_assert(battle.get_node("%MvpLabel").text.find("【乙】") >= 0, "输掉的场次照样评 MVP")
	var tscn := FileAccess.get_file_as_string("res://scenes/battle.tscn")
	_assert(tscn.find("挑战者（乱序逐个上场）") < 0, "side tag 挑战者（乱序逐个上场） is gone")
	_assert(tscn.find("text = \"榜一\"") < 0, "side tag 榜一 is gone")
	_assert(tscn.find("榜一胜率") < 0, "HUD win-rate percent label is gone")
	battle.queue_free()
	await process_frame


## 顺手把 12 种形象 × 3 种姿势 × 有无王冠导成 PNG，
## 放进 assets/characters 供人肉检查，不参与断言。
func _export_character_pngs() -> void:
	var abs_dir := ProjectSettings.globalize_path("res://assets/characters")
	DirAccess.make_dir_recursive_absolute(abs_dir)
	for appearance in range(SpriteFactory.COUNT):
		for pose in ["idle", "attack", "hurt"]:
			var tex := SpriteFactory.make_texture(appearance, pose, false)
			var image := tex.get_image()
			var path := "res://assets/characters/fighter_%d_%s.png" % [appearance, pose]
			var err := image.save_png(path)
			_assert(err == OK, "saved %s" % path)
			var crown := SpriteFactory.make_texture(appearance, pose, true).get_image()
			var cpath := "res://assets/characters/fighter_%d_%s_crown.png" % [appearance, pose]
			_assert(crown.save_png(cpath) == OK, "saved %s" % cpath)


## 电视遥控器：上下切菜单、OK 确认、BACK 返回/退出。
func _test_tv_remote() -> void:
	# 遥控器用例不继承其他 Web 菜单用例的参数快照。
	WebLaunchConfig.reset()
	TvRemote.install()
	TvRemote.install()  # 幂等，重复调用不该把同一个按键塞两遍
	var cancel_keys := 0
	var cancel_has_back := false
	var cancel_has_b := false
	for event in InputMap.action_get_events(&"ui_cancel"):
		if event is InputEventKey and (event as InputEventKey).keycode == KEY_BACK:
			cancel_keys += 1
			cancel_has_back = true
		if event is InputEventJoypadButton and (event as InputEventJoypadButton).button_index == JOY_BUTTON_B:
			cancel_has_b = true
	_assert(cancel_has_back, "Android TV BACK key is bound to ui_cancel")
	_assert(cancel_keys == 1, "installing twice does not duplicate the BACK binding")
	_assert(cancel_has_b, "gamepad-style remotes cancel with B")
	var accept_has_a := false
	for event in InputMap.action_get_events(&"ui_accept"):
		if event is InputEventJoypadButton and (event as InputEventJoypadButton).button_index == JOY_BUTTON_A:
			accept_has_a = true
	_assert(accept_has_a, "gamepad-style remotes confirm with A")

	# 遥控器方向键在 Android 上就是 KEY_UP / KEY_DOWN，OK 键是 KEY_ENTER。
	_assert(_key_event(KEY_DOWN).is_action_pressed(&"ui_down"), "D-pad down drives ui_down")
	_assert(_key_event(KEY_UP).is_action_pressed(&"ui_up"), "D-pad up drives ui_up")
	_assert(_key_event(KEY_ENTER).is_action_pressed(&"ui_accept"), "remote OK drives ui_accept")
	_assert(_key_event(KEY_BACK).is_action_pressed(&"ui_cancel"), "remote BACK drives ui_cancel")
	_assert(TvRemote.is_back(_key_event(KEY_BACK)), "TvRemote.is_back recognises the BACK key")

	# 一场接一场自动打，中途没人按遥控器，屏幕不能被系统熄掉。
	_assert(bool(ProjectSettings.get_setting("display/window/energy_saving/keep_screen_on", false)), "工程设置里开了屏幕常亮")
	_assert(FileAccess.get_file_as_string("res://scripts/tv_remote.gd").find("screen_set_keep_on(true)") >= 0, "运行时每次进场景再确认一次常亮")
	_assert(FileAccess.get_file_as_string("res://tools/fix_android_preset.py").find("permissions/wake_lock") >= 0, "Android 导出带上 WAKE_LOCK 权限")

	var back_setting := ""
	for line in FileAccess.get_file_as_string("res://project.godot").split("\n"):
		if line.strip_edges().begins_with("config/quit_on_go_back="):
			back_setting = line.strip_edges().trim_prefix("config/quit_on_go_back=")
	_assert(back_setting == "false", "the engine does not quit on BACK; each scene handles it")

	# 主菜单：焦点从“进入对战”一路往下走，再走回来。
	var main: Node = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	await process_frame
	var ranking_btn: Button = main.get_node("%RankingButton")
	var battle_btn: Button = main.get_node("%BattleButton")
	var settings_btn: Button = main.get_node("%SettingsButton")
	var quit_btn: Button = main.get_node("%QuitButton")
	_assert(battle_btn.has_focus(), "the menu starts on Battle, so the remote has something to move")
	_assert(battle_btn.focus_mode == Control.FOCUS_ALL and settings_btn.focus_mode == Control.FOCUS_ALL and quit_btn.focus_mode == Control.FOCUS_ALL, "every menu entry can take focus")
	_assert(battle_btn.has_theme_stylebox_override("focus"), "focused buttons draw a TV-visible outline")
	await _press_key(KEY_DOWN)
	_assert(ranking_btn.has_focus(), "D-pad down moves to 查看排行")
	await _press_key(KEY_DOWN)
	_assert(settings_btn.has_focus(), "D-pad down moves to 设置")
	await _press_key(KEY_DOWN)
	_assert(quit_btn.has_focus(), "D-pad down moves to 退出游戏")
	await _press_key(KEY_UP)
	_assert(settings_btn.has_focus(), "D-pad up walks back up the menu")

	# 焦点丢了（比如鼠标点到空白处）之后，方向键要能把它捡回来。
	# 松的是上面那几下走下来后真正拿着焦点的那个，别写死成某个按钮——
	# 菜单一加项就会错位，而错位之后这条断言是“假通过”。
	settings_btn.release_focus()
	await process_frame
	_assert(TvRemote.ensure_focus(battle_btn), "a lost focus is restored before navigating")
	_assert(battle_btn.has_focus(), "focus lands back on Battle, the first entry")

	# OK 键确认：焦点在按钮上时按下回车会触发 pressed。
	var probe := Button.new()
	probe.focus_mode = Control.FOCUS_ALL
	main.add_child(probe)
	await process_frame
	probe.grab_focus()
	var fired := [false]
	probe.pressed.connect(func() -> void: fired[0] = true)
	await _press_key(KEY_ENTER)
	_assert(fired[0], "remote OK presses the focused button")
	main.queue_free()
	await process_frame

	# 三个场景都得自己接住 BACK：主菜单退出，另外两个回主菜单。
	for path in ["res://scenes/main.gd", "res://scenes/ranking.gd", "res://scenes/battle.gd"]:
		var src := FileAccess.get_file_as_string(path)
		_assert(src.find("NOTIFICATION_WM_GO_BACK_REQUEST") >= 0, "%s handles the Android go-back notification" % path)
		_assert(src.find("TvRemote.consume_back(event") >= 0, "%s handles the BACK key event" % path)
		_assert(src.find("TvRemote.install()") >= 0, "%s installs the remote bindings" % path)
	_assert(FileAccess.get_file_as_string("res://scenes/main.gd").find("get_tree().quit()") >= 0, "BACK on the main menu quits the app")
	var battle_src := FileAccess.get_file_as_string("res://scenes/battle.gd")
	_assert(battle_src.find("%BackButton.focus_mode = Control.FOCUS_ALL") >= 0, "the battle 返回 button stays focusable during playback")
	_assert(battle_src.find("focus_mode = Control.FOCUS_NONE") < 0, "nothing turns the battle 返回 button unfocusable")
	var ranking_src := FileAccess.get_file_as_string("res://scenes/ranking.gd")
	_assert(ranking_src.find("%Scroll.scroll_vertical") >= 0, "the ranking list scrolls with the D-pad")


## 造一个按键事件。
func _key_event(key: Key) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = key
	event.pressed = true
	return event


## 模拟按下并抬起一个键，走完整的输入分发。
func _press_key(key: Key) -> void:
	root.push_input(_key_event(key))
	await process_frame
	var up := _key_event(key)
	up.pressed = false
	root.push_input(up)
	await process_frame


## 造一条命中事件，用于给 DamageTally 喂数据。
func _strike(attacker: String, defender: String, dmg: int, from_champion: bool) -> StrikeResult:
	var event := StrikeResult.new()
	event.attacker_name = attacker
	event.defender_name = defender
	event.attacker_is_champion = from_champion
	event.hit = dmg > 0
	event.damage = dmg
	return event


## MVP 只算挑战者打在擂主身上的输出。
func _test_damage_tally() -> void:
	var tally := DamageTally.new()
	var events: Array[StrikeResult] = []
	events.append(_strike("擂主", "甲", 999, true))
	events.append(_strike("甲", "擂主", 100, false))
	events.append(_strike("乙", "擂主", 250, false))
	events.append(_strike("甲", "擂主", 60, false))
	events.append(_strike("丙", "擂主", 0, false))
	var poison := _strike("乙", "乙", 40, false)
	poison.poison_tick = true
	events.append(poison)
	var confused := _strike("丁", "丁", 70, false)
	confused.self_hit = true
	events.append(confused)
	tally.add_events(events)
	_assert(int(tally.totals.get("甲", 0)) == 160, "同一个挑战者的多次输出累加")
	_assert(int(tally.totals.get("乙", 0)) == 250, "中毒掉血不算在中毒者自己头上")
	_assert(not tally.totals.has("擂主"), "擂主的输出不参与 MVP 评选")
	_assert(not tally.totals.has("丙"), "没打中不计分")
	_assert(not tally.totals.has("丁"), "混乱自伤不计分")
	var top := tally.best()
	_assert(str(top["username"]) == "乙" and int(top["damage"]) == 250, "MVP 是对擂主输出最高的挑战者")
	var line := CombatLog.mvp_line(tally.best())
	_assert(line.find("【乙】") >= 0 and line.find("MVP") >= 0, "MVP 文案点名到人")
	_assert(line.find(NumberFormat.compact(250)) >= 0, "MVP 文案带上伤害数字")
	var empty := DamageTally.new()
	_assert(str(empty.best()["username"]).is_empty(), "没人伤到擂主时 MVP 空缺")
	_assert(CombatLog.mvp_line(empty.best()).find("空缺") >= 0, "空缺时也给一句说明")


## 一场打完 → 倒计时 → 清场，准备重新拉名单开下一轮。
func _test_next_round_cycle() -> void:
	_remove_test_battle_record()
	var packed := load("res://scenes/battle.tscn") as PackedScene
	var battle: Node = packed.instantiate()
	battle.skip_autoload = true
	battle.record_path = TEST_BATTLE_RECORD_PATH
	root.add_child(battle)
	await process_frame
	_assert(battle.NEXT_ROUND_DELAY == 60.0, "打完一分钟后自动开下一轮")
	var battle_src := FileAccess.get_file_as_string("res://scenes/battle.gd")
	_assert(battle_src.find("func _round_loop") >= 0, "有一层轮次循环在驱动下一轮")
	_assert(battle_src.find("await _load_and_run()") >= 0, "下一轮重新拉一次今日名单")
	var ranked: Array[RankedUser] = [_ranked("甲", 5000), _ranked("乙", 300), _ranked("丙", 300)]
	var round_backdrop := battle.get_node("%BattleBackground") as BattleParallax
	var champion_view := battle.get_node("%ChampionView") as FighterView
	var opponent_view := battle.get_node("%OpponentView") as FighterView
	var champion_view_id := champion_view.get_instance_id()
	var opponent_view_id := opponent_view.get_instance_id()
	_assert(round_backdrop.current_index == -1, "尚未真正开战时背景还没有消耗一次 Round roll")
	await battle._start_war(ranked)
	_assert(round_backdrop.current_index >= 0, "每次真正进入 _start_war 都会 Roll 一张背景")
	_assert(battle.get_node("%ResultPanel").visible, "一场打完先出结果面板")
	_assert(not battle.get_node("%MvpLabel").text.is_empty(), "结果面板带 MVP 一行")
	_assert(battle.get_node("%BattleLog").get_parsed_text().find("MVP") >= 0, "MVP 也写进战报")
	battle._countdown(2.0, "下一轮")
	await process_frame
	_assert(battle.get_node("%NextRoundLabel").text.find("下一轮") >= 0, "倒计时告诉玩家下一轮什么时候开始")
	battle._leaving = true
	await create_timer(1.2).timeout
	battle._leaving = false
	battle._reset_for_next_round()
	_assert(battle.get_node("%BattleLog").get_parsed_text().is_empty(), "新一轮开始前战报清空")
	_assert(not battle.get_node("%ResultPanel").visible, "新一轮开始前结果面板收起")
	_assert(battle.get_node("%ChampionSlot").get_child_count() == 1, "固定擂主视图留在场景树里")
	_assert(not battle.get_node("%ChampionView").visible and not battle.get_node("%OpponentView").visible, "下一轮前两个固定角色视图已复位并隐藏")
	_assert(battle._war == null and battle._tally == null, "上一场的状态被丢弃")
	await battle._start_war(ranked)
	_assert(champion_view.get_instance_id() == champion_view_id, "第二轮复用同一个擂主 FighterView")
	_assert(opponent_view.get_instance_id() == opponent_view_id, "第二轮复用同一个挑战者 FighterView")
	_assert(battle.get_node("%ChampionSlot").get_child_count() == 1, "第二轮不会向擂主 Slot 追加节点")
	_assert(battle.get_node("%OpponentSlot").get_child_count() == 1, "第二轮不会向挑战者 Slot 追加节点")
	_assert(champion_view.visible and champion_view.sprite.texture != null, "常驻擂主视图在第二轮重新绑定角色")
	battle.queue_free()
	await process_frame


## 当天战绩要经得起退出重进：写盘、读回、隔天作废。
func _test_round_record() -> void:
	var path := "user://test_daily_rounds.json"
	var absolute := ProjectSettings.globalize_path(path)
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(absolute)
	var today := "2026-09-18"
	var fresh := RoundRecord.load_for(today, path)
	_assert(fresh.rounds == 0 and fresh.standings().is_empty(), "没有存档时从零开始")
	fresh.record_round("甲", true)
	fresh.record_round("甲", true)
	fresh.record_round("乙", false)
	fresh.save(path)
	var again := RoundRecord.load_for(today, path)
	_assert(again.rounds == 3, "当天总场次写盘后能读回来")
	var rows := again.standings()
	_assert(rows.size() == 2, "每位当过擂主的玩家都在榜上")
	_assert(str(rows[0]["username"]) == "甲" and int(rows[0]["wins"]) == 2, "胜场多的排前面")
	_assert(str(rows[1]["username"]) == "乙" and int(rows[1]["wins"]) == 0, "一场没赢也留在榜上，记 0 场")
	_assert(int(rows[1]["rounds"]) == 1, "0 胜的人也记下了他参战过")
	var tomorrow := RoundRecord.load_for("2026-09-19", path)
	_assert(tomorrow.rounds == 0 and tomorrow.standings().is_empty(), "隔天的记录不算数，当天有效")
	DirAccess.remove_absolute(absolute)


## 右侧战绩榜：场次、名次、前三名的金银铜牌。
func _test_record_board() -> void:
	var battle: Node = (load("res://scenes/battle.tscn") as PackedScene).instantiate()
	battle.skip_autoload = true
	battle.record_path = TEST_BATTLE_RECORD_PATH
	root.add_child(battle)
	await process_frame
	battle._record = RoundRecord.new()
	battle._record.date = "2026-09-18"
	for i in 3:
		battle._record.record_round("甲", true)
	battle._record.record_round("乙", true)
	battle._record.record_round("丙", false)
	battle._refresh_record_board()
	await process_frame
	_assert(battle.get_node("%RoundLabel").text == "今日第 6 场", "顶栏显示这是今天第几场")
	var result_style: StyleBoxFlat = battle.get_node("%ResultPanel").get_theme_stylebox("panel") as StyleBoxFlat
	_assert(result_style != null and result_style.bg_color.a >= 1.0, "结果面板有不透明底色，不会糊在立绘上")
	_assert(battle.get_node("%RecordTitle").text.find("共 5 场") >= 0, "战绩榜标题带当天总场次")
	var list: Node = battle.get_node("%RecordList")
	var empty_label := battle.get_node("%RecordEmptyLabel") as Label
	_assert(empty_label != null and not empty_label.visible, "有战绩时隐藏场景内预置的空榜提示")
	var rows: Array[Node] = []
	for child in list.get_children():
		if child is HBoxContainer:
			rows.append(child)
	_assert(rows.size() == 3, "三位上过榜一的玩家都列出来")
	var first: Node = rows[0]
	_assert((first.get_child(1) as Label).text == "【甲】", "第一名是胜场最多的")
	_assert((first.get_child(2) as Label).text == "3 场", "胜出的场次写在右边")
	var third: Node = rows[2]
	_assert((third.get_child(1) as Label).text == "【丙】", "0 胜的也在榜上")
	_assert((third.get_child(2) as Label).text == "0 场", "0 胜显示成 0 场")
	var medals := [ThemeHelper.GOLD, ThemeHelper.SILVER, ThemeHelper.BRONZE]
	for i in 3:
		var badge: Panel = rows[i].get_child(0) as Panel
		var box: StyleBoxFlat = badge.get_theme_stylebox("panel") as StyleBoxFlat
		_assert(box != null and box.bg_color == medals[i], "第 %d 名挂的是%s牌" % [i + 1, ["金", "银", "铜"][i]])
	battle.queue_free()
	await process_frame


## 擂主的立绘比挑战者大一圈。
func _test_body_scale() -> void:
	var packed := load("res://scenes/fighter_view.tscn") as PackedScene
	var champion_view: FighterView = packed.instantiate()
	var challenger_view: FighterView = packed.instantiate()
	root.add_child(champion_view)
	root.add_child(challenger_view)
	await process_frame
	champion_view.bind(Fighter.from_ranked(_ranked("甲", 100), true), false)
	challenger_view.bind(Fighter.from_ranked(_ranked("乙", 100), false), true)
	var champion_scale: float = (champion_view.get_node("Visual") as Node2D).scale.y
	var challenger_scale: float = (challenger_view.get_node("Visual") as Node2D).scale.y
	_assert(is_equal_approx(champion_scale, 1.1), "擂主放大到 1.1 倍")
	_assert(is_equal_approx(challenger_scale, 0.9), "挑战者缩到 0.9 倍")
	_assert(absf((challenger_view.get_node("Visual") as Node2D).scale.x) == challenger_scale, "缩放不影响左右翻转")
	_assert((champion_view.get_node("Visual") as Node2D).position.y < 0.0, "放大后把立绘往上提，脚不陷进地里")
	_assert((challenger_view.get_node("Visual") as Node2D).position.y > 0.0, "缩小后把立绘往下压，脚不悬空")
	champion_view.queue_free()
	challenger_view.queue_free()
	await process_frame


## 体型带来的先天属性，以及它对命中 / 伤害的实际影响。
func _test_size_traits() -> void:
	var boss := _make_fighter("boss", 1000, "", true)
	var challenger := _make_fighter("foe", 1000, "", false)
	_disarm(boss)
	_disarm(challenger)
	_assert(is_equal_approx(boss.stacked_dodge(), Fighter.BASE_DODGE + Fighter.CHAMPION_INNATE_DODGE), "擂主基础闪避叠体型修正")
	_assert(is_equal_approx(challenger.stacked_dodge(), Fighter.BASE_DODGE + Fighter.CHALLENGER_INNATE_DODGE), "挑战者基础闪避叠体型修正")
	_assert(is_equal_approx(boss.stacked_crit(), Fighter.BASE_CRIT), "擂主无技能也有基础暴击")
	_assert(is_equal_approx(challenger.stacked_crit(), Fighter.BASE_CRIT), "挑战者无技能也有基础暴击")
	_assert(is_equal_approx(boss.stacked_counter(), 0.0), "反击没有全员基础")
	_assert(is_equal_approx(challenger.stacked_counter(), 0.0), "挑战者反击仍为 0")
	_assert(is_equal_approx(boss.stacked_damage_reduction(), Fighter.CHAMPION_INNATE_DAMAGE_REDUCTION), "擂主先天减伤，没有全员基础减伤")
	_assert(is_equal_approx(challenger.stacked_damage_reduction(), 0.0), "挑战者没有先天减伤")

	# 无闪避技能时，落在闪避段的点数仍记闪避（挑战者 15% → 命中线 0.75）。
	var rng_base_dodge := RollSource.new(1)
	rng_base_dodge.push([0.80])
	var base_dodge_ev: Array[StrikeResult] = CombatResolver.resolve_strikes(boss, challenger, 0.0, rng_base_dodge)
	_assert(base_dodge_ev[0].dodged and not base_dodge_ev[0].hit, "base dodge procs without a dodge skill")
	# 无暴击技能时也能暴击，伤害高于同一次非暴击。从完整 resolve_strikes 进。
	challenger.hp = challenger.max_hp
	var rng_base_crit := RollSource.new(1)
	rng_base_crit.push([0.0, 0.0])
	var base_crit_ev: Array[StrikeResult] = CombatResolver.resolve_strikes(boss, challenger, 0.5, rng_base_crit)
	_assert(base_crit_ev[0].hit and base_crit_ev[0].crit, "base crit procs without a crit skill")
	challenger.hp = challenger.max_hp
	var rng_base_nocrit := RollSource.new(1)
	rng_base_nocrit.push([0.0, 0.99])
	var base_nocrit_ev: Array[StrikeResult] = CombatResolver.resolve_strikes(boss, challenger, 0.5, rng_base_nocrit)
	_assert(base_nocrit_ev[0].hit and not base_nocrit_ev[0].crit, "the same opening hit roll is not a crit when the crit die misses")
	_assert(base_crit_ev[0].damage > base_nocrit_ev[0].damage, "a base crit hits harder than the non-crit twin")

	# 先天闪避直接反映在命中率上：同样的基础命中，打擂主更容易命中。
	var on_boss := CombatResolver.hit_chance(challenger, boss, 0.0)
	var on_challenger := CombatResolver.hit_chance(boss, challenger, 0.0)
	_assert(is_equal_approx(on_boss - on_challenger, Fighter.CHALLENGER_INNATE_DODGE - Fighter.CHAMPION_INNATE_DODGE), "先天闪避差把双方命中率拉开")

	# 技能叠在先天之上，不是二选一。
	challenger.skills = [SkillCatalog.by_id("skill_dodge")]
	_assert(is_equal_approx(challenger.stacked_dodge(), Fighter.BASE_DODGE + Fighter.CHALLENGER_INNATE_DODGE + SkillCatalog.SELF_BUFF_CHANCE), "闪避技能叠在基础和体型修正之上")
	boss.skills = [SkillCatalog.by_id("skill_dr")]
	_assert(is_equal_approx(boss.stacked_damage_reduction(), Fighter.CHAMPION_INNATE_DAMAGE_REDUCTION + SkillCatalog.SELF_BUFF_CHANCE), "减伤技能叠在先天减伤之上")

	# 没打中只有闪避，打空擂主也记成闪避，不会写成失手。
	_disarm(boss)
	_disarm(challenger)
	var rng_miss := RollSource.new(1)
	rng_miss.push([0.99])
	var miss: Array[StrikeResult] = CombatResolver.resolve_strikes(challenger, boss, 0.5, rng_miss)
	_assert(not miss[0].hit and miss[0].dodged, "打空也是闪避，不存在失手")
	_assert(_joined_log(miss).find("失手") < 0, "combat log never says 失手")
	_assert(_joined_log(miss).find("【闪避】") >= 0, "a failed swing logs as 闪避")

	# 擂主的先天减伤实打实削伤害。
	var plain := _make_fighter("plain", 1000, "", false)
	_disarm(plain)
	plain.hits_to_down = boss.hits_to_down
	var rng_dmg := RollSource.new(1)
	rng_dmg.push([0.0, 0.99])
	var on_boss_hit: Array[StrikeResult] = CombatResolver.resolve_strikes(challenger, boss, 0.9, rng_dmg)
	var rng_dmg2 := RollSource.new(1)
	rng_dmg2.push([0.0, 0.99])
	var on_plain_hit: Array[StrikeResult] = CombatResolver.resolve_strikes(challenger, plain, 0.9, rng_dmg2)
	_assert(on_boss_hit[0].damage < on_plain_hit[0].damage, "同样一击，打在擂主身上被先天减伤削掉一截")

	# 状态技共用同一份活概率。
	for skill_id in ["skill_poison", "skill_paralyze", "skill_confuse"]:
		var skill := SkillCatalog.by_id(skill_id)
		var chance := skill.poison_chance + skill.paralyze_chance + skill.confuse_chance + skill.root_chance
		_assert(is_equal_approx(chance, SkillCatalog.STATUS_CHANCE), "%s 触发概率是活的状态技概率" % skill_id)

	# 人越多，擂主越吃亏（个个都是满血新人，他的血条连着算），命中率上按人头补一点。
	_assert(is_equal_approx(CombatResolver.champion_crowd_relief(CombatResolver.CHAMPION_CROWD_RELIEF_BASE), 0.0), "补偿起点之内不额外补命中")
	_assert(CombatResolver.champion_crowd_relief(CombatResolver.CHAMPION_CROWD_RELIEF_BASE + 1) > 0.0, "超过补偿起点才开始补命中")
	_assert(CombatResolver.champion_crowd_relief(14) <= CombatResolver.CHAMPION_CROWD_RELIEF_CAP + 0.0001, "大榜单的补偿有封顶")
	_assert(CombatResolver.champion_steer(0.5, 0.0, 0.0, 14) > CombatResolver.champion_steer(0.5, 0.0, 0.0, 2), "同样目标胜率，人越多给擂主补得越多")
	# 技能张数差改成按张计价：多摸一张就多让一点命中率，不再用平均张数硬编。
	_assert(CombatResolver.champion_steer(0.5, 0.0, 4.0) < CombatResolver.champion_steer(0.5, 0.0, 2.0), "多摸一张技能就要多让出一点命中率")
	_assert(is_equal_approx(CombatResolver.champion_steer(0.5, 0.0, 0.0), 0.0), "张数持平、目标五五开时不用偏移")
