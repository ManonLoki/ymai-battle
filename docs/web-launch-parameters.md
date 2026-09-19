# Web 启动参数

Web 版可在 Godot 启动前通过页面全局对象或 URL 查询参数提供服务器列和需要隐藏的主菜单入口。桌面端、Android 等非 Web 导出不会读取这些参数。

## 页面全局对象

```html
<script>
window.YMAIBattleConfig = {
  BaseURL: [
    "https://battle-a.example.com",
    "https://battle-b.example.com:8443"
  ],
  CloseMenu: ["ranking", "settings", "quit"]
};
</script>
```

`BaseURL` 和 `CloseMenu` 都必须是字符串数组，字段本身可省略。

## URL 查询参数

数组通过重复同名参数传入：

```text
?BaseURL=https%3A%2F%2Fbattle-a.example.com&BaseURL=https%3A%2F%2Fbattle-b.example.com%3A8443&CloseMenu=ranking&CloseMenu=settings
```

查询参数按字段覆盖页面全局对象。例如查询串只出现 `CloseMenu` 时，页面对象中的 `BaseURL` 仍然有效。只要查询串出现过 `BaseURL`，包括 `BaseURL=`，就以查询串结果为准；显式空值表示本次会话使用空候选列表，不回退到本地列表。

## BaseURL

- 只接受 `http://主机[:端口]` 或 `https://主机[:端口]`，不能包含路径、查询串或账号密码。
- 无效项和重复项会被丢弃，剩余项保持首次出现的顺序。
- Web 传入 `BaseURL` 时，它是本次会话设置页下拉框的完整数据源，不能在页面内增删。
- 未传入时，下拉框使用本地保存的服务器列表，并允许增加或删除。
- 下拉框第一项始终是“使用默认服务器”。选中的服务器会保存；只有它仍属于当前数据源时才生效，否则使用程序内置服务器。
- Web 注入列表不会写进本地候选列表。

## CloseMenu

可用菜单 ID：

| ID | 主菜单入口 |
| --- | --- |
| `ranking` | 查看排行 |
| `settings` | 设置 |
| `quit` | 退出游戏 |

ID 不区分大小写并忽略首尾空白；未知值会被忽略。`battle` 不可关闭，保证页面始终保留“进入对战”入口。隐藏“退出游戏”只影响按钮，浏览器或系统返回行为不变。

## 部署注意事项

- 从 HTTPS 页面访问 HTTP 接口会被浏览器按混合内容拦截，生产环境应使用 HTTPS 服务。
- 接口服务仍需允许 Web 页面的 Origin（CORS）。
- 进入对战页时只读取一次今日名单；完成或失败后不会后台轮询，只有玩家点击“再战”才会再次读取。
- `/api/v1/token-usage` 请求不跟随重定向，响应体上限为 8 MiB；越界时结果面板会显示对应错误。
- 查询参数可能进入浏览器历史、访问日志或监控系统，不应放入密钥或令牌。
