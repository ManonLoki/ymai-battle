class_name FighterView
extends Node2D

## 场上一名角色的表现层：立绘、血条、buff / 技能图标和悬停说明。
## 只负责播放 battle.gd 交代的动画，不参与任何战斗判定。

const APPEARANCE_COUNT := SpriteFactory.COUNT
## 立绘基础放大倍数（32px 的像素画放到 224px）。
const BASE_SPRITE_SCALE := 7.0
## 擂主比挑战者大一圈，一眼看出谁是榜一。
## 体型不只是观感：Fighter 那边按它给了先天闪避 / 减伤的差异。
const CHAMPION_BODY_SCALE := 1.1
const CHALLENGER_BODY_SCALE := 0.9
const HEAL_FX := preload("res://scenes/heal_fx.tscn")

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

var _idle_tex: Texture2D
var _attack_tex: Texture2D
var _hurt_tex: Texture2D
var _facing_left := false
var _home: Vector2 = Vector2.ZERO
var _crit_fx: CPUParticles2D
var _poison_fx: CPUParticles2D
var _fx_tween: Tween


func _ready() -> void:
	_home = position
	_build_animations()
	slash.visible = false
	_crit_fx = _make_burst(Color(1.0, 0.82, 0.15, 1.0), 28, Vector2(0, 20))
	_poison_fx = _make_burst(Color(0.35, 0.95, 0.28, 1.0), 16, Vector2(0, 40))
	$Visual.add_child(_crit_fx)
	$Visual.add_child(_poison_fx)
	for label in [name_label, hp_label, tip_label]:
		label.add_theme_font_override("font", ThemeHelper.UI_FONT)
	tip_panel.visible = false
	if anim_player.has_animation(&"idle"):
		anim_player.play(&"idle")


func bind(fighter: Fighter, face_left: bool) -> void:
	_facing_left = face_left
	_idle_tex = SpriteFactory.make_texture(fighter.appearance_id, "idle", fighter.is_champion)
	_attack_tex = SpriteFactory.make_texture(fighter.appearance_id, "attack", fighter.is_champion)
	_hurt_tex = SpriteFactory.make_texture(fighter.appearance_id, "hurt", fighter.is_champion)
	sprite.texture = _idle_tex
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
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
	hp_bar.step = 0.0
	set_hp(fighter.hp, fighter.max_hp)
	_fill_icons(fighter)
	_align_icon_rows_to_hp()
	call_deferred("_align_icon_rows_to_hp")
	modulate = Color.WHITE
	rotation = 0.0
	position = _home
	visible = true
	if anim_player.has_animation(&"idle"):
		anim_player.play(&"idle")


func _fill_icons(fighter: Fighter) -> void:
	_clear_row(buff_row)
	_clear_row(skill_row)
	var icon_px := 20
	# 每个 agent 一个 buff 图标，用了几个 agent 就挂几个。
	for buff in fighter.agent_buffs:
		if buff.icon_id.is_empty():
			continue
		buff_row.add_child(_icon_rect(buff, icon_px))
	for skill in fighter.skills:
		if skill.icon_id.is_empty():
			continue
		skill_row.add_child(_icon_rect(skill, icon_px))
	_fit_row(buff_row, icon_px)
	_fit_row(skill_row, icon_px)
	_align_icon_rows_to_hp()


func _clear_row(row: HBoxContainer) -> void:
	for child in row.get_children():
		row.remove_child(child)
		child.free()


func _fit_row(row: HBoxContainer, icon_px: int) -> void:
	var count := row.get_child_count()
	var width := float(count * icon_px + maxi(0, count - 1) * 4)
	row.alignment = BoxContainer.ALIGNMENT_BEGIN
	row.custom_minimum_size = Vector2(maxi(int(width), icon_px), icon_px)
	row.size = row.custom_minimum_size
	row.reset_size()


func _align_icon_rows_to_hp() -> void:
	status_row.reset_size()
	var left := hp_wrap.position.x
	if left <= 1.0:
		left = name_label.custom_minimum_size.x + float(status_row.get_theme_constant("separation"))
	for row in [buff_row, skill_row]:
		row.alignment = BoxContainer.ALIGNMENT_BEGIN
		row.offset_left = left
		row.position.x = left
		row.reset_size()


