class_name SkillDef
extends Resource

## 一条技能的数值定义。所有字段都是“概率”或“加成比例”，
## 结算时和同名字段相加（见 Fighter._sum），刻意没有任何布尔式的必中 / 必闪开关。

@export var id: String = "none"
@export var display_name: String = "无技能"
@export var description: String = ""
@export var icon_id: String = ""

@export var crit_chance: float = 0.0
@export var dodge_bonus: float = 0.0
@export var accuracy_bonus: float = 0.0
@export var damage_bonus: float = 0.0
@export var damage_reduction: float = 0.0
@export var double_chance: float = 0.0
@export var triple_chance: float = 0.0
@export var root_chance: float = 0.0
@export var poison_chance: float = 0.0
@export var paralyze_chance: float = 0.0
@export var confuse_chance: float = 0.0
@export var guard_chance: float = 0.0
@export var counter_chance: float = 0.0
@export var heal_chance: float = 0.0
## 死亡时满血复活一次，仅此一次。
@export var rebirth: bool = false
## 命中后按伤害比例回血。
@export var lifesteal: bool = false
