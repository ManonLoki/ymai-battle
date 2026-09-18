class_name SkillGrant
extends RefCounted

## 开场发牌：每个用过的 agent 各掷一个 buff，再从技能池里随机抽一手技能。
## 抽到什么直接决定这场仗怎么打，也是胜率在目标值附近上下浮动的来源。


## 逐个渠道掷 buff，顺序跟着用量从高到低。认不出的渠道不产出 buff。
static func roll_agent_buffs(channels: PackedStringArray, rng: RollSource) -> Array[SkillDef]:
	var buffs: Array[SkillDef] = []
	for channel in channels:
		var buff := roll_agent_buff(channel, rng)
		if buff.id != "none":
			buffs.append(buff)
	return buffs


## 单个渠道 buff 的数值每场重掷，落在 [AGENT_BUFF_MIN, AGENT_BUFF_MAX]。
static func roll_agent_buff(channel: String, rng: RollSource) -> SkillDef:
	var buff := SkillCatalog.agent_buff_template(channel)
	if buff.id == "none":
		return buff
	var t := clampf(rng.randf(), 0.0, 1.0)
	var amount := lerpf(SkillCatalog.AGENT_BUFF_MIN, SkillCatalog.AGENT_BUFF_MAX, t)
	var pct := "%.0f%%" % (amount * 100.0)
	match buff.id:
		"buff_codex":
			buff.crit_chance = amount
			buff.description = "暴击概率 +%s" % pct
		"buff_claude":
			buff.accuracy_bonus = amount
			buff.description = "命中概率 +%s" % pct
		"buff_grok":
			buff.dodge_bonus = amount
			buff.description = "闪避概率 +%s" % pct
		"buff_workbuddy":
			buff.damage_reduction = amount
			buff.description = "减伤 +%s" % pct
	return buff


## 洗牌后取前 count 张，保证同一个人不会拿到重复技能。
static func pick_skills(count: int, rng: RollSource) -> Array[SkillDef]:
	var pool: Array[SkillDef] = SkillCatalog.pool()
	var cap := mini(count, pool.size())
	for i in range(pool.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp: SkillDef = pool[i]
		pool[i] = pool[j]
		pool[j] = tmp
	var picked: Array[SkillDef] = []
	for i in range(cap):
		picked.append(pool[i])
	return picked


## 发牌并同步“浴火重生”这类需要预先记账的状态。
## 每个用过的 agent 各掷一个 buff：用了 3 个 agent 就带 3 个 buff，一起叠加生效。
static func apply(fighter: Fighter, rng: RollSource) -> void:
	fighter.agent_buffs = roll_agent_buffs(fighter.channels, rng)
	var cap := SkillCatalog.CHAMPION_SKILL_CAP if fighter.is_champion else SkillCatalog.CHALLENGER_SKILL_CAP
	fighter.skills = pick_skills(cap, rng)
	fighter.rebirth_available = false
	for skill in fighter.skills:
		if skill.rebirth:
			fighter.rebirth_available = true
			break
