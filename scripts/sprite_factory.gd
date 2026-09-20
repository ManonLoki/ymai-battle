class_name SpriteFactory
extends RefCounted

## 按 appearance_id 程序化生成角色立绘，省掉美术资源。
## COUNT 是可选形象总数，Fighter 用用户名的哈希取模来固定每个人的长相。
##
## 每张图都是 32×32 的像素画，靠一堆 _fill_rect 摞出来；
## 三种姿势（idle / attack / hurt）共用同一套画法，只是躯干前倾量和武器位置不同。

## 立绘边长，正方形。
const SIZE := 32
## 可选形象总数。0~3 是四个同款人形，4~7 是四种特殊人形，8~11 是四种动物，12~21 是新增形象。
const COUNT := 22
## 0~3 这四个是最初的同款人形（只有配色不同）。
const ORIGINAL_HUMANS := 4
## 原有动物形象起点；8~11 是猫、狗、鸟、兔。
const ANIMAL_START := 8
## 本批新增形象起点。
const NEW_APPEARANCE_START := 12

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
	{"body": Color("45a857"), "dark": Color("1f5c35"), "skin": Color("f3c9a5"), "accent": Color("f2cf63"), "outline": Color("14251b"), "weapon": Color("8be6d2")},
	{"body": Color("b9d9e8"), "dark": Color("668ba0"), "skin": Color("e9f6ff"), "accent": Color("ffffff"), "outline": Color("263a50"), "weapon": Color("8bd9ff")},
	{"body": Color("a9b3c2"), "dark": Color("505b6b"), "skin": Color("e3b58f"), "accent": Color("e8edf5"), "outline": Color("202733"), "weapon": Color("d5e4f0")},
	{"body": Color("9b6438"), "dark": Color("57351f"), "skin": Color("c98b56"), "accent": Color("e3bd7d"), "outline": Color("2a1a12"), "weapon": Color("76c75b")},
	{"body": Color("f4d13f"), "dark": Color("6b4423"), "skin": Color("ffe76d"), "accent": Color("ef5145"), "outline": Color("2b2417"), "weapon": Color("8cecff")},
	{"body": Color("65717f"), "dark": Color("28323d"), "skin": Color("e8edf0"), "accent": Color("dc8090"), "outline": Color("111820"), "weapon": Color("8fc9df")},
	{"body": Color("4f9c50"), "dark": Color("215333"), "skin": Color("8dd06c"), "accent": Color("e8d291"), "outline": Color("14251b"), "weapon": Color("ff784f")},
	{"body": Color("f2cc3d"), "dark": Color("bf7b24"), "skin": Color("ffe874"), "accent": Color("9bd7f5"), "outline": Color("32281a"), "weapon": Color("ef8b2c")},
	{"body": Color("3275c7"), "dark": Color("184477"), "skin": Color("efb27e"), "accent": Color("df3f3f"), "outline": Color("271b19"), "weapon": Color("f6d06b")},
	{"body": Color("df4f62"), "dark": Color("9e2638"), "skin": Color("f5a3bc"), "accent": Color("e86f96"), "outline": Color("3d2730"), "weapon": Color("ffe07a")},
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
		11:
			_draw_bunny(image, palette, lean, attack, hurt)
		12:
			_draw_forest_elf(image, palette, lean, attack, hurt)
		13:
			_draw_ghost(image, palette, lean, attack, hurt)
		14:
			_draw_knight(image, palette, lean, attack, hurt)
		15:
			_draw_mole_trio(image, palette, lean, attack, hurt)
		16:
			_draw_electric_mouse(image, palette, lean, attack, hurt)
		17:
			_draw_upright_cat(image, palette, lean, attack, hurt)
		18:
			_draw_dragon(image, palette, lean, attack, hurt)
		19:
			_draw_yellow_duck(image, palette, lean, attack, hurt)
		20:
			_draw_plumber(image, palette, lean, attack, hurt)
		21:
			_draw_pink_piglet(image, palette, lean, attack, hurt)
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


## 11 号：兔子。长耳朵。
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


