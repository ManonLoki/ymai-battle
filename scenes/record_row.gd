class_name RecordRow
extends HBoxContainer

## 战绩榜的一行：名次徽章 + 玩家名 + 胜场。
##
## 字号、间距、对齐、描边全摆在 record_row.tscn 里，编辑器改一次就够；
## 这里只做一件事：按名次决定亮哪块徽章、名字染什么色。
## 奖牌和纯数字名次是场景里两个固定节点，切显示而不是现搭控件——
## 两者同宽，所以第四名往后每行文字仍然对得齐。

@onready var medal: TextureRect = $Medal
@onready var rank_number: Label = $RankNumber
@onready var name_label: Label = $NameLabel
@onready var wins_label: Label = $WinsLabel


## 填一行。先 add_child 再调它，@onready 才拿得到节点。
func bind(rank: int, username: String, wins: int) -> void:
	var has_medal := ThemeHelper.has_medal(rank)
	medal.visible = has_medal
	medal.texture = ThemeHelper.medal_texture(rank)
	rank_number.visible = not has_medal
	rank_number.text = str(rank)
	name_label.text = "【%s】" % username
	# 前三名的名字跟着奖牌染色；之后的去掉覆盖，回到场景里的正文色。
	if has_medal:
		name_label.add_theme_color_override("font_color", ThemeHelper.medal_color(rank))
	else:
		name_label.remove_theme_color_override("font_color")
	wins_label.text = "%d 场" % wins
