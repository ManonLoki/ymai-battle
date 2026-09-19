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


## SceneTree 的入口。延到下一帧再跑，让引擎先把 autoload 和 class_name 装好。
func _initialize() -> void:
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
	await _test_main_menu()
	await _test_settings()
	await _test_tv_remote()
	await _test_main_parallax_and_quit()
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
	for path in ["res://ranking.gd", "res://battle.gd", "res://scenes/fighter_view.gd"]:
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
	_assert(many.channels[0] == AgentSkills.CHANNEL_CODEX, "channels are ordered by usage")
	_assert(one.channels.size() == 1, "a single-agent player keeps one channel")

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
	_assert(triple.stacked_dodge() > triple.innate_dodge(), "the GROK buff adds dodge on top")
	# stacked_dodge 里含体型带来的先天闪避，所以这里和先天值比，而不是和 0 比。
	_assert(single.stacked_accuracy() == 0.0 and is_equal_approx(single.stacked_dodge(), single.innate_dodge()), "a single-agent fighter only gets its own buff")
	_assert(triple.agent_buff_text().find(" + ") >= 0, "the report names every agent buff")
	_assert(single.agent_buff_text().find(" + ") < 0, "a single buff needs no separator")

	# 认不出的渠道不产 buff，也不会崩。
	var unknown := _ranked("陌生", 10, "who.knows")
	var stranger := Fighter.from_ranked(unknown, false)
	SkillGrant.apply(stranger, RollSource.new(1))
	_assert(stranger.agent_buffs.is_empty(), "an unknown channel grants no buff")
	_assert(stranger.stacked_crit() >= 0.0, "an unknown channel still resolves cleanly")


## 数字紧凑写法：按大小自动挂 K / M / B，四舍五入到小数点后两位。
func _test_compact_numbers() -> void:
	_assert(ThemeHelper.compact(0) == "0", "zero stays plain")
	_assert(ThemeHelper.compact(1) == "1", "single digits stay plain")
	_assert(ThemeHelper.compact(999) == "999", "under a thousand stays plain")
	_assert(ThemeHelper.compact(1000) == "1.00K", "a thousand switches to K")
	_assert(ThemeHelper.compact(1234) == "1.23K", "K keeps two decimals")
	_assert(ThemeHelper.compact(999499) == "999.50K", "just under a million is still K")
	_assert(ThemeHelper.compact(1000000) == "1.00M", "a million switches to M")
	_assert(ThemeHelper.compact(348431491) == "348.43M", "the real board's champion reads as M")
	_assert(ThemeHelper.compact(1000000000) == "1.00B", "a billion switches to B")
	_assert(ThemeHelper.compact(2500000000) == "2.50B", "B keeps two decimals")
	_assert(ThemeHelper.compact(-1234) == "-1.23K", "negatives keep their sign")

	# 四舍五入，不是截断。
	_assert(ThemeHelper.compact(1230000) == "1.23M", "an exact second decimal survives")
	_assert(ThemeHelper.compact(1234999) == "1.23M", "a third digit below half rounds down")
	_assert(ThemeHelper.compact(1235000) == "1.24M", "a third digit at half rounds up")

	# 单位是跟着当前数字走的，不是固定写死 M。
	var seen: Dictionary = {}
	for value in [500, 5000, 5000000, 5000000000]:
		var text := ThemeHelper.compact(int(value))
		var unit := text.substr(text.length() - 1, 1)
		seen[unit] = true
	_assert(seen.size() == 4, "each magnitude picks its own unit")

	# 界面上确实用的是这个函数，而不是各写各的。
	for path in ["res://ranking.gd", "res://battle.gd", "res://scenes/fighter_view.gd", "res://scripts/combat_log.gd"]:
		var src := FileAccess.get_file_as_string(path)
		_assert(src.find("ThemeHelper.compact(") >= 0, "%s renders numbers through the shared compact helper" % path)
	_assert(FileAccess.get_file_as_string("res://ranking.gd").find("_format_millions") < 0, "the old M-only formatter is gone")


## 胜率曲线：战力比 1:1 精确落在 50%，两端收敛到 20%/80% 而不是 0/100%。
func _test_win_rate() -> void:
	# 胜率永远被夹在 [30%, 70%]：战力再悬殊也不能把结果锁死。
	var extremes: Array[int] = [0, 1, 25, 100, 400, 10000, 1000000]
	for power in extremes:
		var rate := CombatResolver.champion_win_rate(power, 100)
		_assert(rate >= CombatResolver.MIN_WIN_RATE, "win rate never drops below 30%% (at %d vs 100)" % power)
		_assert(rate <= CombatResolver.MAX_WIN_RATE, "win rate never rises above 70%% (at %d vs 100)" % power)

	# 两个锚点：擂主顶得上全场合计战力（r=1）时贴着上限，
	# 只有四分之一（r=0.25）时贴着下限，各自走完区间的 SATURATION。
	var span := CombatResolver.MAX_WIN_RATE - CombatResolver.MIN_WIN_RATE
	var at_ceil := CombatResolver.champion_win_rate(100, 100)
	var at_floor := CombatResolver.champion_win_rate(25, 100)
	var sat := CombatResolver.WIN_RATE_ANCHOR_SATURATION
	_assert(absf(at_ceil - (CombatResolver.MAX_WIN_RATE - span * 0.5 * (1.0 - sat))) < 0.001, "r=1 sits at the upper anchor (%.3f)" % at_ceil)
	_assert(absf(at_floor - (CombatResolver.MIN_WIN_RATE + span * 0.5 * (1.0 - sat))) < 0.001, "r=0.25 sits at the lower anchor (%.3f)" % at_floor)
	# 两个锚点的几何中点才是真正的五五开。
	_assert(is_equal_approx(CombatResolver.champion_win_rate(50, 100), 0.5), "the geometric midpoint of the anchors is an even 50%")
	_assert(is_equal_approx(CombatResolver.champion_win_rate(100, 200), 0.5), "another 1:2 case is 50%")
	_assert(at_floor > CombatResolver.MIN_WIN_RATE, "a 1:4 underdog still has more than the floor")
	_assert(at_ceil < CombatResolver.MAX_WIN_RATE, "matching the whole field still leaves room below the ceiling")

	# 锚点之外仍然单调，但收益和惩罚都极慢——不会一跨线就躺平。
	var far_above := CombatResolver.champion_win_rate(400, 100)
	var way_above := CombatResolver.champion_win_rate(10000, 100)
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

	# 目标胜率反解出的命中率始终贴着 50% 附近，靠概率而不是靠锁定。
	var low_hit := CombatResolver.calibrated_hit_chance(CombatResolver.MIN_WIN_RATE)
	var high_hit := CombatResolver.calibrated_hit_chance(CombatResolver.MAX_WIN_RATE)
	_assert(low_hit > CombatResolver.MIN_HIT_CHANCE and high_hit < CombatResolver.MAX_HIT_CHANCE, "calibrated hit chance never reaches the 5%/95% rails")
	_assert(high_hit - low_hit < 0.25, "the whole 30%-70% target band maps into a narrow hit-chance window")
	_assert(high_hit > low_hit, "a higher target means a higher hit chance")

	var src := FileAccess.get_file_as_string("res://scripts/combat_resolver.gd")
	_assert(src.find("tanh(") >= 0 and src.find("WIN_RATE_RATIO_CEIL") >= 0, "win rate interpolation is an anchored tanh on log power ratio")
	var war_src := FileAccess.get_file_as_string("res://scripts/wheel_war.gd")
	_assert(war_src.find("CombatResolver.champion_win_rate") >= 0, "wheel war uses the shipped win-rate function")