## 12 号：女性精灵。尖耳、长发、短裙和弓让轮廓与普通人形区分开。
static func _draw_forest_elf(image: Image, palette: Dictionary, lean: int, attack: bool, hurt: bool) -> void:
	var outline: Color = palette["outline"]
	var body: Color = palette["body"]
	var dark: Color = palette["dark"]
	var skin: Color = palette["skin"]
	var hair: Color = palette["accent"]
	var weapon: Color = palette["weapon"]
	# 细靴和向两侧展开的叶片短裙。
	_fill_rect(image, 11 + lean, 27, 10, 3, outline)
	_fill_rect(image, 12 + lean, 23, 3, 5, dark)
	_fill_rect(image, 18 + lean, 23, 3, 5, dark)
	_fill_rect(image, 10 + lean, 18, 13, 3, body)
	_fill_rect(image, 12 + lean, 15, 9, 7, body)
	_fill_rect(image, 11 + lean, 21, 4, 3, body)
	_fill_rect(image, 18 + lean, 21, 4, 3, body)
	# 长发包住脸，左右两只耳朵各伸出三像素。
	_fill_rect(image, 11 + lean, 5, 11, 4, hair)
	_fill_rect(image, 10 + lean, 8, 13, 7, hair)
	_fill_rect(image, 12 + lean, 7, 9, 8, skin)
	_fill_rect(image, 7 + lean, 9, 5, 3, skin)
	_px(image, 6 + lean, 10, skin)
	_fill_rect(image, 21 + lean, 9, 5, 3, skin)
	_px(image, 26 + lean, 10, skin)
	_fill_rect(image, 10 + lean, 12, 2, 6, hair)
	_fill_rect(image, 21 + lean, 12, 2, 7, hair)
	_fill_rect(image, 14 + lean, 9, 2, 2, outline)
	_fill_rect(image, 18 + lean, 9, 2, 2, outline)
	# 拉弓时右臂和箭一起前伸；待机时弓竖在身侧。
	_fill_rect(image, 9 + lean, 15, 3, 5, body)
	var hand_x := 20 + lean + (2 if attack else 0)
	_fill_rect(image, hand_x, 15, 3, 3, skin)
	if attack:
		_fill_rect(image, hand_x + 2, 9, 2, 12, weapon)
		_px(image, hand_x + 1, 10, weapon)
		_px(image, hand_x + 1, 19, weapon)
		_fill_rect(image, hand_x - 3, 14, 10, 1, hair)
		_px(image, hand_x + 7, 14, weapon)
	else:
		_fill_rect(image, 24 + lean, 13, 2, 12, weapon)
		_px(image, 23 + lean, 14, weapon)
		_px(image, 23 + lean, 23, weapon)
	if hurt:
		_fill_rect(image, 12 + lean, 11, 9, 2, HURT_FLASH)


## 13 号：幽灵。没有腿，身体末端是三簇漂浮的雾尾。
static func _draw_ghost(image: Image, palette: Dictionary, lean: int, attack: bool, hurt: bool) -> void:
	var outline: Color = palette["outline"]
	var body: Color = palette["body"]
	var dark: Color = palette["dark"]
	var glow: Color = palette["accent"]
	var wisp: Color = palette["weapon"]
	# 先铺深色外轮廓，再填入浅色幽灵本体。
	_fill_rect(image, 10 + lean, 5, 12, 3, outline)
	_fill_rect(image, 8 + lean, 8, 16, 14, outline)
	_fill_rect(image, 10 + lean, 22, 12, 5, outline)
	_fill_rect(image, 11 + lean, 6, 10, 3, glow)
	_fill_rect(image, 9 + lean, 9, 14, 12, body)
	_fill_rect(image, 11 + lean, 21, 10, 4, body)
	# 锯齿雾尾使下沿不像双脚。
	_fill_rect(image, 10 + lean, 25, 3, 3, body)
	_fill_rect(image, 15 + lean, 24, 3, 4, body)
	_fill_rect(image, 20 + lean, 25, 3, 3, body)
	# 空洞的眼睛；攻击时嘴巴张大。
	_fill_rect(image, 12 + lean, 11, 3, 4, dark)
	_fill_rect(image, 18 + lean, 11, 3, 4, dark)
	if attack:
		_fill_rect(image, 14 + lean, 16, 5, 5, outline)
	else:
		_fill_rect(image, 15 + lean, 17, 3, 2, outline)
	# 两条雾手在攻击时一起扑向前方。
	_fill_rect(image, 5 + lean, 14, 4, 4, body)
	_px(image, 4 + lean, 15, wisp)
	var reach_x := 22 + lean + (3 if attack else 0)
	_fill_rect(image, reach_x, 13, 5, 4, body)
	_px(image, reach_x + 4, 14, wisp)
	if attack:
		_px(image, reach_x + 4, 10, wisp)
		_px(image, reach_x + 3, 12, wisp)
		_px(image, reach_x + 4, 18, wisp)
	if hurt:
		_fill_rect(image, 10 + lean, 14, 13, 2, HURT_FLASH)


