class_name SkillDef
extends Resource

## 一条技能的数值定义。所有字段都是“概率”或“加成比例”，
## 结算时和同名字段相加（见 Fighter._sum），刻意没有任何布尔式的必中 / 必闪开关。
##
## agent buff 和普通技能共用这一个结构：区别只在 id 前缀（buff_ / skill_）
## 和数值是每场随机重掷还是固定值。

## 技能标识，"none" 表示空技能。Fighter._sum 之外的地方都靠它区分。
@export var id: String = "none"
## 图标悬停时显示的技能名。
@export var display_name: String = "无技能"
## 图标悬停时显示的效果说明；agent buff 的这行会在掷数值时重写。
@export var description: String = ""
## 对应 assets/icons/<icon_id>.png，空字符串表示不挂图标。
@export var icon_id: String = ""
## 这条定义写的是下面哪个字段（SkillCatalog 建它时按配置表填），空字符串表示没写任何字段。
## 有了它就不用反过来遍历所有字段猜「这条 buff 到底加的是什么」。
@export var prop: String = ""
## prop 上每 1 点数值折算成多少命中当量，只有 agent buff 有；
## 技能牌按张计价（CombatResolver.CHAMPION_SKILL_EDGE_PER_SKILL），所以留 0。
@export var hit_weight: float = 0.0

## 暴击概率，命中后单独掷一次，中了伤害 ×CRIT_MULTIPLIER。
@export var crit_chance: float = 0.0
## 闪避加成，从对方的命中率里直接扣掉。
@export var dodge_bonus: float = 0.0
## 命中加成，直接加到自己的命中率上。
@export var accuracy_bonus: float = 0.0
## 增伤比例，按 ×(1 + 值) 作用在伤害上。
@export var damage_bonus: float = 0.0
## 减伤比例，按 ×(1 - 值) 作用在自己挨的伤害上；总和封顶 90%。
@export var damage_reduction: float = 0.0
## 首击命中后额外再出手一次的概率。
@export var double_chance: float = 0.0
## 首击命中后额外再出手两次的概率，和 double 各掷各的，可以叠加。
@export var triple_chance: float = 0.0
## 主动出手每一刀上，无视闪避触发幻影刺杀的概率（真正掷骰看结算器的身份分率）。
@export var assassinate_chance: float = 0.0
## 主动进攻的每一刀被打时，闪避并立刻还击一次的概率（还手本身不再掷）。
@export var lingbo_chance: float = 0.0
## 主动进攻的每一刀被打时，把本次挥击和附加效果反弹给对方的概率。
@export var reflect_chance: float = 0.0
## 命中后打断对方下一次行动的概率。
@export var root_chance: float = 0.0
## 命中后使对方中毒的概率，中毒会持续掉血。
@export var poison_chance: float = 0.0
## 命中后使对方麻痹（跳过行动）的概率。
@export var paralyze_chance: float = 0.0
## 命中后使对方混乱（有一半几率打自己）的概率。
@export var confuse_chance: float = 0.0
## 挨打时触发“伤害归零”的概率，只免这一次。
@export var guard_chance: float = 0.0
## 被命中后立刻反击一次的概率。
@export var counter_chance: float = 0.0
## 出手时触发治疗的概率（实际概率按身份在 CombatResolver 里定）；触发则不进攻。
@export var heal_chance: float = 0.0
## 主动出手时触发潜能激发的概率；当前生命不够付费时不掷。
@export var awaken_chance: float = 0.0
## 死亡时满血复活一次，仅此一次。
@export var rebirth: bool = false
## 命中后按伤害比例回血。
@export var lifesteal: bool = false
