# Mac 游戏工具箱

[简体中文](README.md) | [English](README_EN.md)

Mac 游戏工具箱是一款原生 SwiftUI macOS 应用，用于集中管理常见的 Mac 游戏辅助操作。当前版本为 3.1.2，适配多国语言，并兼容 Intel Mac 和 Apple Silicon Mac。

## 功能

- 可在设置中选择应用语言；也可以编辑首页选项框，隐藏暂不需要的功能。
- 全局开启或关闭 MetalHUD，或通过最近 App 启动台仅为选定 App 的本次启动启用 MetalHUD；可保存参数预设，并在下次开启游戏时应用。
- 可为 CrossOver 容器写入 MetalHUD 参数预设，也可为已连接的 iOS 设备上的游戏开启 MetalHUD。
- 按 10、15 或 20 秒的可选等待时间辅助启动 HoYoGames，并在任务结束或取消时恢复应用管理的 hosts 配置。
- 自动检测 CrossOver/Wine 进程，支持优化后的手动搜索与选择、常用进程，以及提高或降低进程优先级。
- 将外接磁盘挂载到指定路径，保存预设，并自动或手动恢复上次挂载。
- 一键清理缓存日志，默认仅清理用户缓存和用户日志，也可关闭敏感文件排除执行完整高风险清理。
- 切换或恢复用于兼容性测试的 Steam Deck 主机名模式。
- 导入自定义界面壁纸、导出诊断信息，并提供 Mac 游戏与 CrossOver 教程入口；可自动检查 GitHub 更新。

## 系统要求

- macOS 14 或更高版本。
- Intel 或 Apple Silicon Mac。
- 从源码构建需要 Swift 6、Xcode 16 或兼容版本，以及 Xcode Command Line Tools。
- 使用磁盘挂载、缓存清理、进程优先级、hosts 或主机名相关功能时，需要管理员授权。

## 安装

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

请将应用复制到“应用程序”目录；Mac 游戏工具箱必须从 `/Applications/Mac 游戏工具箱.app` 运行。首次使用需要系统权限的功能时，macOS 会注册随应用提供的特权辅助服务。如果系统要求批准，请前往“系统设置 > 通用 > 登录项与扩展”允许相应后台项目。

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

- 缓存与日志清理属于不可撤销的高风险操作，可能导致登录状态、游戏缓存和诊断日志丢失。执行前请退出游戏及其他应用，并备份重要数据。
- 自定义磁盘挂载、hosts 修改、主机名切换和进程优先级调整会改变系统状态。请确认目标磁盘和路径无误，并避免在系统更新、磁盘读写或重要任务进行时操作。
- Steam Deck 模式只用于兼容性测试，不能保证绕过或兼容任何游戏的反作弊机制；请遵守游戏服务条款。
- 本项目不是 Apple、CodeWeavers、HoYoverse 或 Valve 的官方产品，相关名称和商标归各自权利人所有。
- 作者公开主页：[哔哩哔哩](https://b23.tv/dV7YBJQ) · [YouTube](https://youtube.com/channel/UC0TgypOLHt2fXboVw34SKVQ)

## License

Copyright (C) 2026 我是艾文喵

本项目基于 [GNU General Public License v3.0](LICENSE) 开源。你可以在遵守 GPL-3.0 条款的前提下使用、修改和分发本项目；分发修改版本时必须保留相同的开源许可并提供相应源代码。
