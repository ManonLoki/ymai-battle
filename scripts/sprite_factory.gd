class_name SpriteFactory
extends RefCounted

## 按 appearance_id 程序化生成角色立绘，省掉美术资源。
## COUNT 是可选形象总数，Fighter 用用户名的哈希取模来固定每个人的长相。
##
## 每张图都是 32×32 的像素画，靠一堆 _fill_rect 摞出来；
## 三种姿势（idle / attack / hurt）共用同一套画法，只是躯干前倾量和武器位置不同。

## 立绘边长，正方形。
const SIZE := 32
## 可选形象总数。0~3 是四个同款人形，4~7 是四种特殊人形，8~11 是四种动物。
const COUNT := 12
## 0~3 这四个是最初的同款人形（只有配色不同）。
const ORIGINAL_HUMANS := 4
## 从这个编号起是动物。
const ANIMAL_START := 8

## 擂主头顶王冠的颜色。
const CROWN_GOLD := Color(0.98, 0.84, 0.12)
const CROWN_GOLD_DARK := Color(0.72, 0.52, 0.06)
## 受击姿势下脸上那道红痕。
const HURT_FLASH := Color("f85149")

## 前倾像素数：出招时往前探 2 px，挨打时往后仰 1 px，站立不动。
const LEAN_ATTACK := 2
const LEAN_HURT := -1

## 每个 appearance_id 一套配色。键名在各 _draw_* 里统一使用：
## body 衣服 / dark 暗部 / skin 皮肤 / accent 高光 / outline 描边 / weapon 武器。
const PALETTES := [
	{"body": Color("3ec8e0"), "dark": Color("1a6f86"), "skin": Color("f0c7a0"), "accent": Color("e8f7ff"), "outline": Color("0b1c24"), "weapon": Color("7af0ff")},
	{"body": Color("e08a3e"), "dark": Color("8a4a18"), "skin": Color("f3c9a3"), "accent": Color("ffe6c2"), "outline": Color("2a1608"), "weapon": Color("ffd36a")},
	{"body": Color("9b6bff"), "dark": Color("4b2d9b"), "skin": Color("f0c7a0"), "accent": Color("e4d7ff"), "outline": Color("1b0f33"), "weapon": Color("ff7ad9")},
	{"body": Color("6fbf4a"), "dark": Color("2f6b24"), "skin": Color("c8e8b8"), "accent": Color("eaffd6"), "outline": Color("10240c"), "weapon": Color("d4ff7a")},
	{"body": Color("c45c7a"), "dark": Color("6e2438"), "skin": Color("f2c2b0"), "accent": Color("ffd0dc"), "outline": Color("2a0c14"), "weapon": Color("ff8aa8")},
	{"body": Color("4a63c8"), "dark": Color("1c2a74"), "skin": Color("e8c4a0"), "accent": Color("c8d4ff"), "outline": Color("0c1230"), "weapon": Color("8aa4ff")},
	{"body": Color("b8860b"), "dark": Color("6a4a08"), "skin": Color("f0d0a8"), "accent": Color("ffe9a8"), "outline": Color("2a1c04"), "weapon": Color("e8c040")},
	{"body": Color("5c5c68"), "dark": Color("2a2a32"), "skin": Color("d8d8e0"), "accent": Color("b0b8c8"), "outline": Color("101014"), "weapon": Color("90a0b8")},
	{"body": Color("e09040"), "dark": Color("8a4a10"), "skin": Color("f4d0a0"), "accent": Color("ffe0b0"), "outline": Color("2a1608"), "weapon": Color("ffb060")},
	{"body": Color("c8a068"), "dark": Color("6a4a28"), "skin": Color("f0d8b0"), "accent": Color("ffe8c8"), "outline": Color("241808"), "weapon": Color("e0b070")},
	{"body": Color("38a0d0"), "dark": Color("145878"), "skin": Color("f0e8c8"), "accent": Color("b8e8ff"), "outline": Color("082028"), "weapon": Color("70d0f0")},
	{"body": Color("e8b8d0"), "dark": Color("8a5070"), "skin": Color("ffe0ec"), "accent": Color("ffd0e8"), "outline": Color("301820"), "weapon": Color("f090b8")},
]


