extends Control

## 主菜单。版本号直接读 project.godot 里的 application/config/version，
## 改版本只要动那一处，界面自动跟上。

const RANKING_SCENE := "res://scenes/ranking.tscn"
const BATTLE_SCENE := "res://scenes/battle.tscn"
const SETTINGS_SCENE := "res://scenes/settings.tscn"

## Web 启动参数只负责隐藏入口，不删除节点。固定顺序同时
## 也是电视遥控器的焦点和主次颜色顺序；对战始终排第一、拿默认焦点和实心主色。
var _menu_buttons: Array[Button] = []
var _focus_fallback: Button = null


func _ready() -> void:
	# 光标由 CursorController autoload 全局接管（装贴图 + 每个事件切换），
	# 这里不用再管；遥控器映射是幂等的，每个场景都装一次。
	TvRemote.install()
	# 金冠铃是非战斗三页共用；已经在播时 MusicManager 不会重开。
	MusicManager.play_lounge()
	ThemeHelper.apply(self, 22)
	# 主菜单是唯一的启动入口，所以上次选的窗口模式在这里应用一次就够了，
	# 从设置页返回时顺带再确认一遍，代价只是一次幂等的 DisplayServer 调用。
	AppSettings.apply()
	_menu_buttons = [%BattleButton, %RankingButton, %SettingsButton, %QuitButton]
	_apply_web_menu_visibility()
	_style()
	%RankingButton.pressed.connect(_on_ranking_pressed)
	%BattleButton.pressed.connect(_on_battle_pressed)
	%SettingsButton.pressed.connect(_on_settings_pressed)
	%QuitButton.pressed.connect(_on_quit_pressed)
	# 电视上没有鼠标，一进来就得有个可见控件拿着焦点。
	_focus_fallback = first_visible_menu_button()
	if _focus_fallback != null:
		_focus_fallback.grab_focus()
## 电视遥控器的 BACK 键：引擎会把它变成这个通知（前提是
## project.godot 里 quit_on_go_back=false，否则引擎自己就退了）。
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		_on_quit_pressed()


func _unhandled_input(event: InputEvent) -> void:
	# 主菜单已经是最外层，返回就等于退出游戏。
	if TvRemote.consume_back(event, self):
		_on_quit_pressed()
	elif TvRemote.is_navigation(event):
		# 焦点万一掉了，方向键会全哑，这里补回去。
		TvRemote.ensure_focus(_focus_fallback)


## Web 参数中的 CloseMenu 只影响主菜单入口。Battle 故意不在可关闭清单里，
## 保证即使三个可选入口全隐藏，页面仍有一个能进入且能拿焦点的操作。
func _apply_web_menu_visibility() -> void:
	%RankingButton.visible = not WebLaunchConfig.is_menu_closed(&"ranking")
	%SettingsButton.visible = not WebLaunchConfig.is_menu_closed(&"settings")
	%QuitButton.visible = not WebLaunchConfig.is_menu_closed(&"quit")


## 当前场景顺序中的第一个可见、可用菜单。启动聚焦和丢焦恢复共用这一条，
## 避免两处各自写死排行榜。
func first_visible_menu_button() -> Button:
	for button in _menu_buttons:
		if button.visible and not button.disabled:
			return button
	return null


## 上色和按钮样式。布局本身在 main.tscn 里。
func _style() -> void:
	%Background.color = ThemeHelper.BG
	%Title.add_theme_color_override("font_color", ThemeHelper.TEXT)
	%VersionLabel.text = "v%s" % project_version()
	%VersionLabel.add_theme_color_override("font_color", ThemeHelper.MUTED)
	# 当前第一个可见入口是实心主按钮；Battle 不可隐藏，所以它始终是主按钮。
	var primary := first_visible_menu_button()
	for button in _menu_buttons:
		ThemeHelper.style_button(button, button == primary)


## project.godot 里配置的版本号，没配则回落到 0.0.0。
static func project_version() -> String:
	var value := str(ProjectSettings.get_setting("application/config/version", ""))
	return value if not value.is_empty() else "0.0.0"


func _on_ranking_pressed() -> void:
	get_tree().change_scene_to_file(RANKING_SCENE)


func _on_battle_pressed() -> void:
	get_tree().change_scene_to_file(BATTLE_SCENE)


func _on_settings_pressed() -> void:
	get_tree().change_scene_to_file(SETTINGS_SCENE)


func _on_quit_pressed() -> void:
	get_tree().quit()