func _icon_rect(skill: SkillDef, px: int) -> TextureRect:
	var rect := TextureRect.new()
	rect.custom_minimum_size = Vector2(px, px)
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	rect.texture = SkillCatalog.load_icon(skill.icon_id)
	rect.tooltip_text = ""
	rect.focus_mode = Control.FOCUS_NONE
	rect.mouse_filter = Control.MOUSE_FILTER_STOP
	rect.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	rect.mouse_entered.connect(_show_instant_tip.bind(rect, skill))
	rect.mouse_exited.connect(_hide_instant_tip)
	return rect


func _show_instant_tip(host: Control, skill: SkillDef) -> void:
	tip_label.text = SkillCatalog.tooltip_text(skill)
	tip_panel.visible = true
	tip_panel.reset_size()
	var ui := $UI as Node2D
	var local := host.global_position - ui.global_position
	tip_panel.position = Vector2(local.x, local.y + host.size.y + 4.0)


func _hide_instant_tip() -> void:
	tip_panel.visible = false


func set_hp(hp: int, max_hp: int) -> void:
	hp_bar.max_value = maxi(1, max_hp)
	hp_bar.value = hp
	hp_label.text = "%s / %s" % [ThemeHelper.compact(hp), ThemeHelper.compact(max_hp)]


func play_idle() -> void:
	sprite.texture = _idle_tex
	if anim_player.has_animation(&"idle"):
		anim_player.play(&"idle")


func play_attack() -> void:
	sprite.texture = _attack_tex
	slash.visible = true
	slash.color = Color(1, 1, 1, 0.85)
	slash.scale = Vector2.ONE
	if anim_player.has_animation(&"attack"):
		anim_player.play(&"attack")


func play_hurt() -> void:
	sprite.texture = _hurt_tex
	if anim_player.has_animation(&"hurt"):
		anim_player.play(&"hurt")


func play_death() -> void:
	if anim_player.has_animation(&"death"):
		anim_player.play(&"death")


func play_dodge() -> void:
	if anim_player.has_animation(&"dodge"):
		anim_player.play(&"dodge")


func play_crit_fx() -> void:
	_burst(_crit_fx)
	slash.visible = true
	slash.color = Color(1.0, 0.85, 0.2, 0.95)
	if _fx_tween:
		_fx_tween.kill()
	_fx_tween = create_tween()
	_fx_tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	sprite.modulate = Color(1.0, 0.92, 0.35)
	_fx_tween.tween_property(sprite, "modulate", Color.WHITE, 0.28)


func play_poison_fx() -> void:
	_burst(_poison_fx)
	if _fx_tween:
		_fx_tween.kill()
	_fx_tween = create_tween()
	sprite.modulate = Color(0.45, 1.0, 0.4)
	_fx_tween.tween_property(sprite, "modulate", Color(0.7, 1.0, 0.65), 0.35)


func play_heal_fx() -> void:
	var fx := HEAL_FX.instantiate()
	$Visual.add_child(fx)
	fx.restart()
	fx.emitting = true
	var life := create_tween()
	life.tween_interval(0.7)
	life.tween_callback(fx.queue_free)
	if _fx_tween:
		_fx_tween.kill()
	_fx_tween = create_tween()
	sprite.modulate = Color(0.55, 1.0, 0.7)
	_fx_tween.tween_property(sprite, "modulate", Color.WHITE, 0.35)


func animation_names() -> PackedStringArray:
	return PackedStringArray(["idle", "attack", "hurt", "death", "dodge"])


func _make_burst(color: Color, amount: int, grav: Vector2) -> CPUParticles2D:
	var particles := CPUParticles2D.new()
	particles.emitting = false
	particles.one_shot = true
	particles.explosiveness = 0.94
	particles.amount = amount
	particles.lifetime = 0.42
	particles.direction = Vector2(0, -1)
	particles.spread = 80.0
	particles.gravity = grav
	particles.initial_velocity_min = 50.0
	particles.initial_velocity_max = 140.0
	particles.scale_amount_min = 2.0
	particles.scale_amount_max = 5.0
	particles.color = color
	particles.local_coords = true
	return particles


