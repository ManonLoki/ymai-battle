class_name FighterView
extends Node2D

## 场上一名角色的表现层：立绘、血条、buff / 技能图标和悬停说明。
## 只负责播放 battle.gd 交代的动画，不参与任何战斗判定。

## 立绘基础放大倍数（32px 的像素画放到 224px）。
const BASE_SPRITE_SCALE := 7.0
## 擂主比挑战者大一圈，一眼看出谁是榜一。
## 体型不只是观感：Fighter 那边按它给了先天闪避 / 减伤的差异。
const CHAMPION_BODY_SCALE := 1.1
const CHALLENGER_BODY_SCALE := 0.9
## 回血特效场景，吸血和治疗共用同一个。
const HEAL_FX := preload("res://scenes/heal_fx.tscn")
## buff / 技能图标的边长和间距，_fit_row 算行宽时要用。
const ICON_PX := 20
const ICON_GAP := 4
## 改前暴击粒子数，测试拿它对照“大爆炸”。
const LEGACY_CRIT_AMOUNT := 28

@onready var sprite: Sprite2D = $Visual/Sprite2D
@onready var anim_player: AnimationPlayer = $AnimationPlayer
@onready var status_row: HBoxContainer = $UI/StatusRow
@onready var name_label: Label = $UI/StatusRow/NameLabel
@onready var hp_wrap: Control = $UI/StatusRow/HpWrap
@onready var hp_bar: ProgressBar = $UI/StatusRow/HpWrap/HpBar
@onready var hp_label: Label = $UI/StatusRow/HpWrap/HpLabel
@onready var buff_row: HBoxContainer = $UI/BuffRow
@onready var skill_row: HBoxContainer = $UI/SkillRow
@onready var tip_panel: PanelContainer = $UI/TipPanel
@onready var tip_label: Label = $UI/TipPanel/TipLabel
@onready var slash: Polygon2D = $Visual/Slash

## 三种姿势的立绘，bind 时一次性生成好，播动画时直接换。
var _idle_tex: Texture2D
var _attack_tex: Texture2D
var _hurt_tex: Texture2D
## 节点一开始所在的位置，动画结束后要归位。
var _home: Vector2 = Vector2.ZERO
## 暴击的金色大爆炸粒子。
var _crit_fx: CPUParticles2D
## 中毒的红色粒子（和治疗绿粒子区分开）。
var _poison_fx: CPUParticles2D
## 麻痹的黄色粒子。
var _paralyze_fx: CPUParticles2D
## 混乱头顶眩晕。
var _stun_fx: Node2D
## 幻影刺杀盖在身上的红 X 骷髅。
var _skull_fx: Node2D
## 闪避 / 凌波微步的重影容器，不含本体。
var _afterimages: Node2D
## 当前正在跑的染色 Tween。新特效来了要先把旧的 kill 掉，否则颜色会打架。
var _fx_tween: Tween
var _stun_tween: Tween
var _skull_tween: Tween


