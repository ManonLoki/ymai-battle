class_name SkillCatalog
extends RefCounted

## 全部技能与渠道 buff 的定义表，外加图标加载。

## 技能图标目录，文件名就是 SkillDef.icon_id。
const ICON_DIR := "res://assets/icons/"
## 每场随机抽几张技能，不是每次都发满——同一个人连着当擂主，
## 手里的牌也会一场松一场紧，观感上每场都不一样。
## 擂主以一敌众，区间整体比挑战者高一档，这是他扛住车轮战的主要本钱。
const CHAMPION_SKILL_MIN := 6
const CHAMPION_SKILL_CAP := 8
const CHALLENGER_SKILL_MIN := 2
const CHALLENGER_SKILL_CAP := 4
## 中毒 / 麻痹 / 混乱的触发概率，三个状态技共用一个值。
const STATUS_CHANCE := 0.20
## 暴击 / 命中 / 增伤 / 闪避 / 减伤 / 绝对防御。
const SELF_BUFF_CHANCE := 0.10
## 连击 / 反击 / 凌波：池子里的字面量只在这里出现一次，结算读 stacked，tooltip 读 {pct}。
const DOUBLE_CHANCE := 0.20
const TRIPLE_CHANCE := 0.10
const COUNTER_CHANCE := 0.20
const LINGBO_CHANCE := 0.05
## 图标边框五族。烘焙和测试都读这一份，避免边框颜色各写各的。
const FAMILY_SELF := "self"
const FAMILY_DEFENSE := "defense"
const FAMILY_STATUS := "status"
const FAMILY_RECOVER := "recover"
const FAMILY_TECHNIQUE := "technique"
const ICON_FAMILIES := {
	FAMILY_SELF: ["skill_crit", "skill_hit", "skill_dmg"],
	FAMILY_DEFENSE: ["skill_dodge", "skill_dr", "skill_guard"],
	FAMILY_STATUS: ["skill_poison", "skill_paralyze", "skill_confuse"],
	FAMILY_RECOVER: ["skill_rebirth", "skill_lifesteal", "skill_heal"],
	FAMILY_TECHNIQUE: ["skill_triple", "skill_double", "skill_assassinate", "skill_lingbo", "skill_counter", "skill_awaken"],
}
## 技能行从左到右的展示分组。边框仍是五族；展示把自身强化和防御都合进增强类。
const DISPLAY_GROUP_BUFF := "buff"
const DISPLAY_GROUP_STATUS := "status"
const DISPLAY_GROUP_RECOVER := "recover"
const DISPLAY_GROUP_TECHNIQUE := "technique"
const DISPLAY_GROUP_ORDER := [
	DISPLAY_GROUP_BUFF,
	DISPLAY_GROUP_STATUS,
	DISPLAY_GROUP_RECOVER,
	DISPLAY_GROUP_TECHNIQUE,
]
const FAMILY_DISPLAY_GROUP := {
	FAMILY_SELF: DISPLAY_GROUP_BUFF,
	FAMILY_DEFENSE: DISPLAY_GROUP_BUFF,
	FAMILY_STATUS: DISPLAY_GROUP_STATUS,
	FAMILY_RECOVER: DISPLAY_GROUP_RECOVER,
	FAMILY_TECHNIQUE: DISPLAY_GROUP_TECHNIQUE,
}

## 渠道专属 buff 的数值区间：每场随机落在 5%~10% 之间。
const AGENT_BUFF_MIN := 0.05
const AGENT_BUFF_MAX := 0.10

