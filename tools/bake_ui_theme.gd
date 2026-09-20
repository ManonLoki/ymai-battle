extends SceneTree

## 生成 res://assets/ui_theme.tres —— 全项目共用的 UI 主题。
##
## 跑法：Godot --headless --path . --script tools/bake_ui_theme.gd
##
## 主题本身是**编辑器管理的资源**：日常调按钮圆角、面板透明度直接在编辑器里改 .tres。
## 这个脚本只在配色需要重新对齐 ThemeHelper 的颜色常量时跑一次——颜色写进 .tres
## 必须和 ThemeHelper.ACCENT / CARD 等逐位相等（测试会拿它们对比），
## 手写小数会差几个 ULP，所以由代码算出来存，而不是手敲 Color(0.345, ...)。
##
## 字体、按钮、输入框、滑块、面板全在这一份里；场景只挑 theme_type_variation，
## 不再在 _ready 里一句句 add_theme_*_override。

const OUT_PATH := "res://assets/ui_theme.tres"
const FONT_PATH := "res://assets/fonts/NotoSansSC-Regular.woff2"
const GRABBER_PATH := "res://assets/icons/slider_grabber.png"

## 正文字号。主菜单那几个入口按钮在 main.tscn 里单独放大到 22。
const FONT_SIZE := 18
## 圆角：按钮 / 输入框一档，滑块槽一档，弹出面板一档。
const BUTTON_RADIUS := 10
const SLIDER_RADIUS := 8
const PANEL_RADIUS := 12
const RESULT_RADIUS := 14
## 焦点框宽度。电视上没有鼠标，全靠它看清选中项，所以要粗。
const FOCUS_BORDER := 3
## 浮在明亮背景上的文字描边，保证战报和榜单行不被背景吞掉。
const OUTLINE_SIZE := 2
## 半透明「玻璃」底板的不透明度。背景要透出来，但文字仍要读得清。
const GLASS_ALPHA := 0.56
const GLASS_BORDER_ALPHA := 0.26


func _initialize() -> void:
	var theme := Theme.new()
	theme.default_font = load(FONT_PATH)
	theme.default_font_size = FONT_SIZE

	_build_button(theme)
	_build_secondary_button(theme)
	_build_line_edit(theme)
	_build_slider(theme)
	_build_labels(theme)
	_build_panels(theme)
	_build_battle_log(theme)

	var err := ResourceSaver.save(theme, OUT_PATH)
	if err != OK:
		printerr("theme save failed: %d" % err)
		quit(1)
		return
	print("wrote ", OUT_PATH)
	quit(0)


## 主按钮：实心主色 + 深色字。OptionButton 没有自己的条目，会顺着类继承用这一套。
func _build_button(theme: Theme) -> void:
	theme.set_stylebox("normal", "Button", _flat(ThemeHelper.ACCENT, BUTTON_RADIUS))
	theme.set_stylebox("hover", "Button", _flat(ThemeHelper.ACCENT.lightened(0.12), BUTTON_RADIUS))
	theme.set_stylebox("pressed", "Button", _flat(ThemeHelper.ACCENT.darkened(0.12), BUTTON_RADIUS))
	theme.set_stylebox("disabled", "Button", _flat(ThemeHelper.ACCENT.darkened(0.4), BUTTON_RADIUS))
	theme.set_stylebox("focus", "Button", _focus())
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		theme.set_color(state, "Button", ThemeHelper.BG)
	theme.set_color("font_disabled_color", "Button", Color(ThemeHelper.BG, 0.6))


## 次级按钮：卡片底 + 主色描边。返回、维护、增删都用它。
func _build_secondary_button(theme: Theme) -> void:
	var variation := ThemeHelper.SECONDARY_BUTTON
	theme.set_type_variation(variation, "Button")
	theme.set_stylebox("normal", variation, _outlined(ThemeHelper.CARD))
	theme.set_stylebox("hover", variation, _outlined(ThemeHelper.CARD.lightened(0.12)))
	theme.set_stylebox("pressed", variation, _outlined(ThemeHelper.CARD.darkened(0.12)))
	theme.set_stylebox("disabled", variation, _outlined(ThemeHelper.CARD.darkened(0.3)))
	theme.set_stylebox("focus", variation, _focus())
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		theme.set_color(state, variation, ThemeHelper.TEXT)
	theme.set_color("font_disabled_color", variation, ThemeHelper.MUTED)


## 输入框。焦点框和按钮共用一套金边，不然焦点跳进输入框就看不出来了。
func _build_line_edit(theme: Theme) -> void:
	theme.set_stylebox("normal", "LineEdit", _flat(ThemeHelper.CARD, BUTTON_RADIUS))
	theme.set_stylebox("focus", "LineEdit", _focus())
	theme.set_color("font_color", "LineEdit", ThemeHelper.TEXT)
	theme.set_color("font_placeholder_color", "LineEdit", ThemeHelper.MUTED)
	theme.set_color("caret_color", "LineEdit", ThemeHelper.ACCENT)


