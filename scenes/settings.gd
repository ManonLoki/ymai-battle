extends Control

## 设置页：窗口模式 + 音量 + 榜单服务器列表。
##
## 窗口模式用一个下拉框选择；选项按 AppSettings.MODES 的顺序生成，metadata
## 保存真实模式值，不把下拉索引当成模式。选择后立即保存、应用并刷新说明。
##
## 服务器下拉紧挨窗口模式下拉下方。本地列表的增删改都在「维护」面板里完成；
## Web 注入列表只读，不能改本地存档。

const MAIN_SCENE := "res://scenes/main.tscn"
## “维护 / 增加 / 删除 / 保存”按钮比主按钮窄，给地址和下拉框留空间。
const SERVER_BUTTON_MIN_SIZE := Vector2(140, 48)
const DEFAULT_SERVER_LABEL := "使用默认服务器"

## 已经在切回主菜单的路上，避免连按两次返回触发两次切场景。
var _leaving := false
## 当前选中的模式，用来刷新说明。
var _mode := AppSettings.DEFAULT_MODE
## 两个滑块当前的线性音量。留着是为了推总线时不必再读一次存档——
## 值本来就在 value_changed 的参数里，另一路的值也只在进页面时读过一次。
var _music_linear := AppSettings.DEFAULT_MUSIC_VOLUME
var _sfx_linear := AppSettings.DEFAULT_SFX_VOLUME
## 测试可在节点入树前换成隔离存档；正式运行使用全局设置文件。
var settings_path: String = AppSettings.SAVE_PATH


func _ready() -> void:
	TvRemote.install()
	# 设置页也走共用曲；从战斗返回主菜单再进这里时，由主菜单切回金冠铃。
	MusicManager.play_lounge()
	ThemeHelper.apply(self, 18)
	%Background.color = ThemeHelper.BG
	%Title.add_theme_color_override("font_color", ThemeHelper.TEXT)
	%Hint.add_theme_color_override("font_color", ThemeHelper.MUTED)
	ThemeHelper.style_back_button(%BackButton)
	%BackButton.pressed.connect(_on_back_pressed)
	_mode = AppSettings.load_mode(settings_path)
	_bind_mode_controls()
	_bind_audio_controls()
	_bind_server_controls()
	# 电视上没有鼠标，一进来就让窗口模式下拉框拿焦点。
	%ModeSelect.grab_focus()


func _notification(what: int) -> void:
	# 电视遥控器 BACK 键。
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		_on_back_pressed()


func _unhandled_input(event: InputEvent) -> void:
	if TvRemote.consume_back(event, self):
		_on_back_pressed()
	elif TvRemote.is_navigation(event):
		# 焦点万一掉了，方向键会全哑，这里补回去。
		if %MaintainOverlay.visible:
			TvRemote.ensure_focus(%MaintainClose)
		else:
			TvRemote.ensure_focus(%BackButton)


## 用 AppSettings 的定义填充模式下拉框。metadata 存真实模式值，
## 以后即使模式枚举不再连续，选择也不会因索引错位。
func _bind_mode_controls() -> void:
	ThemeHelper.style_button(%ModeSelect, true)
	%ModeDescription.add_theme_color_override("font_color", ThemeHelper.MUTED)
	_fill_select(
		%ModeSelect,
		AppSettings.MODES,
		AppSettings.mode_display_name,
		AppSettings.mode_description,
		_mode,
	)
	_refresh_mode_description()
	%ModeSelect.item_selected.connect(_on_mode_selected)


## 按 values 重建一个下拉框：文字取 label_of，悬浮提示取 tooltip_of，
## metadata 存原值本身，并选中值等于 current 的那一项（找不到就落回第一项）。
##
## 「下拉索引不等于业务值」这条规矩只在这里写一遍，两个下拉都从这里过。
func _fill_select(
	select: OptionButton,
	values: Array,
	label_of: Callable,
	tooltip_of: Callable,
	current: Variant,
) -> void:
	select.clear()
	var selected_index := 0
	for value in values:
		select.add_item(str(label_of.call(value)))
		var index: int = select.item_count - 1
		select.set_item_metadata(index, value)
		select.set_item_tooltip(index, str(tooltip_of.call(value)))
		if value == current:
			selected_index = index
	select.select(selected_index)


func _refresh_mode_description() -> void:
	%ModeDescription.text = AppSettings.mode_description(_mode)


func _on_mode_selected(index: int) -> void:
	_mode = AppSettings.sanitize_mode(int(%ModeSelect.get_item_metadata(index)))
	# 先存后应用：万一 apply 在某个平台上出岔子，选择也已经落盘了。
	AppSettings.save_mode(_mode, settings_path)
	AppSettings.apply_mode(_mode)
	_refresh_mode_description()


