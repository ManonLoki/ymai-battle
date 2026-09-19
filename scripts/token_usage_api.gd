class_name TokenUsageApi
extends Node

## 取当日 token 用量。返回 {"ok": bool, "data": Dictionary, "error": String}，
## 其中 data.channelUsage 是「设备 × 渠道 × 日期」的明细，
## 交给 RankingAggregator 按玩家聚合。
##
## 做成 Node 是因为 HTTPRequest 必须挂在场景树里；调用方负责 add_child + queue_free。

## 接口路径。换服务器只换基址，路径跟着代码走。
const USAGE_PATH := "/api/v1/token-usage"
## 没在设置里填服务器地址时用的线上地址。
const DEFAULT_USAGE_URL := "https://codex-tracker.yunmai365.com/api/v1/token-usage"


## 这一次该请求哪个地址。候选服务器可能来自 Web 参数，也可能来自本地存档；
## 只有当前选择仍属于活动候选列表时才生效，否则回落到默认地址。
## 默认参数每次调用都现读选择，所以设置页改完不用重启，下一场取榜单就生效；
## 显式传 base 则是「就按这个基址算」，设置页预览和测试都走这条。
static func usage_url(base: String = WebLaunchConfig.effective_base_url()) -> String:
	return DEFAULT_USAGE_URL if base.is_empty() else base + USAGE_PATH


## 拉一次接口。失败时不抛异常，统一用 ok=false + error 文案回报。
func fetch_usage() -> Dictionary:
	# HTTPRequest 用完即弃，避免复用时残留上一次的回调。
	var http := HTTPRequest.new()
	add_child(http)
	# 电视上网络可能很慢，给足 45 秒。
	http.timeout = 45.0
	var err := http.request(usage_url(), PackedStringArray(["Accept: application/json"]), HTTPClient.METHOD_GET)
	if err != OK:
		http.queue_free()
		return _fail("无法发起请求（错误码 %d）" % err)
	# 信号返回 [result, response_code, headers, body]。
	var completed: Array = await http.request_completed
	http.queue_free()
	if completed.size() < 4:
		return _fail("响应不完整")
	var result := int(completed[0])
	var code := int(completed[1])
	var body: PackedByteArray = completed[3]
	# 先看传输层有没有成功（DNS、超时、TLS 都在这一层）。
	if result != HTTPRequest.RESULT_SUCCESS:
		return _fail("网络失败（result=%d）" % result)
	# 再看 HTTP 状态码。
	if code != 200:
		return _fail("HTTP %d" % code)
	# 最后才解析 JSON，任何一步不对都按失败回报，不让脏数据流进排行榜。
	var parsed: Variant = JSON.parse_string(body.get_string_from_utf8())
	if typeof(parsed) != TYPE_DICTIONARY:
		return _fail("JSON 解析失败")
	var payload: Dictionary = parsed
	# 业务层自己还有一个 ok 字段，HTTP 200 不代表接口成功。
	if not bool(payload.get("ok", false)):
		return _fail("接口返回失败：%s" % str(payload.get("error", "")))
	var data: Variant = payload.get("data", {})
	if typeof(data) != TYPE_DICTIONARY:
		return _fail("data 字段缺失")
	return {"ok": true, "data": data, "error": ""}


## 统一的失败返回，保证调用方永远能拿到同一套字段。
static func _fail(message: String) -> Dictionary:
	return {"ok": false, "data": {}, "error": message}


## 拉一次接口并直接聚合成当日排行榜。对战和排行两个场景要的都是这个结果，
## 它们不该各自知道 HTTPRequest 要挂在树上、也不该知道明细藏在 data.channelUsage 里。
##
## host 只用来临时挂这个 Node（HTTPRequest 必须在场景树里），用完就地释放。
## 返回 {"ok": bool, "date": String, "users": Array[RankedUser], "error": String}。
static func fetch_ranking(host: Node) -> Dictionary:
	var api := TokenUsageApi.new()
	host.add_child(api)
	var result: Dictionary = await api.fetch_usage()
	if is_instance_valid(api):
		api.queue_free()
	if not bool(result.get("ok", false)):
		return {"ok": false, "date": "", "users": [] as Array[RankedUser], "error": str(result.get("error", "未知错误"))}
	var data: Dictionary = result.get("data", {})
	var usage: Array = data.get("channelUsage", [])
	# 日期每次现取，跨天之后自然就是新一天的榜。
	var today := DayClock.today()
	var users: Array[RankedUser] = RankingAggregator.rank_users(usage, today)
	return {"ok": true, "date": today, "users": users, "error": ""}