func _ready() -> void:
	_home = position
	_build_animations()
	# 刀光平时藏着，出招动画里才亮一下。剑形砍向面朝方向（即对手）。
	slash.visible = false
	slash.polygon = PackedVector2Array([
		Vector2(10, -4), Vector2(18, -14), Vector2(118, -38), Vector2(136, -8),
		Vector2(118, 22), Vector2(18, 12), Vector2(10, 4), Vector2(0, 6),
		Vector2(-8, 2), Vector2(-8, -2), Vector2(0, -6),
	])
	slash.color = Color(0.95, 0.95, 1.0, 0.95)
	# 粒子 / 重影 / 眩晕 / 骷髅只建一次，之后反复 restart。中毒和麻痹共用爆发构建。
	_crit_fx = CombatFx.make_burst(CombatFx.CRIT_COLOR, CombatFx.CRIT_AMOUNT, Vector2(0, 90), 9.0)
	_crit_fx.name = "CritFx"
	_poison_fx = CombatFx.make_burst(CombatFx.POISON_COLOR, CombatFx.STATUS_AMOUNT, Vector2(0, 40))
	_poison_fx.name = "PoisonFx"
	_paralyze_fx = CombatFx.make_burst(CombatFx.PARALYZE_COLOR, CombatFx.STATUS_AMOUNT, Vector2(0, 10))
	_paralyze_fx.name = "ParalyzeFx"
	_afterimages = Node2D.new()
	_afterimages.name = "Afterimages"
	# 重影垫在立绘后面，终点不透明的本体盖在最上面。
	_afterimages.z_index = -1
	_stun_fx = CombatFx.make_stun("StunFx")
	_skull_fx = CombatFx.make_skull("SkullFx")
	$Visual.add_child(_crit_fx)
	$Visual.add_child(_poison_fx)
	$Visual.add_child(_paralyze_fx)
	$Visual.add_child(_afterimages)
	$Visual.add_child(_stun_fx)
	$Visual.add_child(_skull_fx)
	# 这几个 Label 是场景里摆好的，得单独套上中文字体。
	for label in [name_label, hp_label, tip_label]:
		label.add_theme_font_override("font", ThemeHelper.UI_FONT)
	tip_panel.visible = false
	if anim_player.has_animation(&"idle"):
		anim_player.play(&"idle")


## 把一名角色绑到这个视图上。换人时重复调用，所有状态都要复位。
func bind(fighter: Fighter, face_left: bool) -> void:
	# 三种姿势的立绘现场生成，擂主那张自带王冠。
	_idle_tex = SpriteFactory.make_texture(fighter.appearance_id, "idle", fighter.is_champion)
	_attack_tex = SpriteFactory.make_texture(fighter.appearance_id, "attack", fighter.is_champion)
	_hurt_tex = SpriteFactory.make_texture(fighter.appearance_id, "hurt", fighter.is_champion)
	sprite.texture = _idle_tex
	# 像素画必须最近邻，放大后才不糊。
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	# 上一场的动画可能把这几项改过，全部复位。
	sprite.scale = Vector2(BASE_SPRITE_SCALE, BASE_SPRITE_SCALE)
	sprite.flip_h = false
	sprite.position = Vector2.ZERO
	sprite.rotation = 0.0
	sprite.modulate = Color.WHITE
	# 体型差放在 Visual 上而不是 Sprite2D 上：受击动画会把 Sprite2D 的 scale 压扁再弹回
	# 固定值，写在 Sprite2D 上会被它覆盖掉。翻转也合并到这里。
	var body := CHAMPION_BODY_SCALE if fighter.is_champion else CHALLENGER_BODY_SCALE
	$Visual.scale = Vector2(-body if face_left else body, body)
	# 立绘以原点为中心，放大后脚会陷进地里、缩小后浮在半空，按半身高补回来。
	var half_height := float(SpriteFactory.SIZE) * BASE_SPRITE_SCALE * 0.5
	$Visual.position = Vector2(0, -half_height * (body - 1.0))
	name_label.text = fighter.username
	hp_bar.max_value = fighter.max_hp
	# step=0 让血条平滑变化，不按整数档跳。
	hp_bar.step = 0.0
	set_hp(fighter.hp, fighter.max_hp)
	_fill_icons(fighter)
	_align_icon_rows_to_hp()
	# 布局要等容器算完尺寸才准，所以下一帧再对齐一次。
	call_deferred("_align_icon_rows_to_hp")
	# 上一位可能是死着退场的（死亡动画把 modulate 调暗、转了角度）。
	modulate = Color.WHITE
	rotation = 0.0
	position = _home
	visible = true
	_hide_transient_fx()
	if anim_player.has_animation(&"idle"):
		anim_player.play(&"idle")


## 重建两行图标：上面一行 agent buff，下面一行本场抽到的技能。
func _fill_icons(fighter: Fighter) -> void:
	NodeUtil.clear_children(buff_row)
	NodeUtil.clear_children(skill_row)
	# 每个 agent 一个 buff 图标，用了几个 agent 就挂几个。
	for buff in fighter.agent_buffs:
		if buff.icon_id.is_empty():
			continue
		buff_row.add_child(_icon_rect(buff))
	for skill in fighter.skills:
		if skill.icon_id.is_empty():
			continue
		skill_row.add_child(_icon_rect(skill))
	_fit_row(buff_row)
	_fit_row(skill_row)
	_align_icon_rows_to_hp()


