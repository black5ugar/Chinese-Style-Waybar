# Ink Topbar

独立于 `quickshell/ink` 的顶栏配置。配色沿用原 Waybar 水墨主题，不依赖
Omarchy，也不包含录屏模块。

测试启动：

```sh
qs -c topbar
```

确认工作区、托盘、音量和电源菜单工作正常后，再将会话自启动中的 Waybar
替换为 `qs -c topbar`。开发期间可以同时保留 Waybar，或手动暂时关闭它。

当前原生数据源：Sway/I3、MPRIS、PipeWire、UPower 和 StatusNotifier。
网络、蓝牙与内存通过系统接口进行只读查询；今日诗词由 QML 直接访问 API，
不依赖旧 Waybar 脚本。