## 技能池的数据表：[id, 名字, 说明模板, 生效字段, 数值]。
## 生效字段是 SkillDef 上的属性名，和 Fighter.stacked(prop) 用的是同一套名字——
## 加一个技能只要在这里补一行，不用动任何结算代码。
##
## 说明里**不许写死数字**，一律用 {占位符}（见 _describe）。这些数字有一半是
## CombatResolver 里被蒙特卡洛标定过的常量，写死的话重标定一次 tooltip 就开始撒谎。
## {pct} 是这一行自己的数值，其余占位符指向结算器里的对应常量。
const POOL_SPECS := [
	["skill_crit", "暴击+", "增加暴击概率 {pct}", "crit_chance", SELF_BUFF_CHANCE],
	["skill_dodge", "闪避+", "增加闪避 {pct}", "dodge_bonus", SELF_BUFF_CHANCE],
	["skill_hit", "命中+", "增加命中 {pct}", "accuracy_bonus", SELF_BUFF_CHANCE],
	["skill_dr", "减伤+", "减伤 {pct}", "damage_reduction", SELF_BUFF_CHANCE],
	["skill_dmg", "增伤+", "增伤 {pct}", "damage_bonus", SELF_BUFF_CHANCE],
	["skill_double", "二连击", "{pct} 概率额外出手一次", "double_chance", DOUBLE_CHANCE],
	["skill_triple", "三连击", "{pct} 概率额外出手两次", "triple_chance", TRIPLE_CHANCE],
	["skill_poison", "中毒", "命中后 {pct} 使目标中毒 {turns} 回合", "poison_chance", STATUS_CHANCE],
	["skill_paralyze", "麻痹", "命中后 {pct} 麻痹目标 {turns} 回合", "paralyze_chance", STATUS_CHANCE],
	["skill_confuse", "混乱", "命中后 {pct} 使目标混乱 {turns} 回合，每次行动 {confuse_self} 打自己", "confuse_chance", STATUS_CHANCE],
	["skill_guard", "绝对防御", "{pct} 触发时减免一切伤害，且不附加任何效果", "guard_chance", SELF_BUFF_CHANCE],
	["skill_rebirth", "浴火重生", "死亡后满血复活一次，随后报废", "rebirth", true],
	["skill_counter", "反击", "被命中后 {pct} 反击一次", "counter_chance", COUNTER_CHANCE],
	["skill_lifesteal", "吸血", "命中后按伤害吸血：擂主 {lifesteal_champion}，挑战者 {lifesteal_challenger}", "lifesteal", true],
	["skill_heal", "治疗", "触发时回血且不进攻，本回合 {heal_guard} 闪避（幻影刺杀除外）：擂主 {heal_chance_champion} 回 {heal_share_champion} 生命，挑战者 {heal_chance_challenger} 回 {heal_share_challenger} 生命", "heal_chance", CombatResolver.HEAL_CHANCE_CHAMPION],
	["skill_assassinate", "幻影刺杀", "非追击时无视闪避：擂主 {assassinate_chance_champion} 秒杀并结算浴火重生，挑战者 {assassinate_chance_challenger} 造成 {assassinate_share_challenger} 最大生命伤害", "assassinate_chance", CombatResolver.ASSASSINATE_CHANCE_CHAMPION],
	["skill_lingbo", "凌波微步", "非追击被攻击时 {pct} 闪避并立刻反击一次", "lingbo_chance", LINGBO_CHANCE],
	["skill_awaken", "潜能激发", "{pct} 触发时损失 {awaken_hp} 最大生命，本次攻击命中 +{awaken_hit}、暴击 +{awaken_crit}、伤害 +{awaken_damage}；当前生命不足时不触发", "awaken_chance", CombatResolver.AWAKEN_CHANCE],
]

