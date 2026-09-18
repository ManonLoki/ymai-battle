class_name ThemeHelper
extends RefCounted

## 全局配色、字体和按钮样式，让三个场景保持同一套观感。

const UI_FONT := preload("res://assets/fonts/NotoSansSC-Regular.woff2")

const BG := Color("0d1117")
const PANEL := Color("161b22")
const CARD := Color("21262d")
const ACCENT := Color("58a6ff")
const TEXT := Color("e6edf3")
const MUTED := Color("8b949e")
const DANGER := Color("f85149")
const OK_GREEN := Color("3fb950")
const GOLD := Color("d4a017")
const SILVER := Color("c0c8d0")
const BRONZE := Color("b87333")

## 战绩榜前三的奖牌色，第 1/2/3 名分别是金银铜；之后的没有牌。
static func medal_color(rank: int) -> Color:
	match rank:
		1: return GOLD
		2: return SILVER
		3: return BRONZE
		_: return MUTED


static func apply(control: Control, font_size: int = 18) -> void:
	var theme := Theme.new()
	theme.default_font = UI_FONT
	theme.default_font_size = font_size
	control.theme = theme


static func make_flat(color: Color, radius: int = 8) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = color
	box.corner_radius_top_left = radius
	box.corner_radius_top_right = radius
	box.corner_radius_bottom_left = radius
	box.corner_radius_bottom_right = radius
	box.content_margin_left = 12
	box.content_margin_right = 12
	box.content_margin_top = 8
	box.content_margin_bottom = 8
	return box


## 焦点框。电视上没有鼠标，全靠它看清“现在选中的是哪一个”，所以描边要粗要亮。
static func make_focus(radius: int = 10) -> StyleBoxFlat:
	var box := make_flat(Color(0, 0, 0, 0), radius)
	box.draw_center = false
	box.border_width_left = 3
	box.border_width_top = 3
	box.border_width_right = 3
	box.border_width_bottom = 3
	box.border_color = GOLD
	box.expand_margin_left = 3
	box.expand_margin_top = 3
	box.expand_margin_right = 3
	box.expand_margin_bottom = 3
	return box


static func style_button(button: Button, filled: bool = true) -> void:
	button.custom_minimum_size = Vector2(220, 48)
	button.focus_mode = Control.FOCUS_ALL
	button.add_theme_stylebox_override("focus", make_focus(10))
	if filled:
		button.add_theme_stylebox_override("normal", make_flat(ACCENT, 10))
		button.add_theme_stylebox_override("hover", make_flat(ACCENT.lightened(0.12), 10))
		button.add_theme_stylebox_override("pressed", make_flat(ACCENT.darkened(0.12), 10))
		button.add_theme_color_override("font_color", Color("0d1117"))
		button.add_theme_color_override("font_hover_color", Color("0d1117"))
		button.add_theme_color_override("font_pressed_color", Color("0d1117"))
	else:
		var box := make_flat(CARD, 10)
		box.border_width_left = 1
		box.border_width_top = 1
		box.border_width_right = 1
		box.border_width_bottom = 1
		box.border_color = ACCENT
		button.add_theme_stylebox_override("normal", box)
		button.add_theme_color_override("font_color", TEXT)


## 紧凑写法的进位表，从大到小匹配。
const COMPACT_UNITS := [
	[1000000000, "B"],
	[1000000, "M"],
	[1000, "K"],
]


## 数字的紧凑写法：按当前大小自动挂 K / M / B，保留两位小数（四舍五入）。
## 1234 → "1.23K"，348431491 → "348.43M"，2500000000 → "2.50B"。
## 不足 1000 的直接原样输出，不补小数点。
static func compact(n: int) -> String:
	var sign_text := "-" if n < 0 else ""
	var value := absi(n)
	for unit in COMPACT_UNITS:
		var step := int(unit[0])
		if value >= step:
			return "%s%.2f%s" % [sign_text, float(value) / float(step), str(unit[1])]
	return sign_text + str(value)


static func with_commas(n: int) -> String:
	var s := str(n)
	var out := ""
	for i in range(s.length()):
		if i > 0 and (s.length() - i) % 3 == 0:
			out += ","
		out += s[i]
	return out