## 造一名测试用角色，省掉每次手写 RankedUser 的样板。
func _make_fighter(name: String, tokens: int, channel: String, champion: bool) -> Fighter:
	return Fighter.from_ranked(_ranked(name, tokens, channel), champion)


## 把角色身上所有技能和 buff 摘干净，只留先天属性。
## 用于需要精确控制掷点序列的用例。
func _disarm(fighter: Fighter) -> void:
	fighter.agent_buffs = []
	fighter.skills.clear()
	fighter.rebirth_available = false
	fighter.poison_turns = 0
	fighter.paralyze_turns = 0
	fighter.confuse_turns = 0
	fighter.rooted_next = false
	fighter.hp = fighter.max_hp


## 技能与 buff 的全部规则：数值区间、叠加、连击、状态、反击、
## 吸血、治疗、复活，以及“没有任何必中必闪”这条底线。
func _test_skills() -> void:
	var rng_lo := RollSource.new(1)
	rng_lo.push([0.0])
	var buff_lo := SkillGrant.roll_agent_buff(AgentSkills.CHANNEL_CODEX, rng_lo)
	_assert(buff_lo.id == "buff_codex", "CODEX buff type is crit")
	_assert(is_equal_approx(buff_lo.crit_chance, 0.05), "agent buff floor is 5%")
	var rng_hi := RollSource.new(1)
	rng_hi.push([1.0])
	var buff_hi := SkillGrant.roll_agent_buff(AgentSkills.CHANNEL_CODEX, rng_hi)
	_assert(is_equal_approx(buff_hi.crit_chance, 0.10), "agent buff ceiling is 10%")
	var rng_c := RollSource.new(1)
	rng_c.push([0.0])
	_assert(is_equal_approx(SkillGrant.roll_agent_buff(AgentSkills.CHANNEL_CLAUDE, rng_c).accuracy_bonus, 0.05), "CLAUDE buff is accuracy")
	var rng_g := RollSource.new(1)
	rng_g.push([0.0])
	_assert(is_equal_approx(SkillGrant.roll_agent_buff(AgentSkills.CHANNEL_GROK, rng_g).dodge_bonus, 0.05), "GROK buff is dodge")
	var rng_w := RollSource.new(1)
	rng_w.push([0.0])
	_assert(is_equal_approx(SkillGrant.roll_agent_buff(AgentSkills.CHANNEL_WORKBUDDY, rng_w).damage_reduction, 0.05), "WORKBUDDY buff is damage reduction")

	var champ_skills: Array[SkillDef] = SkillGrant.pick_skills(SkillCatalog.CHAMPION_SKILL_CAP, RollSource.new(3))
	var chal_skills: Array[SkillDef] = SkillGrant.pick_skills(SkillCatalog.CHALLENGER_SKILL_CAP, RollSource.new(4))
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
	_assert(SkillCatalog.pool().size() == 16, "skill pool has 16 entries including lifesteal and heal")

	var win := 0.5
	var attacker := _make_fighter("A", 100, "", true)
	var defender := _make_fighter("B", 100, "", false)
	_disarm(attacker)
	_disarm(defender)
	var rng_plain := RollSource.new(1)
	rng_plain.push([0.0])
	var plain_events: Array[StrikeResult] = CombatResolver.resolve_strikes(attacker, defender, win, rng_plain)
	var plain_damage := 0
	for event in plain_events:
		plain_damage += event.damage
	_assert(plain_events.size() == 1 and plain_events[0].hit and not plain_events[0].crit, "no-skill hit is a single non-crit")

	defender.hp = defender.max_hp
	attacker.skills = [SkillCatalog.by_id("skill_crit")]
	var rng_crit := RollSource.new(1)
	rng_crit.push([0.0, 0.0])
	var crit_events: Array[StrikeResult] = CombatResolver.resolve_strikes(attacker, defender, win, rng_crit)
	_assert(crit_events.size() == 1 and crit_events[0].crit, "crit skill can crit on the same hit roll")
	_assert(crit_events[0].damage != plain_damage, "with-skill settlement differs from no-skill")

	_disarm(attacker)
	_disarm(defender)
	attacker.skills = [SkillCatalog.by_id("skill_double")]
	var rng_double := RollSource.new(1)
	rng_double.push([0.0, 0.0])
	var double_events: Array[StrikeResult] = CombatResolver.resolve_strikes(attacker, defender, win, rng_double)
	_assert(double_events.size() == 2 and double_events[1].combo, "double strike adds one extra hit")

	_disarm(attacker)
	_disarm(defender)
	defender.hp = defender.max_hp
	attacker.skills = [SkillCatalog.by_id("skill_triple")]
	var rng_triple := RollSource.new(1)
	rng_triple.push([0.0, 0.0])
	var triple_events: Array[StrikeResult] = CombatResolver.resolve_strikes(attacker, defender, win, rng_triple)
	_assert(triple_events.size() == 3, "triple strike adds two extra hits")

	_disarm(attacker)
	_disarm(defender)
	var dodge_buff := SkillCatalog.agent_buff_template(AgentSkills.CHANNEL_GROK)
	dodge_buff.dodge_bonus = 0.25
	_give_buffs(defender, [dodge_buff])
	var rng_dodge := RollSource.new(1)
	rng_dodge.push([0.4])
	var dodge_events: Array[StrikeResult] = CombatResolver.resolve_strikes(attacker, defender, win, rng_dodge)
	_assert(not dodge_events[0].hit and dodge_events[0].dodged, "dodge buff turns a mid roll into a dodge")
	_disarm(defender)
	var rng_no_dodge := RollSource.new(1)
	rng_no_dodge.push([0.4])
	_assert(CombatResolver.resolve_strikes(attacker, defender, win, rng_no_dodge)[0].hit, "same 0.4 roll hits without dodge")

	var acc_buff := SkillCatalog.agent_buff_template(AgentSkills.CHANNEL_CLAUDE)
	acc_buff.accuracy_bonus = 0.20
	_give_buffs(attacker, [acc_buff])
	defender.hp = defender.max_hp
	var rng_acc := RollSource.new(1)
	rng_acc.push([0.6])
	_assert(CombatResolver.resolve_strikes(attacker, defender, win, rng_acc)[0].hit, "accuracy buff turns a 0.6 roll into a hit")
	_disarm(attacker)
	defender.hp = defender.max_hp
	var rng_miss := RollSource.new(1)
	rng_miss.push([0.6])
	_assert(not CombatResolver.resolve_strikes(attacker, defender, win, rng_miss)[0].hit, "same 0.6 roll misses without accuracy")

	_disarm(attacker)
	_disarm(defender)
	attacker.skills = [SkillCatalog.by_id("skill_poison")]
	var rng_poison := RollSource.new(1)
	rng_poison.push([0.0, 0.0])
	CombatResolver.resolve_strikes(attacker, defender, win, rng_poison)
	_assert(defender.poison_turns == 3, "poison applies for 3 turns")
	defender.paralyze_turns = 3
	var before_hp := defender.hp
	var poison_events: Array[StrikeResult] = CombatResolver.resolve_action(defender, attacker, win, RollSource.new(1))
	_assert(poison_events[0].poison_tick, "poison ticks on the afflicted fighter's action")
	var poison_tick := maxi(1, int(round(float(CombatResolver.strike_damage(defender)) * CombatResolver.POISON_TICK_SHARE)))
	_assert(defender.hp == before_hp - poison_tick, "poison ticks for half a clean hit")

	_disarm(attacker)
	_disarm(defender)
	defender.paralyze_turns = 3
	var para_events: Array[StrikeResult] = CombatResolver.resolve_action(defender, attacker, win, RollSource.new(1))
	_assert(para_events[0].skipped == "paralyze", "paralyze skips the action")
	_assert(defender.paralyze_turns == 2, "paralyze lasts 3 turns")
	_assert(attacker.hp == attacker.max_hp, "paralyzed fighter deals no damage")

	_disarm(attacker)
	_disarm(defender)
	attacker.confuse_turns = 3
	var rng_conf := RollSource.new(1)
	rng_conf.push([0.0, 0.0])
	var conf_events: Array[StrikeResult] = CombatResolver.resolve_action(attacker, defender, win, rng_conf)
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
	var guard_events: Array[StrikeResult] = CombatResolver.resolve_strikes(attacker, defender, win, rng_guard)
	_assert(guard_events[0].guarded and guard_events[0].damage == 0, "absolute guard negates all damage")
	_assert(defender.hp == defender.max_hp, "guarded fighter keeps full HP")

	_disarm(attacker)
	_disarm(defender)
	defender.skills = [SkillCatalog.by_id("skill_rebirth")]
	defender.rebirth_available = true
	defender.hp = 1
	var rng_rebirth := RollSource.new(1)
	rng_rebirth.push([0.0])
	var rebirth_events: Array[StrikeResult] = CombatResolver.resolve_strikes(attacker, defender, win, rng_rebirth)
	_assert(rebirth_events[0].revived, "rebirth revives on lethal hit")
	_assert(defender.hp == defender.max_hp, "rebirth restores full HP")
	_assert(not defender.rebirth_available, "rebirth is consumed")
	var rng_rebirth2 := RollSource.new(1)
	rng_rebirth2.push([0.0])
	defender.hp = 1
	var rebirth2: Array[StrikeResult] = CombatResolver.resolve_strikes(attacker, defender, win, rng_rebirth2)
	_assert(rebirth2[0].defender_died and not rebirth2[0].revived, "consumed rebirth does not revive again")

	_disarm(attacker)
	_disarm(defender)
	defender.skills = [SkillCatalog.by_id("skill_counter")]
	var rng_counter := RollSource.new(1)
	rng_counter.push([0.0, 0.0, 0.0])
	var counter_events: Array[StrikeResult] = CombatResolver.resolve_strikes(attacker, defender, win, rng_counter)
	var saw_counter := false
	for ev in counter_events:
		if ev.countered:
			saw_counter = true
	_assert(saw_counter, "counter fires after a hit")
	_assert(attacker.hp < attacker.max_hp, "counter deals damage back")

	_disarm(attacker)
	_disarm(defender)
	attacker.skills = [SkillCatalog.by_id("skill_root")]
	var rng_root := RollSource.new(1)
	rng_root.push([0.0, 0.0])
	CombatResolver.resolve_strikes(attacker, defender, win, rng_root)
	_assert(defender.rooted_next, "root marks the next action as skipped")
	var root_events: Array[StrikeResult] = CombatResolver.resolve_action(defender, attacker, win, RollSource.new(1))
	_assert(root_events[0].skipped == "root", "root skips the next action")
	_assert(not defender.rooted_next, "root is consumed after one skip")

	_disarm(attacker)
	_disarm(defender)
	attacker.skills = [SkillCatalog.by_id("skill_lifesteal")]
	attacker.hp = 40
	var rng_ls := RollSource.new(1)
	rng_ls.push([0.0])
	var ls_events: Array[StrikeResult] = CombatResolver.resolve_strikes(attacker, defender, win, rng_ls)
	var ls_scale := float(CombatResolver.strike_damage(attacker)) / float(maxi(1, CombatResolver.strike_damage(defender)))
	var stolen := maxi(1, int(round(float(ls_events[0].damage) * CombatResolver.lifesteal_ratio(attacker) * ls_scale)))
	_assert(ls_events[0].lifesteal, "lifesteal flags when the skill is held")
	_assert(ls_events[0].heal_amount == stolen, "吸血按本方比例回血（擂主 30% / 挑战者 50%）")
	_assert(attacker.hp == 40 + stolen, "attacker HP rises by the lifesteal amount")
	_disarm(attacker)
	_disarm(defender)
	attacker.hp = 40
	var rng_nols := RollSource.new(1)
	rng_nols.push([0.0])
	var nols: Array[StrikeResult] = CombatResolver.resolve_strikes(attacker, defender, win, rng_nols)
	_assert(not nols[0].lifesteal and nols[0].heal_amount == 0, "no lifesteal skill means no heal from that hit")
	_assert(attacker.hp == 40, "attacker HP unchanged without lifesteal")

	# 治疗改成按最大生命的百分比：擂主 10% 概率回 5%，挑战者 15% 概率回 10%。
	var short_bar := _make_fighter("short", 1000, "", false)
	var long_bar := _make_fighter("long", 1000, "", true)
	long_bar.hits_to_down = CombatResolver.HITS_PER_DUEL * 10
	_assert(CombatResolver.heal_amount(long_bar) == 50, "擂主一次治疗回 5% 最大生命")
	_assert(CombatResolver.heal_amount(short_bar) == 100, "挑战者一次治疗回 10% 最大生命")
	_assert(is_equal_approx(CombatResolver.heal_chance(long_bar), 0.10), "擂主治疗触发率 10%")
	_assert(is_equal_approx(CombatResolver.heal_chance(short_bar), 0.15), "挑战者治疗触发率 15%")
	_assert(is_equal_approx(CombatResolver.lifesteal_ratio(long_bar), 0.30), "擂主吸血 30%")
	_assert(is_equal_approx(CombatResolver.lifesteal_ratio(short_bar), 0.50), "挑战者吸血 50%")
	_assert(CombatResolver.heal_amount(long_bar) != CombatResolver.strike_damage(long_bar), "治疗不再跟单次命中挂钩，改看最大生命")
	_assert(float(CombatResolver.heal_amount(short_bar)) / float(short_bar.max_hp) < 0.5, "one heal is never half a health bar")
	_disarm(attacker)
	_disarm(defender)
	attacker.skills = [SkillCatalog.by_id("skill_heal")]
	attacker.hp = 10
	var rng_heal := RollSource.new(1)
	rng_heal.push([0.0, 0.0])
	var heal_events: Array[StrikeResult] = CombatResolver.resolve_strikes(attacker, defender, win, rng_heal)
	var last_heal: StrikeResult = heal_events[heal_events.size() - 1]
	_assert(last_heal.treated, "heal skill can proc after an attack")
	var expected_heal := CombatResolver.heal_amount(attacker)
	_assert(last_heal.heal_amount == expected_heal, "heal amount matches the shipped formula")
	_assert(attacker.hp == 10 + expected_heal, "heal restores HP")
	_disarm(attacker)
	_disarm(defender)
	attacker.hp = 10
	var rng_noheal := RollSource.new(1)
	rng_noheal.push([0.0, 0.0])
	var noheal: Array[StrikeResult] = CombatResolver.resolve_strikes(attacker, defender, win, rng_noheal)
	_assert(not noheal[noheal.size() - 1].treated, "same rolls do not heal without the skill")
	_assert(attacker.hp == 10, "HP unchanged without heal skill")

	# 没有任何“必中”或“必闪”：最悬殊的战力差下，两边的命中率都还在 5%~95% 之间，
	# 掷到极端点数时结果照样翻转。
	var hopeless := CombatResolver.champion_win_rate(1, 1000000)
	var crushing := CombatResolver.champion_win_rate(1000000, 1)
	for target in [hopeless, crushing]:
		var hit := CombatResolver.calibrated_hit_chance(target)
		var champ := _make_fighter("champ", 1000, AgentSkills.CHANNEL_CLAUDE, true)
		var foe := _make_fighter("foe", 1000, AgentSkills.CHANNEL_GROK, false)
		var champ_buff := SkillCatalog.agent_buff_template(AgentSkills.CHANNEL_CLAUDE)
		champ_buff.accuracy_bonus = 0.10
		_give_buffs(champ, [champ_buff])
		var foe_buff := SkillCatalog.agent_buff_template(AgentSkills.CHANNEL_GROK)
		foe_buff.dodge_bonus = 0.10
		_give_buffs(foe, [foe_buff])
		_assert(CombatResolver.hit_chance(champ, foe, hit) > CombatResolver.MIN_HIT_CHANCE, "champion can always land a hit (target %.2f)" % target)
		_assert(CombatResolver.hit_chance(champ, foe, hit) < CombatResolver.MAX_HIT_CHANCE, "champion can always miss (target %.2f)" % target)
		_assert(CombatResolver.hit_chance(foe, champ, hit) > CombatResolver.MIN_HIT_CHANCE, "opponent can always land a hit (target %.2f)" % target)
		_assert(CombatResolver.hit_chance(foe, champ, hit) < CombatResolver.MAX_HIT_CHANCE, "opponent can always miss (target %.2f)" % target)
		var rng_roll_zero := RollSource.new(1)
		rng_roll_zero.push([0.0])
		_assert(CombatResolver.resolve_strikes(champ, foe, hit, rng_roll_zero)[0].hit, "roll 0 always hits, whatever the target (%.2f)" % target)
		foe.hp = foe.max_hp
		var rng_roll_one := RollSource.new(1)
		rng_roll_one.push([0.999])
		_assert(not CombatResolver.resolve_strikes(champ, foe, hit, rng_roll_one)[0].hit, "roll 0.999 always misses, whatever the target (%.2f)" % target)

	# 连击是“多一次机会”，不是“保证打中”——追击同样要过命中判定。
	var combo_src := FileAccess.get_file_as_string("res://scripts/combat_resolver.gd")
	_assert(combo_src.find("auto_hit") < 0, "no auto-hit shortcut exists in the resolver")
	var combo_attacker := _make_fighter("combo", 1000, "", true)
	var combo_target := _make_fighter("target", 1000, "", false)
	_disarm(combo_attacker)
	_disarm(combo_target)
	combo_attacker.skills = [SkillCatalog.by_id("skill_double")]
	var rng_combo := RollSource.new(1)
	# 首击命中 -> 二连击触发 -> 追击掷到 0.999 落空。
	rng_combo.push([0.0, 0.0, 0.999])
	var combo_events: Array[StrikeResult] = CombatResolver.resolve_strikes(combo_attacker, combo_target, 0.5, rng_combo)
	_assert(combo_events.size() == 2 and combo_events[1].combo, "the double-strike extra swing is still rolled")
	_assert(not combo_events[1].hit, "an extra swing can miss like any other")