## 14 号：骑士。封闭头盔、肩甲、盾牌和长剑组成厚重轮廓。
static func _draw_knight(image: Image, palette: Dictionary, lean: int, attack: bool, hurt: bool) -> void:
	var outline: Color = palette["outline"]
	var armor: Color = palette["body"]
	var dark: Color = palette["dark"]
	var accent: Color = palette["accent"]
	var weapon: Color = palette["weapon"]
	# 铁靴、甲裙和胸甲。
	_fill_rect(image, 9 + lean, 27, 14, 3, outline)
	_fill_rect(image, 10 + lean, 23, 5, 5, dark)
	_fill_rect(image, 18 + lean, 23, 5, 5, dark)
	_fill_rect(image, 10 + lean, 14, 13, 10, armor)
	_fill_rect(image, 8 + lean, 14, 4, 5, accent)
	_fill_rect(image, 21 + lean, 14, 4, 5, accent)
	_fill_rect(image, 15 + lean, 15, 3, 8, dark)
	# 头盔和顶部短羽饰。
	_fill_rect(image, 11 + lean, 5, 11, 10, outline)
	_fill_rect(image, 12 + lean, 6, 9, 8, armor)
	_fill_rect(image, 14 + lean, 2, 3, 4, dark)
	_fill_rect(image, 17 + lean, 3, 4, 3, dark)
	_fill_rect(image, 12 + lean, 9, 9, 3, dark)
	_fill_rect(image, 14 + lean, 10, 5, 1, accent)
	# 左侧方盾始终护住身体。
	_fill_rect(image, 5 + lean, 16, 6, 9, outline)
	_fill_rect(image, 6 + lean, 17, 4, 7, armor)
	_px(image, 8 + lean, 20, accent)
	# 攻击时剑从胸前横刺，待机时剑尖朝上。
	if attack:
		_fill_rect(image, 21 + lean, 16, 9, 2, weapon)
		_fill_rect(image, 21 + lean, 14, 2, 6, dark)
		_px(image, 29 + lean, 16, accent)
	else:
		_fill_rect(image, 25 + lean, 8, 2, 17, weapon)
		_fill_rect(image, 23 + lean, 18, 6, 2, dark)
		_px(image, 26 + lean, 7, accent)
	if hurt:
		_fill_rect(image, 12 + lean, 10, 9, 2, HURT_FLASH)


## 15 号：三只地鼠风格的小兽。三颗脑袋从三个土堆中错落冒出。
static func _draw_mole_trio(image: Image, palette: Dictionary, lean: int, attack: bool, hurt: bool) -> void:
	var outline: Color = palette["outline"]
	var body: Color = palette["body"]
	var dark: Color = palette["dark"]
	var snout: Color = palette["skin"]
	var dirt: Color = palette["accent"]
	var sprout: Color = palette["weapon"]
	var mole_xs := [3, 12, 21]
	var mole_tops := [14, 11, 15]
	if attack:
		# 中间那只率先窜高，三只仍保持群体轮廓。
		mole_tops[1] = 6
	for i in range(3):
		var x: int = mole_xs[i] + lean
		var top: int = mole_tops[i]
		# 每个土堆单独分开，确保一眼能数出三只。
		_fill_rect(image, x - 1, 24, 10, 4, outline)
		_fill_rect(image, x, 23, 8, 4, dirt)
		_fill_rect(image, x + 1, top, 6, 11, outline)
		_fill_rect(image, x + 2, top + 1, 4, 10, body)
		_fill_rect(image, x + 2, top + 4, 5, 4, snout)
		_px(image, x + 5, top + 5, dark)
		_px(image, x + 3, top + 2, outline)
		if hurt:
			_fill_rect(image, x + 1, top + 3, 6, 2, HURT_FLASH)
	# 攻击时中间地鼠举起一对小爪，旁边溅出草叶。
	if attack:
		_fill_rect(image, 11 + lean, 13, 3, 3, snout)
		_fill_rect(image, 18 + lean, 13, 3, 3, snout)
		_px(image, 9 + lean, 21, sprout)
		_px(image, 10 + lean, 20, sprout)
		_px(image, 22 + lean, 21, sprout)
		_px(image, 23 + lean, 20, sprout)