## 渠道 buff 的数据表：channel -> [id, 名字, 生效字段]。
## 具体数值每场重掷，由 SkillGrant.roll_agent_buff 填进去。
const AGENT_BUFF_SPECS := {
	AgentChannels.CHANNEL_CODEX: ["buff_codex", "CODEX 暴击", "crit_chance", "暴击概率"],
	AgentChannels.CHANNEL_CLAUDE: ["buff_claude", "CLAUDE 命中", "accuracy_bonus", "命中概率"],
	AgentChannels.CHANNEL_GROK: ["buff_grok", "GROK 闪避", "dodge_bonus", "闪避概率"],
	AgentChannels.CHANNEL_WORKBUDDY: ["buff_workbuddy", "WORKBUDDY 减伤", "damage_reduction", "减伤"],
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
		var skill := _make(spec[0], spec[1], _describe(str(spec[2]), spec[4]))
		# 表里第 4 项是属性名，第 5 项是值；概率和布尔开关都走这一条路。
		skill.set(spec[3], spec[4])
		items.append(skill)
	return items


## 把说明模板补成最终文案。所有数字都从这里注入，模板里一个也不写死。
##
## {pct} 是这条技能自己的数值；其余占位符全部指向 CombatResolver 的标定常量，
## 所以重新标定之后 tooltip 自动跟着变，不会停留在旧数字上。
## format 会忽略模板里没用到的键，一份字典喂给所有模板就够了。
static func _describe(template: String, value: Variant) -> String:
	return template.format({
		"pct": _percent(value),
		"turns": CombatResolver.STATUS_TURNS,
		"lifesteal_champion": _percent(CombatResolver.LIFESTEAL_RATIO_CHAMPION),
		"lifesteal_challenger": _percent(CombatResolver.LIFESTEAL_RATIO_CHALLENGER),
		"heal_chance_champion": _percent(CombatResolver.HEAL_CHANCE_CHAMPION),
		"heal_chance_challenger": _percent(CombatResolver.HEAL_CHANCE_CHALLENGER),
		"heal_share_champion": _percent(CombatResolver.HEAL_SHARE_CHAMPION),
		"heal_share_challenger": _percent(CombatResolver.HEAL_SHARE_CHALLENGER),
		"assassinate_chance_champion": _percent(CombatResolver.ASSASSINATE_CHANCE_CHAMPION),
		"assassinate_chance_challenger": _percent(CombatResolver.ASSASSINATE_CHANCE_CHALLENGER),
		"assassinate_share_challenger": _percent(CombatResolver.ASSASSINATE_SHARE_CHALLENGER),
		"confuse_self": _percent(CombatResolver.CONFUSE_SELF_HIT_CHANCE),
		"awaken_hp": _percent(CombatResolver.AWAKEN_HP_SHARE),
		"awaken_hit": _percent(CombatResolver.AWAKEN_HIT_BONUS),
		"awaken_crit": _percent(CombatResolver.AWAKEN_CRIT_BONUS),
		"awaken_damage": _percent(CombatResolver.AWAKEN_DAMAGE_BONUS),
		"heal_guard": _percent(CombatResolver.HEAL_GUARD_DODGE),
	})


## 比例写成百分数。布尔开关（浴火重生、吸血）没有百分比可言，给空串——
## 它们的模板本来也不带 {pct}。
static func _percent(value: Variant) -> String:
	if typeof(value) == TYPE_BOOL:
		return ""
	return "%d%%" % roundi(float(value) * 100.0)


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


## 图标所属边框族，agent buff 和不在表里的 id 返回空串。
static func icon_family(icon_id: String) -> String:
	for family in ICON_FAMILIES:
		if icon_id in ICON_FAMILIES[family]:
			return str(family)
	return ""


## 技能行展示分组：增强 / 附加 / 治疗 / 高级。
static func display_group(icon_id: String) -> String:
	var family := icon_family(icon_id)
	if FAMILY_DISPLAY_GROUP.has(family):
		return str(FAMILY_DISPLAY_GROUP[family])
	return ""


## 展示分组在从左到右顺序里的位置，未知的排到最后。
static func display_group_rank(icon_id: String) -> int:
	var idx := DISPLAY_GROUP_ORDER.find(display_group(icon_id))
	return idx if idx >= 0 else DISPLAY_GROUP_ORDER.size()


## 把一手技能排成技能行顺序：增强 → 附加 → 治疗 → 高级。
## 同组内按边框族（自身强化在防御前），再按族内表序，这样金框和蓝框各自成块。
static func sort_for_display(skills: Array[SkillDef]) -> Array[SkillDef]:
	var ranked: Array[SkillDef] = skills.duplicate()
	ranked.sort_custom(func(a: SkillDef, b: SkillDef) -> bool:
		var ga := display_group_rank(a.icon_id)
		var gb := display_group_rank(b.icon_id)
		if ga != gb:
			return ga < gb
		var fa := _family_rank(a.icon_id)
		var fb := _family_rank(b.icon_id)
		if fa != fb:
			return fa < fb
		return _id_rank_in_family(a.icon_id) < _id_rank_in_family(b.icon_id)
	)
	return ranked


static func _family_rank(icon_id: String) -> int:
	var family := icon_family(icon_id)
	var i := 0
	for key in ICON_FAMILIES:
		if str(key) == family:
			return i
		i += 1
	return 99


static func _id_rank_in_family(icon_id: String) -> int:
	var family := icon_family(icon_id)
	if family.is_empty():
		return 99
	var ids: Array = ICON_FAMILIES[family]
	var idx: int = ids.find(icon_id)
	return idx if idx >= 0 else 99


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
