class_name BattleParallax
extends TextureRect

## 战斗场景的一张图式视差背景。
##
## 十六张图都保持完整的 16:9 构图，shader 按画面的远景 / 中景 / 近景高度带做
## 不同幅度的水平往返卷轴。背景选择用自己的 RandomNumberGenerator，绝不借用战斗
## 结算的 RollSource；换一张背景因此不会改变任何一次命中、暴击或技能结果。

const BACKGROUND_PATHS: Array[String] = [
	"res://assets/battle_backgrounds/ember_forge.png",
	"res://assets/battle_backgrounds/moonlit_bamboo.png",
	"res://assets/battle_backgrounds/crystal_cavern.png",
	"res://assets/battle_backgrounds/storm_skyship.png",
	"res://assets/battle_backgrounds/spring_tournament_day.png",
	"res://assets/battle_backgrounds/summer_wilderness_day.png",
	"res://assets/battle_backgrounds/autumn_pixel_farm.png",
	"res://assets/battle_backgrounds/winter_high_fantasy.png",
	"res://assets/battle_backgrounds/spring_garden_day.png",
	"res://assets/battle_backgrounds/summer_coast_day.png",
	"res://assets/battle_backgrounds/autumn_valley_day.png",
	"res://assets/battle_backgrounds/winter_village_day.png",
	"res://assets/battle_backgrounds/coral_depths.png",
	"res://assets/battle_backgrounds/cyber_rooftop.png",
	"res://assets/battle_backgrounds/mystic_mushroom_marsh.png",
	"res://assets/battle_backgrounds/desert_oasis_day.png",
]
## 逐张 preload 保证十六张图进入导出包，并把首次 Roll 的磁盘加载挪到进场之前。
const BACKGROUND_TEXTURES: Array[Texture2D] = [
	preload("res://assets/battle_backgrounds/ember_forge.png"),
	preload("res://assets/battle_backgrounds/moonlit_bamboo.png"),
	preload("res://assets/battle_backgrounds/crystal_cavern.png"),
	preload("res://assets/battle_backgrounds/storm_skyship.png"),
	preload("res://assets/battle_backgrounds/spring_tournament_day.png"),
	preload("res://assets/battle_backgrounds/summer_wilderness_day.png"),
	preload("res://assets/battle_backgrounds/autumn_pixel_farm.png"),
	preload("res://assets/battle_backgrounds/winter_high_fantasy.png"),
	preload("res://assets/battle_backgrounds/spring_garden_day.png"),
	preload("res://assets/battle_backgrounds/summer_coast_day.png"),
	preload("res://assets/battle_backgrounds/autumn_valley_day.png"),
	preload("res://assets/battle_backgrounds/winter_village_day.png"),
	preload("res://assets/battle_backgrounds/coral_depths.png"),
	preload("res://assets/battle_backgrounds/cyber_rooftop.png"),
	preload("res://assets/battle_backgrounds/mystic_mushroom_marsh.png"),
	preload("res://assets/battle_backgrounds/desert_oasis_day.png"),
]
const SHADER_TIME_PARAMETER := &"elapsed_seconds"
const SCROLL_DIRECTION_PARAMETER := &"scroll_direction"
const TIME_WRAP_SECONDS := 32.0

## 只供背景挑图的随机源。公开为成员是为了测试能固定 seed；生产环境在 _ready 随机化。
var background_rng := RandomNumberGenerator.new()
## -1 表示只是展示了场景里的预览图、还没有为一场真实战斗掷过背景。
var current_index := -1
var elapsed_seconds := 0.0


func _ready() -> void:
	background_rng.randomize()
	# 像素画不能走线性采样；节点属性也显式设一次，避免场景被复用时继承父节点设置。
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_push_shader_time()


func _process(delta: float) -> void:
	advance_parallax(delta)


## 为一场真实开战随机选图。首次在全部十六张里选；之后保证不连续重复。
## 返回资源路径，方便调试和无渲染测试确认选择结果。
func roll_background() -> String:
	if BACKGROUND_PATHS.is_empty():
		return ""
	var next_index := 0
	if current_index < 0:
		next_index = background_rng.randi_range(0, BACKGROUND_PATHS.size() - 1)
	elif BACKGROUND_PATHS.size() > 1:
		# 在 1..N-1 里掷偏移，分布仍均匀，同时从数学上排除和上一张相同。
		next_index = (current_index + background_rng.randi_range(1, BACKGROUND_PATHS.size() - 1)) % BACKGROUND_PATHS.size()
	if not _apply_background(next_index):
		return ""
	return BACKGROUND_PATHS[current_index]


## 手动推进视差时间。拆成公开函数后，headless 测试不依赖真实帧率也能验证动画。
func advance_parallax(delta: float) -> void:
	if delta <= 0.0:
		return
	elapsed_seconds = fmod(elapsed_seconds + delta, TIME_WRAP_SECONDS)
	_push_shader_time()


func current_background_path() -> String:
	if current_index < 0 or current_index >= BACKGROUND_PATHS.size():
		return ""
	return BACKGROUND_PATHS[current_index]


func _apply_background(index: int) -> bool:
	if index < 0 or index >= BACKGROUND_PATHS.size() or index >= BACKGROUND_TEXTURES.size():
		return false
	var loaded := BACKGROUND_TEXTURES[index]
	if loaded == null:
		push_warning("无法加载战斗背景：%s" % BACKGROUND_PATHS[index])
		return false
	texture = loaded
	current_index = index
	elapsed_seconds = 0.0
	var shader_material := material as ShaderMaterial
	if shader_material != null:
		# 相邻背景从相反方向起步，不额外消耗 RNG，战斗随机序列不变。
		var direction := 1.0 if index % 2 == 0 else -1.0
		shader_material.set_shader_parameter(SCROLL_DIRECTION_PARAMETER, direction)
	_push_shader_time()
	return true


func _push_shader_time() -> void:
	var shader_material := material as ShaderMaterial
	if shader_material != null:
		shader_material.set_shader_parameter(SHADER_TIME_PARAMETER, elapsed_seconds)
