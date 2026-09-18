extends Control

## 主菜单。版本号直接读 project.godot 里的 application/config/version，
## 改版本只要动那一处，界面自动跟上。

const RANKING_SCENE := "res://ranking.tscn"
const BATTLE_SCENE := "res://battle.tscn"


func _ready() -> void:
	GameCursor.boot()
	TvRemote.install()
	ThemeHelper.apply(self, 22)
	_style()
	%RankingButton.pressed.connect(_on_ranking_pressed)
	%BattleButton.pressed.connect(_on_battle_pressed)
	%QuitButton.pressed.connect(_on_quit_pressed)
	%RankingButton.grab_focus()


func _input(event: InputEvent) -> void:
	GameCursor.handle_event(event)


## 电视遥控器的 BACK 键：引擎会把它变成这个通知（前提是
## project.godot 里 quit_on_go_back=false，否则引擎自己就退了）。
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		_on_quit_pressed()


func _unhandled_input(event: InputEvent) -> void:
	if TvRemote.is_back(event):
		accept_event()
		_on_quit_pressed()
	elif TvRemote.is_navigation(event):
		TvRemote.ensure_focus(%RankingButton)


func _style() -> void:
	%Background.color = ThemeHelper.BG
	%Title.add_theme_color_override("font_color", ThemeHelper.TEXT)
	%VersionLabel.text = "v%s" % project_version()
	%VersionLabel.add_theme_color_override("font_color", ThemeHelper.MUTED)
	ThemeHelper.style_button(%RankingButton, true)
	ThemeHelper.style_button(%BattleButton, false)
	ThemeHelper.style_button(%QuitButton, false)


## project.godot 里配置的版本号，没配则回落到 0.0.0。
static func project_version() -> String:
	var value := str(ProjectSettings.get_setting("application/config/version", ""))
	return value if not value.is_empty() else "0.0.0"


func _on_ranking_pressed() -> void:
	get_tree().change_scene_to_file(RANKING_SCENE)


func _on_battle_pressed() -> void:
	get_tree().change_scene_to_file(BATTLE_SCENE)


func _on_quit_pressed() -> void:
	get_tree().quit()
