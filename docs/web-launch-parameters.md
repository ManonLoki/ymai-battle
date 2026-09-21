# Web 启动参数

Web 版可在 Godot 启动前通过页面全局对象或 URL 查询参数提供服务器列和需要隐藏的主菜单入口。桌面端、Android 等非 Web 导出不会读取这些参数。

## 页面全局对象

```html
<script>
window.YMAIBattleConfig = {
  BaseURL: [
    { url: "https://battle-a.example.com", name: "华东" },
    { url: "https://battle-b.example.com:8443", name: "" }
  ],
  CloseMenu: ["ranking", "settings", "quit"]
};
</script>
```

`BaseURL` 必须是对象数组，每项格式为 `{url: "", name: ""}`；`name` 可省略或留空。`CloseMenu` 是字符串数组。两个字段本身都可省略。

## URL 查询参数

数组通过重复同名参数传入。每个 `BaseURL` 值是一个 URL 编码后的 JSON 对象：

```text
?BaseURL=%7B%22url%22%3A%22https%3A%2F%2Fbattle-a.example.com%22%2C%22name%22%3A%22%E5%8D%8E%E4%B8%9C%22%7D&BaseURL=%7B%22url%22%3A%22https%3A%2F%2Fbattle-b.example.com%3A8443%22%2C%22name%22%3A%22%22%7D&CloseMenu=ranking&CloseMenu=settings
```

查询参数按字段覆盖页面全局对象。例如查询串只出现 `CloseMenu` 时，页面对象中的 `BaseURL` 仍然有效。只要查询串出现过 `BaseURL`，包括 `BaseURL=`，就以查询串结果为准；显式空值表示本次会话使用空候选列表，不回退到本地列表。

## BaseURL

- 只接受 `http://主机[:端口]` 或 `https://主机[:端口]`，不能包含路径、查询串或账号密码。
- `name` 去掉首尾空白后用于设置页显示；名称为空时显示 URL 的 Host（主机名和可选端口）。
- 无效项和重复 URL 会被丢弃，剩余项保持首次出现的顺序；重复 URL 以第一次出现的名称为准。
- 旧的字符串项（例如 `BaseURL: ["https://battle-a.example.com"]`）不再接受。
- Web 传入 `BaseURL` 时，它是本次会话设置页下拉框的唯一数据源，既不混入本地保存项，也不增加“使用默认服务器”选项，且不能在页面内增删。
- 外部数组非空时，已保存选择仍在数组中则继续使用；未选择或原选择不在数组中时，立即使用数组第一项。
- 外部数组显式为空时没有可选服务器，使用程序内置服务器。
- 未传入时，下拉框使用本地保存的服务器列表，并允许在维护面板中增加、修改名称和 URL 或删除；本地列表保留“使用默认服务器”选项。
- Web 注入列表不会写进本地候选列表。

## 本地服务器

本地候选也按 `{url: "", name: ""}` 保存，与 Web 输入结构一致。旧版存档中的字符串数组会自动按 `name: ""` 读取，用户下一次增删改时再写回新结构。维护面板内的名称可选，留空时同样显示 URL 的 Host。

## CloseMenu

可用菜单 ID：

| ID | 主菜单入口 |
| --- | --- |
| `ranking` | 查看排行 |
| `settings` | 设置 |
| `quit` | 退出游戏 |

ID 不区分大小写并忽略首尾空白；未知值会被忽略。`battle` 不可关闭，保证页面始终保留“进入对战”入口。隐藏“退出游戏”只影响按钮，浏览器或系统返回行为不变。

## 部署注意事项

- Web 发布必须在仓库根目录运行 `python3 tools/export_web.py`。这个包装器只生成内嵌专用的 `Release/web-embedded/index.html`，再对 Godot 4.7.2 的 Fetch 桥接层做精确、失败关闭的安全修补与产物校验；直接运行 `godot --export-release` 得到的是未修补产物，不可发布。
- 内嵌导出固定为 9 个文件、单线程、无 GDExtension、无 PWA/Service Worker，供宿主原样取用；项目不再提供标准 Web 预设。
- 从 HTTPS 页面访问 HTTP 接口会被浏览器按混合内容拦截，生产环境应使用 HTTPS 服务。
- 接口服务仍需允许 Web 页面的 Origin（CORS）。
- 对战完成或名单读取失败后会在 60 秒倒计时结束时重新读取今日名单；“再战/重试”按钮会显示剩余秒数，也可点击立即开始。
- `/api/v2/token-usage/dashboard` 的 Web 请求以 Fetch `redirect: "error"` 拒绝重定向，并用 `AbortController` 在超限、取消或释放请求时中止网络读取；响应体上限为 16 MiB（对齐看板序列化预算），越界时结果面板会显示对应错误。桌面端与 Android 仍使用 Godot 原生传输实现。请求带当天闭区间 `from`/`to`（`YYYY-MM-DD`）。
- 查询参数可能进入浏览器历史、访问日志或监控系统，不应放入密钥或令牌。

桥接层回归可用 `python3 -m unittest -v tests/test_web_fetch_bridge.py` 运行；生成产物再用 `python3 tools/export_web.py --verify-only` 校验。安装了 Chromium 系浏览器时，可运行 `python3 tests/browser_web_fetch_bridge_smoke.py Release/web-embedded/index.js`，以真实浏览器访问本机 3xx 和流式端点，证明重定向目标未被访问且取消后连接关闭。
