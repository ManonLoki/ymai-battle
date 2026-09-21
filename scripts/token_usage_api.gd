class_name TokenUsageApi
extends Node

## 取当日 token 用量看板。返回 {"ok": bool, "data": Dictionary, "error": String}，
## 其中 data.ranking 是已经按逻辑用户聚合好的桶，交给 RankingAggregator 映成 RankedUser。
##
## 做成 Node 是因为 HTTPRequest 必须挂在场景树里；调用方负责 add_child + queue_free。

## 接口路径。换服务器只换基址，路径和当天 from/to 由代码拼。
const USAGE_PATH := "/api/v2/token-usage/dashboard"
## 没在设置里填服务器地址时用的线上地址（不含 query）。
const DEFAULT_USAGE_URL := "https://codex-tracker.yunmai365.com/api/v2/token-usage/dashboard"
## 看板序列化上限是 16 MiB；客户端按同一预算拒绝，避免合法看板被 8 MiB 误杀。
const MAX_RESPONSE_BYTES := 16 * 1024 * 1024
## 慢速电视网络仍保留原有等待窗口，但请求边界统一在构造函数里设置，测试可以
## 直接验证真实 HTTPRequest 实例，不靠源码字符串猜测。
const REQUEST_TIMEOUT_SECONDS := 45.0


## 这一次该请求哪个地址。候选服务器可能来自 Web 参数，也可能来自本地存档；
## 只有当前选择仍属于活动候选列表时才生效，否则回落到默认地址。
## 默认参数每次调用都现读选择，所以设置页改完不用重启，下一场取榜单就生效；
## 显式传 base 则是「就按这个基址算」，设置页预览和测试都走这条。
## from/to 是当天闭区间，YYYY-MM-DD，每次现取以免跨夜还打昨天。
static func usage_url(base: String = WebLaunchConfig.effective_base_url()) -> String:
	var root := DEFAULT_USAGE_URL if base.is_empty() else base + USAGE_PATH
	var day := DayClock.today()
	return "%s?from=%s&to=%s" % [root, day, day]


## 设置页给人看的 Host。空基址是「默认」；自定义地址去掉协议，只保留主机和端口。
static func display_host(base: String = WebLaunchConfig.effective_base_url()) -> String:
	return "默认" if base.is_empty() else AppSettings.base_url_host(base)


## 每次请求都新建一个实例，并在发出前锁住所有网络边界。
## max_redirects=0 很重要：宿主只批准了精确 BaseURL 对应的固定路径，不能让
## 对方通过 30x 把请求带到任意新地址。
static func new_http_request() -> HTTPRequest:
	var http := HTTPRequest.new()
	http.timeout = REQUEST_TIMEOUT_SECONDS
	http.max_redirects = 0
	http.body_size_limit = MAX_RESPONSE_BYTES
	return http


## 把需要对用户明确说明的传输失败单独翻译。响应过大和重定向都属于主动拒绝，
## 不能混成普通“网络失败”，否则界面上看不出安全边界真的生效了。
static func transport_error_message(result: int) -> String:
	if result == HTTPRequest.RESULT_BODY_SIZE_LIMIT_EXCEEDED:
		return "响应体超过 %d MiB 限制" % (MAX_RESPONSE_BYTES / 1024 / 1024)
	if result == HTTPRequest.RESULT_REDIRECT_LIMIT_REACHED:
		return "服务器返回了重定向，已拒绝"
	return "网络失败（result=%d）" % result


## 业务层拒绝可能携带服务端自定义 error，但它属于不可信响应正文，不能直接
## 显示给用户。这里故意忽略完整 payload，只返回稳定的本地文案。
static func api_rejection_message(_payload: Dictionary) -> String:
	return "接口返回失败"


## 把看板 data 映成名单日期 + RankedUser[]。fetch_ranking 和测试走同一条纯函数。
static func users_from_dashboard(data: Dictionary) -> Dictionary:
	var date := str(data.get("from", "")).strip_edges()
	if date.is_empty():
		date = DayClock.today()
	var ranking_raw: Variant = data.get("ranking", [])
	var ranking: Array = ranking_raw if typeof(ranking_raw) == TYPE_ARRAY else []
	var users: Array[RankedUser] = RankingAggregator.rank_users(ranking)
	return {"date": date, "users": users}


## 拉一次接口。失败时不抛异常，统一用 ok=false + error 文案回报。
func fetch_usage() -> Dictionary:
	# HTTPRequest 用完即弃，避免复用时残留上一次的回调。
	var http := new_http_request()
	add_child(http)
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
		return _fail(transport_error_message(result))
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
		return _fail(api_rejection_message(payload))
	var data: Variant = payload.get("data", {})
	if typeof(data) != TYPE_DICTIONARY:
		return _fail("data 字段缺失")
	return {"ok": true, "data": data, "error": ""}


## 统一的失败返回，保证调用方永远能拿到同一套字段。
static func _fail(message: String) -> Dictionary:
	return {"ok": false, "data": {}, "error": message}


## 拉一次接口并直接聚合成当日排行榜。对战和排行两个场景要的都是这个结果，
## 它们不该各自知道 HTTPRequest 要挂在树上、也不该知道桶长什么样。
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
	var mapped: Dictionary = users_from_dashboard(data)
	var users: Array[RankedUser] = []
	users.assign(mapped["users"])
	return {"ok": true, "date": str(mapped["date"]), "users": users, "error": ""}
