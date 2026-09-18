class_name CombatResolver
extends RefCounted

## 战斗结算。这里的设计底线：任何一次判定都是掷骰子，
## 没有“必中”“必闪”“锁血”之类把结果写死的效果。
## 战力差、技能数值和概率共同决定胜负，胜率永远留在 [20%, 80%] 之间。

## 单次攻击命中率的上下限，保证再劣势也有 5% 的翻盘空间。
const MIN_HIT_CHANCE := 0.05
const MAX_HIT_CHANCE := 0.95

## 擂主胜率的上下限。战力再悬殊也不锁死结果，否则这场仗没有可玩性。
const MIN_WIN_RATE := 0.20
const MAX_WIN_RATE := 0.80

## 一场单挑的标准长度：挑战者被打掉这么多次干净命中就倒下。
## 车轮战里擂主的血条要撑完全部挑战者，所以他的耐打度是 HITS_PER_DUEL × 人数，
## 双方需要的有效命中数因此相等，胜负就只由命中率和技能决定。
const HITS_PER_DUEL := 4

## 擂主技能位是挑战者的两倍（8 vs 4），这份优势换算成命中率约等于这么多。
## 反解命中率时先扣掉它，实测胜率才不会整体偏向擂主。
## 数值由 tests 里的蒙特卡洛回归标定，改技能池或技能位数量时要重新跑。
const CHAMPION_SKILL_EDGE := 0.042

## 擂主的治疗回的是 5% 最大生命，而他的血条要扛 4×人数 次命中：
## 人越多，同样一次治疗折算成“普通命中”就越值钱（15 人榜单里一次≈2.8 次命中）。
## 这份随场次拉长而膨胀的续航优势，超过 BASE 人之后按人头再扣一点命中率，
## 否则人多的大榜单里擂主会明显打超目标胜率。系数同样由蒙特卡洛标定。
const CHAMPION_ENDURANCE_EDGE_BASE := 5
const CHAMPION_ENDURANCE_EDGE_PER_OPPONENT := 0.004

## 每个 agent 换一个 buff，所以 agent 数量本身就是战力的一部分。
## 擂主每比挑战者平均多带一个 buff，命中率就再让出这么多，
## 多开几个 agent 才不会变成白嫖胜率。同样由蒙特卡洛回归标定。
const AGENT_BUFF_HIT_EDGE := 0.033

## 目标胜率每偏离 50% 一个标准正态分位，命中率就偏离中心这么多。
## 一场仗要掷几十次骰子，命中率上几个百分点就足以决定胜负，
## 所以这个系数很小；同样由蒙特卡洛标定。
const WIN_RATE_SPREAD := 0.070

## 中毒每回合按“半次普通命中”掉血。
const POISON_TICK_SHARE := 0.5
## 中毒 / 麻痹 / 混乱的持续回合数。
const STATUS_TURNS := 3

const CRIT_MULTIPLIER := 2.0

## 吸血比例。擂主 30%、挑战者 50%：擂主的血条本来就要扛完全场，
## 同样的吸血比例落在他身上收益大得多，所以按身份分开给。
## 折算方式不变——先把这一击换算成“相当于自己多少次普通命中”再按比例回，
## 否则擂主打一个小号造成的伤害换算到自己那条长血条上会是笔巨款。
const LIFESTEAL_RATIO_CHAMPION := 0.30
const LIFESTEAL_RATIO_CHALLENGER := 0.50

## 治疗：擂主 10% 概率回 5% 最大生命，挑战者 15% 概率回 10% 最大生命。
## 这里按最大生命的百分比算，不再按“几次普通命中”：
## 擂主的一次普通命中只占自己血条的 1/(4×人数)，5% 生命对他其实是笔大钱，
## 而挑战者一次命中就是 25% 生命，10% 反而是小补——这个倾斜是故意的，
## 擂主要靠续航扛完车轮战，挑战者靠的是爆发。胜率那边已经按这个重新标定过。
const HEAL_CHANCE_CHAMPION := 0.10
const HEAL_CHANCE_CHALLENGER := 0.15
const HEAL_SHARE_CHAMPION := 0.05
const HEAL_SHARE_CHALLENGER := 0.10

## 胜率曲线的三次贝塞尔控制点。两端的 handle 收在 0.12 / 0.88，
## 于是曲线中段陡、两头缓：战力接近时一点差距就改变胜率，
## 战力悬殊时再拉开也只是缓慢逼近上下限。
const WIN_RATE_EASE := Vector4(0.0, 0.12, 0.88, 1.0)