## 画一张立绘。pose 取 "idle" / "attack" / "hurt"，crowned 决定加不加王冠（擂主）。
static func make_texture(appearance_id: int, pose: String = "idle", crowned: bool = false) -> Texture2D:
	var image := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	# 全透明打底，没画到的地方就是镂空。
	image.fill(Color(0, 0, 0, 0))
	# 取模保证任何 id 都能落到合法范围。
	var id := posmod(appearance_id, COUNT)
	var palette: Dictionary = PALETTES[id]
	var attack := pose == "attack"
	var hurt := pose == "hurt"
	# 整个身子的水平偏移，三种姿势各不同。
	var lean := LEAN_ATTACK if attack else (LEAN_HURT if hurt else 0)
	# 按编号分派到各自的画法。
	match id:
		_ when id < ORIGINAL_HUMANS:
			_draw_human_base(image, palette, lean, attack, hurt)
		4:
			_draw_human_tall(image, palette, lean, attack, hurt)
		5:
			_draw_human_bulk(image, palette, lean, attack, hurt)
		6:
			_draw_human_mage(image, palette, lean, attack, hurt)
		7:
			_draw_human_visor(image, palette, lean, attack, hurt)
		ANIMAL_START:
			_draw_cat(image, palette, lean, attack, hurt)
		9:
			_draw_dog(image, palette, lean, attack, hurt)
		10:
			_draw_bird(image, palette, lean, attack, hurt)
		_:
			_draw_bunny(image, palette, lean, attack, hurt)
	# 王冠最后画，盖在头顶上。
	if crowned:
		_draw_crown(image, lean)
	return ImageTexture.create_from_image(image)


## 画一个像素，越界的直接丢掉——各 _draw_* 里的坐标加上 lean 之后可能出界。
static func _px(image: Image, x: int, y: int, color: Color) -> void:
	if x < 0 or y < 0 or x >= SIZE or y >= SIZE:
		return
	image.set_pixel(x, y, color)


## 画一块实心矩形，所有身体部件都是由它摞出来的。
static func _fill_rect(image: Image, x: int, y: int, w: int, h: int, color: Color) -> void:
	for py in range(y, y + h):
		for px in range(x, x + w):
			_px(image, px, py, color)


## 擂主的王冠：一条底边 + 三个尖，尖顶点上一点暗色当阴影。
static func _draw_crown(image: Image, lean: int) -> void:
	_fill_rect(image, 11 + lean, 4, 10, 2, CROWN_GOLD)
	_fill_rect(image, 11 + lean, 3, 2, 3, CROWN_GOLD)
	_fill_rect(image, 15 + lean, 1, 2, 4, CROWN_GOLD)
	_fill_rect(image, 19 + lean, 3, 2, 3, CROWN_GOLD)
	_px(image, 16 + lean, 1, CROWN_GOLD_DARK)
	_px(image, 12 + lean, 3, CROWN_GOLD_DARK)
	_px(image, 20 + lean, 3, CROWN_GOLD_DARK)