## 16 号：黄色电气鼠风格。长耳、圆红脸颊和折线尾巴是主要特征。
static func _draw_electric_mouse(image: Image, palette: Dictionary, lean: int, attack: bool, hurt: bool) -> void:
	var outline: Color = palette["outline"]
	var body: Color = palette["body"]
	var dark: Color = palette["dark"]
	var face: Color = palette["skin"]
	var cheek: Color = palette["accent"]
	var spark: Color = palette["weapon"]
	# 折线尾巴从身体后方一路折向左上。
	_fill_rect(image, 7 + lean, 17, 5, 3, dark)
	_fill_rect(image, 5 + lean, 14, 4, 4, body)
	_fill_rect(image, 3 + lean, 11, 4, 4, body)
	_fill_rect(image, 5 + lean, 8, 4, 4, body)
	# 身体、短腿和前爪。
	_fill_rect(image, 11 + lean, 18, 13, 9, body)
	_fill_rect(image, 12 + lean, 26, 4, 4, dark)
	_fill_rect(image, 20 + lean, 26, 4, 4, dark)
	_fill_rect(image, 9 + lean, 7, 16, 11, body)
	_fill_rect(image, 11 + lean, 9, 12, 8, face)
	# 两只长耳的顶端颜色更深。
	_fill_rect(image, 11 + lean, 1, 4, 8, body)
	_fill_rect(image, 20 + lean, 1, 4, 8, body)
	_fill_rect(image, 11 + lean, 1, 4, 3, dark)
	_fill_rect(image, 20 + lean, 1, 4, 3, dark)
	_fill_rect(image, 13 + lean, 10, 2, 3, outline)
	_fill_rect(image, 20 + lean, 10, 2, 3, outline)
	_px(image, 17 + lean, 13, outline)
	_fill_rect(image, 10 + lean, 14, 4, 3, cheek)
	_fill_rect(image, 22 + lean, 14, 4, 3, cheek)
	var paw_x := 22 + lean + (2 if attack else 0)
	_fill_rect(image, paw_x, 19, 4, 3, body)
	if attack:
		# 蓝白电火花和身体色分离，出招时很醒目。
		_px(image, paw_x + 4, 16, spark)
		_fill_rect(image, paw_x + 4, 17, 2, 2, spark)
		_fill_rect(image, paw_x + 3, 20, 2, 2, spark)
		_px(image, paw_x + 5, 22, spark)
	if hurt:
		_fill_rect(image, 11 + lean, 12, 13, 2, HURT_FLASH)