## 车轮战里“其余人”的合计战力。
##
## 用平方和开根（RMS 口径）而不是直接求和：擂主是挨个单挑过去的，
## 一个 2 亿 token 的对手造成的威胁远大于两个 1 亿的，
## 平方和正好刻画了这种“单点强度”的差别，胜率曲线才对得上真实难度。
static func aggregate_power(powers: Array[int]) -> int:
	var sum_of_squares := 0.0
	for power in powers:
		var value := float(maxi(0, power))
		sum_of_squares += value * value
	return int(round(sqrt(sum_of_squares)))


## 擂主的目标胜率，由战力比 r = 擂主 / 其余人合计 推出。
##
## 先把 r ∈ [0, ∞) 压成进度 s = r / (r + 1)（势均力敌时 s = 0.5），
## 再过一遍对称的贝塞尔缓动，最后映射到 [MIN_WIN_RATE, MAX_WIN_RATE]。
## 因为缓动对称，r = 1 精确落在 50%，两端则收敛到 20% / 80% 而不是 0 / 100%。
static func champion_win_rate(champion_power: int, others_power: int) -> float:
	if others_power <= 0:
		return MAX_WIN_RATE
	if champion_power <= 0:
		return MIN_WIN_RATE
	var ratio := float(champion_power) / float(others_power)
	var progress := ratio / (ratio + 1.0)
	var eased := cubic_bezier(progress, WIN_RATE_EASE.x, WIN_RATE_EASE.y, WIN_RATE_EASE.z, WIN_RATE_EASE.w)
	return lerpf(MIN_WIN_RATE, MAX_WIN_RATE, clampf(eased, 0.0, 1.0))


static func cubic_bezier(t: float, p0: float, p1: float, p2: float, p3: float) -> float:
	var u := 1.0 - t
	return u * u * u * p0 + 3.0 * u * u * t * p1 + 3.0 * u * t * t * p2 + t * t * t * p3


## 一名角色被打掉多少次干净命中才倒下 → 每次命中打掉多少血。
## 伤害只看防守方，因为耐打度已经在 WheelWar 里按“要扛几场”分配好了。
static func strike_damage(defender: Fighter) -> int:
	return maxi(1, int(round(float(defender.max_hp) / float(maxi(1, defender.hits_to_down)))))


## 治疗量：自己最大生命的固定百分比。
static func heal_amount(fighter: Fighter) -> int:
	var share := HEAL_SHARE_CHAMPION if fighter.is_champion else HEAL_SHARE_CHALLENGER
	return maxi(1, int(round(float(fighter.max_hp) * share)))


## 治疗的触发概率，按身份分。
static func heal_chance(fighter: Fighter) -> float:
	return HEAL_CHANCE_CHAMPION if fighter.is_champion else HEAL_CHANCE_CHALLENGER


## 吸血比例，按身份分。
static func lifesteal_ratio(fighter: Fighter) -> float:
	return LIFESTEAL_RATIO_CHAMPION if fighter.is_champion else LIFESTEAL_RATIO_CHALLENGER


## 标准正态分位数（probit）在 [0.2, 0.8] 上的三次近似：z ≈ 1.2517x + 0.371x³，x = 2p - 1。
## 胜率本来就被夹在这个区间里，不必引入完整的反误差函数。
static func probit(p: float) -> float:
	var x := 2.0 * clampf(p, MIN_WIN_RATE, MAX_WIN_RATE) - 1.0
	return 1.2517 * x + 0.371 * x * x * x


## 把“这场仗擂主该赢多少次”的目标胜率，反解成他单次攻击的命中率。
##
## 中心点是 0.5 减去擂主的两项固有优势（技能位更多、buff 可能更多），
## 扣掉之后双方才算真正五五开；再按目标胜率的正态分位左右挪 WIN_RATE_SPREAD。
## buff_edge 是擂主的 buff 数减去挑战者的平均 buff 数，可正可负。
## 一场仗要掷几十次骰子，命中率上几个百分点就已经是压倒性优势，
## 所以算出来的命中率始终贴着 50% 附近——胜率是靠概率调出来的，不是锁出来的。
## 人数超过 BASE 之后，擂主每多一个对手要多让出的命中率。
static func champion_endurance_edge(opponent_count: int) -> float:
	return CHAMPION_ENDURANCE_EDGE_PER_OPPONENT * float(maxi(0, opponent_count - CHAMPION_ENDURANCE_EDGE_BASE))


