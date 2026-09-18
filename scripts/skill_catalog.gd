class_name SkillCatalog
extends RefCounted

## 全部技能与渠道 buff 的定义表，外加图标加载。

const ICON_DIR := "res://assets/icons/"
## 擂主以一敌众，技能位比挑战者多一倍，这是他扛住车轮战的主要本钱。
const CHAMPION_SKILL_CAP := 8
const CHALLENGER_SKILL_CAP := 4
## 中毒 / 麻痹 / 混乱 / 定身的触发概率，四个状态技共用一个值。
const STATUS_CHANCE := 0.10

## 渠道专属 buff 的数值区间：每场随机落在 5%~10% 之间。
const AGENT_BUFF_MIN := 0.05
const AGENT_BUFF_MAX := 0.10


static func none_buff() -> SkillDef:
	var skill := SkillDef.new()
	skill.id = "none"
	skill.display_name = "无"
	return skill


static func agent_buff_template(channel: String) -> SkillDef:
	var skill := SkillDef.new()
	match channel:
		AgentSkills.CHANNEL_CODEX:
			skill.id = "buff_codex"
			skill.display_name = "CODEX 暴击"
			skill.description = "暴击概率 +5%~10%"
			skill.icon_id = "buff_codex"
			skill.crit_chance = AGENT_BUFF_MIN
		AgentSkills.CHANNEL_CLAUDE:
			skill.id = "buff_claude"
			skill.display_name = "CLAUDE 命中"
			skill.description = "命中概率 +5%~10%"
			skill.icon_id = "buff_claude"
			skill.accuracy_bonus = AGENT_BUFF_MIN
		AgentSkills.CHANNEL_GROK:
			skill.id = "buff_grok"
			skill.display_name = "GROK 闪避"
			skill.description = "闪避概率 +5%~10%"
			skill.icon_id = "buff_grok"
			skill.dodge_bonus = AGENT_BUFF_MIN
		AgentSkills.CHANNEL_WORKBUDDY:
			skill.id = "buff_workbuddy"
			skill.display_name = "WORKBUDDY 减伤"
			skill.description = "减伤 +5%~10%"
			skill.icon_id = "buff_workbuddy"
			skill.damage_reduction = AGENT_BUFF_MIN
		_:
			return none_buff()
	return skill


static func pool() -> Array[SkillDef]:
	var items: Array[SkillDef] = []
	items.append(_make("skill_crit", "暴击+", "增加暴击概率 5%"))
	items[items.size() - 1].crit_chance = 0.05
	items.append(_make("skill_dodge", "闪避+", "增加闪避 5%"))
	items[items.size() - 1].dodge_bonus = 0.05
	items.append(_make("skill_hit", "命中+", "增加命中 5%"))
	items[items.size() - 1].accuracy_bonus = 0.05
	items.append(_make("skill_dr", "减伤+", "减伤 5%"))
	items[items.size() - 1].damage_reduction = 0.05
	items.append(_make("skill_dmg", "增伤+", "增伤 5%"))
	items[items.size() - 1].damage_bonus = 0.05
	items.append(_make("skill_double", "二连击", "10% 概率额外出手一次"))
	items[items.size() - 1].double_chance = 0.10
	items.append(_make("skill_triple", "三连击", "5% 概率额外出手两次"))
	items[items.size() - 1].triple_chance = 0.05
	items.append(_make("skill_root", "定身", "命中后 10% 打断目标下一次行动"))
	items[items.size() - 1].root_chance = STATUS_CHANCE
	items.append(_make("skill_poison", "中毒", "命中后 10% 使目标中毒 3 回合"))
	items[items.size() - 1].poison_chance = STATUS_CHANCE
	items.append(_make("skill_paralyze", "麻痹", "命中后 10% 麻痹目标 3 回合"))
	items[items.size() - 1].paralyze_chance = STATUS_CHANCE
	items.append(_make("skill_confuse", "混乱", "命中后 10% 使目标混乱 3 回合"))
	items[items.size() - 1].confuse_chance = STATUS_CHANCE
	items.append(_make("skill_guard", "绝对防御", "5% 触发时减免一切伤害"))
	items[items.size() - 1].guard_chance = 0.05
	items.append(_make("skill_rebirth", "浴火重生", "死亡后满血复活一次，随后报废"))
	items[items.size() - 1].rebirth = true
	items.append(_make("skill_counter", "反击", "被命中后 10% 反击一次"))
	items[items.size() - 1].counter_chance = 0.10
	items.append(_make("skill_lifesteal", "吸血", "命中后按伤害吸血：擂主 30%，挑战者 50%"))
	items[items.size() - 1].lifesteal = true
	items.append(_make("skill_heal", "治疗", "攻击后回血：擂主 10% 回 5% 生命，挑战者 15% 回 10% 生命"))
	items[items.size() - 1].heal_chance = 0.10
	return items


static func tooltip_text(skill: SkillDef) -> String:
	if skill == null:
		return ""
	return "%s\n%s" % [skill.display_name, skill.description]


static func _make(id: String, name: String, desc: String) -> SkillDef:
	var skill := SkillDef.new()
	skill.id = id
	skill.display_name = name
	skill.description = desc
	skill.icon_id = id
	return skill


static func all_icon_ids() -> PackedStringArray:
	return PackedStringArray([
		"buff_codex", "buff_claude", "buff_grok", "buff_workbuddy",
		"skill_crit", "skill_dodge", "skill_hit", "skill_dr", "skill_dmg",
		"skill_double", "skill_triple", "skill_root", "skill_poison",
		"skill_paralyze", "skill_confuse", "skill_guard", "skill_rebirth", "skill_counter",
		"skill_lifesteal", "skill_heal",
	])


static func icon_path(icon_id: String) -> String:
	if icon_id.is_empty():
		return ""
	return ICON_DIR + icon_id + ".png"


static func load_icon(icon_id: String) -> Texture2D:
	var path := icon_path(icon_id)
	if path.is_empty():
		return null
	if ResourceLoader.exists(path):
		var loaded := load(path)
		if loaded is Texture2D:
			return loaded
	var image := Image.new()
	if image.load(path) != OK:
		return null
	return ImageTexture.create_from_image(image)


static func by_id(skill_id: String) -> SkillDef:
	match skill_id:
		"buff_codex":
			return agent_buff_template(AgentSkills.CHANNEL_CODEX)
		"buff_claude":
			return agent_buff_template(AgentSkills.CHANNEL_CLAUDE)
		"buff_grok":
			return agent_buff_template(AgentSkills.CHANNEL_GROK)
		"buff_workbuddy":
			return agent_buff_template(AgentSkills.CHANNEL_WORKBUDDY)
	for skill in pool():
		if skill.id == skill_id:
			return skill
	return none_buff()
