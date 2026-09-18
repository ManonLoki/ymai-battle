class_name StrikeResult
extends RefCounted

## 一次判定产生的战报事件。结算器只负责把发生了什么填进来，
## 动画（battle.gd）和文案（CombatLog）各自读自己关心的字段。

var attacker_name: String = ""
var defender_name: String = ""
var attacker_is_champion: bool = false
var hit: bool = false
var dodged: bool = false
var crit: bool = false
var combo: bool = false
var damage: int = 0
var defender_hp_after: int = 0
var defender_died: bool = false
var skill_id: String = "none"
var skill_name: String = ""
var guarded: bool = false
var revived: bool = false
var countered: bool = false
var self_hit: bool = false
var poisoned: bool = false
var paralyzed: bool = false
var confused: bool = false
var rooted: bool = false
var poison_tick: bool = false
var skipped: String = ""
var extra_index: int = 0
var heal_amount: int = 0
var lifesteal: bool = false
var treated: bool = false
var attacker_hp_after: int = 0
var burst_count: int = 0
