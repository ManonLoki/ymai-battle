class_name CombatResolver
extends RefCounted

## 战斗结算。这里的设计底线：任何一次判定都是掷骰子，
## 没有把结果写死的效果——唯一例外是掷中的【幻影刺杀】，
## 它仍要先过按身份分的骰子，中了才无视闪避把对方打到 0 血。
## 战力差、技能数值和概率共同决定胜负，胜率永远留在 [30%, 70%] 之间。

## 谁出手都从这个命中率起步，再按双方的命中 / 闪避加成和这一场的胜率偏移调整。
const BASE_HIT_CHANCE := 0.90

## 命中加成减掉对方闪避之后，净差达到这个值就必中。
## 中间是线性的：净差 0 是 BASE_HIT_CHANCE，净差 FULL_HIT_EDGE 是 100%，
## 所以 +10% 的净优势大约落在 95%。
const FULL_HIT_EDGE := 0.20
## 必中就是 100%，单独起个名字是为了让“这一击必中”在代码里有话可说。
const CERTAIN_HIT_CHANCE := 1.0

## 单次攻击命中率的上下限，保证再劣势也有 5% 的翻盘空间。
## 上限只夹“靠战力差推上去”的那部分：净差满 FULL_HIT_EDGE 的必中越过它，
## 光靠胜率偏移则永远越不过——必中只能自己堆出来。
const MIN_HIT_CHANCE := 0.05
const MAX_HIT_CHANCE := 0.95

## 擂主胜率的上下限。战力再悬殊也不锁死结果，否则这场仗没有可玩性。
## 区间比早期窄（原来是 20%~80%）：榜一被全场围攻本来就常年贴着下限，
## 太低就完全没有参与感；上限压到 70% 则是不让断层第一白拿胜利。
const MIN_WIN_RATE := 0.30
const MAX_WIN_RATE := 0.70

## 一场单挑的标准长度：挑战者被打掉这么多次干净命中就倒下。
## 车轮战里擂主的血条要撑完全部挑战者，所以他的耐打度是 HITS_PER_DUEL × 人数，
## 双方需要的有效命中数因此相等，胜负就只由命中率和技能决定。
const HITS_PER_DUEL := 4

## 擂主每**多拿一张**技能，换算成命中率大约值这么多，反解命中率时按张扣掉。
##
## 以前这里存的是“按平均张数（6.5 对 3）算出来的一个总量”，于是每次调整
## 发牌区间都得重新跑一遍蒙特卡洛，而且擂主刚好只摸到 5 张、挑战者摸满 4 张的
## 那些场次仍按“多 3.5 张”计价，凭空多吃一口。改成按张计价之后，
## WheelWar 把这一场真实的张数差喂进来，发牌区间就成了自由参数。
## 数值仍由 tests 里的蒙特卡洛回归标定，改技能池本身时要重新跑。
const CHAMPION_SKILL_EDGE_PER_SKILL := 0.030

## 人越多，擂主越吃亏：每位挑战者都是满血新人，他的血条却要一路连着算下去。
## 基础命中提到 90% 之后这份吃亏更明显——一场仗的挥击次数少了一半，
## 他没那么多回合把治疗、反击这些续航手段的收益攒出来。所以超过 BASE 人之后
## 按人头**补**一点命中率，封顶以免大榜单补过头。系数由蒙特卡洛标定。
##
## （基础命中还是 50% 的那一版这里是反过来的：那时挥击多、治疗攒得出来，
## 人越多擂主越占便宜，得按人头扣。换算口径之后实测直接翻了个号。）
## 按**人数翻番**计，不按人头：从 1v3 到 1v10 的差别，和从 1v30 到 1v100 的差别
## 差不多大，线性按人头算会在几十人处就撞上封顶，再往上一视同仁。
##
## 这是「让实测追上目标」的一侧；定目标的那一侧是 CROWD_PRESSURE_*（人越多目标越低）。
## 两边都按人数走但单位不同（这里是命中率，那里是胜率），改任意一边都要重跑蒙特卡洛。
const CHAMPION_CROWD_RELIEF_BASE := 3
const CHAMPION_CROWD_RELIEF_PER_DOUBLING := 0.010
const CHAMPION_CROWD_RELIEF_CAP := 0.060

## 擂主的 buff 命中当量每比挑战者平均高 1 点，命中率就让出这么多。
## 「命中当量」怎么算见下面那三个权重常量（AGENT_BUFF_WEIGHT_*）。
## 多开几个 agent、或者掷到更高的数值，才不会变成白嫖胜率。
## 由 tests 里的蒙特卡洛回归标定，改 buff 区间或权重都要重新跑。
const AGENT_BUFF_HIT_EDGE := 0.550

