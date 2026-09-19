class_name SkillCatalog
extends RefCounted

## 全部技能与渠道 buff 的定义表，外加图标加载。

## 技能图标目录，文件名就是 SkillDef.icon_id。
const ICON_DIR := "res://assets/icons/"
## 每场随机抽几张技能，不是每次都发满——同一个人连着当擂主，
## 手里的牌也会一场松一场紧，观感上每场都不一样。
## 擂主以一敌众，区间整体比挑战者高一档，这是他扛住车轮战的主要本钱。
const CHAMPION_SKILL_MIN := 5
const CHAMPION_SKILL_CAP := 8
const CHALLENGER_SKILL_MIN := 2
const CHALLENGER_SKILL_CAP := 4
## 中毒 / 麻痹 / 混乱 / 定身的触发概率，四个状态技共用一个值。
const STATUS_CHANCE := 0.10

## 渠道专属 buff 的数值区间：每场随机落在 5%~10% 之间。
const AGENT_BUFF_MIN := 0.05
const AGENT_BUFF_MAX := 0.10

## 技能池的数据表：[id, 名字, 说明, 生效字段, 数值]。
## 生效字段是 SkillDef 上的属性名，和 Fighter._sum(prop) 用的是同一套名字——
## 加一个技能只要在这里补一行，不用动任何结算代码。
const POOL_SPECS := [
	["skill_crit", "暴击+", "增加暴击概率 5%", "crit_chance", 0.05],
	["skill_dodge", "闪避+", "增加闪避 5%", "dodge_bonus", 0.05],
	["skill_hit", "命中+", "增加命中 5%", "accuracy_bonus", 0.05],
	["skill_dr", "减伤+", "减伤 5%", "damage_reduction", 0.05],
	["skill_dmg", "增伤+", "增伤 5%", "damage_bonus", 0.05],
	["skill_double", "二连击", "10% 概率额外出手一次", "double_chance", 0.10],
	["skill_triple", "三连击", "5% 概率额外出手两次", "triple_chance", 0.05],
	["skill_root", "定身", "命中后 10% 打断目标下一次行动", "root_chance", STATUS_CHANCE],
	["skill_poison", "中毒", "命中后 10% 使目标中毒 3 回合", "poison_chance", STATUS_CHANCE],
	["skill_paralyze", "麻痹", "命中后 10% 麻痹目标 3 回合", "paralyze_chance", STATUS_CHANCE],
	["skill_confuse", "混乱", "命中后 10% 使目标混乱 3 回合", "confuse_chance", STATUS_CHANCE],
	["skill_guard", "绝对防御", "5% 触发时减免一切伤害", "guard_chance", 0.05],
	["skill_rebirth", "浴火重生", "死亡后满血复活一次，随后报废", "rebirth", true],
	["skill_counter", "反击", "被命中后 10% 反击一次", "counter_chance", 0.10],
	["skill_lifesteal", "吸血", "命中后按伤害吸血：擂主 30%，挑战者 50%", "lifesteal", true],
	["skill_heal", "治疗", "攻击后回血：擂主 10% 回 5% 生命，挑战者 15% 回 10% 生命", "heal_chance", 0.10],
]

## 渠道 buff 的数据表：channel -> [id, 名字, 生效字段]。
## 具体数值每场重掷，由 SkillGrant.roll_agent_buff 填进去。
const AGENT_BUFF_SPECS := {
	AgentSkills.CHANNEL_CODEX: ["buff_codex", "CODEX 暴击", "crit_chance", "暴击概率"],
	AgentSkills.CHANNEL_CLAUDE: ["buff_claude", "CLAUDE 命中", "accuracy_bonus", "命中概率"],
	AgentSkills.CHANNEL_GROK: ["buff_grok", "GROK 闪避", "dodge_bonus", "闪避概率"],
	AgentSkills.CHANNEL_WORKBUDDY: ["buff_workbuddy", "WORKBUDDY 减伤", "damage_reduction", "减伤"],
}


## 空技能。用它而不是 null，调用方就不用到处判空。
static func none_buff() -> SkillDef:
	var skill := SkillDef.new()
	skill.id = "none"
	skill.display_name = "无"
	return skill


## 某个渠道对应的 buff 模板。不给 amount 就按区间下限填数值、说明里写出整个区间；
## SkillGrant 掷出这一场的具体数值后带着 amount 再要一次，说明就跟着变成真实加成。
## 生效字段和说明文案都只在这里拼一次，改文案不用两头找。
## 认不出的渠道返回空技能。
static func agent_buff_template(channel: String, amount: float = -1.0) -> SkillDef:
	if not AGENT_BUFF_SPECS.has(channel):
		return none_buff()
	var spec: Array = AGENT_BUFF_SPECS[channel]
	var skill := SkillDef.new()
	skill.id = spec[0]
	skill.display_name = spec[1]
	# 图标文件名和 id 同名。
	skill.icon_id = spec[0]
	if amount < 0.0:
		skill.description = "%s +%.0f%%~%.0f%%" % [spec[3], AGENT_BUFF_MIN * 100.0, AGENT_BUFF_MAX * 100.0]
		skill.set(spec[2], AGENT_BUFF_MIN)
	else:
		skill.description = "%s +%.0f%%" % [spec[3], amount * 100.0]
		skill.set(spec[2], amount)
	return skill


## 可抽技能池。每次返回全新的对象，调用方可以随便洗牌、改数值。
static func pool() -> Array[SkillDef]:
	var items: Array[SkillDef] = []
	for spec in POOL_SPECS:
		var skill := _make(spec[0], spec[1], spec[2])
		# 表里第 4 项是属性名，第 5 项是值；概率和布尔开关都走这一条路。
		skill.set(spec[3], spec[4])
		items.append(skill)
	return items


## 图标悬停时显示的两行文字。
static func tooltip_text(skill: SkillDef) -> String:
	if skill == null:
		return ""
	return "%s\n%s" % [skill.display_name, skill.description]


## 建一条技能的公共部分，图标文件名和 id 同名。
static func _make(id: String, name: String, desc: String) -> SkillDef:
	var skill := SkillDef.new()
	skill.id = id
	skill.display_name = name
	skill.description = desc
	skill.icon_id = id
	return skill


## 全部图标 id，测试拿它检查 assets/icons 下有没有漏图。
static func all_icon_ids() -> PackedStringArray:
	var ids: PackedStringArray = PackedStringArray()
	for spec in AGENT_BUFF_SPECS.values():
		ids.append(str(spec[0]))
	for spec in POOL_SPECS:
		ids.append(str(spec[0]))
	return ids


## icon_id 对应的贴图路径，空 id 返回空串。
static func icon_path(icon_id: String) -> String:
	if icon_id.is_empty():
		return ""
	return ICON_DIR + icon_id + ".png"


## 读一张图标。优先走导入后的资源；导出包外（比如测试直接跑源码目录）
## 资源可能没导入过，这时回落到从原始 PNG 现场建一张贴图。
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


## 按 id 找回一条技能定义，找不到返回空技能。
static func by_id(skill_id: String) -> SkillDef:
	for channel in AGENT_BUFF_SPECS:
		if AGENT_BUFF_SPECS[channel][0] == skill_id:
			return agent_buff_template(channel)
	for skill in pool():
		if skill.id == skill_id:
			return skill
	return none_buff()