## 音量滑块：电视上靠左右键调，所以必须能拿焦点，焦点框和按钮同一套金边。
## 把手是 assets/icons/slider_grabber.png（纯金色实底，由 tools/icon_bake.py 烘焙）。
func _build_slider(theme: Theme) -> void:
	theme.set_stylebox("slider", "HSlider", _flat(ThemeHelper.CARD, SLIDER_RADIUS))
	theme.set_stylebox("grabber_area", "HSlider", _flat(ThemeHelper.ACCENT, SLIDER_RADIUS))
	theme.set_stylebox("grabber_area_highlight", "HSlider", _flat(ThemeHelper.ACCENT.lightened(0.12), SLIDER_RADIUS))
	theme.set_stylebox("focus", "HSlider", _focus())
	var grabber: Texture2D = load(GRABBER_PATH)
	for icon_name in ["grabber", "grabber_highlight", "grabber_disabled"]:
		theme.set_icon(icon_name, "HSlider", grabber)


## 正文色是默认；两个变体分别管「次要说明」和「浮在明亮背景上的动态文字」。
func _build_labels(theme: Theme) -> void:
	theme.set_color("font_color", "Label", ThemeHelper.TEXT)

	theme.set_type_variation(ThemeHelper.MUTED_LABEL, "Label")
	theme.set_color("font_color", ThemeHelper.MUTED_LABEL, ThemeHelper.MUTED)

	# 描边让战报、战绩榜的字在任何一张战斗背景上都读得清。
	theme.set_type_variation(ThemeHelper.READABLE_LABEL, "Label")
	theme.set_color("font_color", ThemeHelper.READABLE_LABEL, ThemeHelper.TEXT)
	theme.set_color("font_outline_color", ThemeHelper.READABLE_LABEL, _outline_color())
	theme.set_constant("outline_size", ThemeHelper.READABLE_LABEL, OUTLINE_SIZE)

	theme.set_type_variation(ThemeHelper.MUTED_READABLE_LABEL, "Label")
	theme.set_color("font_color", ThemeHelper.MUTED_READABLE_LABEL, ThemeHelper.MUTED)
	theme.set_color("font_outline_color", ThemeHelper.MUTED_READABLE_LABEL, _outline_color())
	theme.set_constant("outline_size", ThemeHelper.MUTED_READABLE_LABEL, OUTLINE_SIZE)


## 三块面板：战斗页的半透明玻璃底、结果面板的不透明底、设置页的维护弹窗。
func _build_panels(theme: Theme) -> void:
	theme.set_type_variation(ThemeHelper.GLASS_PANEL, "PanelContainer")
	theme.set_stylebox("panel", ThemeHelper.GLASS_PANEL, _glass())

	# 结果面板压在立绘和战报上面，必须不透明，否则糊成一片。
	theme.set_type_variation(ThemeHelper.RESULT_PANEL, "PanelContainer")
	var result := _flat(ThemeHelper.PANEL, RESULT_RADIUS)
	result.content_margin_left = 24
	result.content_margin_right = 24
	result.content_margin_top = 18
	result.content_margin_bottom = 18
	result.set_border_width_all(2)
	result.border_color = ThemeHelper.CARD
	theme.set_stylebox("panel", ThemeHelper.RESULT_PANEL, result)

	theme.set_type_variation(ThemeHelper.DIALOG_PANEL, "PanelContainer")
	var dialog := _flat(ThemeHelper.PANEL, PANEL_RADIUS)
	dialog.set_border_width_all(1)
	dialog.border_color = ThemeHelper.ACCENT
	theme.set_stylebox("panel", ThemeHelper.DIALOG_PANEL, dialog)


## 战报：和战绩榜同一块玻璃底，外加正文描边。
func _build_battle_log(theme: Theme) -> void:
	var variation := ThemeHelper.GLASS_LOG
	theme.set_type_variation(variation, "RichTextLabel")
	var box := _glass()
	box.content_margin_left = 14
	box.content_margin_right = 14
	box.content_margin_top = 10
	box.content_margin_bottom = 10
	theme.set_stylebox("normal", variation, box)
	theme.set_color("default_color", variation, ThemeHelper.TEXT)
	theme.set_color("font_outline_color", variation, _outline_color())
	theme.set_constant("outline_size", variation, OUTLINE_SIZE)


## 一块纯色圆角底。文字和边框之间留点空隙，不然贴边很难看。
func _flat(color: Color, radius: int) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = color
	box.set_corner_radius_all(radius)
	box.content_margin_left = 12
	box.content_margin_right = 12
	box.content_margin_top = 8
	box.content_margin_bottom = 8
	return box


## 次级按钮那层「卡片底 + 一圈主色」。
func _outlined(color: Color) -> StyleBoxFlat:
	var box := _flat(color, BUTTON_RADIUS)
	box.set_border_width_all(1)
	box.border_color = ThemeHelper.ACCENT
	return box


## 半透明玻璃底板：背景透出来，弱描边只负责勾出边界。
func _glass() -> StyleBoxFlat:
	var box := _flat(Color(ThemeHelper.PANEL, GLASS_ALPHA), BUTTON_RADIUS)
	box.set_border_width_all(1)
	box.border_color = Color(ThemeHelper.ACCENT, GLASS_BORDER_ALPHA)
	return box


## 焦点框。全透明底 + draw_center=false：只画一圈框，不盖住控件本来的颜色；
## 往外扩同样的宽度，框就落在控件外沿而不是压在上面。
func _focus() -> StyleBoxFlat:
	var box := _flat(Color(0, 0, 0, 0), BUTTON_RADIUS)
	box.draw_center = false
	box.set_border_width_all(FOCUS_BORDER)
	box.border_color = ThemeHelper.GOLD
	box.set_expand_margin_all(FOCUS_BORDER)
	return box


func _outline_color() -> Color:
	return Color(ThemeHelper.BG, 0.96)
