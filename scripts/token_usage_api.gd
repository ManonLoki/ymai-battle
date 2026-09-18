class_name TokenUsageApi
extends Node

## 取当日 token 用量。返回 {"ok": bool, "data": Dictionary, "error": String}，
## 其中 data.channelUsage 是「设备 × 渠道 × 日期」的明细，
## 交给 RankingAggregator 按玩家聚合。

const USAGE_URL := "https://codex-tracker.yunmai365.com/api/v1/token-usage"


## 拉一次接口。失败时不抛异常，统一用 ok=false + error 文案回报。
func fetch_usage() -> Dictionary:
	var http := HTTPRequest.new()
	add_child(http)
	http.timeout = 45.0
	var err := http.request(USAGE_URL, PackedStringArray(["Accept: application/json"]), HTTPClient.METHOD_GET)
	if err != OK:
		http.queue_free()
		return _fail("无法发起请求（错误码 %d）" % err)
	var completed: Array = await http.request_completed
	http.queue_free()
	if completed.size() < 4:
		return _fail("响应不完整")
	var result := int(completed[0])
	var code := int(completed[1])
	var body: PackedByteArray = completed[3]
	if result != HTTPRequest.RESULT_SUCCESS:
		return _fail("网络失败（result=%d）" % result)
	if code != 200:
		return _fail("HTTP %d" % code)
	var parsed: Variant = JSON.parse_string(body.get_string_from_utf8())
	if typeof(parsed) != TYPE_DICTIONARY:
		return _fail("JSON 解析失败")
	var payload: Dictionary = parsed
	if not bool(payload.get("ok", false)):
		return _fail("接口返回失败：%s" % str(payload.get("error", "")))
	var data: Variant = payload.get("data", {})
	if typeof(data) != TYPE_DICTIONARY:
		return _fail("data 字段缺失")
	return {"ok": true, "data": data, "error": ""}


static func _fail(message: String) -> Dictionary:
	return {"ok": false, "data": {}, "error": message}
