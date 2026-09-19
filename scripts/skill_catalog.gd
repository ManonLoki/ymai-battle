class_name SkillCatalog
extends RefCounted

## 全部技能与渠道 buff 的定义表，外加图标加载。
##
## 这里只有**一张表**（SPECS）是手写的：一条技能的 id、名字、说明模板、边框族、
## 生效字段和数值全写在同一行上。技能池、图标族、展示分组、排序、图标清单
## 全部由这张表算出来，加一条技能只要补一行，不用动任何结算或展示代码。

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
## 边框族的先后顺序，同一展示分组里按它分块（金框和蓝框各自成块）。
const FAMILY_ORDER := [
	FAMILY_SELF,
	FAMILY_DEFENSE,
	FAMILY_STATUS,
	FAMILY_RECOVER,
	FAMILY_TECHNIQUE,
]
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

## 技能池的数据表，一行就是一条技能的全部配置：
##   id   技能标识，同时也是图标文件名（assets/icons/<id>.png）。
##   name 悬停时显示的技能名。
##   desc 说明模板，见下面关于占位符的约定。
##   family 图标边框族，同时决定展示分组和技能行里的左右顺序。
##   prop 生效字段：SkillDef 上的属性名，也是 Fighter.stacked(prop) 用的那个名字。
##   value 写进 prop 的值，概率是 float，浴火重生 / 吸血这类开关是 true。
##
## **表的顺序有意义**：pool() 按这个顺序建池子，SkillGrant 再洗牌，
## 所以调换行等于改掉所有定种子测试的结果。展示顺序也读这个次序（同族内）。
##
## 说明里**不许写死数字**，一律用 {占位符}（见 _describe）。这些数字有一半是
## CombatResolver 里被蒙特卡洛标定过的常量，写死的话重标定一次 tooltip 就开始撒谎。
## {pct} 是这一行自己的数值，其余占位符指向结算器里的对应常量（见 DESC_CONSTANTS）。
const SPECS := [
	{"id": "skill_crit", "name": "暴击+", "desc": "增加暴击概率 {pct}", "family": FAMILY_SELF, "prop": "crit_chance", "value": SELF_BUFF_CHANCE},
	{"id": "skill_dodge", "name": "闪避+", "desc": "增加闪避 {pct}", "family": FAMILY_DEFENSE, "prop": "dodge_bonus", "value": SELF_BUFF_CHANCE},
	{"id": "skill_hit", "name": "命中+", "desc": "增加命中 {pct}", "family": FAMILY_SELF, "prop": "accuracy_bonus", "value": SELF_BUFF_CHANCE},
	{"id": "skill_dr", "name": "减伤+", "desc": "减伤 {pct}", "family": FAMILY_DEFENSE, "prop": "damage_reduction", "value": SELF_BUFF_CHANCE},
	{"id": "skill_dmg", "name": "增伤+", "desc": "增伤 {pct}", "family": FAMILY_SELF, "prop": "damage_bonus", "value": SELF_BUFF_CHANCE},
	{"id": "skill_double", "name": "二连击", "desc": "{pct} 概率额外出手一次", "family": FAMILY_TECHNIQUE, "prop": "double_chance", "value": DOUBLE_CHANCE},
	{"id": "skill_triple", "name": "三连击", "desc": "{pct} 概率额外出手两次", "family": FAMILY_TECHNIQUE, "prop": "triple_chance", "value": TRIPLE_CHANCE},
	{"id": "skill_poison", "name": "中毒", "desc": "命中后 {pct} 使目标中毒 {turns} 回合", "family": FAMILY_STATUS, "prop": "poison_chance", "value": STATUS_CHANCE},
	{"id": "skill_paralyze", "name": "麻痹", "desc": "命中后 {pct} 麻痹目标 {turns} 回合", "family": FAMILY_STATUS, "prop": "paralyze_chance", "value": STATUS_CHANCE},
	{"id": "skill_confuse", "name": "混乱", "desc": "命中后 {pct} 使目标混乱 {turns} 回合，每次行动 {confuse_self} 打自己", "family": FAMILY_STATUS, "prop": "confuse_chance", "value": STATUS_CHANCE},
	{"id": "skill_guard", "name": "绝对防御", "desc": "{pct} 触发时减免一切伤害，且不附加任何效果", "family": FAMILY_DEFENSE, "prop": "guard_chance", "value": SELF_BUFF_CHANCE},
	{"id": "skill_rebirth", "name": "浴火重生", "desc": "死亡后满血复活一次，随后报废", "family": FAMILY_RECOVER, "prop": "rebirth", "value": true},
	{"id": "skill_counter", "name": "反击", "desc": "被命中后 {pct} 反击一次", "family": FAMILY_TECHNIQUE, "prop": "counter_chance", "value": COUNTER_CHANCE},
	{"id": "skill_lifesteal", "name": "吸血", "desc": "命中后按伤害吸血：擂主 {lifesteal_champion}，挑战者 {lifesteal_challenger}", "family": FAMILY_RECOVER, "prop": "lifesteal", "value": true},
	{"id": "skill_heal", "name": "治疗", "desc": "触发时回血且不进攻，本回合 {heal_guard} 闪避（幻影刺杀除外）：擂主 {heal_chance_champion} 回 {heal_share_champion} 生命，挑战者 {heal_chance_challenger} 回 {heal_share_challenger} 生命", "family": FAMILY_RECOVER, "prop": "heal_chance", "value": CombatResolver.HEAL_CHANCE_CHAMPION},
	{"id": "skill_assassinate", "name": "幻影刺杀", "desc": "非追击时无视闪避：擂主 {assassinate_chance_champion} 秒杀并结算浴火重生，挑战者 {assassinate_chance_challenger} 造成 {assassinate_share_challenger} 最大生命伤害", "family": FAMILY_TECHNIQUE, "prop": "assassinate_chance", "value": CombatResolver.ASSASSINATE_CHANCE_CHAMPION},
	{"id": "skill_lingbo", "name": "凌波微步", "desc": "非追击被攻击时 {pct} 闪避并立刻反击一次", "family": FAMILY_TECHNIQUE, "prop": "lingbo_chance", "value": LINGBO_CHANCE},
	{"id": "skill_awaken", "name": "潜能激发", "desc": "{pct} 触发时损失 {awaken_hp} 最大生命，本次攻击命中 +{awaken_hit}、暴击 +{awaken_crit}、伤害 +{awaken_damage}；当前生命不足时不触发", "family": FAMILY_TECHNIQUE, "prop": "awaken_chance", "value": CombatResolver.AWAKEN_CHANCE},
]

