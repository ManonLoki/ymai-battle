extends Control

## 排行榜场景：按逻辑玩家展示当日聚合后的 token 战力和用过的 agent。

const MAIN_SCENE := "res://main.tscn"
## 遥控器上下键一次滚多少像素：榜单本身不吃焦点，只能手动推 ScrollContainer。
const SCROLL_STEP := 64

var _leaving := false


func _ready() -> void:
	TvRemote.install()
	ThemeHelper.apply(self, 18)
	%Background.color = ThemeHelper.BG
	%Title.add_theme_color_override("font_color", ThemeHelper.TEXT)
	%Status.add_theme_color_override("font_color", ThemeHelper.MUTED)
	ThemeHelper.style_button(%BackButton, false)
	%BackButton.custom_minimum_size = Vector2(120, 40)
	%BackButton.pressed.connect(_on_back_pressed)
	%BackButton.grab_focus()
	await _load_ranking()


## 电视遥控器 BACK 键。
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		_on_back_pressed()


func _unhandled_input(event: InputEvent) -> void:
	if TvRemote.is_back(event):
		accept_event()
		_on_back_pressed()
		return
	TvRemote.ensure_focus(%BackButton)
	## 榜单里只有“返回”一个可聚焦控件，上下键找不到邻居就落到这里，用来翻榜。
	var step := 0
	if event.is_action_pressed(&"ui_down", true):
		step = SCROLL_STEP
	elif event.is_action_pressed(&"ui_up", true):
		step = -SCROLL_STEP
	if step != 0:
		accept_event()
		%Scroll.scroll_vertical = maxi(0, %Scroll.scroll_vertical + step)


func _on_back_pressed() -> void:
	if _leaving:
		return
	_leaving = true
	get_tree().change_scene_to_file(MAIN_SCENE)


func _load_ranking() -> void:
	%Status.text = "正在拉取今日排行…"
	_clear_grid()
	var api := TokenUsageApi.new()
	add_child(api)
	var result: Dictionary = await api.fetch_usage()
	if is_instance_valid(api):
		api.queue_free()
	if not is_instance_valid(self):
		return
	if not bool(result.get("ok", false)):
		%Status.text = "加载失败：%s" % str(result.get("error", "未知错误"))
		%Status.add_theme_color_override("font_color", ThemeHelper.DANGER)
		return
	var data: Dictionary = result.get("data", {})
	var usage: Array = data.get("channelUsage", [])
	var today := Time.get_date_string_from_system()
	var ranked: Array[RankedUser] = RankingAggregator.rank_users(usage, today)
	_render(today, ranked)


func _render(date: String, ranked: Array[RankedUser]) -> void:
	%Title.text = "今日排行 · %s" % date
	%Status.text = "%d 人上榜 · Token 即基础战力" % ranked.size()
	%Status.add_theme_color_override("font_color", ThemeHelper.MUTED)
	_clear_grid()
	_add_header()
	for user in ranked:
		_add_row(user)


func _clear_grid() -> void:
	for child in %Grid.get_children():
		%Grid.remove_child(child)
		child.free()


func _add_header() -> void:
	_add_cells(["#", "用户", "Agent", "Token / 战力"], ThemeHelper.MUTED, true)


func _add_row(user: RankedUser) -> void:
	var agent_text := user.agent_name
	if user.agents.size() > 1:
		agent_text = ", ".join(user.agents)
	var tokens_text := "%s  (%s)" % [ThemeHelper.compact(user.tokens), ThemeHelper.with_commas(user.tokens)]
	_add_cells([str(user.rank), user.username, agent_text, tokens_text], ThemeHelper.TEXT, false)


func _add_cells(texts: PackedStringArray, color: Color, header: bool) -> void:
	for i in range(texts.size()):
		var label := Label.new()
		label.text = texts[i]
		label.add_theme_color_override("font_color", color)
		label.focus_mode = Control.FOCUS_NONE
		if header:
			label.add_theme_font_size_override("font_size", 14)
		if i == 3:
			label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if i == 1:
			label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		%Grid.add_child(label)

