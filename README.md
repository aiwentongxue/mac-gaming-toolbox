# Mac 游戏工具箱

[简体中文](README.md) | [English](README_EN.md)

Mac 游戏工具箱是一款原生 SwiftUI macOS 应用，用于集中管理常见的 Mac 游戏辅助操作。当前版本为 4.0.3，改进磁盘单盘与批量操作、预设识别和挂载校验，支持从访达拖入 App 添加 MetalHUD 快捷方式；保留 AppDrop 九语言适配、价格历史与降价通知，集成 ClickFlow 1.0.1，并兼容 Intel Mac 和 Apple Silicon Mac。

## 功能

- 使用统一的两栏侧边栏访问游戏性能、存储维护、ClickFlow、AppDrop 与帮助页面，在统一的“设置”页面管理显示语言和更新检查。
- 内置 ClickFlow 1.0.1 连点器、鼠标宏和组合宏；支持通过实验性 XInput 代理为 CrossOver 游戏回放手柄宏，并提供按游戏安装、诊断、备份和安全恢复。接受首次使用声明后，即使停留在其他工具页面也能通过全局快捷键使用，并与独立版 ClickFlow 的偏好、宏文件和适配记录完全隔离。
- 全局开启或关闭 MetalHUD，或通过最近 App 启动台仅为选定 App 的本次启动启用 MetalHUD。可从访达拖入 `.app` 或通过文件选择器添加快捷方式，支持 Steam 等自定义目录；添加不会自动启动，点击卡片右上角播放按钮才启动。可保存参数预设，并在下次开启游戏时应用。
- 可为 CrossOver 容器写入 MetalHUD 参数预设，也可为已连接的 iOS 设备上的游戏开启 MetalHUD。
- 按 10、15 或 20 秒的可选等待时间辅助启动 HoYoGames，并在任务结束或取消时恢复应用管理的 hosts 配置。
- 自动检测 CrossOver/Wine 进程，支持优化后的手动搜索与选择、常用进程，以及三个模式独立保存的五档进程优先级。
- 将磁盘挂载到指定路径，保存按 UUID 关联的预设，并自动或手动恢复上次挂载。单盘操作仅作用于当前详情磁盘；批量模式在可用磁盘列表下集中显示勾选数量、批量挂载和批量恢复按钮，并校验目标路径、报告失败和回滚结果。
- 一键清理缓存日志，默认仅清理用户缓存和用户日志，也可关闭敏感文件排除执行完整高风险清理。
- 在 HoYoGames 页面切换或恢复用于兼容性测试的 Steam Deck 主机名模式。
- 导出诊断信息，并提供 Mac 游戏与 CrossOver 教程入口；在“设置”中开启启动时检查更新或立即检查 GitHub 更新。
- 内置 AppDrop 心愿单、今日降价、历史低价和价格设置；支持 App Store 链接、关键词搜索、17 个商店区域、`.wishdrop` 导入导出、价格历史与降价通知。
- AppDrop 使用工具箱独立的 `~/Library/Application Support/MacGameToolbox/AppDrop` 数据目录，不读取或修改独立版 AppDrop 数据；需要后台检查时，可在 AppDrop 设置中注册专用的用户级 Helper。
- AppDrop 支持简体中文、繁体中文、英文、日语、韩语、德语、法语、西班牙语和葡萄牙语。设置中分别提供工具箱与后台助手的通知授权、状态和测试入口；恢复授权后会先重新核实价格，再合并提醒仍有效的漏发降价。

## 系统要求

- macOS 14 或更高版本。
- Intel 或 Apple Silicon Mac。
- 从源码构建需要 Swift 6、Xcode 16 或兼容版本，以及 Xcode Command Line Tools。
- 使用磁盘挂载、缓存清理、进程优先级、hosts 或主机名相关功能时，需要管理员授权。
- ClickFlow 的全局输入功能需要单独为 Mac 游戏工具箱授予“辅助功能”和“输入监控”权限。

## 安装

### 下载安装包