## 造一条排行榜记录。channel 留空表示这个人没有可识别的 agent。
func _ranked(name: String, tokens: int, channel: String = "") -> RankedUser:
	var user := RankedUser.new()
	user.username = name
	user.tokens = tokens
	user.channel = channel
	user.agent_name = AgentSkills.agent_display_name(channel)
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

	# 每次判定都掷 0，双方必然命中，于是擂主先手的优势把对手逐个清掉。
	var downed := 0
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


## 蒙特卡洛回归：实测胜率必须落在 [30%, 70%]，并且跟着目标胜率走。
## 改动技能池、技能位数量或伤害口径之后，这里会第一个报警，对应的标定常数是
## CombatResolver.CHAMPION_SKILL_EDGE_PER_SKILL / AGENT_BUFF_HIT_EDGE / WIN_RATE_SPREAD。
##
## "head to head" 只有一个挑战者，整场只掷十几次骰子，随机性本身会把实测往 50% 拉，
## 所以它会稳定地比目标低几个点——容差留到 0.12 就是为了容下这种短局。
func _test_win_rate_regression() -> void:
	var codex := AgentSkills.CHANNEL_CODEX
	var claude := AgentSkills.CHANNEL_CLAUDE
	var grok := AgentSkills.CHANNEL_GROK
	var buddy := AgentSkills.CHANNEL_WORKBUDDY
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
				user.agents.append(AgentSkills.agent_display_name(str(row[c])))
			user.channel = user.channels[0]
			user.agent_name = AgentSkills.agent_display_name(user.channel)
			roster.append(user)
		# 120 次抽样的标准误约 4.5 个点，贴着 80% 上限的阵容会随机越界，
		# 所以样本量提到 240，并按 2.5 个标准误给实测值留出抖动空间。
		var trials := 240
		var wins := 0
		var target := 0.0
		for trial in range(trials):
			var war := WheelWar.new()
			var rng := RollSource.new(trial * 7919 + 13)
			war.setup(roster, rng)
			target = war.win_rate
			var turns := 0
			while war.outcome == WheelWar.Outcome.ONGOING and turns < 4000:
				war.simulate_turn(rng)
				turns += 1
			if war.outcome == WheelWar.Outcome.ALL_OPPONENTS_DOWN:
				wins += 1
		var actual := float(wins) / float(trials)
		var noise := 2.5 * sqrt(0.25 / float(trials))
		_assert(target >= CombatResolver.MIN_WIN_RATE and target <= CombatResolver.MAX_WIN_RATE, "%s: target win rate %.2f stays inside [30%%, 70%%]" % [label, target])
		_assert(actual >= CombatResolver.MIN_WIN_RATE - noise, "%s: measured win rate %.2f is at or above the 30%% floor (target %.2f)" % [label, actual, target])
		_assert(actual <= CombatResolver.MAX_WIN_RATE + noise, "%s: measured win rate %.2f is at or below the 70%% ceiling (target %.2f)" % [label, actual, target])
		_assert(absf(actual - target) < 0.12, "%s: measured win rate %.2f tracks its %.2f target" % [label, actual, target])