## 把一行的尺寸收紧到刚好装下现有图标，免得空 HBox 撑开布局。
func _fit_row(row: HBoxContainer) -> void:
	var count := row.get_child_count()
	# n 个图标之间有 n-1 个间隙。
	var width := float(count * ICON_PX + maxi(0, count - 1) * ICON_GAP)
	row.alignment = BoxContainer.ALIGNMENT_BEGIN
	# 至少留一个图标宽，空行也不会塌成 0。
	row.custom_minimum_size = Vector2(maxi(int(width), ICON_PX), ICON_PX)
	row.size = row.custom_minimum_size
	row.reset_size()


## 两行图标的左边缘对齐血条，而不是对齐名字，看起来才是一列。
func _align_icon_rows_to_hp() -> void:
	status_row.reset_size()
	var left := hp_wrap.position.x
	# 布局还没算出来时 position 会是 0，这时按“名字宽度 + 间距”估一个。
	if left <= 1.0:
		left = name_label.custom_minimum_size.x + float(status_row.get_theme_constant("separation"))
	for row in [buff_row, skill_row]:
		row.alignment = BoxContainer.ALIGNMENT_BEGIN
		row.offset_left = left
		row.position.x = left
		row.reset_size()


## 建一个图标格子，并接上悬停显示说明的回调。
func _icon_rect(skill: SkillDef) -> TextureRect:
	var rect := TextureRect.new()
	rect.custom_minimum_size = Vector2(ICON_PX, ICON_PX)
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	rect.texture = SkillCatalog.load_icon(skill.icon_id)
	# 清掉内置 tooltip：它有延迟，这里改用自己的即时提示面板。
	rect.tooltip_text = ""
	rect.focus_mode = Control.FOCUS_NONE
	# STOP 才收得到 mouse_entered。
	rect.mouse_filter = Control.MOUSE_FILTER_STOP
	rect.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	rect.mouse_entered.connect(_show_instant_tip.bind(rect, skill))
	rect.mouse_exited.connect(_hide_instant_tip)
	return rect


## 把说明面板挪到图标正下方并显示出来。
func _show_instant_tip(host: Control, skill: SkillDef) -> void:
	tip_label.text = SkillCatalog.tooltip_text(skill)
	tip_panel.visible = true
	# 先显示再 reset_size，才能拿到文字撑出来的真实尺寸。
	tip_panel.reset_size()
	# 图标的全局坐标换算成 UI 层的局部坐标。
	var ui := $UI as Node2D
	var local := host.global_position - ui.global_position
	tip_panel.position = Vector2(local.x, local.y + host.size.y + 4.0)


func _hide_instant_tip() -> void:
	tip_panel.visible = false


## 刷新血条和血量文字。max_hp 至少按 1 算，避免除零。
func set_hp(hp: int, max_hp: int) -> void:
	hp_bar.max_value = maxi(1, max_hp)
	hp_bar.value = hp
	hp_label.text = "%s / %s" % [NumberFormat.compact(hp), NumberFormat.compact(max_hp)]


## 回到站立：换回站立立绘并循环播待机动画。
func play_idle() -> void:
	sprite.texture = _idle_tex
	if anim_player.has_animation(&"idle"):
		anim_player.play(&"idle")


## 出招：换攻击立绘，亮出从自身砍向对手的剑。
func play_attack() -> void:
	sprite.texture = _attack_tex
	slash.visible = true
	# 每次都重置刀光的颜色和大小，暴击特效可能把它改过。
	slash.color = Color(0.95, 0.95, 1.0, 0.95)
	slash.scale = Vector2.ONE
	slash.position = Vector2.ZERO
	if anim_player.has_animation(&"attack"):
		anim_player.play(&"attack")