## 目标胜率每偏离 50% 一个标准正态分位，命中率就偏离中心这么多。
## 一场仗要掷几十次骰子，命中率上几个百分点就足以决定胜负，
## 所以这个系数很小；同样由蒙特卡洛标定。
##
## 注意它是按十几人的真实榜单标的。人数很少时（比如只有一个挑战者）
## 整场只掷十几次骰子，随机性本身就把结果往 50% 拉，
## 实测胜率会比目标低几个点——这是短局固有的，不是标定没标准。
const WIN_RATE_SPREAD := 0.220

## 中毒每回合按“半次普通命中”掉血。
const POISON_TICK_SHARE := 0.5
## 中毒 / 麻痹 / 混乱的持续回合数。
const STATUS_TURNS := 3

## 命中后可能给对方挂上的状态。每行是
## [技能字段, Fighter 上的状态字段, 写进去的值, StrikeResult 上的标记（空串表示没有）]。
## 加一种新状态只要往这里补一行，_apply_on_hit_status 不用动。
##
## 两条硬约束，改之前先读：
## 1. **行的顺序就是掷骰顺序**。调换顺序等于改掉所有定种子测试的结果，
##    以及蒙特卡洛标定出来的胜率。
## 2. **概率为 0 时不许掷骰**——这条由 _rolls 统一守着，所有判定都走它。
const ON_HIT_STATUSES := [
	["poison_chance", "poison_turns", STATUS_TURNS, "poisoned"],
	["paralyze_chance", "paralyze_turns", STATUS_TURNS, "paralyzed"],
	["confuse_chance", "confuse_turns", STATUS_TURNS, "confused"],
]

## 暴击伤害倍率。
const CRIT_MULTIPLIER := 2.0

## agent buff 折算成「命中当量」的权重。每条 buff 的权重写在
## SkillCatalog.AGENT_BUFF_SPECS 的行里，取值就是下面这几个常量。
##
## 以前擂主的 buff 优势只数**个数**，因为数值区间窄（5%~10%），哪种 buff 都差不多
## 值钱。区间放宽到 5%~20% 之后，一个 20% 的闪避和一个 5% 的暴击差了三四倍，
## 再按个数计价，手里全是闪避的那一边就白赚一截胜率。
##
## 命中 / 闪避直接加减命中率，一比一。
const AGENT_BUFF_WEIGHT_HIT := 1.0
## 伤害口径折算成命中当量的系数：伤害多打 / 少挨一成，大约值半次命中——
## 它只缩短自己这一侧的血条，另一侧照旧，所以不是一比一。由蒙特卡洛标定。
const AGENT_BUFF_WEIGHT_PER_DAMAGE := 0.5
## 暴击：每 1 点暴击率让期望伤害涨 (CRIT_MULTIPLIER - 1)，再按上面的系数折成当量。
## 写成推导式是为了让暴击倍率和它的定价绑在一起——调倍率这里自动跟着变。
const AGENT_BUFF_WEIGHT_CRIT := (CRIT_MULTIPLIER - 1.0) * AGENT_BUFF_WEIGHT_PER_DAMAGE
## 减伤：每 1 点减伤就少挨 1 点伤害，和暴击倍率无关，所以直接就是那个系数。
const AGENT_BUFF_WEIGHT_REDUCTION := AGENT_BUFF_WEIGHT_PER_DAMAGE

## 混乱状态下打到自己的概率，剩下一半照常打对面。
const CONFUSE_SELF_HIT_CHANCE := 0.5

## 吸血比例。擂主 25%、挑战者 50%：擂主的血条本来就要扛完全场，
## 同样的吸血比例落在他身上收益大得多，所以按身份分开给。
## 折算方式不变——先把这一击换算成“相当于自己多少次普通命中”再按比例回，
## 否则擂主打一个小号造成的伤害换算到自己那条长血条上会是笔巨款。
const LIFESTEAL_RATIO_CHAMPION := 0.25
const LIFESTEAL_RATIO_CHALLENGER := 0.50

## 治疗：双方都是 20% 概率；擂主回 5% 最大生命，挑战者回 10% 最大生命。
## 触发时这一手不进攻，并进入 100% 闪避（幻影刺杀除外），直到自己下一次行动。
## 这里按最大生命的百分比算，不再按“几次普通命中”：
## 擂主的一次普通命中只占自己血条的 1/(4×人数)，5% 生命对他其实是笔大钱，
## 而挑战者一次命中就是 25% 生命，10% 反而是小补——这个倾斜是故意的，
## 擂主要靠续航扛完车轮战，挑战者靠的是爆发。胜率那边已经按这个重新标定过。
const HEAL_CHANCE_CHAMPION := 0.20
const HEAL_CHANCE_CHALLENGER := 0.20
const HEAL_SHARE_CHAMPION := 0.05
const HEAL_SHARE_CHALLENGER := 0.10
## 治疗触发后的闪避：不是掷骰，是直到下一次行动前的满闪（幻影刺杀除外）。
const HEAL_GUARD_DODGE := 1.0