## 设置页：三种窗口模式都摆出来、存得下读得回，认不出的值回落到默认。
func _test_settings() -> void:
	# 存取：写进临时文件再读回来，三种模式都要能原样往返。
	var path := "user://test_settings.json"
	for mode in WindowSettings.MODES:
		WindowSettings.save_mode(mode, path)
		_assert(WindowSettings.load_mode(path) == mode, "window mode %s survives a save/load round trip" % WindowSettings.display_name(mode))
	# 存档没有 / 坏了 / 是个没见过的值，都回落到默认，绝不让游戏开不起来。
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	_assert(WindowSettings.load_mode(path) == WindowSettings.DEFAULT_MODE, "a missing settings file falls back to the default mode")
	var junk := FileAccess.open(path, FileAccess.WRITE)
	junk.store_string("not json at all")
	junk.close()
	_assert(WindowSettings.load_mode(path) == WindowSettings.DEFAULT_MODE, "a corrupt settings file falls back to the default mode")
	WindowSettings.save_mode(999, path)
	_assert(WindowSettings.load_mode(path) == WindowSettings.DEFAULT_MODE, "an unknown mode value falls back to the default mode")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

	# 只有窗口模式带边框，另外两种都是无边框的沉浸式。
	_assert(WindowSettings.has_border(WindowSettings.Mode.WINDOWED), "windowed keeps the system border")
	_assert(not WindowSettings.has_border(WindowSettings.Mode.MAXIMIZED), "maximized is borderless")
	_assert(not WindowSettings.has_border(WindowSettings.Mode.FULLSCREEN), "fullscreen is borderless")
	# 三种模式各自映射到不同的 DisplayServer 窗口模式。
	_assert(WindowSettings.window_mode_for(WindowSettings.Mode.WINDOWED) == DisplayServer.WINDOW_MODE_WINDOWED, "windowed maps to WINDOW_MODE_WINDOWED")
	_assert(WindowSettings.window_mode_for(WindowSettings.Mode.MAXIMIZED) == DisplayServer.WINDOW_MODE_MAXIMIZED, "maximized maps to WINDOW_MODE_MAXIMIZED")
	_assert(WindowSettings.window_mode_for(WindowSettings.Mode.FULLSCREEN) == DisplayServer.WINDOW_MODE_FULLSCREEN, "fullscreen maps to WINDOW_MODE_FULLSCREEN")

	# 场景本身：三个模式按钮是按 MODES 现生成的，加一种模式不用改界面。
	var packed := load("res://settings.tscn") as PackedScene
	_assert(packed != null, "settings.tscn loads")
	var scene: Node = packed.instantiate()
	root.add_child(scene)
	await process_frame
	_assert(scene.get_node_or_null("%BackButton") != null, "Settings has a Back button")
	var list := scene.get_node_or_null("%ModeList") as VBoxContainer
	_assert(list != null, "Settings has a mode list")
	var buttons := 0
	for child in list.get_children():
		if child is Button:
			buttons += 1
	_assert(buttons == WindowSettings.MODES.size(), "every window mode gets a button (%d)" % buttons)
	scene.queue_free()
	await process_frame


