# AppDrop 合并实现说明

## 架构

- AppDrop 核心逻辑来自 AppDrop No Sandbox 提交 `e18f266`。
- vendored Swift Package：`Packages/AppDropCore`。
- 主界面直接挂接四个全局侧边栏页面：心愿单、今日降价、历史低价、设置。
- 应用详情使用右侧 `NavigationStack`，不创建第二套 `NavigationSplitView`。

## 数据与 Helper

- 数据目录：`~/Library/Application Support/MacGameToolbox/AppDrop`。
- 不读取或迁移独立版 `AppDropNoSandbox` 数据。
- AppDrop Helper Bundle ID：`com.iven.macgametoolbox.appdrop.helper`。
- LaunchAgent：`com.iven.macgametoolbox.appdrop.helper.plist`。
- Helper 嵌入主 App 的 `Contents/Library/LoginItems/AppDropHelper.app`。
- LaunchAgent plist 位于 `Contents/Library/LaunchAgents/`。
- 后台检查默认关闭，只在 AppDrop 设置中启用后注册。
- 原 root 特权 Helper 保持不变。

## 侧边栏

- 各功能分组支持收起与展开。
- 展开状态保存到 `app.expandedSidebarSections`。
- 折叠箭头位于分组标题左侧，方向与访达习惯一致。
- 程序化跳转到 AppDrop 时自动展开 AppDrop 分组。

## 更新检查

- GitHub Releases API 仍为首选。
- API 返回 `403` 或暂时不可用时，依次回退到 Releases Atom Feed 和 Releases 页面重定向。
- 手动检查、启动检查和关于页使用同一结构化结果。

## 授权

- AppDrop 代码和 Helper 不启用 App Sandbox。
- 界面不显示“无沙盒”或“No Sandbox”字样。
- 集成代码与独立仓库分别演进，不修改独立 AppDrop 仓库。