## 潜能激发：5% 触发；扣 10% 最大生命，本次主动出手命中 / 暴击 / 伤害各 +50%。
## 当前生命必须严格大于扣费，否则不掷——付完之后还要能站着打出去。
const AWAKEN_CHANCE := 0.05
const AWAKEN_HP_SHARE := 0.10
const AWAKEN_HIT_BONUS := 0.50
const AWAKEN_CRIT_BONUS := 0.50
const AWAKEN_DAMAGE_BONUS := 0.50

## 幻影刺杀：擂主 1% 秒杀；挑战者 2% 打对方最大生命的 50%。
## 两边都无视闪避。技能表上的 assassinate_chance 只表示“有这招”，真正掷骰看这里。
const ASSASSINATE_CHANCE_CHAMPION := 0.01
const ASSASSINATE_CHANCE_CHALLENGER := 0.02
const ASSASSINATE_SHARE_CHALLENGER := 0.50

## 胜率曲线的两个锚点，按**人均**战力比 s = 擂主 / 挑战者人均战力（RMS 口径）定：
## s = CEIL（比人均强 4 倍）贴着上半程的 SATURATION，s = FLOOR（只有人均的四分之一）
## 对称地贴着下半程；两个锚点的几何中点 s = 1，也就是“和人均一样强”正好五五开。
##
## 锚点以前定在「擂主 / 全场**合计**战力」上，人数就藏在 RMS 合计里
## （N 个等战力的人合计是人均的 √N 倍）。这么算 1v1 里两个一模一样的人对打，
## 擂主会被判到 69%——因为“一个人顶得上全场”在 1v1 里是白送的。
## 现在战力比只管强弱，人多人少交给 crowd_pressure 单独算，两件事各归各的。
const WIN_RATE_RATIO_FLOOR := 0.25
const WIN_RATE_RATIO_CEIL := 4.0
## 锚点处走完了上下限之间的百分之多少。留 5% 不走完，是为了让锚点之外
## 还能继续缓升 / 缓降——战力再往上堆或者再往下掉都仍有反馈，
## 只是收益和惩罚都变得极慢，不会一跨过锚点就彻底躺平。
const WIN_RATE_ANCHOR_SATURATION := 0.95

## 人数压力：围攻的人越多，擂主的目标胜率整体往下压这么多（按 log 人数走 tanh）。
##
## 人数和战力分开算，1v2 / 1v5 / 1v10 / 1v30 才各有各的难度，而不是过了十几人
## 就一律贴着下限。压力有封顶，所以再多人也留得住参与感：等战力时 1v1 是 50%，
## 1v10 落到 40%，1v100 落到 35%，不会变成“人多就没得打”。
## CAP 和锚点都由这份手感反推，不是蒙特卡洛标的——它定的是**目标**，
## 实测能不能贴住目标才是蒙特卡洛的事（见 tests 里的胜率回归）。
##
## 注意人数一共影响两处，改之前两处一起看：这里按人数**压低目标胜率**（意图），
## 而 CHAMPION_CROWD_RELIEF_* 按人数**补命中率**（让实测追得上这个意图）。
## 两条曲线的单位和形状都不一样，只调一边一定要重跑蒙特卡洛。
##
## 它们看着重复，但**合不成一条**：目标一旦压低，反解出来的偏移就跟着变负，
## 也就是人越多越扣擂主的命中率；而实测说人越多擂主越吃亏、需要往回补。
## 一条只活在胜率域的曲线没法同时表达这两件相反的事。
const CROWD_PRESSURE_CAP := 0.175
## 压力曲线的锚点：到 ANCHOR 人时，压力走完 CAP 的 SATURATION。
const CROWD_PRESSURE_ANCHOR := 100
const CROWD_PRESSURE_SATURATION := 0.86


## 车轮战里“其余人”的合计战力。
##
## 用平方和开根（RMS 口径）而不是直接求和：擂主是挨个单挑过去的，
## 一个 2 亿 token 的对手造成的威胁远大于两个 1 亿的，
## 平方和正好刻画了这种“单点强度”的差别，胜率曲线才对得上真实难度。
static func aggregate_power(powers: Array[int]) -> int:
	var sum_of_squares := 0.0
	for power in powers:
		# 负战力当 0 处理，脏数据不至于把开方搞崩。
		var value := float(maxi(0, power))
		sum_of_squares += value * value
	return int(round(sqrt(sum_of_squares)))


## 挑战者的人均战力（RMS 口径）。合计是 √(Σx²)，除以 √N 就回到人均，
## 所以“一个大号比两个半大号更难打”这件事在人均口径下照样成立。
static func per_challenger_power(others_power: int, challenger_count: int) -> float:
	if challenger_count <= 0:
		return 0.0
	return float(others_power) / sqrt(float(challenger_count))