## 背景音乐 / 音效两个滑块。0–100，步进 5，电视上左右键就是调音量。
func _bind_audio_controls() -> void:
	%AudioTitle.add_theme_color_override("font_color", ThemeHelper.TEXT)
	_music_linear = AppSettings.load_music_volume(settings_path)
	_sfx_linear = AppSettings.load_sfx_volume(settings_path)
	_bind_volume_slider(%MusicSlider, %MusicLabel, _music_linear)
	_bind_volume_slider(%SfxSlider, %SfxLabel, _sfx_linear)
	_refresh_audio_labels()
	%MusicSlider.value_changed.connect(_on_music_volume_changed)
	%SfxSlider.value_changed.connect(_on_sfx_volume_changed)
	AppSettings.apply_mix(_music_linear, _sfx_linear)


## 一个音量滑块的配色、样式和初值。两个滑块在这一层没有任何区别。
func _bind_volume_slider(slider: HSlider, label: Label, linear: float) -> void:
	label.add_theme_color_override("font_color", ThemeHelper.TEXT)
	ThemeHelper.style_slider(slider)
	slider.set_value_no_signal(float(AppSettings.volume_percent(linear)))


func _refresh_audio_labels() -> void:
	%MusicLabel.text = "背景音乐 %d%%" % int(%MusicSlider.value)
	%SfxLabel.text = "音效 %d%%" % int(%SfxSlider.value)


func _on_music_volume_changed(value: float) -> void:
	_music_linear = value / 100.0
	AppSettings.save_music_volume(_music_linear, settings_path)
	AppSettings.apply_mix(_music_linear, _sfx_linear)
	_refresh_audio_labels()


func _on_sfx_volume_changed(value: float) -> void:
	_sfx_linear = value / 100.0
	AppSettings.save_sfx_volume(_sfx_linear, settings_path)
	AppSettings.apply_mix(_music_linear, _sfx_linear)
	_refresh_audio_labels()
	# 音效滑块自带试听：调完立刻听到这一档是什么响度，不用退出去打一场。
	var preview := StrikeResult.new()
	preview.hit = true
	CombatSfx.play_event(preview)


## 绑定服务器下拉、维护面板和状态行。Web 参数提供列表时，列表是只读数据源；
## 没提供时才允许维护本地列表。
func _bind_server_controls() -> void:
	%ServerTitle.add_theme_color_override("font_color", ThemeHelper.TEXT)
	%ServerHint.add_theme_color_override("font_color", ThemeHelper.MUTED)
	%MaintainTitle.add_theme_color_override("font_color", ThemeHelper.TEXT)
	ThemeHelper.style_button(%ServerSelect, true)
	ThemeHelper.style_button(%ServerMaintain, false, SERVER_BUTTON_MIN_SIZE)
	ThemeHelper.style_back_button(%MaintainClose)
	ThemeHelper.style_line_edit(%ServerAddInput)
	ThemeHelper.style_button(%ServerAdd, false, SERVER_BUTTON_MIN_SIZE)
	%ServerAddInput.placeholder_text = AppSettings.SERVER_PLACEHOLDER
	%ServerSelect.item_selected.connect(_on_server_selected)
	%ServerMaintain.pressed.connect(_on_server_maintain_pressed)
	%MaintainClose.pressed.connect(_close_maintain_panel)
	# 电视遥控器按 OK 收完键盘会发 text_submitted，等同于按“增加”。
	%ServerAddInput.text_submitted.connect(_on_server_add_submitted)
	%ServerAdd.pressed.connect(_on_server_add_pressed)
	var injected := WebLaunchConfig.has_base_urls_override()
	%ServerAddRow.visible = not injected
	%ServerAddInput.editable = not injected
	%ServerAdd.disabled = injected
	%ServerMaintain.visible = not injected
	%ServerMaintain.disabled = injected
	%ServerHint.text = (
		"服务器列表由网页启动参数提供；选择空项使用内置地址。"
		if injected
		else "从下拉框选择服务器；选择空项使用内置地址。点维护可增删改本地服务器。"
	)
	_style_maintain_panel()
	_refresh_server_view()


func _style_maintain_panel() -> void:
	var box := ThemeHelper.make_flat(ThemeHelper.PANEL, 12)
	box.set_border_width_all(1)
	box.border_color = ThemeHelper.ACCENT
	%MaintainPanel.add_theme_stylebox_override("panel", box)