func _burst(particles: CPUParticles2D) -> void:
	particles.restart()
	particles.emitting = true


func _build_animations() -> void:
	if anim_player.has_animation(&"idle"):
		return
	var lib := AnimationLibrary.new()
	lib.add_animation(&"idle", _idle_anim())
	lib.add_animation(&"attack", _attack_anim())
	lib.add_animation(&"hurt", _hurt_anim())
	lib.add_animation(&"death", _death_anim())
	lib.add_animation(&"dodge", _dodge_anim())
	anim_player.add_animation_library(&"", lib)


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


func _attack_anim() -> Animation:
	var anim := Animation.new()
	anim.length = 0.36
	anim.loop_mode = Animation.LOOP_NONE
	var pos_track := anim.add_track(Animation.TYPE_VALUE)
	anim.track_set_path(pos_track, NodePath("Visual/Sprite2D:position:x"))
	anim.track_insert_key(pos_track, 0.0, 0.0)
	anim.track_insert_key(pos_track, 0.12, 48.0)
	anim.track_insert_key(pos_track, 0.36, 0.0)
	var rot_track := anim.add_track(Animation.TYPE_VALUE)
	anim.track_set_path(rot_track, NodePath("Visual/Sprite2D:rotation"))
	anim.track_insert_key(rot_track, 0.0, 0.0)
	anim.track_insert_key(rot_track, 0.12, 0.18)
	anim.track_insert_key(rot_track, 0.36, 0.0)
	var slash_track := anim.add_track(Animation.TYPE_VALUE)
	anim.track_set_path(slash_track, NodePath("Visual/Slash:modulate:a"))
	anim.track_insert_key(slash_track, 0.0, 0.0)
	anim.track_insert_key(slash_track, 0.1, 1.0)
	anim.track_insert_key(slash_track, 0.36, 0.0)
	return anim


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


func _dodge_anim() -> Animation:
	var anim := Animation.new()
	anim.length = 0.36
	anim.loop_mode = Animation.LOOP_NONE
	var pos_track := anim.add_track(Animation.TYPE_VALUE)
	anim.track_set_path(pos_track, NodePath("Visual/Sprite2D:position:x"))
	anim.track_insert_key(pos_track, 0.0, 0.0)
	anim.track_insert_key(pos_track, 0.12, -72.0)
	anim.track_insert_key(pos_track, 0.36, 0.0)
	var scale_track := anim.add_track(Animation.TYPE_VALUE)
	anim.track_set_path(scale_track, NodePath("Visual/Sprite2D:scale"))
	anim.track_insert_key(scale_track, 0.0, Vector2(7, 7))
	anim.track_insert_key(scale_track, 0.12, Vector2(6.2, 7.4))
	anim.track_insert_key(scale_track, 0.36, Vector2(7, 7))
	return anim


func _death_anim() -> Animation:
	var anim := Animation.new()
	anim.length = 0.5
	anim.loop_mode = Animation.LOOP_NONE
	var rot_track := anim.add_track(Animation.TYPE_VALUE)
	anim.track_set_path(rot_track, NodePath("Visual/Sprite2D:rotation"))
	anim.track_insert_key(rot_track, 0.0, 0.0)
	anim.track_insert_key(rot_track, 0.5, 1.2)
	var mod_track := anim.add_track(Animation.TYPE_VALUE)
	anim.track_set_path(mod_track, NodePath(".:modulate:a"))
	anim.track_insert_key(mod_track, 0.0, 1.0)
	anim.track_insert_key(mod_track, 0.5, 0.15)
	var pos_track := anim.add_track(Animation.TYPE_VALUE)
	anim.track_set_path(pos_track, NodePath("Visual/Sprite2D:position:y"))
	anim.track_insert_key(pos_track, 0.0, 0.0)
	anim.track_insert_key(pos_track, 0.5, 40.0)
	return anim