## 光是人多就给擂主压下去的那部分目标胜率。一个人时是 0，往后按 log 人数长，封顶。
static func crowd_pressure(challenger_count: int) -> float:
	if challenger_count <= 1:
		return 0.0
	return CROWD_PRESSURE_CAP * tanh(log(float(challenger_count)) / crowd_pressure_log_width())


## 压力曲线的宽度：正好让 ANCHOR 人落在 tanh 的 SATURATION 上。
static func crowd_pressure_log_width() -> float:
	return tanh_log_width(log(float(CROWD_PRESSURE_ANCHOR)), CROWD_PRESSURE_SATURATION)


## 一条以对数为自变量的 tanh 曲线该多宽：让 log_span 之外的那个锚点
## 正好落在 tanh 的 saturation 上。胜率曲线和人数压力曲线是同一道题，
## 各推一遍就会各错一遍，所以只在这里推。
static func tanh_log_width(log_span: float, saturation: float) -> float:
	return log_span / atanh(saturation)


## 擂主的目标胜率 = 人均战力比给的强弱 − 人数压力，再夹回 [30%, 70%]。
##
## 强弱那一项是以 log s 为自变量的 tanh（s = 擂主 / 挑战者人均战力）：
## 中段陡、两头自然饱和。用对数是因为战力比本来就是倍数关系——1 倍到 2 倍和
## 2 倍到 4 倍是同样大的一步，直接拿线性比值会让高战力段挤成一团。
## 锚点在 s = FLOOR 和 s = CEIL 上，各自走完上下限之间的 SATURATION，
## 锚点之外仍单调逼近上下限：再强也只是缓升、再弱也只是缓降，不会一跨线就锁死。
##
## 人数压力是**减项**，所以战力能把人数劣势补回来，但补不满：1v100 里
## 就算人均战力比拉到顶，也只能摸到 MAX_WIN_RATE 减去那份封顶压力。
static func champion_win_rate(champion_power: int, others_power: int, challenger_count: int = 1) -> float:
	# 没有对手 / 擂主没战力这两种退化情形直接给端点，避免除零和 log(0)。
	if others_power <= 0 or challenger_count <= 0:
		return MAX_WIN_RATE
	if champion_power <= 0:
		return MIN_WIN_RATE
	# 人均战力至少按 1 算：整场只有零头 token 的时候不至于除出个天文数字。
	var per_head := maxf(per_challenger_power(others_power, challenger_count), 1.0)
	var ratio := float(champion_power) / per_head
	var mid := (MIN_WIN_RATE + MAX_WIN_RATE) * 0.5
	var half := (MAX_WIN_RATE - MIN_WIN_RATE) * 0.5
	var strength := half * tanh((log(ratio) - win_rate_log_center()) / win_rate_log_width())
	return clampf(mid + strength - crowd_pressure(challenger_count), MIN_WIN_RATE, MAX_WIN_RATE)


## 曲线中心：两个锚点在对数轴上的中点，也就是胜率正好 50% 的战力比。
static func win_rate_log_center() -> float:
	return 0.5 * (log(WIN_RATE_RATIO_FLOOR) + log(WIN_RATE_RATIO_CEIL))


## 曲线宽度：正好让两个锚点落在 tanh 的 ±SATURATION 上。
static func win_rate_log_width() -> float:
	return tanh_log_width(log(WIN_RATE_RATIO_CEIL) - win_rate_log_center(), WIN_RATE_ANCHOR_SATURATION)


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


## 幻影刺杀的触发率，按身份分。
static func assassinate_chance(fighter: Fighter) -> float:
	return ASSASSINATE_CHANCE_CHAMPION if fighter.is_champion else ASSASSINATE_CHANCE_CHALLENGER


## 幻影刺杀的伤害：擂主打到 0 血，挑战者打最大生命的一半。
static func assassinate_damage(attacker: Fighter, defender: Fighter) -> int:
	if attacker.is_champion:
		return maxi(defender.hp, 1)
	return maxi(1, int(round(float(defender.max_hp) * ASSASSINATE_SHARE_CHALLENGER)))


## 潜能激发的生命扣费，至少 1 点。
static func awaken_cost(fighter: Fighter) -> int:
	return maxi(1, int(round(float(fighter.max_hp) * AWAKEN_HP_SHARE)))


## 当前生命严格大于扣费、且带着这张技能，才允许触发潜能激发。
static func can_awaken(fighter: Fighter) -> bool:
	return fighter.stacked_awaken() > 0.0 and fighter.hp > awaken_cost(fighter)