## 0~3 号：标准人形，持剑。四个编号只有配色不同。
static func _draw_human_base(image: Image, palette: Dictionary, lean: int, attack: bool, hurt: bool) -> void:
	var outline: Color = palette["outline"]
	var body: Color = palette["body"]
	var dark: Color = palette["dark"]
	var skin: Color = palette["skin"]
	var accent: Color = palette["accent"]
	var weapon: Color = palette["weapon"]
	# 脚底阴影和两条腿。
	_fill_rect(image, 11 + lean, 26, 10, 3, outline)
	_fill_rect(image, 12 + lean, 24, 3, 4, dark)
	_fill_rect(image, 17 + lean, 24, 3, 4, dark)
	# 躯干，外层衣服 + 内层暗部。
	_fill_rect(image, 12 + lean, 14, 8, 11, body)
	_fill_rect(image, 13 + lean, 15, 6, 9, dark.lightened(0.08))
	# 头：帽子边 + 脸。
	_fill_rect(image, 11 + lean, 7, 10, 8, body)
	_fill_rect(image, 12 + lean, 8, 8, 6, skin)
	# 双眼和嘴。
	_fill_rect(image, 13 + lean, 9, 2, 2, outline)
	_fill_rect(image, 17 + lean, 9, 2, 2, outline)
	_fill_rect(image, 14 + lean, 12, 4, 1, outline)
	# 帽檐和两侧护耳。
	_fill_rect(image, 11 + lean, 6, 10, 2, dark)
	_fill_rect(image, 10 + lean, 7, 2, 3, dark)
	_fill_rect(image, 20 + lean, 7, 2, 3, dark)
	# 出招时持剑的手臂抬高并前伸。
	var arm_x := 20 + lean + (4 if attack else 0)
	var arm_y := 16 - (2 if attack else 0)
	# 后手（不持武器的那只）。
	_fill_rect(image, 9 + lean, 16, 3, 6, body)
	# 前手 + 手掌。
	_fill_rect(image, arm_x, arm_y, 5 if attack else 3, 3, body)
	_fill_rect(image, arm_x + (4 if attack else 2), arm_y - 1, 2, 2, skin)
	if attack:
		# 出招：剑横着挥出去。
		_fill_rect(image, arm_x + 5, arm_y - 6, 2, 8, weapon)
		_fill_rect(image, arm_x + 4, arm_y - 7, 4, 2, accent)
	else:
		# 站立：剑竖着背在身侧。
		_fill_rect(image, 21 + lean, 18, 2, 7, weapon)
		_fill_rect(image, 20 + lean, 17, 4, 2, accent)
	# 受击时脸上多一道红痕。
	if hurt:
		_fill_rect(image, 12 + lean, 10, 8, 2, HURT_FLASH)


## 4 号：瘦高个，持长枪。
static func _draw_human_tall(image: Image, palette: Dictionary, lean: int, attack: bool, hurt: bool) -> void:
	var outline: Color = palette["outline"]
	var body: Color = palette["body"]
	var dark: Color = palette["dark"]
	var skin: Color = palette["skin"]
	var weapon: Color = palette["weapon"]
	# 脚底阴影 + 两条细腿。
	_fill_rect(image, 13 + lean, 27, 6, 3, outline)
	_fill_rect(image, 13 + lean, 22, 2, 6, dark)
	_fill_rect(image, 17 + lean, 22, 2, 6, dark)
	# 窄躯干。
	_fill_rect(image, 13 + lean, 12, 6, 12, body)
	# 头和脸。
	_fill_rect(image, 12 + lean, 5, 8, 8, body)
	_fill_rect(image, 13 + lean, 6, 6, 6, skin)
	_fill_rect(image, 14 + lean, 7, 1, 2, outline)
	_fill_rect(image, 17 + lean, 7, 1, 2, outline)
	# 后手。
	_fill_rect(image, 11 + lean, 14, 2, 8, body)
	# 前手和长枪：出招时枪往上抬，站立时拄在地上。
	var ax := 19 + lean + (3 if attack else 0)
	_fill_rect(image, ax, 13, 2, 8, body)
	_fill_rect(image, ax + 1, 11 if attack else 20, 2, 6, weapon)
	if hurt:
		_fill_rect(image, 13 + lean, 8, 6, 2, HURT_FLASH)


## 5 号：壮汉，持大锤。
static func _draw_human_bulk(image: Image, palette: Dictionary, lean: int, attack: bool, hurt: bool) -> void:
	var outline: Color = palette["outline"]
	var body: Color = palette["body"]
	var dark: Color = palette["dark"]
	var skin: Color = palette["skin"]
	var weapon: Color = palette["weapon"]
	# 又宽又矮的脚和腿。
	_fill_rect(image, 9 + lean, 26, 14, 4, outline)
	_fill_rect(image, 10 + lean, 23, 4, 5, dark)
	_fill_rect(image, 18 + lean, 23, 4, 5, dark)
	# 宽躯干。
	_fill_rect(image, 9 + lean, 13, 14, 12, body)
	# 脸和头巾。
	_fill_rect(image, 11 + lean, 6, 10, 8, skin)
	_fill_rect(image, 10 + lean, 5, 12, 3, dark)
	_fill_rect(image, 13 + lean, 8, 2, 2, outline)
	_fill_rect(image, 17 + lean, 8, 2, 2, outline)
	# 粗手臂 + 锤子。
	var ax := 22 + lean + (2 if attack else 0)
	_fill_rect(image, ax, 14, 4, 6, body)
	_fill_rect(image, ax + 2, 10, 3, 8, weapon)
	if hurt:
		_fill_rect(image, 12 + lean, 9, 8, 2, HURT_FLASH)


