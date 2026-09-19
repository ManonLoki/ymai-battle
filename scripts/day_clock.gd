class_name DayClock
extends RefCounted

## 系统日期的唯一入口，外加“跨天了没有”的判断。
##
## 对战和排行两个场景都会整夜开着，所以“今天是哪天”必须每次现取——
## 在 _ready 里算一次存着，挂到第二天就还在拿昨天的数据。
## 这里只取值和比较、不缓存，两个场景问的就是同一个问题、走的同一条路。


## 今天的日期字符串（YYYY-MM-DD），榜单和存档都用它当键。
static func today() -> String:
	return Time.get_date_string_from_system()


## 手上这份数据标着 shown_date，它是不是已经不属于今天了。
static func rolled_over(shown_date: String) -> bool:
	return shown_date != today()