## 标准正态分位数（probit）的三次近似：z ≈ 1.2517x + 0.371x³，x = 2p - 1。
## 拟合区间是 [0.2, 0.8]，而胜率被夹在更窄的 [MIN_WIN_RATE, MAX_WIN_RATE] 里，
## 所以落在拟合区间内侧，不必引入完整的反误差函数。
static func probit(p: float) -> float:
	var x := 2.0 * clampf(p, MIN_WIN_RATE, MAX_WIN_RATE) - 1.0
	return 1.2517 * x + 0.371 * x * x * x


## 一身 agent buff 折算成多少命中当量。每条 buff 自己带着「写的是哪个字段」和
## 「这个字段值多少当量」（SkillCatalog 建它的时候写进去的），所以这里只要
## 取一次值乘一次权重。掷出来的真实数值直接参与，手气好的那一场也会如实计价。
static func agent_buff_hit_value(buffs: Array[SkillDef]) -> float:
	var total := 0.0
	for buff in buffs:
		# 技能牌的权重是 0（它们按张计价，见 CHAMPION_SKILL_EDGE_PER_SKILL），
		# 空技能连 prop 都没有，两种都不参与当量。
		if buff.hit_weight == 0.0 or buff.prop.is_empty():
			continue
		total += float(buff.get(buff.prop)) * buff.hit_weight
	return total


## 人数超过 BASE 之后，人数每翻一番补给擂主的那点命中率，封顶以免极端榜单补穿。
static func champion_crowd_relief(challenger_count: int) -> float:
	if challenger_count <= CHAMPION_CROWD_RELIEF_BASE:
		return 0.0
	var doublings := log(float(challenger_count) / float(CHAMPION_CROWD_RELIEF_BASE)) / log(2.0)
	return minf(CHAMPION_CROWD_RELIEF_PER_DOUBLING * doublings, CHAMPION_CROWD_RELIEF_CAP)


## 把“这场仗擂主该赢多少次”的目标胜率，反解成擂主命中率的偏移量。
##
## 偏移是**第三步**（见 hit_chance 的三步口径）：0 表示双方按各自的命中/闪避算完
## 就此打住，正数表示擂主每次出手更容易打中、挑战者相应更难，两边一加一减。
##
## 先扣掉擂主的两项固有优势（技能张数更多、buff 可能更多），再把“人多时更吃亏”
## 那一点补回来，算完才是真正的五五开；然后按目标胜率的正态分位左右挪 WIN_RATE_SPREAD。
## buff_edge / skill_edge 都是“擂主减去挑战者的平均值”，可正可负，
## 由 WheelWar 按这一场真实发出来的牌现算，不用任何平均值假设。
## 一场仗要掷几十次骰子，命中率上几个百分点就已经是压倒性优势，
## 所以偏移始终是个小数——胜率是靠概率调出来的，不是锁出来的。
static func champion_steer(win_rate: float, buff_edge: float = 0.0, skill_edge: float = 0.0, challenger_count: int = 0) -> float:
	var handicap := CHAMPION_SKILL_EDGE_PER_SKILL * skill_edge + AGENT_BUFF_HIT_EDGE * buff_edge - champion_crowd_relief(challenger_count)
	return probit(win_rate) * WIN_RATE_SPREAD - handicap


## 攻方命中加成减守方闪避的净差。正数表示攻方在这一击上占优。
## extra_accuracy 是这一次出手的额外命中（潜能激发），不写进常驻 stacked。
static func net_hit_edge(attacker: Fighter, defender: Fighter, extra_accuracy: float = 0.0) -> float:
	return attacker.stacked_accuracy() + extra_accuracy - defender.stacked_dodge()


## 净差折算成命中率，还没算胜率偏移。
##
## 净差为负就从基础命中里一比一扣；为正则**往必中方向补**：把“还差多少到 100%”
## 按 净差 / FULL_HIT_EDGE 的比例填掉，净差满 FULL_HIT_EDGE 就是必中。
## 这条曲线是刻意不对称的——堆命中堆到压过对方闪避，就该看得见回报，
## 而不是像以前那样先被夹在 95% 上、超出的加成全打水漂。
static func hit_chance_before_steer(net_edge: float) -> float:
	if net_edge <= 0.0:
		return BASE_HIT_CHANCE + net_edge
	return BASE_HIT_CHANCE + (1.0 - BASE_HIT_CHANCE) * minf(net_edge / FULL_HIT_EDGE, 1.0)


## 胜率偏移在这一击上还剩多少话语权。净差为负或为零时说了全算；净差越往上走
## 越轮不到它说话，满 FULL_HIT_EDGE 时归零。
##
## 有这条权重，「必中是自己堆出来的、战力差撼不动」才是**连着成立**的：
## 早先的写法是净差跨过 FULL_HIT_EDGE 就整段跳过偏移，于是净差 19.9% 配一个
## −0.30 的偏移只有 70%，再往上挪 0.1 个百分点就直接 100%，中间是一道断崖。
static func steer_weight(net_edge: float) -> float:
	if net_edge <= 0.0:
		return 1.0
	return maxf(0.0, 1.0 - net_edge / FULL_HIT_EDGE)