## 挨打：换受击立绘（脸上带红痕）。
func play_hurt() -> void:
	sprite.texture = _hurt_tex
	if anim_player.has_animation(&"hurt"):
		anim_player.play(&"hurt")


## 倒下：转倒并淡出，不再回到站立。
func play_death() -> void:
	if anim_player.has_animation(&"death"):
		anim_player.play(&"death")


## 闪避 / 凌波微步：后退约 1 个自身身位，原位到终点叠 3 个当前立绘。
func play_dodge() -> void:
	var offset := Vector2(CombatFx.dodge_sprite_offset(), 0.0)
	CombatFx.spawn_afterimages(sprite, _afterimages, offset)
	if anim_player.has_animation(&"dodge"):
		anim_player.play(&"dodge")
	var fade := create_tween()
	fade.tween_interval(0.36)
	fade.tween_callback(func() -> void:
		if is_instance_valid(_afterimages):
			NodeUtil.clear_children(_afterimages)
	)


## 暴击特效：大爆炸粒子 + 金色刀光 + 立绘闪一下金。
func play_crit_fx() -> void:
	CombatFx.burst(_crit_fx)
	slash.visible = true
	slash.color = Color(1.0, 0.85, 0.2, 0.95)
	_fx_tween = _restart_tint(Color(1.0, 0.92, 0.35), Color.WHITE, 0.28, true)


## 中毒特效：红色粒子 + 立绘泛红，和治疗绿粒子区分开。
func play_poison_fx() -> void:
	CombatFx.burst(_poison_fx)
	_fx_tween = _restart_tint(Color(1.0, 0.35, 0.32), Color(1.0, 0.7, 0.68), 0.35, false)


## 麻痹特效：黄色粒子 + 立绘泛黄。
func play_paralyze_fx() -> void:
	CombatFx.burst(_paralyze_fx)
	_fx_tween = _restart_tint(Color(1.0, 0.95, 0.35), Color(1.0, 0.92, 0.55), 0.35, false)


## 混乱特效：头顶眩晕星旋转。
func play_confuse_fx() -> void:
	_stun_fx.visible = true
	_stun_fx.rotation = 0.0
	if _stun_tween:
		_stun_tween.kill()
	_stun_tween = create_tween()
	_stun_tween.set_loops()
	_stun_tween.tween_property(_stun_fx, "rotation", TAU, 0.8)


## 幻影刺杀：在对方身上盖红色画了 X 的骷髅。
func play_assassinate_fx() -> void:
	_skull_fx.visible = true
	_skull_fx.modulate = Color(1, 1, 1, 1)
	_skull_fx.scale = Vector2(0.6, 0.6)
	if _skull_tween:
		_skull_tween.kill()
	_skull_tween = create_tween()
	_skull_tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_skull_tween.tween_property(_skull_fx, "scale", Vector2.ONE, 0.18)
	_skull_tween.tween_interval(0.45)
	_skull_tween.tween_property(_skull_fx, "modulate:a", 0.0, 0.2)
	_skull_tween.tween_callback(func() -> void:
		if is_instance_valid(_skull_fx):
			_skull_fx.visible = false
			_skull_fx.modulate = Color.WHITE
	)


## 回血特效：一次性粒子场景 + 立绘泛绿后回白。吸血和治疗共用。
func play_heal_fx() -> void:
	var fx := HEAL_FX.instantiate()
	$Visual.add_child(fx)
	fx.restart()
	fx.emitting = true
	# 粒子播完自己删掉，不然一场下来会攒一堆节点。
	var life := create_tween()
	life.tween_interval(0.7)
	life.tween_callback(fx.queue_free)
	_fx_tween = _restart_tint(Color(0.55, 1.0, 0.7), Color.WHITE, 0.35, false)


