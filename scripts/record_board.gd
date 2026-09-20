class_name RecordBoard
extends RefCounted

## 右侧“今日榜一战绩”那块板子：今天打了几场，以及每位上过榜一的玩家各赢了几场。
## 输入只有一个 RoundRecord——和演出、战斗判定都没有关系，所以从 battle.gd 里
## 拆出来单独放，改榜单不用碰播放逻辑。
##
## 一行长什么样归 record_row.tscn（在编辑器里改），这里只决定摆几行、每行填谁。

## 一行的场景。前三名亮奖牌、之后显示数字名次，都由它自己按名次切换。
const RECORD_ROW := preload("res://scenes/record_row.tscn")


## 重建整块榜单。前三名挂金银铜牌，没赢过的也留在榜上（0 场），
## 因为他确实当过榜一。
static func refresh(list: Node, record: RoundRecord) -> void:
	var empty_label := list.get_node_or_null("RecordEmptyLabel") as Label
	# 空榜提示是场景里的第一个固定子节点，跳过它，只清理上次按数据生成的行。
	NodeUtil.clear_children(list, 1)
	var rows := record.standings()
	# 当天第一场（或者刚跨天）时只显示场景里预置的占位。
	if empty_label != null:
		empty_label.visible = rows.is_empty()
	for i in range(rows.size()):
		var row: RecordRow = RECORD_ROW.instantiate()
		list.add_child(row)
		row.bind(i + 1, str(rows[i].get("username", "")), int(rows[i].get("wins", 0)))


## 榜单标题：今天一共打了几场。
static func title_text(record: RoundRecord) -> String:
	return "今日榜一战绩 · 共 %d 场" % record.rounds


## 顶部的场次文字。正在打的这一场还没记进去，所以显示 rounds + 1。
static func round_text(record: RoundRecord) -> String:
	return "今日第 %d 场" % maxi(1, record.rounds + 1)
