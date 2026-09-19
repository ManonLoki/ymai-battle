class_name NumberFormat
extends RefCounted

## 数字的展示写法。纯字符串处理，不碰任何界面对象——
## 战报（CombatLog）和伤害统计（DamageTally）都要用，它们不该为了格式化
## 去依赖一个拥有字体和 StyleBox 的主题模块。

## 紧凑写法的进位表，从大到小匹配。
const COMPACT_UNITS := [
	[1000000000, "B"],
	[1000000, "M"],
	[1000, "K"],
]

## 数字的紧凑写法：按当前大小自动挂 K / M / B，保留两位小数（四舍五入）。
## 1234 → "1.23K"，348431491 → "348.43M"，2500000000 → "2.50B"。
## 不足 1000 的直接原样输出，不补小数点。
static func compact(n: int) -> String:
	# 先把符号摘出来单独处理，后面只跟绝对值打交道。
	var sign_text := "-" if n < 0 else ""
	var value := absi(n)
	# 从大到小匹配，第一个够得着的单位就是要用的那个。
	for unit in COMPACT_UNITS:
		var step := int(unit[0])
		if value >= step:
			return "%s%.2f%s" % [sign_text, float(value) / float(step), str(unit[1])]
	return sign_text + str(value)


## 千分位写法，排行榜上和 compact 并排显示精确值。
static func with_commas(n: int) -> String:
	var s := str(n)
	var out := ""
	for i in range(s.length()):
		# 从右往左每三位插一个逗号，开头不插。
		if i > 0 and (s.length() - i) % 3 == 0:
			out += ","
		out += s[i]
	return out