## 17 号：直立的灰白猫。胸前白围脖和卷曲大尾巴与 8 号四足猫明显不同。
static func _draw_upright_cat(image: Image, palette: Dictionary, lean: int, attack: bool, hurt: bool) -> void:
	var outline: Color = palette["outline"]
	var body: Color = palette["body"]
	var dark: Color = palette["dark"]
	var fur: Color = palette["skin"]
	var ear: Color = palette["accent"]
	var claw: Color = palette["weapon"]
	# 卷尾先画在身后：先向右，再向上，最后卷回身体。
	_fill_rect(image, 21 + lean, 21, 7, 3, outline)
	_fill_rect(image, 26 + lean, 15, 3, 8, outline)
	_fill_rect(image, 23 + lean, 13, 5, 3, outline)
	_fill_rect(image, 22 + lean, 15, 3, 3, body)
	_fill_rect(image, 22 + lean, 22, 5, 2, body)
	_fill_rect(image, 27 + lean, 16, 2, 6, body)
	# 直立躯干、白围脖和两只宽脚。
	_fill_rect(image, 10 + lean, 17, 13, 10, body)
	_fill_rect(image, 13 + lean, 18, 7, 8, fur)
	_fill_rect(image, 9 + lean, 26, 7, 4, dark)
	_fill_rect(image, 18 + lean, 26, 7, 4, dark)
	# 方脸、尖耳和额头条纹。
	_fill_rect(image, 9 + lean, 6, 15, 12, body)
	_fill_rect(image, 10 + lean, 2, 5, 6, body)
	_fill_rect(image, 19 + lean, 2, 5, 6, body)
	_fill_rect(image, 11 + lean, 4, 2, 3, ear)
	_fill_rect(image, 21 + lean, 4, 2, 3, ear)
	_fill_rect(image, 11 + lean, 12, 11, 5, fur)
	_fill_rect(image, 12 + lean, 9, 2, 2, outline)
	_fill_rect(image, 20 + lean, 9, 2, 2, outline)
	_px(image, 17 + lean, 13, outline)
	_fill_rect(image, 15 + lean, 6, 2, 4, dark)
	_fill_rect(image, 18 + lean, 6, 2, 4, dark)
	# 攻击时一只前爪伸长并亮出三根爪尖。
	_fill_rect(image, 7 + lean, 18, 4, 6, body)
	var paw_x := 21 + lean + (2 if attack else 0)
	_fill_rect(image, paw_x, 17, 5, 5, body)
	if attack:
		_px(image, paw_x + 5, 17, claw)
		_px(image, paw_x + 6, 19, claw)
		_px(image, paw_x + 5, 21, claw)
	if hurt:
		_fill_rect(image, 10 + lean, 11, 13, 2, HURT_FLASH)


## 18 号：巨龙。双翼、双角、长吻和盘向身后的尾巴占满画面。
static func _draw_dragon(image: Image, palette: Dictionary, lean: int, attack: bool, hurt: bool) -> void:
	var outline: Color = palette["outline"]
	var body: Color = palette["body"]
	var dark: Color = palette["dark"]
	var belly: Color = palette["skin"]
	var horn: Color = palette["accent"]
	var flame: Color = palette["weapon"]
	# 左右翼膜在身体之后展开。
	_fill_rect(image, 3 + lean, 9, 8, 3, dark)
	_fill_rect(image, 5 + lean, 12, 6, 8, body)
	_fill_rect(image, 7 + lean, 17, 4, 6, dark)
	_fill_rect(image, 22 + lean, 8, 7, 3, dark)
	_fill_rect(image, 22 + lean, 11, 5, 10, body)
	_fill_rect(image, 22 + lean, 18, 3, 5, dark)
	# 粗壮身躯、腹甲和四肢。
	_fill_rect(image, 9 + lean, 13, 15, 13, outline)
	_fill_rect(image, 10 + lean, 14, 13, 12, body)
	_fill_rect(image, 14 + lean, 16, 6, 10, belly)
	_fill_rect(image, 9 + lean, 24, 6, 5, dark)
	_fill_rect(image, 20 + lean, 24, 6, 5, dark)
	_px(image, 9 + lean, 29, horn)
	_px(image, 14 + lean, 29, horn)
	_px(image, 21 + lean, 29, horn)
	_px(image, 25 + lean, 29, horn)
	# 尾巴向左盘卷，末端形成尖刺。
	_fill_rect(image, 5 + lean, 23, 6, 4, body)
	_fill_rect(image, 2 + lean, 21, 5, 3, body)
	_px(image, 1 + lean, 20, horn)
	# 龙头、角和朝右的长吻。
	_fill_rect(image, 11 + lean, 5, 13, 11, outline)
	_fill_rect(image, 12 + lean, 6, 11, 9, body)
	_fill_rect(image, 21 + lean, 10, 7, 6, outline)
	_fill_rect(image, 21 + lean, 11, 6, 4, belly)
	_fill_rect(image, 13 + lean, 2, 3, 5, horn)
	_fill_rect(image, 20 + lean, 2, 3, 5, horn)
	_fill_rect(image, 19 + lean, 8, 2, 2, outline)
	_px(image, 25 + lean, 12, outline)
	if attack:
		# 张口喷出三段火焰，越靠外越细。
		_fill_rect(image, 25 + lean, 14, 5, 3, outline)
		_fill_rect(image, 26 + lean, 14, 4, 2, flame)
		_px(image, 29 + lean, 13, flame)
		_px(image, 29 + lean, 16, horn)
	if hurt:
		_fill_rect(image, 12 + lean, 10, 12, 2, HURT_FLASH)


