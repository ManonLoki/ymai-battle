extends Control

## 主菜单。版本号直接读 project.godot 里的 application/config/version，
## 改版本只要动那一处，界面自动跟上。

const RANKING_SCENE := "res://ranking.tscn"
const BATTLE_SCENE := "res://battle.tscn"
const SETTINGS_SCENE := "res://settings.tscn"


func _ready() -> void:
	# 光标和遥控器映射在每个场景都装一次，从任何入口进来都成立。
	GameCursor.boot()
	TvRemote.install()
	ThemeHelper.apply(self, 22)
	# 主菜单是唯一的启动入口，所以上次选的窗口模式在这里应用一次就够了，
	# 从设置页返回时顺带再确认一遍，代价只是一次幂等的 DisplayServer 调用。
	WindowSettings.apply(WindowSettings.load_mode())
	_style()
	%RankingButton.pressed.connect(_on_ranking_pressed)
	%BattleButton.pressed.connect(_on_battle_pressed)
	%SettingsButton.pressed.connect(_on_settings_pressed)
	%QuitButton.pressed.connect(_on_quit_pressed)
	# 电视上没有鼠标，一进来就得有个控件拿着焦点。
	%RankingButton.grab_focus()


func _input(event: InputEvent) -> void:
	GameCursor.handle_event(event)


## 电视遥控器的 BACK 键：引擎会把它变成这个通知（前提是
## project.godot 里 quit_on_go_back=false，否则引擎自己就退了）。
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		_on_quit_pressed()


func _unhandled_input(event: InputEvent) -> void:
	# 主菜单已经是最外层，返回就等于退出游戏。
	if TvRemote.is_back(event):
		accept_event()
		_on_quit_pressed()
	elif TvRemote.is_navigation(event):
		# 焦点万一掉了，方向键会全哑，这里补回去。
		TvRemote.ensure_focus(%RankingButton)


## 上色和按钮样式。布局本身在 main.tscn 里。
func _style() -> void:
	%Background.color = ThemeHelper.BG
	%Title.add_theme_color_override("font_color", ThemeHelper.TEXT)
	%VersionLabel.text = "v%s" % project_version()
	%VersionLabel.add_theme_color_override("font_color", ThemeHelper.MUTED)
	# 只有“排行榜”是实心主按钮，其余都走描边样式。
	ThemeHelper.style_button(%RankingButton, true)
	ThemeHelper.style_button(%BattleButton, false)
	ThemeHelper.style_button(%SettingsButton, false)
	ThemeHelper.style_button(%QuitButton, false)


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
