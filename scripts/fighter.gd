class_name Fighter
extends RefCounted

## 一名上场角色。战力（tokens）同时就是最大生命值，
## 技能效果全部按“加成之和”叠加，没有任何一条能把结果锁死。

var username: String = ""
var tokens: int = 0
var hp: int = 1
var max_hp: int = 1
## 用量最高的渠道，排行榜和战报用它显示主 agent。
var channel: String = ""
var agent_name: String = ""
## 当天用过的全部渠道，按用量从高到低。
var channels: PackedStringArray = PackedStringArray()
## 每个用过的 agent 各自换来一个独立 buff：用了 3 个 agent 就带 3 个 buff。
## 和 skills 分开存，是因为战报和头像上要单独标出它们。
var agent_buffs: Array[SkillDef] = []
## 本场随机抽到的技能，擂主 8 个、挑战者 4 个。
var skills: Array[SkillDef] = []
var is_champion: bool = false
var appearance_id: int = 0
## 要挨多少次干净命中才倒下。默认按一场单挑算，进入车轮战后由 WheelWar
## 按“这条血要扛几场”重新分配。单次伤害就是 max_hp / hits_to_down，
## 所以双方需要的有效命中总数是对等的。
var hits_to_down: int = CombatResolver.HITS_PER_DUEL

## 体型带来的先天差异，不占技能位，谁都改不掉：
## 擂主块头大，闪避吃 5% 的亏，但皮糙肉厚多 5% 减伤；
## 挑战者个子小、身法灵活，先天多 5% 闪避。
const CHAMPION_INNATE_DODGE := -0.05
const CHAMPION_INNATE_DAMAGE_REDUCTION := 0.05
const CHALLENGER_INNATE_DODGE := 0.05

var poison_turns: int = 0
var paralyze_turns: int = 0
var confuse_turns: int = 0
var rooted_next: bool = false
## 是否还留着一次“浴火重生”。
var rebirth_available: bool = false


static func from_ranked(user: RankedUser, p_is_champion: bool) -> Fighter:
	var fighter := Fighter.new()
	fighter.username = user.username
	fighter.tokens = maxi(0, user.tokens)
	fighter.max_hp = maxi(1, fighter.tokens)
	fighter.hp = fighter.max_hp
	fighter.channel = user.channel
	fighter.agent_name = user.agent_name
	fighter.channels = user.channels
	fighter.agent_buffs = []
	fighter.is_champion = p_is_champion
	fighter.appearance_id = absi(user.username.hash()) % SpriteFactory.COUNT
	return fighter


func is_alive() -> bool:
	return hp > 0


func apply_damage(amount: int) -> void:
	hp = maxi(0, hp - maxi(0, amount))


## 回血并返回实际回复量（可能被最大生命截断）。
func apply_heal(amount: int) -> int:
	var before := hp
	hp = mini(max_hp, hp + maxi(0, amount))
	return hp - before


## 倒下瞬间尝试复活一次；用掉之后这张技能就从卡组里移除。
func try_rebirth() -> bool:
	if hp > 0 or not rebirth_available:
		return false
	hp = max_hp
	rebirth_available = false
	var kept: Array[SkillDef] = []
	for skill in skills:
		if not skill.rebirth:
			kept.append(skill)
	skills = kept
	return true


func stacked_crit() -> float:
	return _sum("crit_chance")


## 先天闪避：擂主是负的（更容易被打中），挑战者是正的。
func innate_dodge() -> float:
	return CHAMPION_INNATE_DODGE if is_champion else CHALLENGER_INNATE_DODGE


## 先天减伤：只有擂主有。
func innate_damage_reduction() -> float:
	return CHAMPION_INNATE_DAMAGE_REDUCTION if is_champion else 0.0


## 可能是负数（擂主没带闪避技能时）。结算那边认得负值：
## 命中率会因此上浮，而且不会被记成“闪避”，只会是实打实的命中。
func stacked_dodge() -> float:
	return _sum("dodge_bonus") + innate_dodge()


func stacked_accuracy() -> float:
	return _sum("accuracy_bonus")


func stacked_damage_bonus() -> float:
	return _sum("damage_bonus")


## 减伤最多吃到 90%，留 10% 保证伤害永远打得进去。
func stacked_damage_reduction() -> float:
	return clampf(_sum("damage_reduction") + innate_damage_reduction(), 0.0, 0.9)


func stacked_double() -> float:
	return _sum("double_chance")


func stacked_triple() -> float:
	return _sum("triple_chance")


func stacked_root() -> float:
	return _sum("root_chance")


func stacked_poison() -> float:
	return _sum("poison_chance")


func stacked_paralyze() -> float:
	return _sum("paralyze_chance")


func stacked_confuse() -> float:
	return _sum("confuse_chance")


func stacked_guard() -> float:
	return _sum("guard_chance")


func stacked_counter() -> float:
	return _sum("counter_chance")


func stacked_heal_chance() -> float:
	return _sum("heal_chance")


## 主 agent 的 buff，只用于战报署名；没有 agent 时回落到“无”。
func primary_agent_buff() -> SkillDef:
	return agent_buffs[0] if agent_buffs.size() > 0 else SkillCatalog.none_buff()


## 战报里“某某（XX 暴击 · N 技能）”那一段的 buff 文案。
func agent_buff_text() -> String:
	if agent_buffs.is_empty():
		return SkillCatalog.none_buff().display_name
	var names: PackedStringArray = PackedStringArray()
	for buff in agent_buffs:
		names.append(buff.display_name)
	return " + ".join(names)


## 带没带治疗技能。具体几率和回多少由 CombatResolver 按擂主 / 挑战者分别定，
## 所以这里只问“有没有”。
func has_heal() -> bool:
	for buff in agent_buffs:
		if buff.heal_chance > 0.0:
			return true
	for skill in skills:
		if skill.heal_chance > 0.0:
			return true
	return false


func has_lifesteal() -> bool:
	for buff in agent_buffs:
		if buff.lifesteal:
			return true
	for skill in skills:
		if skill.lifesteal:
			return true
	return false


## 把所有 agent buff 和所有技能上的同名数值加起来。
func _sum(prop: String) -> float:
	var total := 0.0
	for buff in agent_buffs:
		total += float(buff.get(prop))
	for skill in skills:
		total += float(skill.get(prop))
	return total
