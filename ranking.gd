extends Control

## 排行榜场景：按逻辑玩家展示当日聚合后的 token 战力和用过的 agent。

const MAIN_SCENE := "res://main.tscn"
## 遥控器上下键一次滚多少像素：榜单本身不吃焦点，只能手动推 ScrollContainer。
const SCROLL_STEP := 64
## 表头字号，比正文小一号；正文跟随场景主题。
const HEADER_FONT_PX := 14
## 表格的四列：标题就是表头文字，expand 的列会被拉伸撑开，
## right 的列（战力）数字右对齐才好比较。加减列只要动这一张表。
const COLUMNS := [
	{"title": "#"},
	{"title": "用户", "expand": true},
	{"title": "Agent"},
	{"title": "Token / 战力", "expand": true, "right": true},
]

## 已经在切回主菜单的路上，避免连按两次返回触发两次切场景。
var _leaving := false
## 当前榜单是哪一天的。从后台切回来时拿它和系统日期比，跨天了就重拉。
var _shown_date := ""


func _ready() -> void:
	TvRemote.install()
	ThemeHelper.apply(self, 18)
	%Background.color = ThemeHelper.BG
	%Title.add_theme_color_override("font_color", ThemeHelper.TEXT)
	%Status.add_theme_color_override("font_color", ThemeHelper.MUTED)
	ThemeHelper.style_back_button(%BackButton)
	%BackButton.pressed.connect(_on_back_pressed)
	# 场上唯一可聚焦的控件，一进来就给它焦点。
	%BackButton.grab_focus()
	await _load_ranking()


func _notification(what: int) -> void:
	# 电视遥控器 BACK 键。
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		_on_back_pressed()
	# 从后台切回来：榜单只在进场景时拉过一次，挂了一整夜再回来就是昨天的。
	# 跨天了就重新拉一次，不用玩家退出去再进来。判断和对战场景走的是同一条 DayClock。
	elif what == NOTIFICATION_APPLICATION_RESUMED and not _leaving and is_inside_tree():
		if DayClock.rolled_over(_shown_date):
			_load_ranking()


func _unhandled_input(event: InputEvent) -> void:
	if TvRemote.consume_back(event, self):
		_on_back_pressed()
		return
	TvRemote.ensure_focus(%BackButton)
	# 榜单里只有“返回”一个可聚焦控件，上下键找不到邻居就落到这里，用来翻榜。
	var step := 0
	if event.is_action_pressed(&"ui_down", true):
		step = SCROLL_STEP
	elif event.is_action_pressed(&"ui_up", true):
		step = -SCROLL_STEP
	if step != 0:
		accept_event()
		# 夹在 0 以上，往上翻到顶就停住。
		%Scroll.scroll_vertical = maxi(0, %Scroll.scroll_vertical + step)


func _on_back_pressed() -> void:
	if _leaving:
		return
	_leaving = true
	get_tree().change_scene_to_file(MAIN_SCENE)


## 拉一次接口并渲染榜单。日期每次进场景时现取，所以跨天重进就是新一天的榜。
func _load_ranking() -> void:
	%Status.text = "正在拉取今日排行…"
	NodeUtil.clear_children(%Grid)
	var result: Dictionary = await TokenUsageApi.fetch_ranking(self)
	# await 期间玩家可能已经按返回走了，节点没了就别再碰界面。
	if not is_instance_valid(self):
		return
	if not bool(result.get("ok", false)):
		%Status.text = "加载失败：%s" % str(result.get("error", "未知错误"))
		%Status.add_theme_color_override("font_color", ThemeHelper.DANGER)
		return
	_render(str(result.get("date", "")), result.get("users", [] as Array[RankedUser]))


## 把聚合结果铺进表格。
func _render(date: String, ranked: Array[RankedUser]) -> void:
	_shown_date = date
	%Title.text = "今日排行 · %s" % date
	%Status.text = "%d 人上榜 · Token 即基础战力" % ranked.size()
	# 上一次可能因为报错被染成红色，这里改回普通说明色。
	%Status.add_theme_color_override("font_color", ThemeHelper.MUTED)
	NodeUtil.clear_children(%Grid)
	_add_header()
	for user in ranked:
		_add_row(user)


func _add_header() -> void:
	var titles := PackedStringArray()
	for column in COLUMNS:
		titles.append(str(column["title"]))
	_add_cells(titles, ThemeHelper.MUTED, true)


## 一名玩家一行。
func _add_row(user: RankedUser) -> void:
	# 用过多个 agent 就全列出来，只有一个时直接用主 agent 名。
	var agent_text := user.agent_name
	if user.agents.size() > 1:
		agent_text = ", ".join(user.agents)
	# 紧凑值方便扫一眼，括号里的精确值方便核对。
	var tokens_text := "%s  (%s)" % [NumberFormat.compact(user.tokens), NumberFormat.with_commas(user.tokens)]
	_add_cells([str(user.rank), user.username, agent_text, tokens_text], ThemeHelper.TEXT, false)


## 往 GridContainer 里塞一行单元格。列数由 %Grid 的 columns 决定。
func _add_cells(texts: PackedStringArray, color: Color, header: bool) -> void:
	for i in range(texts.size()):
		var label := ThemeHelper.make_label(texts[i], color, HEADER_FONT_PX if header else 0)
		# 表格不参与遥控器导航，翻页靠 _unhandled_input 直接推滚动条。
		label.focus_mode = Control.FOCUS_NONE
		var column: Dictionary = COLUMNS[i]
		if bool(column.get("right", false)):
			label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		if bool(column.get("expand", false)):
			label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		%Grid.add_child(label)