static func calibrated_hit_chance(win_rate: float, buff_edge: float = 0.0, opponent_count: int = 0) -> float:
	var center := 0.5 - CHAMPION_SKILL_EDGE - AGENT_BUFF_HIT_EDGE * buff_edge - champion_endurance_edge(opponent_count)
	return clampf(center + probit(win_rate) * WIN_RATE_SPREAD, MIN_HIT_CHANCE, MAX_HIT_CHANCE)


## 不含任何技能修正时的命中率：擂主拿反解出来的命中率，挑战者拿它的补集。
static func base_hit_chance(attacker_is_champion: bool, champion_hit: float) -> float:
	return champion_hit if attacker_is_champion else 1.0 - champion_hit


## 只算攻击方命中加成、还没被闪避扣减的命中率。
## 用于区分“自己失手”和“被对方闪掉”。
static func hit_chance_before_dodge(attacker: Fighter, champion_hit: float) -> float:
	var raw := base_hit_chance(attacker.is_champion, champion_hit) + attacker.stacked_accuracy()
	return clampf(raw, MIN_HIT_CHANCE, MAX_HIT_CHANCE)


## 最终命中率：基础命中 + 攻击方命中加成 - 防守方闪避，再夹回 [5%, 95%]。
static func hit_chance(attacker: Fighter, defender: Fighter, champion_hit: float) -> float:
	var raw := hit_chance_before_dodge(attacker, champion_hit) - defender.stacked_dodge()
	return clampf(raw, MIN_HIT_CHANCE, MAX_HIT_CHANCE)


## 结算一名角色的一次行动：先跑中毒掉血，再判定麻痹 / 定身 / 混乱，
## 最后才真正出手。返回这次行动产生的全部战报事件。
static func resolve_action(actor: Fighter, foe: Fighter, champion_hit: float, rng: RollSource, allow_counter: bool = true) -> Array[StrikeResult]:
	var events: Array[StrikeResult] = []
	if actor.poison_turns > 0:
		events.append(_resolve_poison_tick(actor))
		if not actor.is_alive():
			return events
	if actor.paralyze_turns > 0:
		actor.paralyze_turns -= 1
		events.append(_skip_event(actor, "paralyze"))
		return events
	if actor.rooted_next:
		actor.rooted_next = false
		events.append(_skip_event(actor, "root"))
		return events
	var target := foe
	var self_hit := false
	if actor.confuse_turns > 0:
		actor.confuse_turns -= 1
		if rng.randf() < 0.5:
			target = actor
			self_hit = true
	var strikes := resolve_strikes(actor, target, champion_hit, rng, allow_counter and not self_hit)
	for strike in strikes:
		strike.self_hit = self_hit
		if self_hit:
			strike.defender_name = actor.username
	events.append_array(strikes)
	return events


## 一次出手的完整结算：首击 →（二连 / 三连追击）→ 治疗 → 对方反击。
static func resolve_strikes(attacker: Fighter, defender: Fighter, champion_hit: float, rng: RollSource, allow_counter: bool = true) -> Array[StrikeResult]:
	var events: Array[StrikeResult] = []
	var first := _one_strike(attacker, defender, champion_hit, rng, 0)
	events.append(first)
	if first.hit and (not first.defender_died) and defender != attacker:
		var extras := 0
		if attacker.stacked_double() > 0.0 and rng.randf() < attacker.stacked_double():
			extras += 1
		if attacker.stacked_triple() > 0.0 and rng.randf() < attacker.stacked_triple():
			extras += 2
		for i in range(extras):
			if not defender.is_alive():
				break
			# 追击同样要过命中判定，连击只是多给机会，不是保证打中。
			events.append(_one_strike(attacker, defender, champion_hit, rng, i + 1))
	_apply_heal_skill(attacker, events, rng)
	if allow_counter and first.hit and defender.is_alive() and defender.stacked_counter() > 0.0 and rng.randf() < defender.stacked_counter():
		var counters := resolve_strikes(defender, attacker, champion_hit, rng, false)
		for counter in counters:
			counter.countered = true
		events.append_array(counters)
	return events


static func _resolve_poison_tick(actor: Fighter) -> StrikeResult:
	var tick := StrikeResult.new()
	tick.attacker_name = actor.username
	tick.defender_name = actor.username
	tick.attacker_is_champion = actor.is_champion
	tick.poison_tick = true
	tick.hit = true
	tick.damage = maxi(1, int(round(float(strike_damage(actor)) * POISON_TICK_SHARE)))
	actor.apply_damage(tick.damage)
	actor.poison_turns -= 1
	tick.revived = actor.try_rebirth()
	tick.defender_hp_after = actor.hp
	tick.defender_died = not actor.is_alive()
	return tick