## 立绘染色：立刻变成 from，再在 duration 内过渡到 to。
## 每次都先 kill 掉上一个 Tween，否则两个特效会抢着改同一个 modulate。
func _restart_tint(from: Color, to: Color, duration: float, ease_out: bool) -> Tween:
	if _fx_tween:
		_fx_tween.kill()
	var tween := create_tween()
	if ease_out:
		tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	sprite.modulate = from
	tween.tween_property(sprite, "modulate", to, duration)
	return tween


## 测试拿它核对五种动画都建出来了。
func animation_names() -> PackedStringArray:
	return PackedStringArray(["idle", "attack", "hurt", "death", "dodge"])


## 当前显示身宽（像素），闪避位移按它的 1 倍算。
func displayed_body_width() -> float:
	return CombatFx.displayed_body_width($Visual.scale.x)


## 含本体在内的重影个数。闪避播放后应为 3。
func dodge_ghost_count() -> int:
	return 1 + _afterimages.get_child_count()


func _hide_transient_fx() -> void:
	if _afterimages:
		NodeUtil.clear_children(_afterimages)
	if _stun_fx:
		_stun_fx.visible = false
		_stun_fx.rotation = 0.0
	if _skull_fx:
		_skull_fx.visible = false
		_skull_fx.modulate = Color.WHITE
	if _stun_tween:
		_stun_tween.kill()
	if _skull_tween:
		_skull_tween.kill()


## 五种动画全部用代码建，场景文件里不存动画数据。
## 已经建过就直接返回（场景被复用时会重复调）。
func _build_animations() -> void:
	if anim_player.has_animation(&"idle"):
		return
	var lib := AnimationLibrary.new()
	lib.add_animation(&"idle", _idle_anim())
	lib.add_animation(&"attack", _attack_anim())
	lib.add_animation(&"hurt", _hurt_anim())
	lib.add_animation(&"death", _death_anim())
	lib.add_animation(&"dodge", _dodge_anim())
	# 空字符串表示默认库，动画名前面就不用带库名前缀。
	anim_player.add_animation_library(&"", lib)


## 待机：整个人上下浮动，循环播放。
func _idle_anim() -> Animation:
	var anim := Animation.new()
	anim.length = 0.8
	anim.loop_mode = Animation.LOOP_LINEAR
	var track := anim.add_track(Animation.TYPE_VALUE)
	anim.track_set_path(track, NodePath("Visual/Sprite2D:position:y"))
	anim.track_insert_key(track, 0.0, 0.0)
	anim.track_insert_key(track, 0.4, -8.0)
	anim.track_insert_key(track, 0.8, 0.0)
	return anim


## 出招：前冲 + 微微转身 + 剑从自身砍向对手。
func _attack_anim() -> Animation:
	var anim := Animation.new()
	anim.length = 0.36
	anim.loop_mode = Animation.LOOP_NONE
	# 往前冲出去再收回来。
	var pos_track := anim.add_track(Animation.TYPE_VALUE)
	anim.track_set_path(pos_track, NodePath("Visual/Sprite2D:position:x"))
	anim.track_insert_key(pos_track, 0.0, 0.0)
	anim.track_insert_key(pos_track, 0.12, 48.0)
	anim.track_insert_key(pos_track, 0.36, 0.0)
	# 顺带扭一点角度，冲劲更足。
	var rot_track := anim.add_track(Animation.TYPE_VALUE)
	anim.track_set_path(rot_track, NodePath("Visual/Sprite2D:rotation"))
	anim.track_insert_key(rot_track, 0.0, 0.0)
	anim.track_insert_key(rot_track, 0.12, 0.18)
	anim.track_insert_key(rot_track, 0.36, 0.0)
	# 剑只在最前面那一下亮，并往对手方向送出去。
	var slash_track := anim.add_track(Animation.TYPE_VALUE)
	anim.track_set_path(slash_track, NodePath("Visual/Slash:modulate:a"))
	anim.track_insert_key(slash_track, 0.0, 0.0)
	anim.track_insert_key(slash_track, 0.08, 1.0)
	anim.track_insert_key(slash_track, 0.36, 0.0)
	var slash_pos := anim.add_track(Animation.TYPE_VALUE)
	anim.track_set_path(slash_pos, NodePath("Visual/Slash:position:x"))
	anim.track_insert_key(slash_pos, 0.0, 0.0)
	anim.track_insert_key(slash_pos, 0.14, 90.0)
	anim.track_insert_key(slash_pos, 0.36, 40.0)
	var slash_vis := anim.add_track(Animation.TYPE_VALUE)
	anim.track_set_path(slash_vis, NodePath("Visual/Slash:visible"))
	anim.track_insert_key(slash_vis, 0.0, true)
	anim.track_insert_key(slash_vis, 0.36, false)
	return anim


