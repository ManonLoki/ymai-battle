class_name DamageTally
extends RefCounted

## 一场车轮战里，每位挑战者对擂主打出的伤害累计，用来评本场 MVP。
##
## 自伤（混乱状态下打到自己）和中毒掉血不算在任何人头上：前者不是别人的输出，
## 后者事件里只记了中毒的人自己，没留下当初下毒的是谁。

var totals: Dictionary = {}


func add_events(events: Array[StrikeResult]) -> void:
	for event in events:
		if event.attacker_is_champion or not event.hit or event.damage <= 0:
			continue
		if event.poison_tick or event.self_hit or event.attacker_name == event.defender_name:
			continue
		totals[event.attacker_name] = int(totals.get(event.attacker_name, 0)) + event.damage


## 输出最高的挑战者，{"username": String, "damage": int}。
## 并列时取先打出这个伤害的那位（字典按写入顺序遍历，结果是稳定的）。
## 没有人碰到擂主就返回空名字。
func best() -> Dictionary:
	var best_name := ""
	var best_damage := 0
	for key in totals:
		var value := int(totals[key])
		if value > best_damage:
			best_name = str(key)
			best_damage = value
	return {"username": best_name, "damage": best_damage}


## 结果面板和战报共用的一句话。
func mvp_line() -> String:
	var top := best()
	var username := str(top.get("username", ""))
	if username.is_empty():
		return "本场没有挑战者伤到擂主，MVP 空缺"
	return "【%s】获得了本场战斗 MVP，造成了【%s】伤害" % [
		username,
		ThemeHelper.compact(int(top.get("damage", 0))),
	]
