class_name RoundRecord
extends RefCounted

## 当天的乱斗战绩：一共打了多少场，以及每位上过榜一（当过擂主）的玩家赢了几场。
##
## 榜单是实时变化的，谁都可能成为榜一，所以只要当过一次擂主、打过一场，
## 就一直留在这份记录里——哪怕一场没赢，也按 0 场显示。
## 存在 user:// 下，退出重进照样在；日期一换就整份作废重来，保证“当天有效”。

## 存档位置。user:// 在 Android 上落在 app 的私有目录里。
const SAVE_PATH := "user://daily_rounds.json"

## 这份记录属于哪一天，格式 "YYYY-MM-DD"。
var date: String = ""
## 当天打完的总场次。
var rounds: int = 0
## username -> {"wins": int, "rounds": int}
var champions: Dictionary = {}


## 读当天的记录。存档是别的日期（或者根本没有、坏了）就返回一份空的。
static func load_for(today: String, path: String = SAVE_PATH) -> RoundRecord:
	var record := RoundRecord.new()
	record.date = today
	# 下面任何一步不对都直接返回这份空记录——存档坏了不该让游戏打不开。
	if not FileAccess.file_exists(path):
		return record
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return record
	var text := file.get_as_text()
	file.close()
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return record
	var data: Dictionary = parsed
	# 关键的一步：存档是昨天的就当没有，当天战绩从零开始。
	if str(data.get("date", "")) != today:
		return record
	record.rounds = maxi(0, int(data.get("rounds", 0)))
	var saved: Variant = data.get("champions", {})
	if typeof(saved) != TYPE_DICTIONARY:
		return record
	var saved_map: Dictionary = saved
	for key in saved_map:
		var entry: Variant = saved_map[key]
		# 单条坏了就跳过这一条，其余的照常读。
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var row: Dictionary = entry
		record.champions[str(key)] = {
			"wins": maxi(0, int(row.get("wins", 0))),
			"rounds": maxi(0, int(row.get("rounds", 0))),
		}
	return record


## 记一场：这场的擂主是谁、他赢没赢。
func record_round(champion_name: String, won: bool) -> void:
	# 没擂主名字的场次不记，否则榜上会多出一个空条目。
	if champion_name.is_empty():
		return
	rounds += 1
	# 第一次上榜一的人现场建条目，从 0 开始记。
	var entry: Dictionary = champions.get(champion_name, {"wins": 0, "rounds": 0})
	entry["rounds"] = int(entry.get("rounds", 0)) + 1
	if won:
		entry["wins"] = int(entry.get("wins", 0)) + 1
	champions[champion_name] = entry


## 胜场从多到少；同胜场的看参战场次，再同就按名字排，保证每次刷新顺序一样。
func standings() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for key in champions:
		var entry: Dictionary = champions[key]
		rows.append({
			"username": str(key),
			"wins": int(entry.get("wins", 0)),
			"rounds": int(entry.get("rounds", 0)),
		})
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a["wins"]) != int(b["wins"]):
			return int(a["wins"]) > int(b["wins"])
		if int(a["rounds"]) != int(b["rounds"]):
			return int(a["rounds"]) > int(b["rounds"])
		# 名字兜底：三项全同也要有个确定的先后，否则每次刷新顺序会跳。
		return str(a["username"]) < str(b["username"])
	)
	return rows


## 落盘。写不进去只警告不报错——战绩丢了不值得把游戏搞崩。
func save(path: String = SAVE_PATH) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_warning("战绩存档写不进去：%s" % path)
		return
	file.store_string(JSON.stringify({
		"date": date,
		"rounds": rounds,
		"champions": champions,
	}))
	file.close()