## 受击：往后弹一下，同时闪红。
func _hurt_anim() -> Animation:
	var anim := Animation.new()
	anim.length = 0.28
	anim.loop_mode = Animation.LOOP_NONE
	var pos_track := anim.add_track(Animation.TYPE_VALUE)
	anim.track_set_path(pos_track, NodePath("Visual/Sprite2D:position:x"))
	anim.track_insert_key(pos_track, 0.0, 0.0)
	anim.track_insert_key(pos_track, 0.08, -22.0)
	anim.track_insert_key(pos_track, 0.28, 0.0)
	var mod_track := anim.add_track(Animation.TYPE_VALUE)
	anim.track_set_path(mod_track, NodePath("Visual/Sprite2D:modulate"))
	anim.track_insert_key(mod_track, 0.0, Color.WHITE)
	anim.track_insert_key(mod_track, 0.06, Color("ff6b6b"))
	anim.track_insert_key(mod_track, 0.28, Color.WHITE)
	return anim


## 闪避：往后撤约 1 个身位，顺便压扁一点表示发力。
func _dodge_anim() -> Animation:
	var anim := Animation.new()
	anim.length = 0.36
	anim.loop_mode = Animation.LOOP_NONE
	var pos_track := anim.add_track(Animation.TYPE_VALUE)
	anim.track_set_path(pos_track, NodePath("Visual/Sprite2D:position:x"))
	var dodge_x := CombatFx.dodge_sprite_offset()
	anim.track_insert_key(pos_track, 0.0, 0.0)
	anim.track_insert_key(pos_track, 0.12, dodge_x)
	anim.track_insert_key(pos_track, 0.36, 0.0)
	# 关键帧写的是绝对 scale，所以必须和 BASE_SPRITE_SCALE 对得上。
	var scale_track := anim.add_track(Animation.TYPE_VALUE)
	anim.track_set_path(scale_track, NodePath("Visual/Sprite2D:scale"))
	var base := BASE_SPRITE_SCALE
	anim.track_insert_key(scale_track, 0.0, Vector2(base, base))
	anim.track_insert_key(scale_track, 0.12, Vector2(base - 0.8, base + 0.4))
	anim.track_insert_key(scale_track, 0.36, Vector2(base, base))
	return anim


## 倒下：转倒 + 整体淡到很暗 + 往下沉，结束后停在这个状态不再复位。
func _death_anim() -> Animation:
	var anim := Animation.new()
	anim.length = 0.5
	anim.loop_mode = Animation.LOOP_NONE
	var rot_track := anim.add_track(Animation.TYPE_VALUE)
	anim.track_set_path(rot_track, NodePath("Visual/Sprite2D:rotation"))
	anim.track_insert_key(rot_track, 0.0, 0.0)
	anim.track_insert_key(rot_track, 0.5, 1.2)
	# "." 指 FighterView 自己：连名字血条一起淡下去。
	var mod_track := anim.add_track(Animation.TYPE_VALUE)
	anim.track_set_path(mod_track, NodePath(".:modulate:a"))
	anim.track_insert_key(mod_track, 0.0, 1.0)
	anim.track_insert_key(mod_track, 0.5, 0.15)
	var pos_track := anim.add_track(Animation.TYPE_VALUE)
	anim.track_set_path(pos_track, NodePath("Visual/Sprite2D:position:y"))
	anim.track_insert_key(pos_track, 0.0, 0.0)
	anim.track_insert_key(pos_track, 0.5, 40.0)
	return anim