## 单次攻击的命中率，三步走：
##   1. 双方都从 BASE_HIT_CHANCE 起步；
##   2. 加上自己的命中加成、减去对方的闪避，走 hit_chance_before_steer 的曲线；
##   3. 再叠上这一场的胜率偏移（擂主加、挑战者减），按 steer_weight 打折后生效。
##
## 上轨取「95% 和自己这条曲线算出来的值之中更高的那个」：光靠战力差顶多推到
## MAX_HIT_CHANCE，推不出必中；而净差满 FULL_HIT_EDGE 挣来的那个 100%，
## 偏移的权重此时已经是 0，谁也拿不走。
##
## 凌波微步不在这条算式里——它是挨打时另掷一次的被动，见 _one_strike。
static func hit_chance(attacker: Fighter, defender: Fighter, champion_steer_amount: float, extra_accuracy: float = 0.0) -> float:
	var net_edge := net_hit_edge(attacker, defender, extra_accuracy)
	var earned := hit_chance_before_steer(net_edge)
	var steer := champion_steer_amount if attacker.is_champion else -champion_steer_amount
	return clampf(earned + steer * steer_weight(net_edge), MIN_HIT_CHANCE, maxf(MAX_HIT_CHANCE, earned))


## 掷一次概率骰。**全场所有概率判定都必须走这里**，因为它守着一条硬约束：
## 概率为 0 时一次骰子也不掷。白掷一次会让这一场后面所有点数整体错位，
## 定种子测试和蒙特卡洛标定出来的胜率会一起失效。
## 顺带把 chance 收成一个值——以前写成 `x.stacked_y() > 0.0 and rng.randf() < x.stacked_y()`，
## 同一份加总要走两遍技能表。
static func _rolls(rng: RollSource, chance: float) -> bool:
	if chance <= 0.0:
		return false
	return rng.randf() < chance


## 结算一名角色的一次行动：先跑中毒掉血，再判定麻痹 / 治疗 / 混乱，
## 最后才真正出手。返回这次行动产生的全部战报事件。
static func resolve_action(actor: Fighter, defender: Fighter, champion_steer_amount: float, rng: RollSource) -> Array[StrikeResult]:
	var events: Array[StrikeResult] = []
	# 自己的新行动开始，上一手治疗留下的 100% 闪避到此结束。
	actor.heal_guard = false
	# 中毒先掉血，毒死了这一步就结束，连手都出不了。
	if actor.poison_turns > 0:
		events.append(_resolve_poison_tick(actor))
		if not actor.is_alive():
			return events
	# 麻痹：整个行动跳过，回合数减一。
	if actor.paralyze_turns > 0:
		actor.paralyze_turns -= 1
		events.append(_skip_event(actor, StrikeResult.SKIP_PARALYZE))
		return events
	# 治疗：触发则回血、不进攻，并进入 100% 闪避直到下一次行动。
	if actor.has_heal() and _rolls(rng, heal_chance(actor)):
		var healed := actor.apply_heal(heal_amount(actor))
		actor.heal_guard = true
		var heal_event := _skip_event(actor, StrikeResult.SKIP_HEAL)
		heal_event.treated = true
		heal_event.heal_amount = healed
		events.append(heal_event)
		return events
	var target := defender
	var self_hit := false
	# 混乱：有一半概率把这一手打到自己身上。
	if actor.confuse_turns > 0:
		actor.confuse_turns -= 1
		if _rolls(rng, CONFUSE_SELF_HIT_CHANCE):
			target = actor
			self_hit = true
	# 打自己时连击和反击都不该发生，这两条 resolve_strikes 自己按 defender != attacker 拦着。
	var strikes := resolve_strikes(actor, target, champion_steer_amount, rng)
	for strike in strikes:
		strike.self_hit = self_hit
		# 自伤时挨打方就是自己，战报里要写对名字。
		if self_hit:
			strike.defender_name = actor.username
	events.append_array(strikes)
	return events


