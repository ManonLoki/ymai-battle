class_name RecordBoard
extends RefCounted

## 右侧“今日榜一战绩”那块板子：今天打了几场，以及每位上过榜一的玩家各赢了几场。
## 纯控件构建，输入只有一个 RoundRecord——和演出、战斗判定都没有关系，
## 所以从 battle.gd 里拆出来单独放，改徽章样式不用碰播放逻辑。

## 名次列宽度；奖牌与纯数字排名共用，保证每行文字对齐。
const BADGE_PX := 22
## 第四名起名次数字的字号。
const BADGE_FONT_PX := 13
## 一行（名字、胜场）的字号。
const ROW_FONT_PX := 16


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
	if rows.is_empty():
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


## 榜单行浮在透明底板上，玩家名、胜场和空榜提示都要能从明亮背景里读出来。
## 描边本身归 ThemeHelper.style_readable_text，战斗页的战报用的是同一份。
static func _readable_label(text: String, color: Color, font_size: int) -> Label:
	var label := ThemeHelper.make_label(text, color, font_size)
	ThemeHelper.style_readable_text(label)
	return label


## 前三名用奖牌色，之后的用普通文字色。
static func _rank_color(rank: int) -> Color:
	return ThemeHelper.medal_color(rank) if ThemeHelper.has_medal(rank) else ThemeHelper.TEXT


## 前三名显示金银铜奖牌纹理；之后只保留同宽、居中的纯数字名次。
static func _medal(rank: int) -> Control:
	var texture := ThemeHelper.medal_texture(rank)
	if texture != null:
		var medal := TextureRect.new()
		medal.custom_minimum_size = Vector2(BADGE_PX, BADGE_PX)
		medal.texture = texture
		medal.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		medal.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		medal.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		return medal

	var number := _readable_label(str(rank), ThemeHelper.MUTED, BADGE_FONT_PX)
	number.custom_minimum_size = Vector2(BADGE_PX, BADGE_PX)
	number.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	number.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return number