## 19 号：黄色鸭子风格。三根头毛、宽扁嘴和抱头翅膀形成独特剪影。
static func _draw_yellow_duck(image: Image, palette: Dictionary, lean: int, attack: bool, hurt: bool) -> void:
	var outline: Color = palette["outline"]
	var body: Color = palette["body"]
	var dark: Color = palette["dark"]
	var face: Color = palette["skin"]
	var aura: Color = palette["accent"]
	var bill: Color = palette["weapon"]
	# 椭圆躯干、蹼足和圆头。
	_fill_rect(image, 10 + lean, 18, 14, 9, body)
	_fill_rect(image, 12 + lean, 25, 4, 4, bill)
	_fill_rect(image, 20 + lean, 25, 4, 4, bill)
	_fill_rect(image, 9 + lean, 7, 15, 12, body)
	_fill_rect(image, 11 + lean, 8, 12, 10, face)
	# 三根稀疏头毛。
	_fill_rect(image, 13 + lean, 3, 2, 5, dark)
	_fill_rect(image, 17 + lean, 2, 2, 6, dark)
	_fill_rect(image, 21 + lean, 3, 2, 5, dark)
	_fill_rect(image, 13 + lean, 10, 2, 3, outline)
	_fill_rect(image, 20 + lean, 10, 2, 3, outline)
	_fill_rect(image, 19 + lean, 14, 8, 4, bill)
	_px(image, 24 + lean, 15, outline)
	# 待机抱头；攻击时右翅前指，并在嘴前出现两道能量波纹。
	_fill_rect(image, 7 + lean, 9, 4, 7, body)
	_fill_rect(image, 8 + lean, 7, 3, 3, bill)
	var wing_x := 21 + lean + (2 if attack else 0)
	var wing_y := 16 if attack else 9
	_fill_rect(image, wing_x, wing_y, 4, 6, body)
	if attack:
		_fill_rect(image, 26 + lean, 10, 2, 2, aura)
		_fill_rect(image, 28 + lean, 8, 2, 6, aura)
		_px(image, 29 + lean, 15, aura)
	else:
		_fill_rect(image, 23 + lean, 7, 3, 3, bill)
	if hurt:
		_fill_rect(image, 11 + lean, 12, 12, 2, HURT_FLASH)


## 20 号：红帽蓝背带裤的水管工风格角色。帽子无文字和标志。
static func _draw_plumber(image: Image, palette: Dictionary, lean: int, attack: bool, hurt: bool) -> void:
	var outline: Color = palette["outline"]
	var overalls: Color = palette["body"]
	var denim_dark: Color = palette["dark"]
	var skin: Color = palette["skin"]
	var red: Color = palette["accent"]
	var button: Color = palette["weapon"]
	# 棕色大鞋、蓝色裤腿和方形背带裤。
	_fill_rect(image, 8 + lean, 27, 8, 3, outline)
	_fill_rect(image, 19 + lean, 27, 8, 3, outline)
	_fill_rect(image, 11 + lean, 22, 5, 6, denim_dark)
	_fill_rect(image, 19 + lean, 22, 5, 6, denim_dark)
	_fill_rect(image, 10 + lean, 15, 15, 9, red)
	_fill_rect(image, 12 + lean, 16, 11, 9, overalls)
	_fill_rect(image, 13 + lean, 14, 3, 6, overalls)
	_fill_rect(image, 20 + lean, 14, 3, 6, overalls)
	_px(image, 14 + lean, 18, button)
	_px(image, 21 + lean, 18, button)
	# 圆鼻、浓胡子和一顶没有标记的红帽。
	_fill_rect(image, 10 + lean, 6, 14, 9, skin)
	_fill_rect(image, 9 + lean, 4, 13, 4, red)
	_fill_rect(image, 12 + lean, 2, 10, 3, red)
	_fill_rect(image, 20 + lean, 5, 6, 2, red)
	_fill_rect(image, 10 + lean, 7, 3, 6, denim_dark)
	_fill_rect(image, 14 + lean, 8, 2, 2, outline)
	_fill_rect(image, 20 + lean, 8, 2, 2, outline)
	_fill_rect(image, 21 + lean, 10, 5, 3, skin)
	_fill_rect(image, 15 + lean, 12, 8, 2, outline)
	# 白手套用金色高光近似；攻击时拳头举高并向前。
	_fill_rect(image, 7 + lean, 16, 4, 6, red)
	_fill_rect(image, 6 + lean, 20, 4, 4, button)
	var fist_x := 22 + lean + (2 if attack else 0)
	var fist_y := 8 if attack else 17
	_fill_rect(image, 23 + lean, 14 if attack else 16, 4, 7, red)
	_fill_rect(image, fist_x, fist_y, 5, 5, button)
	if attack:
		_px(image, fist_x + 2, fist_y - 2, button)
		_px(image, fist_x + 5, fist_y + 1, red)
	if hurt:
		_fill_rect(image, 11 + lean, 10, 13, 2, HURT_FLASH)