## 一次出手的完整结算：潜能激发 → 首击 →（二连 / 三连追击）→ 对方反击。
##
## is_counter=true 表示这一手本身就是反击：既不再引发反击的反击，也不许掷连击，
## 于是连击只会从主动出手里长出来，不会在反击链上继续滚雪球。
static func resolve_strikes(
	attacker: Fighter,
	defender: Fighter,
	champion_steer_amount: float,
	rng: RollSource,
	is_counter: bool = false,
) -> Array[StrikeResult]:
	var events: Array[StrikeResult] = []
	var extra_hit := 0.0
	var extra_crit := 0.0
	var extra_damage := 0.0
	var awakened := false
	var paid := 0
	# 潜能激发只在主动出手上掷；反击和追击都不另开一轮。
	if not is_counter and can_awaken(attacker) and _rolls(rng, AWAKEN_CHANCE):
		paid = awaken_cost(attacker)
		attacker.apply_damage(paid)
		awakened = true
		extra_hit = AWAKEN_HIT_BONUS
		extra_crit = AWAKEN_CRIT_BONUS
		extra_damage = AWAKEN_DAMAGE_BONUS
	# extra_index=0 标记这是首击。追击和反击都不许再掷连击类（含幻影刺杀 / 凌波微步）。
	var first := _one_strike(attacker, defender, champion_steer_amount, rng, 0, not is_counter, extra_hit, extra_crit, extra_damage)
	if awakened:
		first.awakened = true
		first.awaken_cost = paid
	events.append(first)
	# 打空、把人打死了、或者这一手是打自己，都不进连击。
	if not is_counter and first.hit and (not first.defender_died) and defender != attacker:
		for i in range(_roll_extra_strikes(attacker, rng)):
			if not defender.is_alive():
				break
			# 追击同样要过命中判定，连击只是多给机会，不是保证打中。
			# allow_techniques=false：追击不再掷任何连击类。
			events.append(_one_strike(attacker, defender, champion_steer_amount, rng, i + 1, false, extra_hit, extra_crit, extra_damage))
	# 反击：凌波微步在未成击时也还一下；普通反击只看首击有没有打中。
	# 挨打的人得还站着。打自己时没有“对方”，也就没有反击。
	var should_counter := false
	if not is_counter and defender != attacker and defender.is_alive():
		if first.lingbo:
			should_counter = true
		elif first.hit and _rolls(rng, defender.stacked_counter()):
			should_counter = true
	if should_counter:
		# 反击既不能再反击，也不能掷连击：只还一下。
		var counters := resolve_strikes(defender, attacker, champion_steer_amount, rng, true)
		for counter in counters:
			counter.countered = true
		events.append_array(counters)
	return events


## 首击命中后追加几下。三连和二连各掷各的，可同时成功：
## 名字次数之和再共享一次首击（2+3=5），所以一次出手最多打五下。
static func _roll_extra_strikes(attacker: Fighter, rng: RollSource) -> int:
	var named := 0
	if _rolls(rng, attacker.stacked_triple()):
		named += 3
	if _rolls(rng, attacker.stacked_double()):
		named += 2
	if named <= 0:
		return 0
	return named - 1


## 中毒的每回合掉血。攻守双方都记成中毒者自己，战报才知道这不是谁打的。
static func _resolve_poison_tick(actor: Fighter) -> StrikeResult:
	var tick := StrikeResult.new()
	tick.attacker_name = actor.username
	tick.defender_name = actor.username
	tick.attacker_is_champion = actor.is_champion
	tick.poison_tick = true
	tick.hit = true
	# 按“半次普通命中”掉血，至少 1 点。
	tick.damage = maxi(1, int(round(float(strike_damage(actor)) * POISON_TICK_SHARE)))
	actor.apply_damage(tick.damage)
	actor.poison_turns -= 1
	# 毒死也能触发浴火重生。
	tick.revived = actor.try_rebirth()
	tick.defender_hp_after = actor.hp
	tick.defender_died = not actor.is_alive()
	return tick


## 麻痹 / 治疗导致整个行动被跳过时的占位事件，reason 决定战报怎么写。
static func _skip_event(actor: Fighter, reason: String) -> StrikeResult:
	var result := StrikeResult.new()
	result.attacker_name = actor.username
	result.defender_name = actor.username
	result.attacker_is_champion = actor.is_champion
	result.skip_reason = reason
	result.defender_hp_after = actor.hp
	result.attacker_hp_after = actor.hp
	return result


