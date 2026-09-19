class_name ThemeHelper
extends RefCounted

## 全局配色、字体和按钮样式，让三个场景保持同一套观感。

## 全局中文字体。三个场景的 Theme 和运行时新建的 Label 都用它。
const UI_FONT := preload("res://assets/fonts/NotoSansSC-Regular.woff2")

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

## 焦点框的描边宽度。电视上没有鼠标，全靠它看清选中项，所以要粗。
const FOCUS_BORDER := 3
## 主按钮的最小尺寸。
const BUTTON_MIN_SIZE := Vector2(220, 48)
## 次级“返回”按钮的最小尺寸，比主按钮小一圈。各场景套完 style_button 再盖这个。
const BACK_BUTTON_MIN_SIZE := Vector2(120, 40)
## 战绩榜上挂奖牌的名次上限，medal_color 的分档也按它来。
const MEDAL_RANKS := 3

## 这个名次有没有奖牌。挑底色、字色的地方都问它，
## 免得每个调用方各自记一遍“前三名”这个边界。
static func has_medal(rank: int) -> bool:
	return rank <= MEDAL_RANKS


## 战绩榜前三的奖牌色，第 1/2/3 名分别是金银铜；之后的没有牌。
static func medal_color(rank: int) -> Color:
	match rank:
		1: return GOLD
		2: return SILVER
		3: return BRONZE
		_: return MUTED


## 给一棵控件子树套上统一字体。Theme 会往下继承，所以只要套在根上。
static func apply(control: Control, font_size: int = 18) -> void:
	var theme := Theme.new()
	theme.default_font = UI_FONT
	theme.default_font_size = font_size
	control.theme = theme


## 一块纯色圆角底。按钮和面板都从它派生。
static func make_flat(color: Color, radius: int = 8) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = color
	box.set_corner_radius_all(radius)
	# 文字和边框之间留点空隙，不然贴边很难看。
	box.content_margin_left = 12
	box.content_margin_right = 12
	box.content_margin_top = 8
	box.content_margin_bottom = 8
	return box


## 一个纯色圆片：圆角开到边长的一半，且不留内边距。
## 奖牌徽章这类“只有一个居中数字”的小圆用它——make_flat 的内边距会把它撑成椭圆。
static func make_circle(color: Color, diameter: int) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = color
	box.set_corner_radius_all(diameter / 2)
	return box


## 焦点框。电视上没有鼠标，全靠它看清“现在选中的是哪一个”，所以描边要粗要亮。
static func make_focus(radius: int = 10) -> StyleBoxFlat:
	# 全透明底 + draw_center=false：只画一圈框，不盖住按钮本来的颜色。
	var box := make_flat(Color(0, 0, 0, 0), radius)
	box.draw_center = false
	box.set_border_width_all(FOCUS_BORDER)
	box.border_color = GOLD
	# 往外扩同样的宽度，框就落在按钮外沿而不是压在上面。
	box.set_expand_margin_all(FOCUS_BORDER)
	return box


## 统一的按钮样式。filled=true 是主按钮（实心主色），false 是次级按钮（描边）。
static func style_button(button: Button, filled: bool = true) -> void:
	button.custom_minimum_size = BUTTON_MIN_SIZE
	# 电视上靠方向键选按钮，必须能拿焦点。
	button.focus_mode = Control.FOCUS_ALL
	button.add_theme_stylebox_override("focus", make_focus(10))
	if filled:
		button.add_theme_stylebox_override("normal", make_flat(ACCENT, 10))
		button.add_theme_stylebox_override("hover", make_flat(ACCENT.lightened(0.12), 10))
		button.add_theme_stylebox_override("pressed", make_flat(ACCENT.darkened(0.12), 10))
		# 主色底上用深色字，三种状态都要单独盖一次。
		for state in ["font_color", "font_hover_color", "font_pressed_color"]:
			button.add_theme_color_override(state, BG)
	else:
		var box := make_flat(CARD, 10)
		box.set_border_width_all(1)
		box.border_color = ACCENT
		button.add_theme_stylebox_override("normal", box)
		button.add_theme_color_override("font_color", TEXT)


## 次级“返回”按钮。style_button 会盖上主按钮的最小尺寸，所以必须紧跟着改回来——
## 把这两步绑在一起，新加的页面就不会只抄走前半句。
static func style_back_button(button: Button) -> void:
	style_button(button, false)
	button.custom_minimum_size = BACK_BUTTON_MIN_SIZE


## 运行时现造的 Label。四个场景都要按“文字 + 颜色 + 字号”造一堆，
## 主题覆盖的键名只在这里写一次。font_size 传 0 表示跟随父级主题。
static func make_label(text: String, color: Color, font_size: int = 0) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_color_override("font_color", color)
	if font_size > 0:
		label.add_theme_font_size_override("font_size", font_size)
	return label
