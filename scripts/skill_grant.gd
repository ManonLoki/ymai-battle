class_name SkillGrant
extends RefCounted

## 开场发牌：每个用过的 agent 各掷一个 buff，再从技能池里随机抽一手技能。
## 抽到什么直接决定这场仗怎么打，也是胜率在目标值附近上下浮动的来源。


## 逐个渠道掷 buff，顺序跟着用量从高到低。认不出的渠道不产出 buff。
static func roll_agent_buffs(channels: PackedStringArray, rng: RollSource) -> Array[SkillDef]:
	var buffs: Array[SkillDef] = []
	for channel in channels:
		var buff := roll_agent_buff(channel, rng)
		# id 为 "none" 表示这个 channel 不在表里，跳过。
		if buff.id != "none":
			buffs.append(buff)
	return buffs


## 单个渠道 buff 的数值每场重掷，落在 [AGENT_BUFF_MIN, AGENT_BUFF_MAX]。
static func roll_agent_buff(channel: String, rng: RollSource) -> SkillDef:
	# 认不出的渠道不产出 buff，而且必须在掷点之前就返回——
	# 白掷一次会让后面每个人的点数都往后错一位，测试里的定种子结果就对不上了。
	if not SkillCatalog.AGENT_BUFF_SPECS.has(channel):
		return SkillCatalog.none_buff()
	# 掷一个 [0, 1] 的点数，线性映射到数值区间。
	var amount := lerpf(SkillCatalog.AGENT_BUFF_MIN, SkillCatalog.AGENT_BUFF_MAX, clampf(rng.randf(), 0.0, 1.0))
	# 带着掷出来的数值建模板：生效字段和说明文案都按这一场的真实加成来。
	return SkillCatalog.agent_buff_template(channel, amount)


## 洗牌后取前 count 张，保证同一个人不会拿到重复技能。
static func pick_skills(count: int, rng: RollSource) -> Array[SkillDef]:
	var pool: Array[SkillDef] = SkillCatalog.pool()
	# 池子可能比要抽的张数还少，取小的那个。
	var cap := mini(count, pool.size())
	rng.shuffle(pool)
	var picked: Array[SkillDef] = []
	for i in range(cap):
		picked.append(pool[i])
	return picked


## 这一场发几张技能。擂主 5~8 张、挑战者 2~4 张，每场重掷，
## 所以同一个人连着上场，手里的牌也是一场松一场紧，不会每次都发满。
static func roll_skill_count(is_champion: bool, rng: RollSource) -> int:
	if is_champion:
		return rng.randi_range(SkillCatalog.CHAMPION_SKILL_MIN, SkillCatalog.CHAMPION_SKILL_CAP)
	return rng.randi_range(SkillCatalog.CHALLENGER_SKILL_MIN, SkillCatalog.CHALLENGER_SKILL_CAP)


## 发牌并同步“浴火重生”这类需要预先记账的状态。
## 每个用过的 agent 各掷一个 buff：用了 3 个 agent 就带 3 个 buff，一起叠加生效。
static func apply(fighter: Fighter, rng: RollSource) -> void:
	fighter.agent_buffs = roll_agent_buffs(fighter.channels, rng)
	# 先掷这一场发几张，再从池子里抽这么多张。
	fighter.skills = pick_skills(roll_skill_count(fighter.is_champion, rng), rng)
	# 复活次数是记在 Fighter 上的一次性额度，抽到这张牌才点亮。
	fighter.rebirth_available = false
	for skill in fighter.skills:
		if skill.rebirth:
			fighter.rebirth_available = true
			break
