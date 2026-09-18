class_name CombatLog
extends RefCounted

## 把 StrikeResult 翻译成战报文案。纯展示层，不改动任何战斗状态。


## 给连击的首击标上 burst_count，好让文案写成“瞬间进攻了两次”。
static func annotate(events: Array[StrikeResult]) -> void:
	for i in events.size():
		var event: StrikeResult = events[i]
		if not event.hit or event.extra_index != 0 or event.countered or event.poison_tick or event.skipped != "":
			continue
		var n := 1
		var j := i + 1
		while j < events.size():
			var nxt: StrikeResult = events[j]
			if not nxt.combo or nxt.attacker_name != event.attacker_name or nxt.countered:
				break
			n += 1
			j += 1
		if n >= 2:
			event.burst_count = n


static func line_for(event: StrikeResult) -> String:
	var body := _body(event)
	if event.burst_count >= 2:
		var times := "两" if event.burst_count == 2 else "三"
		var burst := "%s对%s瞬间进攻了【%s】次" % [event.attacker_name, event.defender_name, times]
		if body.is_empty():
			return burst
		return burst + "\n" + body
	return body


## 一整轮事件的逐行文案，按时间正序排列。
static func lines_for(events: Array[StrikeResult]) -> PackedStringArray:
	annotate(events)
	var lines: PackedStringArray = PackedStringArray()
	for event in events:
		var text := line_for(event)
		if text.is_empty():
			continue
		for piece in text.split("\n"):
			if not piece.is_empty():
				lines.append(piece)
	return lines


static func _body(event: StrikeResult) -> String:
	if event.poison_tick:
		var tick := "%s 中毒，损失 %s 生命" % [event.attacker_name, ThemeHelper.compact(event.damage)]
		if event.revived:
			tick += "，浴火重生！"
		elif event.defender_died:
			tick += "，倒下！"
		return tick
	if event.skipped == "paralyze":
		return "%s 麻痹，无法行动" % event.attacker_name
	if event.skipped == "root":
		return "%s 被定身，错过行动" % event.attacker_name
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
	if event.dodged:
		return "%s【闪避】了%s的伤害" % [event.defender_name, event.attacker_name]
	if not event.hit:
		return "%s 失手，没有打中 %s" % [event.attacker_name, event.defender_name]
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
	if chunks.is_empty():
		if event.guarded:
			chunks.append("%s 打中 %s，伤害被全部减免" % [event.attacker_name, event.defender_name])
		else:
			chunks.append("%s对%s造成了伤害" % [event.attacker_name, event.defender_name])
	var line := "\n".join(chunks)
	if event.heal_amount > 0:
		line += "，回复 %s" % ThemeHelper.compact(event.heal_amount)
	if event.revived:
		line += "，浴火重生！"
	elif event.defender_died:
		line += "，击倒！"
	return line