## 用当前数据源重建下拉，状态行只显示主机或「默认」，不把接口路径摊给用户。
func _refresh_server_view(note: String = "", color: Color = ThemeHelper.MUTED) -> void:
	var selected := WebLaunchConfig.effective_base_url(settings_path)
	# 空串那一项代表“用内置地址”，和真实地址一样把值存进 metadata。
	var bases: Array = [""]
	for raw_base in WebLaunchConfig.active_base_urls(settings_path):
		bases.append(str(raw_base))
	_fill_select(
		%ServerSelect,
		bases,
		func(base: Variant) -> String: return DEFAULT_SERVER_LABEL if str(base).is_empty() else str(base),
		func(base: Variant) -> String: return TokenUsageApi.display_host(str(base)),
		selected,
	)
	var line := "当前：%s" % TokenUsageApi.display_host(selected)
	_set_server_status(line if note.is_empty() else "%s　%s" % [note, line], color)
	if %MaintainOverlay.visible:
		_refresh_maintain_list()


## 状态行。报错走 DANGER，其余都是灰字。
func _set_server_status(text: String, color: Color) -> void:
	%ServerStatus.text = text
	%ServerStatus.add_theme_color_override("font_color", color)


## 下拉选择立即落盘；选第一项就是清空覆盖、恢复内置服务器。
func _on_server_selected(index: int) -> void:
	var base := str(%ServerSelect.get_item_metadata(index))
	if not AppSettings.save_base_url(base, settings_path):
		_refresh_server_view("选择未能保存。", ThemeHelper.DANGER)
		return
	_refresh_server_view("已切换。")


func _on_server_maintain_pressed() -> void:
	if WebLaunchConfig.has_base_urls_override():
		return
	%MaintainOverlay.visible = true
	_refresh_maintain_list()
	%ServerAddInput.grab_focus()


func _close_maintain_panel() -> void:
	%MaintainOverlay.visible = false
	%ServerSelect.grab_focus()


## 维护面板顶部的列表：每一行可改可删。
func _refresh_maintain_list() -> void:
	NodeUtil.clear_children(%ServerList)
	if WebLaunchConfig.has_base_urls_override():
		return
	for base in AppSettings.load_base_urls(settings_path):
		%ServerList.add_child(_make_server_row(str(base)))


func _make_server_row(base: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var edit := LineEdit.new()
	edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	edit.text = base
	edit.set_meta("original", base)
	ThemeHelper.style_line_edit(edit)
	var save_btn := Button.new()
	save_btn.text = "保存"
	ThemeHelper.style_button(save_btn, false, SERVER_BUTTON_MIN_SIZE)
	save_btn.pressed.connect(_on_server_row_save_pressed.bind(edit))
	var delete_btn := Button.new()
	delete_btn.text = "删除"
	ThemeHelper.style_button(delete_btn, false, SERVER_BUTTON_MIN_SIZE)
	delete_btn.pressed.connect(_on_server_row_delete_pressed.bind(base))
	row.add_child(edit)
	row.add_child(save_btn)
	row.add_child(delete_btn)
	return row


func _on_server_row_save_pressed(edit: LineEdit) -> void:
	if WebLaunchConfig.has_base_urls_override():
		return
	var old_base := str(edit.get_meta("original", ""))
	if not AppSettings.replace_base_url(old_base, edit.text, settings_path):
		_set_server_status("地址格式不对或存不下来，服务器未修改", ThemeHelper.DANGER)
		return
	_refresh_server_view("已修改。")


func _on_server_row_delete_pressed(base: String) -> void:
	if WebLaunchConfig.has_base_urls_override():
		return
	if not AppSettings.remove_base_url(base, settings_path):
		_set_server_status("存不下来，服务器未删除", ThemeHelper.DANGER)
		return
	_refresh_server_view("已删除。")


## 输入框回车 / 遥控器 OK 等同于按“增加”。
func _on_server_add_submitted(_text: String) -> void:
	_on_server_add_pressed()


## 本地模式增加一台服务器并立即选中；Web 注入模式下即使手动调用也不改存档。
func _on_server_add_pressed() -> void:
	if WebLaunchConfig.has_base_urls_override():
		return
	var text := str(%ServerAddInput.text)
	if AppSettings.normalize_base_url(text).is_empty():
		_set_server_status("地址格式不对，应该是 %s" % AppSettings.SERVER_PLACEHOLDER, ThemeHelper.DANGER)
		return
	if not AppSettings.add_and_select_base_url(text, settings_path):
		_set_server_status("存不下来，服务器未增加", ThemeHelper.DANGER)
		return
	%ServerAddInput.clear()
	_refresh_server_view("已增加并切换。")


func _on_back_pressed() -> void:
	if %MaintainOverlay.visible:
		_close_maintain_panel()
		return
	if _leaving:
		return
	_leaving = TvRemote.leave_to(self, MAIN_SCENE)