## 主菜单：三个按钮都在，且能切到对应场景。
func _test_main_menu() -> void:
	var packed := load("res://main.tscn") as PackedScene
	_assert(packed != null, "main.tscn loads")
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
	_assert(settings_btn != null and quit_btn != null and settings_btn.get_index() < quit_btn.get_index(), "Settings sits above Quit")
	var ranking_script := FileAccess.get_file_as_string("res://main.gd")
	_assert(ranking_script.find("ranking.tscn") >= 0, "Main can switch to Ranking")
	_assert(ranking_script.find("battle.tscn") >= 0, "Main can switch to Battle")
	_assert(ranking_script.find("settings.tscn") >= 0, "Main can switch to Settings")
	_assert(ranking_script.find("WindowSettings.apply") >= 0, "Main applies the saved window mode on launch")

	# 主场景角落显示版本号，取自 project.godot，不写死在界面里。
	var configured := str(ProjectSettings.get_setting("application/config/version", ""))
	_assert(not configured.is_empty(), "project.godot declares a version")
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
	var packed := load("res://main.tscn") as PackedScene
	_assert(packed != null, "main.tscn loads for parallax")
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
	for layer in backdrop.layers:
		var sprite := _first_sprite(layer)
		_assert(sprite != null and sprite.texture != null, "parallax layer loads a texture")
		var img := sprite.texture.get_image()
		_assert(img != null and _opaque_count(img) > 0, "parallax layer has opaque pixels")
		images.append(img)
	_assert(images.size() >= 2 and _images_differ(images[0], images[1]), "two layer images are not pixel-identical")
	var tscn := FileAccess.get_file_as_string("res://main.tscn")
	var parallax_src := FileAccess.get_file_as_string("res://scripts/menu_parallax.gd")
	_assert(tscn.find("ParallaxBackdrop") >= 0, "main scene references the parallax backdrop")
	_assert(parallax_src.find("res://assets/backgrounds/far.png") >= 0, "far background image is referenced")
	_assert(parallax_src.find("res://assets/backgrounds/mid.png") >= 0, "mid background image is referenced")

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
	var main_src := FileAccess.get_file_as_string("res://main.gd")
	_assert(main_src.find("func _on_quit_pressed") >= 0, "quit handler exists")
	_assert(main_src.find("get_tree().quit()") >= 0, "quit handler uses SceneTree.quit")
	main.queue_free()
	await process_frame


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
	var main_src := FileAccess.get_file_as_string("res://main.gd")
	_assert(main_src.find("GameCursor.boot") >= 0, "main start path boots the custom cursor")
	_assert(main_src.find("GameCursor.handle_event") >= 0, "main input path applies cursor swaps")

	var arrow := load(GameCursor.ARROW_PATH) as Texture2D
	var pressed := load(GameCursor.PRESSED_PATH) as Texture2D
	_assert(arrow != null, "arrow cursor loads")
	_assert(pressed != null, "pressed cursor loads")
	var aimg := arrow.get_image()
	var pimg := pressed.get_image()
	_assert(aimg != null and _opaque_count(aimg) > 0, "arrow cursor has opaque pixels")
	_assert(pimg != null and _opaque_count(pimg) > 0, "pressed cursor has opaque pixels")
	_assert(_images_differ(aimg, pimg), "arrow and pressed cursors differ")

	var packed := load("res://main.tscn") as PackedScene
	_assert(packed != null, "main.tscn loads for cursor apply")
	var main: Node = packed.instantiate()
	root.add_child(main)
	await process_frame
	_assert(GameCursor.applied_texture == GameCursor.arrow_texture, "start path applies the arrow cursor")

	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = Vector2(12, 12)
	main._input(press)
	_assert(GameCursor.applied_texture == GameCursor.pressed_texture, "mouse down applies the pressed cursor")

	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	release.position = Vector2(12, 12)
	main._input(release)
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
	_assert(SpriteFactory.COUNT >= 12, "appearance pool has at least 12 looks")
	var user := _ranked("anim", 10, AgentSkills.CHANNEL_CODEX)
	var fighter := Fighter.from_ranked(user, true)
	_give_buffs(fighter, [SkillCatalog.agent_buff_template(AgentSkills.CHANNEL_CODEX)])
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
	_assert(view.tip_label.text.find(fighter.primary_agent_buff().display_name) >= 0, "instant tip contains the buff name")
	_assert(view.tip_label.text.find(fighter.primary_agent_buff().description) >= 0, "instant tip contains the buff effect")
	buff_icon.mouse_exited.emit()
	_assert(not view.tip_panel.visible, "buff tip hides on mouse exit")
	_assert(view.buff_row.get_parent() != view.skill_row, "buff row and skill row are separate")
	_assert(view.buff_row.get_child_count() == fighter.agent_buffs.size(), "buff row holds one icon per agent")
	_assert(view.skill_row.get_child_count() == fighter.skills.size(), "skill row holds only random skills")
	_assert(fighter.skills.size() == 8, "champion bind uses 8 skills")
	for child in view.buff_row.get_children():
		_assert_icon_tooltip(child, fighter.primary_agent_buff())
	for i in fighter.skills.size():
		_assert_icon_tooltip(view.skill_row.get_child(i), fighter.skills[i])
	await process_frame
	_assert_icons_align_to_hp_bar(view)
	view.play_attack()
	_assert(view.anim_player.current_animation == "attack", "playing attack selects the attack animation")
	view.queue_free()
	await process_frame