static func _skip_event(actor: Fighter, reason: String) -> StrikeResult:
	var result := StrikeResult.new()
	result.attacker_name = actor.username
	result.defender_name = actor.username
	result.attacker_is_champion = actor.is_champion
	result.skipped = reason
	result.defender_hp_after = actor.hp
	return result


static func _one_strike(attacker: Fighter, defender: Fighter, champion_hit: float, rng: RollSource, extra_index: int) -> StrikeResult:
	var result := StrikeResult.new()
	result.attacker_name = attacker.username
	result.defender_name = defender.username
	result.attacker_is_champion = attacker.is_champion
	var signature := attacker.primary_agent_buff()
	result.skill_id = signature.id
	result.skill_name = signature.display_name
	result.combo = extra_index > 0
	result.extra_index = extra_index

	var before_dodge := hit_chance_before_dodge(attacker, champion_hit)
	var chance := hit_chance(attacker, defender, champion_hit)
	var roll := rng.randf()
	if roll >= chance:
		# 落在 [chance, before_dodge) 的点数是被闪避挡下的，再往上才是自己失手。
		result.dodged = defender.stacked_dodge() > 0.0 and roll < before_dodge
		result.defender_hp_after = defender.hp
		result.attacker_hp_after = attacker.hp
		result.defender_died = not defender.is_alive()
		return result
	result.hit = true

	if defender.stacked_guard() > 0.0 and rng.randf() < defender.stacked_guard():
		result.guarded = true
		result.damage = 0
		result.defender_hp_after = defender.hp
		result.attacker_hp_after = attacker.hp
		_apply_on_hit_status(attacker, defender, rng, result)
		return result

	var damage := float(strike_damage(defender))
	if attacker.stacked_crit() > 0.0 and rng.randf() < attacker.stacked_crit():
		result.crit = true
		damage *= CRIT_MULTIPLIER
	damage *= 1.0 + attacker.stacked_damage_bonus()
	damage *= 1.0 - defender.stacked_damage_reduction()
	result.damage = maxi(1, int(round(damage)))
	defender.apply_damage(result.damage)
	if attacker.has_lifesteal() and attacker != defender:
		var scale := float(strike_damage(attacker)) / float(maxi(1, strike_damage(defender)))
		var stolen := maxi(1, int(round(float(result.damage) * lifesteal_ratio(attacker) * scale)))
		result.heal_amount = attacker.apply_heal(stolen)
		result.lifesteal = result.heal_amount > 0
	result.revived = defender.try_rebirth()
	result.defender_hp_after = defender.hp
	result.attacker_hp_after = attacker.hp
	result.defender_died = not defender.is_alive()
	_apply_on_hit_status(attacker, defender, rng, result)
	return result


## 命中之后逐个掷骰，看是否挂上中毒 / 麻痹 / 混乱 / 定身。
static func _apply_on_hit_status(attacker: Fighter, defender: Fighter, rng: RollSource, result: StrikeResult) -> void:
	if attacker == defender:
		return
	if attacker.stacked_poison() > 0.0 and rng.randf() < attacker.stacked_poison():
		defender.poison_turns = STATUS_TURNS
		result.poisoned = true
	if attacker.stacked_paralyze() > 0.0 and rng.randf() < attacker.stacked_paralyze():
		defender.paralyze_turns = STATUS_TURNS
		result.paralyzed = true
	if attacker.stacked_confuse() > 0.0 and rng.randf() < attacker.stacked_confuse():
		defender.confuse_turns = STATUS_TURNS
		result.confused = true
	if attacker.stacked_root() > 0.0 and rng.randf() < attacker.stacked_root():
		defender.rooted_next = true
		result.rooted = true


## 治疗技能在整轮出手之后结算一次，成功则并入最后一条战报。
static func _apply_heal_skill(attacker: Fighter, events: Array[StrikeResult], rng: RollSource) -> void:
	if not attacker.has_heal() or events.is_empty():
		return
	if rng.randf() >= heal_chance(attacker):
		for event in events:
			event.attacker_hp_after = attacker.hp
		return
	var healed := attacker.apply_heal(heal_amount(attacker))
	var last: StrikeResult = events[events.size() - 1]
	last.treated = true
	last.heal_amount += healed
	for event in events:
		event.attacker_hp_after = attacker.hp