## 21 号：粉色小猪。侧向长嘴、圆耳、红裙、细腿黑鞋和卷尾组成鲜明轮廓。
static func _draw_pink_piglet(image: Image, palette: Dictionary, lean: int, attack: bool, hurt: bool) -> void:
	var outline: Color = palette["outline"]
	var dress: Color = palette["body"]
	var dress_dark: Color = palette["dark"]
	var skin: Color = palette["skin"]
	var cheek: Color = palette["accent"]
	var spark: Color = palette["weapon"]
	# 卷尾先画在裙子后面，小方环比一条直尾更容易辨认。
	_fill_rect(image, 6 + lean, 21, 5, 2, skin)
	_fill_rect(image, 4 + lean, 18, 2, 4, skin)
	_fill_rect(image, 5 + lean, 16, 4, 2, skin)
	_fill_rect(image, 8 + lean, 17, 2, 3, skin)
	_px(image, 7 + lean, 19, outline)
	# 红色裙摆逐层变宽，下面露出两条细腿和黑鞋。
	_fill_rect(image, 11 + lean, 17, 12, 4, dress)
	_fill_rect(image, 9 + lean, 20, 16, 5, dress)
	_fill_rect(image, 8 + lean, 24, 18, 3, dress_dark)
	_fill_rect(image, 11 + lean, 27, 2, 3, skin)
	_fill_rect(image, 21 + lean, 27, 2, 3, skin)
	_fill_rect(image, 8 + lean, 29, 6, 2, outline)
	_fill_rect(image, 20 + lean, 29, 6, 2, outline)
	# 侧向圆头和向右突出的长嘴。
	_fill_rect(image, 10 + lean, 6, 13, 12, skin)
	_fill_rect(image, 19 + lean, 10, 9, 7, skin)
	_fill_rect(image, 12 + lean, 3, 6, 5, skin)
	_fill_rect(image, 13 + lean, 4, 4, 3, cheek)
	_fill_rect(image, 16 + lean, 8, 2, 3, outline)
	_px(image, 17 + lean, 8, Color.WHITE)
	_fill_rect(image, 26 + lean, 12, 2, 3, cheek)
	_px(image, 27 + lean, 13, outline)
	_fill_rect(image, 14 + lean, 13, 4, 3, cheek)
	_fill_rect(image, 21 + lean, 16, 4, 1, outline)
	# 一只胳膊留在身后；出招时另一只胳膊前伸并带出亮色星点。
	_fill_rect(image, 7 + lean, 18, 5, 2, skin)
	var arm_x := 21 + lean + (2 if attack else 0)
	var arm_y := 18 if attack else 20
	_fill_rect(image, arm_x, arm_y, 6, 2, skin)
	_fill_rect(image, arm_x + 4, arm_y - 1, 3, 3, skin)
	if attack:
		_px(image, arm_x + 5, arm_y - 3, spark)
		_px(image, arm_x + 6, arm_y - 1, spark)
		_px(image, arm_x + 5, arm_y + 2, spark)
	if hurt:
		_fill_rect(image, 11 + lean, 11, 15, 2, HURT_FLASH)