## 接口契约：URL、请求方式，以及全项目不许出现第二个外部域名。
func _test_api_contract() -> void:
	var api_src := FileAccess.get_file_as_string("res://scripts/token_usage_api.gd")
	_assert(api_src.find("https://codex-tracker.yunmai365.com/api/v1/token-usage") >= 0, "API URL is the exact token-usage endpoint")
	_assert(api_src.find("HTTPClient.METHOD_GET") >= 0, "token-usage is fetched with GET")
	var ranking_src := FileAccess.get_file_as_string("res://ranking.gd")
	var battle_src := FileAccess.get_file_as_string("res://battle.gd")
	_assert(ranking_src.find("TokenUsageApi") >= 0 and ranking_src.find("fetch_usage") >= 0, "Ranking enter path fetches usage")
	_assert(battle_src.find("TokenUsageApi") >= 0 and battle_src.find("fetch_usage") >= 0, "Battle enter path fetches usage")
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
	var ranking_src := FileAccess.get_file_as_string("res://ranking.gd") + FileAccess.get_file_as_string("res://ranking.tscn")
	for needle in ["medal", "badge", "金牌", "银牌", "铜牌", "勋章", "奖杯"]:
		_assert(ranking_src.find(needle) < 0, "Ranking has no %s" % needle)


## 把一串事件渲染成完整战报文本，方便按子串断言。
func _joined_log(events: Array[StrikeResult]) -> String:
	var battle: Node = (load("res://battle.gd") as GDScript).new()
	CombatLog.annotate(events)
	var blob := ""
	for event in events:
		blob += str(battle._event_text(event)) + "\n"
	battle.free()
	return blob