## 说明模板里除 {pct} 和 {turns} 之外的占位符，一律指向 CombatResolver 的标定常量，
## 并按百分数渲染。重新标定之后 tooltip 自动跟着变，不会停留在旧数字上。
const DESC_CONSTANTS := {
	"lifesteal_champion": CombatResolver.LIFESTEAL_RATIO_CHAMPION,
	"lifesteal_challenger": CombatResolver.LIFESTEAL_RATIO_CHALLENGER,
	"heal_chance_champion": CombatResolver.HEAL_CHANCE_CHAMPION,
	"heal_chance_challenger": CombatResolver.HEAL_CHANCE_CHALLENGER,
	"heal_share_champion": CombatResolver.HEAL_SHARE_CHAMPION,
	"heal_share_challenger": CombatResolver.HEAL_SHARE_CHALLENGER,
	"heal_guard": CombatResolver.HEAL_GUARD_DODGE,
	"assassinate_chance_champion": CombatResolver.ASSASSINATE_CHANCE_CHAMPION,
	"assassinate_chance_challenger": CombatResolver.ASSASSINATE_CHANCE_CHALLENGER,
	"assassinate_share_challenger": CombatResolver.ASSASSINATE_SHARE_CHALLENGER,
	"confuse_self": CombatResolver.CONFUSE_SELF_HIT_CHANCE,
	"awaken_hp": CombatResolver.AWAKEN_HP_SHARE,
	"awaken_hit": CombatResolver.AWAKEN_HIT_BONUS,
	"awaken_crit": CombatResolver.AWAKEN_CRIT_BONUS,
	"awaken_damage": CombatResolver.AWAKEN_DAMAGE_BONUS,
}

## 渠道 buff 的数据表：channel -> 配置。字段名和 SPECS 一致（id / name / prop），
## 多一个 label 用来拼说明；具体数值每场重掷，由 SkillGrant.roll_agent_buff 填进去。
const AGENT_BUFF_SPECS := {
	AgentChannels.CHANNEL_CODEX: {"id": "buff_codex", "name": "CODEX 暴击", "prop": "crit_chance", "label": "暴击概率"},
	AgentChannels.CHANNEL_CLAUDE: {"id": "buff_claude", "name": "CLAUDE 命中", "prop": "accuracy_bonus", "label": "命中概率"},
	AgentChannels.CHANNEL_GROK: {"id": "buff_grok", "name": "GROK 闪避", "prop": "dodge_bonus", "label": "闪避概率"},
	AgentChannels.CHANNEL_WORKBUDDY: {"id": "buff_workbuddy", "name": "WORKBUDDY 减伤", "prop": "damage_reduction", "label": "减伤"},
}

