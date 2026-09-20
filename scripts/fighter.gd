class_name Fighter
extends RefCounted

## 一名上场角色。战力（tokens）同时就是最大生命值，
## 技能效果全部按“加成之和”叠加，没有任何一条能把结果锁死。

## 玩家名，战报和血条上显示的就是它。
var username: String = ""
## 当日 token 总量，既是战力也是最大生命。
var tokens: int = 0
## 当前血量。
var hp: int = 1
## 最大血量，等于 tokens（至少 1）。
var max_hp: int = 1
## 用量最高的渠道，排行榜和战报用它显示主 agent。
var channel: String = ""
## channel 对应的展示名。
var agent_name: String = ""
## 当天用过的全部渠道，按用量从高到低。
var channels: PackedStringArray = PackedStringArray()
## 每个用过的 agent 各自换来一个独立 buff：用了 3 个 agent 就带 3 个 buff。
## 和 skills 分开存，是因为战报和头像上要单独标出它们。
var agent_buffs: Array[SkillDef] = []
## 本场随机抽到的技能，擂主 4~10 张、挑战者 2~6 张。
var skills: Array[SkillDef] = []
## 是不是这一场的擂主（榜首）。体型、技能位、先天加成都看它。
var is_champion: bool = false
## 立绘 canonical 编号。单人创建时使用稳定兜底；完整战斗名单会在洗牌前均衡重分配。
var appearance_id: int = 0
## 要挨多少次干净命中才倒下。默认按一场单挑算，进入车轮战后由 WheelWar
## 按“这条血要扛几场”重新分配。单次伤害就是 max_hp / hits_to_down，
## 所以双方需要的有效命中总数是对等的。
var hits_to_down: int = CombatResolver.HITS_PER_DUEL

## 全员都有的基础闪避 / 暴击，不占技能位。反击和减伤没有这份基础。
const BASE_DODGE := 0.10
const BASE_CRIT := 0.10
## 体型带来的额外修正，叠在全员基础之上：
## 擂主块头大，闪避再吃 5% 的亏，但皮糙肉厚多 5% 减伤；
## 挑战者个子小、身法灵活，再多 5% 闪避。
const CHAMPION_INNATE_DODGE := -0.05
const CHAMPION_INNATE_DAMAGE_REDUCTION := 0.05
const CHALLENGER_INNATE_DODGE := 0.05

## 减伤总和的上限，留 10% 保证伤害永远打得进去。
const MAX_DAMAGE_REDUCTION := 0.9

## 剩余中毒回合数，每回合开头掉一次血。
var poison_turns: int = 0
## 剩余麻痹回合数，每回合直接跳过行动。
var paralyze_turns: int = 0
## 剩余混乱回合数，出手时有一半概率打自己。
var confuse_turns: int = 0
## 是否还留着一次“浴火重生”。
var rebirth_available: bool = false
## 上一手治疗触发后，直到自己下一次行动开始前 100% 闪避（幻影刺杀除外）。
var heal_guard: bool = false
## 本手潜能激发留下的临时加成。自己下一次行动开始时清掉，还手仍可读。
var awaken_accuracy_bonus: float = 0.0
var awaken_crit_bonus: float = 0.0
var awaken_damage_bonus: float = 0.0
var awaken_cost_paid: int = 0


func clear_awaken() -> void:
	awaken_accuracy_bonus = 0.0
	awaken_crit_bonus = 0.0
	awaken_damage_bonus = 0.0
	awaken_cost_paid = 0


func has_awaken_bonus() -> bool:
	return awaken_accuracy_bonus > 0.0 or awaken_crit_bonus > 0.0 or awaken_damage_bonus > 0.0


## 从排行榜条目建一名上场角色。技能和 buff 由 SkillGrant 另行发放。
static func from_ranked(user: RankedUser, p_is_champion: bool) -> Fighter:
	var fighter := Fighter.new()
	fighter.username = user.username
	# 负 token 当 0；血量至少 1，否则一上场就是死的。
	fighter.tokens = maxi(0, user.tokens)
	fighter.max_hp = maxi(1, fighter.tokens)
	fighter.hp = fighter.max_hp
	fighter.channel = user.channel
	fighter.agent_name = user.agent_name
	fighter.channels = user.channels
	fighter.agent_buffs = []
	fighter.is_champion = p_is_champion
	# 单人调用也只会落进可选池；WheelWar 拿到完整名单后还会做一次无重复均衡分配。
	fighter.appearance_id = SpriteFactory.fallback_appearance_id(user.username)
	return fighter