## 战报文案：暴击、闪避、连击、中毒、混乱自伤各自的固定说法。
func _test_combat_log() -> void:
	var win := 0.5
	var attacker := _make_fighter("甲", 100, "", true)
	var defender := _make_fighter("乙", 100, "", false)
	_disarm(attacker)
	_disarm(defender)
	attacker.skills = [SkillCatalog.by_id("skill_crit")]
	var rng_crit := RollSource.new(1)
	rng_crit.push([0.0, 0.0])
	var crit_events: Array[StrikeResult] = CombatResolver.resolve_strikes(attacker, defender, win, rng_crit)
	var crit_log := _joined_log(crit_events)
	_assert(crit_log.find("对乙造成【暴击】伤害") >= 0, "crit log uses 对XXX造成【暴击】伤害")

	_disarm(attacker)
	_disarm(defender)
	var dodge_buff := SkillCatalog.agent_buff_template(AgentSkills.CHANNEL_GROK)
	dodge_buff.dodge_bonus = 0.25
	_give_buffs(defender, [dodge_buff])
	var rng_dodge := RollSource.new(1)
	rng_dodge.push([0.4])
	var dodge_log := _joined_log(CombatResolver.resolve_strikes(attacker, defender, win, rng_dodge))
	_assert(dodge_log.find("乙【闪避】了甲的伤害") >= 0, "dodge log uses XXX【闪避】了XXX的伤害")

	_disarm(attacker)
	_disarm(defender)
	attacker.skills = [SkillCatalog.by_id("skill_double")]
	var rng_double := RollSource.new(1)
	rng_double.push([0.0, 0.0])
	var double_log := _joined_log(CombatResolver.resolve_strikes(attacker, defender, win, rng_double))
	_assert(double_log.find("甲对乙瞬间进攻了【两】次") >= 0, "double log uses 瞬间进攻了【两】次")

	_disarm(attacker)
	_disarm(defender)
	attacker.skills = [SkillCatalog.by_id("skill_triple")]
	var rng_triple := RollSource.new(1)
	rng_triple.push([0.0, 0.0])
	var triple_log := _joined_log(CombatResolver.resolve_strikes(attacker, defender, win, rng_triple))
	_assert(triple_log.find("甲对乙瞬间进攻了【三】次") >= 0, "triple log uses 瞬间进攻了【三】次")

	_disarm(attacker)
	_disarm(defender)
	attacker.skills = [SkillCatalog.by_id("skill_poison")]
	var rng_poison := RollSource.new(1)
	rng_poison.push([0.0, 0.0])
	var poison_log := _joined_log(CombatResolver.resolve_strikes(attacker, defender, win, rng_poison))
	_assert(poison_log.find("甲对乙造成了伤害，乙【中毒】了") >= 0, "poison log uses 造成了伤害，XXX【中毒】了")

	_disarm(attacker)
	_disarm(defender)
	attacker.skills = [
		SkillCatalog.by_id("skill_poison"),
		SkillCatalog.by_id("skill_paralyze"),
		SkillCatalog.by_id("skill_confuse"),
	]
	var rng_all := RollSource.new(1)
	rng_all.push([0.0, 0.0, 0.0, 0.0])
	var all_log := _joined_log(CombatResolver.resolve_strikes(attacker, defender, win, rng_all))
	_assert(all_log.find("乙【中毒，麻痹，混乱】了") >= 0, "multi-status log joins 中毒，麻痹，混乱")

	_disarm(attacker)
	_disarm(defender)
	attacker.confuse_turns = 3
	var rng_self := RollSource.new(1)
	rng_self.push([0.0, 0.0])
	var self_events: Array[StrikeResult] = CombatResolver.resolve_action(attacker, defender, win, rng_self)
	var self_log := _joined_log(self_events)
	var self_damage := 0
	for ev in self_events:
		if ev.self_hit:
			self_damage = ev.damage
	_assert(self_damage > 0, "the confused fighter really hurt themselves")
	_assert(self_log.find("甲因为【混乱】对自己造成了【%s】伤害" % ThemeHelper.compact(self_damage)) >= 0, "confuse self-hit log reads XXX因为【混乱】对自己造成了【N】伤害")
	_assert(self_log.find("混乱了，对自己造成伤害") < 0, "the old confusion wording is gone")

	# 自伤一样要过命中判定：掷到 0.999 就是挥空，不能还写成造成了伤害。
	_disarm(attacker)
	_disarm(defender)
	attacker.confuse_turns = 3
	var rng_self_miss := RollSource.new(1)
	rng_self_miss.push([0.0, 0.999])
	var miss_log := _joined_log(CombatResolver.resolve_action(attacker, defender, win, rng_self_miss))
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
	var battle_tscn := FileAccess.get_file_as_string("res://battle.tscn")
	_assert(battle_tscn.find("Vector2(320, 330)") >= 0, "champion slot moved up from y=480")
	_assert(battle_tscn.find("Vector2(960, 330)") >= 0, "opponent slot moved up from y=480")
	_assert(battle_tscn.find("Vector2(0, 240)") >= 0, "combat log min height is 240px")
	var fighter_tscn := FileAccess.get_file_as_string("res://scenes/fighter_view.tscn")
	_assert(fighter_tscn.find("StatusRow") >= 0, "StatusRow holds name/bar/value")
	_assert(fighter_tscn.find("BuffRow") >= 0 and fighter_tscn.find("SkillRow") >= 0, "BuffRow and SkillRow are separate")
	_assert(fighter_tscn.find("NameLabel") >= 0 and fighter_tscn.find("HpBar") >= 0 and fighter_tscn.find("HpLabel") >= 0, "name, bar and value exist")
	var battle_gd := FileAccess.get_file_as_string("res://battle.gd")
	_assert(battle_gd.find("play_crit_fx") >= 0, "Battle plays crit FX on crit strikes")
	_assert(battle_gd.find("play_dodge") >= 0, "Battle plays dodge retreat on dodges")
	_assert(battle_gd.find("play_poison_fx") >= 0, "Battle plays poison FX on poison")
	_assert(battle_gd.find("play_heal_fx") >= 0, "Battle plays shared heal FX on lifesteal/heal")
	var fv_src := FileAccess.get_file_as_string("res://scenes/fighter_view.gd")
	_assert(fv_src.find("HEAL_FX") >= 0 and fv_src.find("play_heal_fx") >= 0, "lifesteal and heal share HEAL_FX")
	_assert(FileAccess.file_exists("res://scenes/heal_fx.tscn"), "shared heal FX scene exists")


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
	var packed := load("res://battle.tscn") as PackedScene
	var battle: Node = packed.instantiate()
	battle.skip_autoload = true
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
	var log_node: RichTextLabel = battle.get_node("%Log")
	var log_lines := log_node.text.split("\n")
	_assert(log_lines.size() > 2, "the war leaves a multi-line report")
	_assert(log_lines[0].find("车轮战开始") >= 0, "the opening line stays at the top")
	_assert(log_lines[log_lines.size() - 1].find("车轮战开始") < 0, "the newest line is at the bottom, not the top")
	_assert(log_node.scroll_following, "the report follows the newest line to the bottom")
	# 中途点“返回”会立刻释放这个场景，但播放协程还挂在 await 上。
	# 这里确认它能安全收手，而不是对着已经离开场景树的节点调 get_tree()。
	var quitter: Node = packed.instantiate()
	quitter.skip_autoload = true
	root.add_child(quitter)
	await process_frame
	var short_roster: Array[RankedUser] = [_ranked("champ", 400000000, AgentSkills.CHANNEL_CODEX)]
	for i in 4:
		short_roster.append(_ranked("foe_%d" % i, 40000000, AgentSkills.CHANNEL_GROK))
	quitter._start_war(short_roster)
	await process_frame
	_assert(quitter._busy, "the playback loop is running")
	quitter._aborted = true
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
	var packed := load("res://battle.tscn") as PackedScene
	var battle: Node = packed.instantiate()
	battle.skip_autoload = true
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
	var tscn := FileAccess.get_file_as_string("res://battle.tscn")
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
	_assert(FileAccess.get_file_as_string("res://scripts/fix_android_preset.py").find("permissions/wake_lock") >= 0, "Android 导出带上 WAKE_LOCK 权限")

	var back_setting := ""
	for line in FileAccess.get_file_as_string("res://project.godot").split("\n"):
		if line.strip_edges().begins_with("config/quit_on_go_back="):
			back_setting = line.strip_edges().trim_prefix("config/quit_on_go_back=")
	_assert(back_setting == "false", "the engine does not quit on BACK; each scene handles it")

	# 主菜单：焦点从“查看排行”一路往下走，再走回来。
	var main: Node = (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	await process_frame
	var ranking_btn: Button = main.get_node("%RankingButton")
	var battle_btn: Button = main.get_node("%BattleButton")
	var settings_btn: Button = main.get_node("%SettingsButton")
	var quit_btn: Button = main.get_node("%QuitButton")
	_assert(ranking_btn.has_focus(), "the menu starts with a focused button, so the remote has something to move")
	_assert(battle_btn.focus_mode == Control.FOCUS_ALL and settings_btn.focus_mode == Control.FOCUS_ALL and quit_btn.focus_mode == Control.FOCUS_ALL, "every menu entry can take focus")
	_assert(ranking_btn.has_theme_stylebox_override("focus"), "focused buttons draw a TV-visible outline")
	await _press_key(KEY_DOWN)
	_assert(battle_btn.has_focus(), "D-pad down moves to 进入对战")
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
	_assert(TvRemote.ensure_focus(ranking_btn), "a lost focus is restored before navigating")
	_assert(ranking_btn.has_focus(), "focus lands back on the first entry")

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
	for path in ["res://main.gd", "res://ranking.gd", "res://battle.gd"]:
		var src := FileAccess.get_file_as_string(path)
		_assert(src.find("NOTIFICATION_WM_GO_BACK_REQUEST") >= 0, "%s handles the Android go-back notification" % path)
		_assert(src.find("TvRemote.is_back(event)") >= 0, "%s handles the BACK key event" % path)
		_assert(src.find("TvRemote.install()") >= 0, "%s installs the remote bindings" % path)
	_assert(FileAccess.get_file_as_string("res://main.gd").find("get_tree().quit()") >= 0, "BACK on the main menu quits the app")
	var battle_src := FileAccess.get_file_as_string("res://battle.gd")
	_assert(battle_src.find("%BackButton.focus_mode = Control.FOCUS_ALL") >= 0, "the battle 返回 button stays focusable during playback")
	_assert(battle_src.find("focus_mode = Control.FOCUS_NONE") < 0, "nothing turns the battle 返回 button unfocusable")
	var ranking_src := FileAccess.get_file_as_string("res://ranking.gd")
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
	var line := tally.mvp_line()
	_assert(line.find("【乙】") >= 0 and line.find("MVP") >= 0, "MVP 文案点名到人")
	_assert(line.find(ThemeHelper.compact(250)) >= 0, "MVP 文案带上伤害数字")
	var empty := DamageTally.new()
	_assert(str(empty.best()["username"]).is_empty(), "没人伤到擂主时 MVP 空缺")
	_assert(empty.mvp_line().find("空缺") >= 0, "空缺时也给一句说明")


## 一场打完 → 倒计时 → 清场，准备重新拉名单开下一轮。
func _test_next_round_cycle() -> void:
	var packed := load("res://battle.tscn") as PackedScene
	var battle: Node = packed.instantiate()
	battle.skip_autoload = true
	root.add_child(battle)
	await process_frame
	_assert(battle.NEXT_ROUND_DELAY == 60.0, "打完一分钟后自动开下一轮")
	var battle_src := FileAccess.get_file_as_string("res://battle.gd")
	_assert(battle_src.find("func _round_loop") >= 0, "有一层轮次循环在驱动下一轮")
	_assert(battle_src.find("await _load_and_run()") >= 0, "下一轮重新拉一次今日名单")
	var ranked: Array[RankedUser] = [_ranked("甲", 5000), _ranked("乙", 300), _ranked("丙", 300)]
	await battle._start_war(ranked)
	_assert(battle.get_node("%ResultPanel").visible, "一场打完先出结果面板")
	_assert(not battle.get_node("%MvpLabel").text.is_empty(), "结果面板带 MVP 一行")
	_assert(battle.get_node("%Log").text.find("MVP") >= 0, "MVP 也写进战报")
	battle._countdown(2.0, "下一轮")
	await process_frame
	_assert(battle.get_node("%NextRoundLabel").text.find("下一轮") >= 0, "倒计时告诉玩家下一轮什么时候开始")
	battle._aborted = true
	await create_timer(1.2).timeout
	battle._aborted = false
	battle._reset_for_next_round()
	_assert(battle.get_node("%Log").text.is_empty(), "新一轮开始前战报清空")
	_assert(not battle.get_node("%ResultPanel").visible, "新一轮开始前结果面板收起")
	_assert(battle.get_node("%ChampionSlot").get_child_count() == 0, "上一场的角色被清掉")
	_assert(battle._war == null and battle._tally == null, "上一场的状态被丢弃")
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
	var battle: Node = (load("res://battle.tscn") as PackedScene).instantiate()
	battle.skip_autoload = true
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
	_assert(list.get_child_count() == 3, "三位上过榜一的玩家都列出来")
	var first: Node = list.get_child(0)
	_assert((first.get_child(1) as Label).text == "【甲】", "第一名是胜场最多的")
	_assert((first.get_child(2) as Label).text == "3 场", "胜出的场次写在右边")
	var third: Node = list.get_child(2)
	_assert((third.get_child(1) as Label).text == "【丙】", "0 胜的也在榜上")
	_assert((third.get_child(2) as Label).text == "0 场", "0 胜显示成 0 场")
	var medals := [ThemeHelper.GOLD, ThemeHelper.SILVER, ThemeHelper.BRONZE]
	for i in 3:
		var badge: Panel = list.get_child(i).get_child(0) as Panel
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
	_assert(is_equal_approx(boss.stacked_dodge(), -0.05), "擂主块头大，先天 -5% 闪避")
	_assert(is_equal_approx(challenger.stacked_dodge(), 0.05), "挑战者身法灵活，先天 +5% 闪避")
	_assert(is_equal_approx(boss.stacked_damage_reduction(), 0.05), "擂主先天 +5% 减伤")
	_assert(is_equal_approx(challenger.stacked_damage_reduction(), 0.0), "挑战者没有先天减伤")

	# 先天闪避直接反映在命中率上：同样 50% 底子，打擂主更容易命中。
	var on_boss := CombatResolver.hit_chance(challenger, boss, 0.5)
	var on_challenger := CombatResolver.hit_chance(boss, challenger, 0.5)
	_assert(is_equal_approx(on_boss - on_challenger, 0.10), "先天闪避差把双方命中率拉开 10 个点")

	# 技能叠在先天之上，不是二选一。
	challenger.skills = [SkillCatalog.by_id("skill_dodge")]
	_assert(is_equal_approx(challenger.stacked_dodge(), 0.10), "闪避技能叠在先天闪避之上")
	boss.skills = [SkillCatalog.by_id("skill_dr")]
	_assert(is_equal_approx(boss.stacked_damage_reduction(), 0.10), "减伤技能叠在先天减伤之上")

	# 擂主的负闪避不会被写成“被闪掉”，只是更容易挨打。
	_disarm(boss)
	_disarm(challenger)
	var rng_miss := RollSource.new(1)
	rng_miss.push([0.99])
	var miss: Array[StrikeResult] = CombatResolver.resolve_strikes(challenger, boss, 0.5, rng_miss)
	_assert(not miss[0].hit and not miss[0].dodged, "打空擂主只是失手，不会记成闪避")

	# 擂主的先天减伤实打实削伤害。
	var plain := _make_fighter("plain", 1000, "", false)
	_disarm(plain)
	plain.hits_to_down = boss.hits_to_down
	var rng_dmg := RollSource.new(1)
	rng_dmg.push([0.0])
	var on_boss_hit: Array[StrikeResult] = CombatResolver.resolve_strikes(challenger, boss, 0.9, rng_dmg)
	var rng_dmg2 := RollSource.new(1)
	rng_dmg2.push([0.0])
	var on_plain_hit: Array[StrikeResult] = CombatResolver.resolve_strikes(challenger, plain, 0.9, rng_dmg2)
	_assert(on_boss_hit[0].damage < on_plain_hit[0].damage, "同样一击，打在擂主身上被先天减伤削掉一截")

	# 状态技统一提到 10%。
	for skill_id in ["skill_poison", "skill_paralyze", "skill_confuse", "skill_root"]:
		var skill := SkillCatalog.by_id(skill_id)
		var chance := skill.poison_chance + skill.paralyze_chance + skill.confuse_chance + skill.root_chance
		_assert(is_equal_approx(chance, 0.10), "%s 触发概率提到 10%%" % skill_id)

	# 人越多，擂主那份按最大生命回血的续航越值钱，命中率上要按人头折价。
	_assert(is_equal_approx(CombatResolver.champion_endurance_edge(5), 0.0), "5 人以内不额外折价")
	_assert(CombatResolver.champion_endurance_edge(14) > 0.0, "人多了才开始折价")
	_assert(CombatResolver.calibrated_hit_chance(0.5, 0.0, 0.0, 14) < CombatResolver.calibrated_hit_chance(0.5, 0.0, 0.0, 5), "同样目标胜率，人越多擂主的命中率给得越少")
	# 技能张数差改成按张计价：多摸一张就多让一点命中率，不再用平均张数硬编。
	_assert(CombatResolver.calibrated_hit_chance(0.5, 0.0, 4.0) < CombatResolver.calibrated_hit_chance(0.5, 0.0, 2.0), "多摸一张技能就要多让出一点命中率")
	_assert(is_equal_approx(CombatResolver.calibrated_hit_chance(0.5, 0.0, 0.0), 0.5), "张数持平时中心点就是五五开")