从 [4.0.3 Release](https://github.com/aiwentongxue/mac-gaming-toolbox/releases/tag/v4.0.3) 下载 `MacGameToolbox-4.0.3.dmg`，将应用拖入 `Applications`。同一个 Universal 安装包同时包含 `x86_64` 与 `arm64`，无需按芯片分别下载。安装包使用 Apple Development 身份签名，未经过 Apple 公证；Release 同时提供 SHA-256 校验文件和核验记录。

### 从源码构建应用

```bash
git clone https://github.com/aiwentongxue/mac-gaming-toolbox.git
cd mac-gaming-toolbox
./Scripts/build-release.sh
```

构建完成后，应用位于：

```text
build/DerivedData/Build/Products/Release/Mac 游戏工具箱.app
```

请将应用复制到“应用程序”目录；Mac 游戏工具箱必须从 `/Applications/Mac 游戏工具箱.app` 运行。首次使用需要系统权限的功能时，macOS 会注册随应用提供的特权辅助服务；AppDrop 后台检查使用单独的登录项，并仅在用户主动开启后注册。请按系统提示在“系统设置 > 通用 > 登录项与扩展”允许对应后台项目。

也可以使用 Swift Package Manager 进行调试构建：

```bash
swift build
```

## 使用方法

1. 若 macOS 阻止应用启动，请先在“系统设置 > 隐私与安全性”中开启“任何来源”（如该选项可用），再在同一页面点击“仍要打开”；或者在“终端”中执行以下完整命令移除下载隔离属性：

   ```bash
   sudo xattr -dr com.apple.quarantine "/Applications/Mac 游戏工具箱.app"
   ```

2. 启动“Mac 游戏工具箱”。
3. 在主界面选择需要的功能，并阅读对应说明。
4. 涉及系统修改时，按 macOS 提示完成管理员授权。
5. HoYoGames 启动帮助开启后，请在倒计时内启动游戏；取消任务会尝试恢复由本项目添加的 hosts 项目。
6. 自定义磁盘挂载前先选择外接磁盘和目标目录；需要开机恢复时，可保存预设、启用自动恢复，并将应用加入登录项。

视频教程：[【Mac游戏工具箱重磅发布!支持MetalHUD米游启动磁盘挂载等功能!】](https://b23.tv/qnJBcbk) · [YouTube](https://youtu.be/Y9g4F0_6ipI?si=i3G9dxiXMbk2NSzY)

## 测试

```bash
swift test --disable-sandbox
```

## 注意事项

- AppDrop 的工具箱通知与后台助手通知需要分别授权。恢复授权后的漏发提醒只包含成功重新核实、仍然有效的最新降价；界面中的“已提交给系统”不代表用户一定看到横幅，专注模式及屏幕共享静音设置仍然生效。
- 更新后如后台助手通知仍显示旧占位图，可在“活动监视器”中正常退出“通知中心”进程，让系统重新启动显示进程并刷新图标缓存。无需删除通知数据库或重置授权。
- 缓存与日志清理属于不可撤销的高风险操作，可能导致登录状态、游戏缓存和诊断日志丢失。执行前请退出游戏及其他应用，并备份重要数据。
- 自定义磁盘挂载、hosts 修改、主机名切换和进程优先级调整会改变系统状态。请确认目标磁盘和路径无误，并避免在系统更新、磁盘读写或重要任务进行时操作。
- Steam Deck 模式只用于兼容性测试，不能保证绕过或兼容任何游戏的反作弊机制；请遵守游戏服务条款。
- ClickFlow 的 CrossOver XInput 代理不是系统级虚拟手柄，仅适用于所选 CrossOver/Wine XInput 游戏。部分反作弊、DirectInput、Raw HID、GameInput 或 SDL 直连游戏可能拒绝或绕过该代理；安装前请备份并确认游戏规则。
- 本项目不是 Apple、CodeWeavers、HoYoverse 或 Valve 的官方产品，相关名称和商标归各自权利人所有。
- 作者公开主页：[哔哩哔哩](https://b23.tv/dV7YBJQ) · [YouTube](https://youtube.com/channel/UC0TgypOLHt2fXboVw34SKVQ)

## License

Copyright (C) 2026 我是艾文喵

本项目基于 [GNU General Public License v3.0](LICENSE) 开源。你可以在遵守 GPL-3.0 条款的前提下使用、修改和分发本项目；分发修改版本时必须保留相同的开源许可并提供相应源代码。

内置 ClickFlow 1.0.1 功能来源于同一作者维护的 GPL-3.0 项目 ClickFlow，并保留其版权与许可要求。
AppDrop 功能来源于同一作者维护的 GPL-3.0 项目 AppDrop No Sandbox，并保留其版权与许可要求。
