class_name ThemeHelper
extends RefCounted

## 全局配色和奖牌表。
##
## **观感本身不在这里**：字体、按钮、输入框、滑块、面板的样式全在
## res://assets/ui_theme.tres 里，由 project.godot 注册成全局主题，
## 场景在编辑器里挑 theme_type_variation 就能套上，不需要任何运行时代码。
## 这份脚本只留两样代码真正还要问的东西：
## 1. 颜色常量——只在“颜色由数据决定”的地方用（报错标红、胜负、奖牌）。
## 2. 奖牌档位表——第几名配什么颜色和哪张图。
##
## 主题里的配色由 tools/bake_ui_theme.gd 从下面这些常量算出来，所以两边不会走散。

## 深色背景（最底层）。
const BG := Color("0d1117")
## 面板底色，比背景亮一档。
const PANEL := Color("161b22")
## 卡片 / 次级按钮底色，再亮一档。
const CARD := Color("21262d")
## 主色，用在主按钮和描边上。
const ACCENT := Color("58a6ff")
## 正文文字色。
const TEXT := Color("e6edf3")
## 次要文字色（说明、表头）。
const MUTED := Color("8b949e")
## 失败 / 报错色。
const DANGER := Color("f85149")
## 胜利色。
const OK_GREEN := Color("3fb950")
## 战绩榜前三的奖牌色。
const GOLD := Color("d4a017")
const SILVER := Color("c0c8d0")
const BRONZE := Color("b87333")

## 战绩榜前三的奖牌图，和上面三种颜色一一对应。
const MEDAL_GOLD := preload("res://assets/icons/medal_gold.png")
const MEDAL_SILVER := preload("res://assets/icons/medal_silver.png")
const MEDAL_BRONZE := preload("res://assets/icons/medal_bronze.png")

## ui_theme.tres 里的 theme_type_variation 名字。场景里是手写字符串（.tscn 只认字面量），
## 烘焙脚本和运行时切换主/次按钮的代码用这几个常量，保证至少代码这一侧不会拼错。
const SECONDARY_BUTTON := &"SecondaryButton"
const MUTED_LABEL := &"MutedLabel"
const READABLE_LABEL := &"ReadableLabel"
const MUTED_READABLE_LABEL := &"MutedReadableLabel"
const GLASS_PANEL := &"GlassPanel"
const RESULT_PANEL := &"ResultPanel"
const DIALOG_PANEL := &"DialogPanel"
const GLASS_LOG := &"GlassLog"

## 战绩榜的奖牌档位，从第一名往下排。**这是唯一一份清单**：
## 有没有牌、什么颜色、配哪张图全从它算，加减档位只改这里。
const MEDALS := [
	{"color": GOLD, "texture": MEDAL_GOLD},
	{"color": SILVER, "texture": MEDAL_SILVER},
	{"color": BRONZE, "texture": MEDAL_BRONZE},
]


## 这个名次有没有奖牌。挑底色、字色、图的地方都问它，
## 免得每个调用方各自记一遍“前三名”这个边界。
static func has_medal(rank: int) -> bool:
	return rank >= 1 and rank <= MEDALS.size()


## 有牌的名次按档次取金银铜；之后的用次要文字色。
static func medal_color(rank: int) -> Color:
	return MEDALS[rank - 1]["color"] if has_medal(rank) else MUTED


## 有牌的名次取对应奖牌图，免得调用方另记一份「第几名配哪张图」的表。
## 没有牌的名次返回 null。
static func medal_texture(rank: int) -> Texture2D:
	return MEDALS[rank - 1]["texture"] if has_medal(rank) else null
