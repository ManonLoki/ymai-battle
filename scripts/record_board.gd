class_name RecordBoard
extends RefCounted

## 右侧“今日榜一战绩”那块板子：今天打了几场，以及每位上过榜一的玩家各赢了几场。
## 纯控件构建，输入只有一个 RoundRecord——和演出、战斗判定都没有关系，
## 所以从 battle.gd 里拆出来单独放，改徽章样式不用碰播放逻辑。

## 奖牌徽章的直径，圆角取一半就是正圆。
const BADGE_PX := 22
## 徽章里名次数字的字号。
const BADGE_FONT_PX := 13
## 一行（名字、胜场）的字号。
const ROW_FONT_PX := 16


## 重建整块榜单。前三名挂金银铜牌，没赢过的也留在榜上（0 场），
## 因为他确实当过榜一。
static func refresh(list: Node, record: RoundRecord) -> void:
	NodeUtil.clear_children(list)
	var rows := record.standings()
	# 当天第一场（或者刚跨天）时榜是空的，放一句占位。
	if rows.is_empty():
		list.add_child(_readable_label("还没有人打完一场", ThemeHelper.MUTED, 15))
		return
	for i in range(rows.size()):
		list.add_child(_row(i + 1, rows[i]))


## 榜单标题：今天一共打了几场。
static func title_text(record: RoundRecord) -> String:
	return "今日榜一战绩 · 共 %d 场" % record.rounds


## 顶部的场次文字。正在打的这一场还没记进去，所以显示 rounds + 1。
static func round_text(record: RoundRecord) -> String:
	return "今日第 %d 场" % maxi(1, record.rounds + 1)


## 一行：奖牌 + 名字 + 胜场。
static func _row(rank: int, row: Dictionary) -> Control:
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 8)
	line.add_child(_medal(rank))
	var name_label := _readable_label("【%s】" % str(row.get("username", "")), _rank_color(rank), ROW_FONT_PX)
	# 名字占满中间，把胜场推到最右。
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.add_child(name_label)
	var wins_label := _readable_label("%d 场" % int(row.get("wins", 0)), ThemeHelper.TEXT, ROW_FONT_PX)
	wins_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	line.add_child(wins_label)
	return line


## 榜单行浮在透明底板上，玩家名、胜场和空榜提示都加深色描边，避免被明亮背景吞掉。
## 徽章数字刻意不走这里：圆形实底已经提供了足够对比度。
static func _readable_label(text: String, color: Color, font_size: int) -> Label:
	var label := ThemeHelper.make_label(text, color, font_size)
	label.add_theme_color_override("font_outline_color", Color(ThemeHelper.BG, 0.96))
	label.add_theme_constant_override("outline_size", 2)
	return label


## 前三名用奖牌色，之后的用普通文字色。
static func _rank_color(rank: int) -> Color:
	return ThemeHelper.medal_color(rank) if ThemeHelper.has_medal(rank) else ThemeHelper.TEXT


## 前三名的金银铜牌。用一个圆底 + 名次数字，不依赖字体里有没有奖牌字符。
static func _medal(rank: int) -> Control:
	var badge := Panel.new()
	badge.custom_minimum_size = Vector2(BADGE_PX, BADGE_PX)
	# 底色和别的控件一样从 ThemeHelper 出，圆片样式也是。
	var bg := ThemeHelper.medal_color(rank) if ThemeHelper.has_medal(rank) else ThemeHelper.CARD
	badge.add_theme_stylebox_override("panel", ThemeHelper.make_circle(bg, BADGE_PX))
	# 名次数字铺满整个圆，居中显示。亮底上用深色字，暗底上用浅灰字。
	var number := ThemeHelper.make_label(
		str(rank),
		ThemeHelper.BG if ThemeHelper.has_medal(rank) else ThemeHelper.MUTED,
		BADGE_FONT_PX,
	)
	number.set_anchors_preset(Control.PRESET_FULL_RECT)
	number.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	number.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	badge.add_child(number)
	return badge
