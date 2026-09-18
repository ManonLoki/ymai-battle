class_name CombatLog
extends RefCounted

## 把 StrikeResult 翻译成战报文案。纯展示层，不改动任何战斗状态。

## burst_count 达到这个数才值得单独写一句“瞬间进攻了 N 次”。
const BURST_MIN := 2
## burst_count 到数字的中文写法。一次出手最多三下，所以只需要这两个。
const BURST_WORDS := {2: "两", 3: "三"}


## 给连击的首击标上 burst_count，好让文案写成“瞬间进攻了两次”。
static func annotate(events: Array[StrikeResult]) -> void:
	for i in events.size():
		var event: StrikeResult = events[i]
		# 只有“打中了的主动首击”才当一串连击的开头：
		# 追击自己、反击、中毒掉血、被跳过的行动都不算。
		if not event.hit or event.extra_index != 0 or event.countered or event.poison_tick or event.skipped != "":
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
	var times := str(BURST_WORDS.get(event.burst_count, event.burst_count))
	var burst := "%s对%s瞬间进攻了【%s】次" % [event.attacker_name, event.defender_name, times]
	# 首击本身也有话要说（暴击、上状态之类），接在后面。
	return burst if body.is_empty() else burst + "\n" + body


## 事件正文。按“最特殊的情况优先”往下判，命中了才走到最后一段。
static func _body(event: StrikeResult) -> String:
	# 中毒掉血：不是谁打的，单独一句。
	if event.poison_tick:
		var tick := "%s 中毒，损失 %s 生命" % [event.attacker_name, ThemeHelper.compact(event.damage)]
		if event.revived:
			tick += "，浴火重生！"
		elif event.defender_died:
			tick += "，倒下！"
		return tick
	# 行动被跳过。
	if event.skipped == "paralyze":
		return "%s 麻痹，无法行动" % event.attacker_name
	if event.skipped == "root":
		return "%s 被定身，错过行动" % event.attacker_name
	# 混乱下打自己。
	if event.self_hit:
		# 混乱下的自伤同样要过命中和绝对防御判定，不是必定见血。
		if not event.hit:
			return "%s因为【混乱】挥空了" % event.attacker_name
		if event.guarded:
			return "%s因为【混乱】打了自己，伤害被全部减免" % event.attacker_name
		var self_line := "%s因为【混乱】对自己造成了【%s】伤害" % [
			event.attacker_name,
			ThemeHelper.compact(event.damage),
		]
		if event.revived:
			self_line += "，浴火重生！"
		elif event.defender_died:
			self_line += "，倒下！"
		return self_line
	# 没打中：分“被闪开”和“自己失手”两种写法。
	if event.dodged:
		return "%s【闪避】了%s的伤害" % [event.defender_name, event.attacker_name]
	if not event.hit:
		return "%s 失手，没有打中 %s" % [event.attacker_name, event.defender_name]
	# 打中了。暴击和上状态各写一句，能同时出现。
	var chunks: PackedStringArray = PackedStringArray()
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
		line += "，回复 %s" % ThemeHelper.compact(event.heal_amount)
	if event.revived:
		line += "，浴火重生！"
	elif event.defender_died:
		line += "，击倒！"
	return line
