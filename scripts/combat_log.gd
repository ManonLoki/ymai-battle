class_name CombatLog
extends RefCounted

## 把 StrikeResult 翻译成战报文案。纯展示层，不改动任何战斗状态。

## burst_count 达到这个数才值得单独写一句“瞬间进攻了 N 次”。
const BURST_MIN := 2


## 给连击的首击标上 burst_count，好让文案写成“瞬间进攻了两次”。
static func annotate(events: Array[StrikeResult]) -> void:
	for i in events.size():
		var event: StrikeResult = events[i]
		# 只有“打中了的主动首击”才当一串连击的开头：
		# 追击自己、反击、中毒掉血、被跳过的行动都不算。
		if not event.hit or event.extra_index != 0 or event.countered or event.poison_tick or event.skip_reason != "":
			continue
		# 往后数连续属于同一个人的追击，数出这一串一共几下。
		var n := 1
		var j := i + 1
		while j < events.size():
			var nxt: StrikeResult = events[j]
			if not nxt.combo or nxt.attacker_name != event.attacker_name or nxt.countered:
				break
			n += 1
			j += 1
		if n >= BURST_MIN:
			event.burst_count = n


## 单条事件的战报文字。连击的首击会多顶一行“瞬间进攻了 N 次”。
static func line_for(event: StrikeResult) -> String:
	var body := _body(event)
	if event.burst_count < BURST_MIN:
		return body
	# 2 / 3 / 5 连各写一字；2、3 连沿用原说法。
	var times := "两"
	if event.burst_count == 3:
		times = "三"
	elif event.burst_count == 5:
		times = "五"
	var burst := "%s对%s瞬间进攻了【%s】次" % [event.attacker_name, event.defender_name, times]
	# 首击本身也有话要说（暴击、上状态之类），接在后面。
	return burst if body.is_empty() else burst + "\n" + body


## 事件正文。按“最特殊的情况优先”往下判，命中了才走到最后一段。
static func _body(event: StrikeResult) -> String:
	# 中毒掉血：不是谁打的，单独一句。
	if event.poison_tick:
		var tick := "%s 中毒，损失 %s 生命" % [event.attacker_name, NumberFormat.compact(event.damage)]
		if event.revived:
			tick += "，浴火重生！"
		elif event.defender_died:
			tick += "，倒下！"
		return tick
	# 行动被跳过。
	if event.skip_reason == StrikeResult.SKIP_PARALYZE:
		return "%s 麻痹，无法行动" % event.attacker_name
	if event.skip_reason == StrikeResult.SKIP_HEAL:
		var heal_line := "%s发动【治疗】" % event.attacker_name
		if event.heal_amount > 0:
			heal_line += "，回复 %s" % NumberFormat.compact(event.heal_amount)
		heal_line += "，本回合不进攻"
		return heal_line
	# 混乱下打自己。
	if event.self_hit:
		# 混乱下的自伤同样要过命中和绝对防御判定，不是必定见血。
		if not event.hit:
			return "%s因为【混乱】挥空了" % event.attacker_name
		if event.guarded:
			return "%s因为【混乱】打了自己，伤害被全部减免" % event.attacker_name
		var self_line := "%s因为【混乱】对自己造成了【%s】伤害" % [
			event.attacker_name,
			NumberFormat.compact(event.damage),
		]
		if event.revived:
			self_line += "，浴火重生！"
		elif event.defender_died:
			self_line += "，倒下！"
		return self_line
	# 没打中只有凌波微步和闪避，没有失手。
	if event.lingbo:
		return _awaken_prefix(event) + "%s以【凌波微步】闪避了%s的伤害" % [event.defender_name, event.attacker_name]
	if event.dodged or not event.hit:
		return _awaken_prefix(event) + "%s【闪避】了%s的伤害" % [event.defender_name, event.attacker_name]
	# 打中了。幻影刺杀单独一句；暴击和上状态各写一句，能同时出现。
	var chunks: PackedStringArray = PackedStringArray()
	if event.awakened:
		chunks.append(_awaken_line(event).rstrip("\n"))
	if event.assassinated:
		chunks.append("%s对%s发动【幻影刺杀】" % [event.attacker_name, event.defender_name])
	if event.crit:
		chunks.append("%s对%s造成【暴击】伤害" % [event.attacker_name, event.defender_name])
	var statuses: PackedStringArray = PackedStringArray()
	if event.poisoned:
		statuses.append("中毒")
	if event.paralyzed:
		statuses.append("麻痹")
	if event.confused:
		statuses.append("混乱")
	if statuses.size() > 0:
		chunks.append("%s对%s造成了伤害，%s【%s】了" % [
			event.attacker_name,
			event.defender_name,
			event.defender_name,
			"，".join(statuses),
		])
	# 既没暴击也没上状态，就用一句朴素的描述兜底。
	if chunks.is_empty():
		if event.guarded:
			chunks.append("%s 打中 %s，伤害被全部减免" % [event.attacker_name, event.defender_name])
		else:
			chunks.append("%s对%s造成了伤害" % [event.attacker_name, event.defender_name])
	var line := "\n".join(chunks)
	# 回血、复活、击倒这几个后缀挂在最后。
	if event.heal_amount > 0:
		line += "，回复 %s" % NumberFormat.compact(event.heal_amount)
	if event.revived:
		line += "，浴火重生！"
	elif event.defender_died:
		line += "，击倒！"
	return line


## 闪避类文案前面补一句潜能激发（命中走 chunks，不会走到这里）。
static func _awaken_prefix(event: StrikeResult) -> String:
	if not event.awakened:
		return ""
	return _awaken_line(event)


static func _awaken_line(event: StrikeResult) -> String:
	var line := "%s发动【潜能激发】" % event.attacker_name
	if event.awaken_cost > 0:
		line += "，损失 %s 生命" % NumberFormat.compact(event.awaken_cost)
	return line + "\n"


## 出场介绍里的一个人：“某某（XX 暴击 + YY 命中 · 5 技能）”。
## 开场和“下一位”共用同一份格式，两处写法不会再分叉。
static func roster_line(fighter: Fighter) -> String:
	return "%s（%s · %d 技能）" % [
		fighter.username,
		fighter.agent_buff_text(),
		fighter.skills.size(),
	]


## 车轮战的开场白。
static func opening_line(champion: Fighter, challenger_count: int) -> String:
	return "车轮战开始：%s迎战其余 %d 人" % [roster_line(champion), challenger_count]


## 换人时的那一句。
static func next_up_line(fighter: Fighter) -> String:
	return "下一位：%s" % roster_line(fighter)


## 一场打完的结论。champion_won 为假时 killer 是终结擂主的那位挑战者。
static func outcome_line(champion_name: String, killer_name: String, champion_won: bool) -> String:
	if champion_won:
		return "%s经过艰难的鏖战，终于干掉了所有的挑战者，成为了唯一神" % champion_name
	return "%s在经过多轮鏖战，惜败于%s" % [champion_name, killer_name]


## 结果面板和战报共用的 MVP 那句话。best 是 DamageTally.best() 的结果。
static func mvp_line(best: Dictionary) -> String:
	var username := str(best.get("username", ""))
	# 全场没人碰到擂主（比如擂主一路秒杀），MVP 就空着。
	if username.is_empty():
		return "本场没有挑战者伤到擂主，MVP 空缺"
	return "【%s】获得了本场战斗 MVP，造成了【%s】伤害" % [
		username,
		NumberFormat.compact(int(best.get("damage", 0))),
	]