## 6 号：法师，尖帽 + 长袍 + 法杖。
static func _draw_human_mage(image: Image, palette: Dictionary, lean: int, attack: bool, hurt: bool) -> void:
	var outline: Color = palette["outline"]
	var body: Color = palette["body"]
	var dark: Color = palette["dark"]
	var skin: Color = palette["skin"]
	var accent: Color = palette["accent"]
	var weapon: Color = palette["weapon"]
	# 长袍拖到地上，看不见腿。
	_fill_rect(image, 11 + lean, 26, 10, 3, outline)
	_fill_rect(image, 10 + lean, 14, 12, 13, body)
	# 脸。
	_fill_rect(image, 12 + lean, 8, 8, 7, skin)
	# 尖帽：帽尖 + 帽檐。
	_fill_rect(image, 14 + lean, 2, 4, 7, dark)
	_fill_rect(image, 12 + lean, 6, 8, 3, dark)
	_fill_rect(image, 13 + lean, 10, 2, 2, outline)
	_fill_rect(image, 17 + lean, 10, 2, 2, outline)
	# 法杖 + 杖头宝石，出招时往前伸。
	var staff := 22 + lean + (3 if attack else 0)
	_fill_rect(image, staff, 8, 2, 18, weapon)
	_fill_rect(image, staff - 1, 7, 4, 3, accent)
	if hurt:
		_fill_rect(image, 13 + lean, 11, 6, 2, HURT_FLASH)


## 7 号：护目镜战士。
static func _draw_human_visor(image: Image, palette: Dictionary, lean: int, attack: bool, hurt: bool) -> void:
	var outline: Color = palette["outline"]
	var body: Color = palette["body"]
	var dark: Color = palette["dark"]
	var skin: Color = palette["skin"]
	var accent: Color = palette["accent"]
	var weapon: Color = palette["weapon"]
	_fill_rect(image, 11 + lean, 26, 10, 4, outline)
	_fill_rect(image, 11 + lean, 14, 10, 13, body)
	# 脸上横着一条发亮的护目镜，代替眼睛。
	_fill_rect(image, 11 + lean, 6, 10, 9, skin)
	_fill_rect(image, 12 + lean, 8, 8, 3, accent)
	_fill_rect(image, 11 + lean, 5, 10, 2, dark)
	# 后手 + 前手 + 武器。
	_fill_rect(image, 8 + lean, 16, 3, 5, body)
	var ax := 21 + lean + (3 if attack else 0)
	_fill_rect(image, ax, 15, 4, 4, body)
	_fill_rect(image, ax + 3, 12, 2, 8, weapon)
	if hurt:
		_fill_rect(image, 12 + lean, 10, 8, 2, HURT_FLASH)


## 8 号：猫。尖耳朵 + 长尾巴 + 爪子。
static func _draw_cat(image: Image, palette: Dictionary, lean: int, attack: bool, hurt: bool) -> void:
	var outline: Color = palette["outline"]
	var body: Color = palette["body"]
	var dark: Color = palette["dark"]
	var skin: Color = palette["skin"]
	var weapon: Color = palette["weapon"]
	# 身子和两条后腿。
	_fill_rect(image, 10 + lean, 20, 12, 8, body)
	_fill_rect(image, 11 + lean, 26, 3, 4, dark)
	_fill_rect(image, 18 + lean, 26, 3, 4, dark)
	# 大头 + 两只尖耳朵。
	_fill_rect(image, 12 + lean, 8, 10, 10, skin)
	_fill_rect(image, 11 + lean, 4, 3, 6, body)
	_fill_rect(image, 20 + lean, 4, 3, 6, body)
	_fill_rect(image, 14 + lean, 11, 2, 2, outline)
	_fill_rect(image, 18 + lean, 11, 2, 2, outline)
	# 尾巴往身后翘。
	_fill_rect(image, 21 + lean, 18, 6, 2, body)
	_fill_rect(image, 25 + lean, 16, 3, 3, dark)
	# 前爪 + 武器。
	var paw := 20 + lean + (4 if attack else 0)
	_fill_rect(image, paw, 14, 4, 3, skin)
	_fill_rect(image, paw + 3, 10, 2, 6, weapon)
	if hurt:
		_fill_rect(image, 13 + lean, 13, 7, 2, HURT_FLASH)


