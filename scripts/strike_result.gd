class_name StrikeResult
extends RefCounted

## 一次判定产生的战报事件。结算器只负责把发生了什么填进来，
## 动画（battle.gd）和文案（CombatLog）各自读自己关心的字段。
##
## 一次“行动”可能产出多条：中毒掉血、连击的每一下、对方的反击各算一条。

## 出手方的名字；中毒 / 麻痹这类自身事件里填的是当事人自己。
## skip_reason 的两个取值。写和读都走常量，免得两头各拼一次字符串。
const SKIP_PARALYZE := "paralyze"
const SKIP_ROOT := "root"

var attacker_name: String = ""
## 挨打方的名字；自伤（混乱）时会被改写成出手方自己。
var defender_name: String = ""
## 出手方是不是擂主。battle.gd 靠它决定动画播在左边还是右边。
var attacker_is_champion: bool = false
## 是否打中。没打中时只有闪避或凌波微步，没有失手。
var hit: bool = false
## 没打中且是被对方闪避挡下的（含普通闪避；凌波微步也会把这个标上）。
var dodged: bool = false
## 这一下触发了幻影刺杀：无视闪避，把对方打到 0 血后再结算浴火重生。
var assassinated: bool = false
## 这一下被凌波微步闪掉，随后会跟一条反击。
var lingbo: bool = false
## 是否暴击。
var crit: bool = false
## 这一下是不是连击追加出来的（首击为 false）。
var combo: bool = false
## 本次实际造成的伤害，已经算进减伤和绝对防御。
var damage: int = 0
## 挨打方结算后的剩余血量，给血条用。
var defender_hp_after: int = 0
## 挨打方是否在这一下倒下（复活成功时为 false）。
var defender_died: bool = false
## 被绝对防御挡下，伤害归零。
var guarded: bool = false
## 倒下瞬间触发了“浴火重生”，已满血站起来。
var revived: bool = false
## 这一下是对方的反击，不是主动出手。
var countered: bool = false
## 混乱状态下打到了自己。
var self_hit: bool = false
## 这一下给对方挂上了中毒。
var poisoned: bool = false
## 这一下给对方挂上了麻痹。
var paralyzed: bool = false
## 这一下给对方挂上了混乱。
var confused: bool = false
## 这条事件是中毒的每回合掉血，不是谁打的。
var poison_tick: bool = false
## 本次行动被跳过的原因，空串表示正常行动。取值只有下面两个常量。
var skip_reason: String = ""
## 连击序号：0 是首击，1、2 是追加出来的。
var extra_index: int = 0
## 出手方这一下回了多少血（吸血或治疗），0 表示没回。
var heal_amount: int = 0
## heal_amount 来自吸血（而不是治疗技能）。
var lifesteal: bool = false
## heal_amount 来自治疗技能。
var treated: bool = false
## 出手方结算后的剩余血量，回血时血条要跟着动。
var attacker_hp_after: int = 0
## 这一连串出手一共打了几下，由 CombatLog.annotate 回填到首击上。
var burst_count: int = 0