## id -> 在 SPECS 里的行号。第一次用到时算一遍就缓存，之后查表都是 O(1)。
static var _rank_by_id: Dictionary = {}


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
	var spec: Dictionary = AGENT_BUFF_SPECS[channel]
	var label := str(spec["label"])
	if amount < 0.0:
		var span := "%s +%.0f%%~%.0f%%" % [label, AGENT_BUFF_MIN * 100.0, AGENT_BUFF_MAX * 100.0]
		return _build(spec, AGENT_BUFF_MIN, span)
	return _build(spec, amount, "%s +%.0f%%" % [label, amount * 100.0])


## 可抽技能池。每次返回全新的对象，调用方可以随便洗牌、改数值。
## 顺序就是 SPECS 的顺序——洗牌是定种子的，调换行会改掉所有回归结果。
static func pool() -> Array[SkillDef]:
	var items: Array[SkillDef] = []
	for spec in SPECS:
		items.append(_from_spec(spec))
	return items


## 按一行配置建出技能定义，概率和布尔开关都走这一条路。
static func _from_spec(spec: Dictionary) -> SkillDef:
	return _build(spec, spec["value"], _describe(str(spec["desc"]), spec["value"]))


## 技能和渠道 buff 共用的建法：图标文件名和 id 同名，数值按 prop 写进去。
static func _build(spec: Dictionary, value: Variant, description: String) -> SkillDef:
	var skill := SkillDef.new()
	skill.id = str(spec["id"])
	skill.display_name = str(spec["name"])
	skill.description = description
	skill.icon_id = skill.id
	skill.set(str(spec["prop"]), value)
	return skill


## 把说明模板补成最终文案。所有数字都从这里注入，模板里一个也不写死。
##
## {pct} 是这条技能自己的数值，{turns} 是状态回合数（整数，不写成百分比），
## 其余占位符全部来自 DESC_CONSTANTS。
## format 会忽略模板里没用到的键，一份字典喂给所有模板就够了。
static func _describe(template: String, value: Variant) -> String:
	var args := {
		"pct": _percent(value),
		"turns": CombatResolver.STATUS_TURNS,
	}
	for key in DESC_CONSTANTS:
		args[key] = _percent(DESC_CONSTANTS[key])
	return template.format(args)


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


## 一条技能在 SPECS 里的行号，不在表里（agent buff、空技能）返回 -1。
static func spec_rank(skill_id: String) -> int:
	if _rank_by_id.is_empty():
		for i in SPECS.size():
			_rank_by_id[str(SPECS[i]["id"])] = i
	return _rank_by_id.get(skill_id, -1)


## 一条技能的配置行，不在表里返回空字典。
static func spec_of(skill_id: String) -> Dictionary:
	var rank := spec_rank(skill_id)
	return SPECS[rank] if rank >= 0 else {}


## 图标所属边框族，agent buff 和不在表里的 id 返回空串。
static func icon_family(icon_id: String) -> String:
	return str(spec_of(icon_id).get("family", ""))


## 边框族 -> 族内图标 id，顺序同 FAMILY_ORDER 与表序。
## 烘焙出来的边框颜色按族检查时读它。
static func icon_families() -> Dictionary:
	var families := {}
	for family in FAMILY_ORDER:
		families[family] = []
	for spec in SPECS:
		var family := str(spec["family"])
		if not families.has(family):
			families[family] = []
		families[family].append(str(spec["id"]))
	return families


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
## 同组内按边框族（自身强化在防御前），再按表序，这样金框和蓝框各自成块。
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
		return spec_rank(a.icon_id) < spec_rank(b.icon_id)
	)
	return ranked


## 边框族在 FAMILY_ORDER 里的位置，未知的排到最后。
static func _family_rank(icon_id: String) -> int:
	var idx := FAMILY_ORDER.find(icon_family(icon_id))
	return idx if idx >= 0 else FAMILY_ORDER.size()


## 全部图标 id，测试拿它检查 assets/icons 下有没有漏图。
static func all_icon_ids() -> PackedStringArray:
	var ids: PackedStringArray = PackedStringArray()
	for spec in AGENT_BUFF_SPECS.values():
		ids.append(str(spec["id"]))
	for spec in SPECS:
		ids.append(str(spec["id"]))
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


## 按 id 找回一条技能定义，找不到返回空技能。每次都是新对象，改了不影响别人。
static func by_id(skill_id: String) -> SkillDef:
	for channel in AGENT_BUFF_SPECS:
		if str(AGENT_BUFF_SPECS[channel]["id"]) == skill_id:
			return agent_buff_template(channel)
	var spec := spec_of(skill_id)
	if spec.is_empty():
		return none_buff()
	return _from_spec(spec)