## 9 号：狗。垂耳 + 长吻。
static func _draw_dog(image: Image, palette: Dictionary, lean: int, attack: bool, hurt: bool) -> void:
	var outline: Color = palette["outline"]
	var body: Color = palette["body"]
	var dark: Color = palette["dark"]
	var skin: Color = palette["skin"]
	var weapon: Color = palette["weapon"]
	_fill_rect(image, 9 + lean, 18, 14, 9, body)
	_fill_rect(image, 10 + lean, 26, 4, 4, dark)
	_fill_rect(image, 18 + lean, 26, 4, 4, dark)
	# 头 + 往前伸的吻部。
	_fill_rect(image, 12 + lean, 8, 10, 11, skin)
	_fill_rect(image, 20 + lean, 12, 6, 4, skin)
	# 两只垂耳。
	_fill_rect(image, 10 + lean, 8, 3, 5, dark)
	_fill_rect(image, 20 + lean, 8, 3, 5, dark)
	_fill_rect(image, 14 + lean, 11, 2, 2, outline)
	_fill_rect(image, 18 + lean, 11, 2, 2, outline)
	_fill_rect(image, 8 + lean, 16, 3, 6, body)
	var ax := 22 + lean + (3 if attack else 0)
	_fill_rect(image, ax, 16, 4, 3, body)
	_fill_rect(image, ax + 3, 12, 2, 7, weapon)
	if hurt:
		_fill_rect(image, 13 + lean, 13, 7, 2, HURT_FLASH)


## 10 号：鸟。喙 + 尾羽 + 翅膀。
static func _draw_bird(image: Image, palette: Dictionary, lean: int, attack: bool, hurt: bool) -> void:
	var outline: Color = palette["outline"]
	var body: Color = palette["body"]
	var dark: Color = palette["dark"]
	var accent: Color = palette["accent"]
	var weapon: Color = palette["weapon"]
	# 身子 + 两条细爪。
	_fill_rect(image, 12 + lean, 14, 10, 10, body)
	_fill_rect(image, 13 + lean, 24, 2, 5, outline)
	_fill_rect(image, 19 + lean, 24, 2, 5, outline)
	# 头 + 尖喙（喙用 weapon 色，它就是这只鸟的武器）。
	_fill_rect(image, 13 + lean, 7, 9, 8, body)
	_fill_rect(image, 21 + lean, 11, 5, 3, weapon)
	_fill_rect(image, 15 + lean, 10, 2, 2, outline)
	# 身后的尾羽。
	_fill_rect(image, 8 + lean, 12, 6, 8, dark)
	# 翅膀，出招时往前扇。
	var wing := 20 + lean + (3 if attack else 0)
	_fill_rect(image, wing, 12, 7, 4, accent)
	if hurt:
		_fill_rect(image, 14 + lean, 12, 6, 2, HURT_FLASH)


## 11 号（以及其余编号的兜底）：兔子。长耳朵。
static func _draw_bunny(image: Image, palette: Dictionary, lean: int, attack: bool, hurt: bool) -> void:
	var outline: Color = palette["outline"]
	var body: Color = palette["body"]
	var dark: Color = palette["dark"]
	var skin: Color = palette["skin"]
	var weapon: Color = palette["weapon"]
	_fill_rect(image, 11 + lean, 18, 10, 10, body)
	_fill_rect(image, 12 + lean, 26, 3, 4, dark)
	_fill_rect(image, 18 + lean, 26, 3, 4, dark)
	# 脸 + 两只竖到画面顶的长耳朵。
	_fill_rect(image, 12 + lean, 10, 9, 9, skin)
	_fill_rect(image, 13 + lean, 1, 2, 10, body)
	_fill_rect(image, 18 + lean, 1, 2, 10, body)
	_fill_rect(image, 14 + lean, 12, 2, 2, outline)
	_fill_rect(image, 17 + lean, 12, 2, 2, outline)
	var paw := 20 + lean + (4 if attack else 0)
	_fill_rect(image, paw, 16, 4, 3, skin)
	_fill_rect(image, paw + 3, 12, 2, 6, weapon)
	if hurt:
		_fill_rect(image, 13 + lean, 14, 6, 2, HURT_FLASH)