## 按完整名单批量分配形象。名单顺序不影响 username -> appearance_id 的结果；同名角色
## 会保持同一形象，符合用户名作为稳定身份键的既有约定。
static func assign_balanced_appearances(fighters: Array[Fighter]) -> void:
	var usernames: Array[String] = []
	for fighter in fighters:
		usernames.append(fighter.username)
	var assignments := SpriteFactory.assign_appearance_ids(usernames)
	for fighter in fighters:
		fighter.appearance_id = int(assignments[fighter.username])


func is_alive() -> bool:
	return hp > 0


## 扣血，扣到 0 为止；负数伤害按 0 处理。
func apply_damage(amount: int) -> void:
	hp = maxi(0, hp - maxi(0, amount))


## 回血并返回实际回复量（可能被最大生命截断）。
func apply_heal(amount: int) -> int:
	var before := hp
	hp = mini(max_hp, hp + maxi(0, amount))
	return hp - before


## 倒下瞬间尝试复活一次；用掉之后这张技能就从卡组里移除。
func try_rebirth() -> bool:
	# 还活着、或者额度已经用掉了，都不触发。
	if hp > 0 or not rebirth_available:
		return false
	hp = max_hp
	rebirth_available = false
	# 把这张牌从技能里摘掉，图标也会跟着消失。
	var kept: Array[SkillDef] = []
	for skill in skills:
		if not skill.rebirth:
			kept.append(skill)
	skills = kept
	return true


func stacked_crit() -> float:
	return stacked("crit_chance") + BASE_CRIT


## 先天闪避：擂主是负的（更容易被打中），挑战者是正的。
func innate_dodge() -> float:
	return CHAMPION_INNATE_DODGE if is_champion else CHALLENGER_INNATE_DODGE


## 先天减伤：只有擂主有。
func innate_damage_reduction() -> float:
	return CHAMPION_INNATE_DAMAGE_REDUCTION if is_champion else 0.0


## 全员基础 10% + 体型修正 + 技能/buff。没抽到闪避技能也会闪。
func stacked_dodge() -> float:
	return stacked("dodge_bonus") + BASE_DODGE + innate_dodge()


func stacked_accuracy() -> float:
	return stacked("accuracy_bonus")


func stacked_damage_bonus() -> float:
	return stacked("damage_bonus")


## 减伤最多吃到 90%，留 10% 保证伤害永远打得进去。
func stacked_damage_reduction() -> float:
	return clampf(stacked("damage_reduction") + innate_damage_reduction(), 0.0, MAX_DAMAGE_REDUCTION)


func stacked_double() -> float:
	return stacked("double_chance")


func stacked_triple() -> float:
	return stacked("triple_chance")


func stacked_assassinate() -> float:
	return stacked("assassinate_chance")


func stacked_lingbo() -> float:
	return stacked("lingbo_chance")


func stacked_reflect() -> float:
	return stacked("reflect_chance")


func stacked_guard() -> float:
	return stacked("guard_chance")


func stacked_counter() -> float:
	return stacked("counter_chance")


func stacked_awaken() -> float:
	return stacked("awaken_chance")


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
	return _has_any("heal_chance")


## 带没带吸血技能，同样只问有没有。
func has_lifesteal() -> bool:
	return _has_any("lifesteal")


## 把所有 agent buff 和所有技能上的同名数值加起来。
## 用属性名字符串索引，加技能时只要往 SkillCatalog 的表里补一行就行。
##
## 公开是因为表驱动的效果派发（CombatResolver.ON_HIT_STATUSES）只有字段名，
## 拿不到对应的 stacked_xxx 具名方法；中毒 / 麻痹 / 混乱三个字段就只有这一条路，
## 所以它们没有具名包装。手写的调用点仍然走上面那些包装，它们有类型、也好搜。
func stacked(prop: String) -> float:
	var total := 0.0
	for buff in agent_buffs:
		total += float(buff.get(prop))
	for skill in skills:
		total += float(skill.get(prop))
	return total


## buff 或技能里有没有任何一条把这个字段设成了真 / 非零。
func _has_any(prop: String) -> bool:
	for buff in agent_buffs:
		if buff.get(prop):
			return true
	for skill in skills:
		if skill.get(prop):
			return true
	return false
