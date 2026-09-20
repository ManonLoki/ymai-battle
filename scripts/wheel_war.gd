class_name WheelWar
extends RefCounted

## 车轮战：榜首（擂主）留在左侧，其余人按随机顺序轮流上场挑战。
## 擂主的血量不会在换人时回满，所以越往后越吃紧。

## 战斗状态：进行中 / 擂主倒下 / 挑战者全灭。
enum Outcome { ONGOING, CHAMPION_DOWN, ALL_OPPONENTS_DOWN }

## 擂主，全场就他一个，血条从头用到尾。
var champion: Fighter
## 还没上场的挑战者，按出场顺序排列。
var waiting: Array[Fighter] = []
## 正在场上的那位挑战者，没人了就是 null。
var current_opponent: Fighter
## 其余人的合计战力（RMS 口径，见 CombatResolver.aggregate_power）。
var others_power: int = 0
## 擂主本场的目标胜率，始终落在 [MIN_WIN_RATE, MAX_WIN_RATE] 内。
## 它是“最终获胜的概率”，不是单次命中率。
var win_rate: float = 0.5
## 由 win_rate 反解出的擂主命中率偏移：正数擂主更容易打中、挑战者更难，
## 两边一加一减，通常只有几个百分点（见 CombatResolver.champion_steer）。
var champion_steer: float = 0.0
var outcome: Outcome = Outcome.ONGOING


## 用一份排行榜开一场新的车轮战：榜首当擂主，其余人洗牌后排队上。
func setup(ranked: Array[RankedUser], rng: RollSource) -> void:
	waiting.clear()
	current_opponent = null
	outcome = Outcome.ONGOING
	# 空榜单就什么都不做，outcome 留在 ONGOING，调用方自己判断人数。
	if ranked.is_empty():
		return
	champion = Fighter.from_ranked(ranked[0], true)
	# 第 2 名往后全是挑战者。
	var challengers: Array[Fighter] = []
	var powers: Array[int] = []
	for i in range(1, ranked.size()):
		var challenger := Fighter.from_ranked(ranked[i], false)
		challengers.append(challenger)
		powers.append(challenger.tokens)
	# 全员创建完毕后按完整名单均衡形象；必须放在洗牌前，保证随机出场顺序不会改变长相。
	var roster: Array[Fighter] = []
	roster.append(champion)
	roster.append_array(challengers)
	Fighter.assign_balanced_appearances(roster)
	# 出场顺序随机，同一份榜单每场打起来都不一样。
	rng.shuffle(challengers)
	waiting = challengers
	others_power = CombatResolver.aggregate_power(powers)
	win_rate = CombatResolver.champion_win_rate(champion.tokens, others_power, waiting.size())
	# 每位挑战者吃 HITS_PER_DUEL 次命中就倒下；擂主的血条要扛完所有人，
	# 于是两边需要的有效命中总数相等，胜负回到命中率和技能上。
	champion.hits_to_down = CombatResolver.HITS_PER_DUEL * waiting.size()
	for fighter in waiting:
		fighter.hits_to_down = CombatResolver.HITS_PER_DUEL
	# 先发牌，再反解偏移——偏移要扣掉擂主多带的那几个 buff。
	SkillGrant.apply(champion, rng)
	for fighter in waiting:
		SkillGrant.apply(fighter, rng)
	champion_steer = CombatResolver.champion_steer(win_rate, _champion_buff_edge(), _champion_skill_edge(), waiting.size())
	# 让第一位挑战者上场。
	_advance_opponent()


## 场上还站着的挑战者数量，永远是 0 或 1。
func active_opponent_count() -> int:
	return 1 if current_opponent != null and current_opponent.is_alive() else 0


## 右侧还剩多少人（含正在场上的那位）。
func remaining_including_current() -> int:
	return waiting.size() + active_opponent_count()


## 推进一个回合：挑战者永远先手，擂主还活着就还手。
func simulate_turn(rng: RollSource) -> Array[StrikeResult]:
	var events: Array[StrikeResult] = []
	# 已经打完、或者根本没开起来，就什么都不产出。
	if outcome != Outcome.ONGOING or champion == null or current_opponent == null:
		return events
	# 挑战者永远先手。
	events.append_array(CombatResolver.resolve_action(current_opponent, champion, champion_steer, rng))
	if not champion.is_alive():
		outcome = Outcome.CHAMPION_DOWN
		return events
	# 挑战者可能毒死或自杀，这回合擂主不再打这个人。
	if not current_opponent.is_alive():
		_advance_opponent()
		return events
	# 擂主还手。
	events.append_array(CombatResolver.resolve_action(champion, current_opponent, champion_steer, rng))
	if not champion.is_alive():
		outcome = Outcome.CHAMPION_DOWN
	# 挑战者可能死在擂主的出手或反击下，同样要换人。
	if current_opponent != null and not current_opponent.is_alive():
		_advance_opponent()
	return events


## 擂主这一身 buff 比挑战者平均值钱多少，单位是命中当量（见 CombatResolver.agent_buff_hit_value）。
## 多带一个 agent、或者这一场掷到更高的数值，都是实打实的战力，
## 反解命中率时要扣掉，否则多开 agent 的人等于白嫖胜率。
## 按当量而不是按个数算，是因为 buff 数值每场重掷、区间还挺宽，
## 同样一个 buff 掷到 5% 和掷到 20% 根本不是一回事。
func _champion_buff_edge() -> float:
	if waiting.is_empty():
		return 0.0
	var total := 0.0
	for fighter in waiting:
		total += CombatResolver.agent_buff_hit_value(fighter.agent_buffs)
	return CombatResolver.agent_buff_hit_value(champion.agent_buffs) - total / float(waiting.size())


## 擂主这一场的技能张数比挑战者平均多几张。发牌张数每场重掷（擂主 4~10、挑战者 2~6），
## 所以这个差值每场都不一样，必须现算——按平均值硬编的话，
## 擂主手气差只摸到下限的那些场次会按“平均多几张”被扣命中率，白亏。
func _champion_skill_edge() -> float:
	if waiting.is_empty():
		return 0.0
	var total := 0
	for fighter in waiting:
		total += fighter.skills.size()
	return float(champion.skills.size()) - float(total) / float(waiting.size())


## 擂主赢没赢下这一场。胜负的判定标准归 WheelWar，别在场景脚本里就地比 outcome。
func champion_won() -> bool:
	return outcome == Outcome.ALL_OPPONENTS_DOWN


## 换下一位挑战者上场；队列空了就是挑战者全灭，擂主赢下整场。
func _advance_opponent() -> void:
	if waiting.is_empty():
		current_opponent = null
		outcome = Outcome.ALL_OPPONENTS_DOWN
		return
	current_opponent = waiting.pop_front()