## 一次单独的挥击：命中判定 →（幻影刺杀 / 治疗闪避 / 凌波微步）→ 绝对防御 →（秒杀 / 伤害）→ 吸血 → 复活 → 挂状态。
##
## allow_techniques 只在主动首击上为真。追击和反击都不许再掷幻影刺杀、凌波微步。
## extra_* 是潜能激发给这一串出手的临时加成。
static func _one_strike(
	attacker: Fighter,
	defender: Fighter,
	champion_steer_amount: float,
	rng: RollSource,
	extra_index: int,
	allow_techniques: bool = true,
	extra_accuracy: float = 0.0,
	extra_crit: float = 0.0,
	extra_damage: float = 0.0,
) -> StrikeResult:
	var result := StrikeResult.new()
	result.attacker_name = attacker.username
	result.defender_name = defender.username
	result.attacker_is_champion = attacker.is_champion
	# extra_index 大于 0 就是连击追加出来的那几下。
	result.combo = extra_index > 0
	result.extra_index = extra_index

	var chance := hit_chance(attacker, defender, champion_steer_amount, extra_accuracy)
	var roll := rng.randf()
	# 幻影刺杀在命中骰之后掷，这样“本会闪掉的点数”仍然进队列，测试能证明它无视闪避。
	var assassinated := false
	if allow_techniques and attacker != defender and attacker.stacked_assassinate() > 0.0 and _rolls(rng, assassinate_chance(attacker)):
		assassinated = true
	# 治疗留下的 100% 闪避：普通挥击全部当闪避，不走凌波微步；幻影刺杀仍能打中。
	if not assassinated and defender.heal_guard:
		result.dodged = true
		result.defender_hp_after = defender.hp
		result.attacker_hp_after = attacker.hp
		result.defender_died = not defender.is_alive()
		return result
	# 凌波微步：非追击挥击打来时掷中，本下记为闪避并稍后还击。刺杀已中则无视闪避，不再掷。
	if not assassinated and allow_techniques and attacker != defender and _rolls(rng, defender.stacked_lingbo()):
		result.dodged = true
		result.lingbo = true
		result.defender_hp_after = defender.hp
		result.attacker_hp_after = attacker.hp
		result.defender_died = not defender.is_alive()
		return result
	if not assassinated and roll >= chance:
		# 没打中只有闪避，没有失手。凌波微步走上面的分支。
		result.dodged = true
		result.defender_hp_after = defender.hp
		result.attacker_hp_after = attacker.hp
		result.defender_died = not defender.is_alive()
		return result
	result.hit = true

	# 绝对防御：打中了但伤害归零，不挂中毒/麻痹/混乱，也不吸血。
	# 每一次打中的挥击都掷一次——首击、连击追击、反击、混乱自伤，以及幻影刺杀：
	# 刺杀无视的是**闪避**，不是防御，所以它掷中之后仍要过这一关。
	if _rolls(rng, defender.stacked_guard()):
		result.guarded = true
		result.damage = 0
		result.defender_hp_after = defender.hp
		result.attacker_hp_after = attacker.hp
		return result

	if assassinated:
		result.assassinated = true
		# 擂主秒杀打到 0 血；挑战者打最大生命的一半。再走浴火重生。
		result.damage = assassinate_damage(attacker, defender)
		defender.apply_damage(result.damage)
		result.revived = defender.try_rebirth()
		result.defender_hp_after = defender.hp
		result.attacker_hp_after = attacker.hp
		result.defender_died = not defender.is_alive()
		_apply_on_hit_status(attacker, defender, rng, result)
		return result

	# 伤害：基准值 →（暴击 ×2）→ 增伤 → 对方减伤。
	var damage := float(strike_damage(defender))
	var crit_chance := attacker.stacked_crit() + extra_crit
	if _rolls(rng, crit_chance):
		result.crit = true
		damage *= CRIT_MULTIPLIER
	damage *= 1.0 + attacker.stacked_damage_bonus() + extra_damage
	damage *= 1.0 - defender.stacked_damage_reduction()
	# 至少打掉 1 点，减伤再高也不会变成挠痒痒。
	result.damage = maxi(1, int(round(damage)))
	defender.apply_damage(result.damage)
	if attacker.has_lifesteal() and attacker != defender:
		# 先把这一击折算成“相当于自己的多少次普通命中”，再按比例回血，
		# 否则打小号造成的伤害换算到自己那条长血条上会是笔巨款。
		var scale := float(strike_damage(attacker)) / float(maxi(1, strike_damage(defender)))
		var stolen := maxi(1, int(round(float(result.damage) * lifesteal_ratio(attacker) * scale)))
		result.heal_amount = attacker.apply_heal(stolen)
		# 血满了就吸不进去，这时候不算触发吸血。
		result.lifesteal = result.heal_amount > 0
	# 掉到 0 血时试一次浴火重生，成功就不算死。
	result.revived = defender.try_rebirth()
	result.defender_hp_after = defender.hp
	result.attacker_hp_after = attacker.hp
	result.defender_died = not defender.is_alive()
	_apply_on_hit_status(attacker, defender, rng, result)
	return result


## 命中之后逐个掷骰，看是否挂上中毒 / 麻痹 / 混乱。
static func _apply_on_hit_status(attacker: Fighter, defender: Fighter, rng: RollSource, result: StrikeResult) -> void:
	# 混乱自伤时不给自己上状态。
	if attacker == defender:
		return
	for status in ON_HIT_STATUSES:
		if not _rolls(rng, attacker.stacked(str(status[0]))):
			continue
		defender.set(str(status[1]), status[2])
		var flag := str(status[3])
		if not flag.is_empty():
			result.set(flag, true)
