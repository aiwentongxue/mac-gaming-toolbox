# Mac 游戏工具箱

Mac 游戏工具箱是一款原生 SwiftUI macOS 应用，用于集中管理常见的 Mac 游戏辅助操作。当前版本为 2.4.0，支持中文与英文界面，并兼容 Intel Mac 和 Apple Silicon Mac。

## 功能

- 全局开启或关闭 MetalHUD 性能监视器，或仅为选定 App 的本次启动启用 MetalHUD。
- 辅助启动 HoYoGames，并在任务结束或取消时恢复应用管理的 hosts 配置。
- 检测 CrossOver/Wine 进程并提高其运行优先级。
- 将外接磁盘挂载到指定路径，保存预设并按需自动恢复挂载。
- 扫描并清理用户缓存、应用缓存和系统日志。
- 切换或恢复用于兼容性测试的 Steam Deck 主机名模式。
- 导入自定义界面壁纸、导出诊断信息，并提供 Mac 游戏与 CrossOver 教程入口。

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

你可以直接运行该应用，或将其复制到“应用程序”目录。首次使用需要系统权限的功能时，macOS 会注册随应用提供的特权辅助服务。如果系统要求批准，请前往“系统设置 > 通用 > 登录项与扩展”允许相应后台项目。

也可以使用 Swift Package Manager 进行调试构建：

```bash
swift build
```

## 使用方法

1. 启动“Mac 游戏工具箱”。
2. 在主界面选择需要的功能，并阅读对应说明。
3. 涉及系统修改时，按 macOS 提示完成管理员授权。
4. HoYoGames 启动帮助开启后，请在倒计时内启动游戏；取消任务会尝试恢复由本项目添加的 hosts 项目。
5. 自定义磁盘挂载前先选择外接磁盘和目标目录；需要开机恢复时，可保存预设、启用自动恢复，并将应用加入登录项。

## 测试

```bash
swift test --disable-sandbox
```

## 正式签名与公证

正式分发需要开发者自行准备 Apple Developer ID Application 证书，并使用 `notarytool` 在本机钥匙串中保存公证配置。仓库不会包含证书、私钥、钥匙串、Team ID 或公证凭据。

```bash
export DEVELOPER_ID_APPLICATION='Developer ID Application: Your Name (TEAMID)'
export NOTARY_KEYCHAIN_PROFILE='your-notary-profile'
./Scripts/sign-and-notarize.sh '/path/to/Mac 游戏工具箱.app' 'MacGameToolbox-2.4.0.dmg'
```

请勿把真实证书、公证密码、App Store Connect API Key 或环境变量文件提交到仓库。

## 注意事项

- 缓存与日志清理属于不可撤销的高风险操作，可能导致登录状态、游戏缓存和诊断日志丢失。执行前请退出游戏及其他应用，并备份重要数据。
- 自定义磁盘挂载、hosts 修改、主机名切换和进程优先级调整会改变系统状态。请确认目标磁盘和路径无误，并避免在系统更新、磁盘读写或重要任务进行时操作。
- Steam Deck 模式只用于兼容性测试，不能保证绕过或兼容任何游戏的反作弊机制；请遵守游戏服务条款。
- 本项目不是 Apple、CodeWeavers、HoYoverse 或 Valve 的官方产品，相关名称和商标归各自权利人所有。
- 作者公开主页：[哔哩哔哩](https://b23.tv/dV7YBJQ) · [YouTube](https://youtube.com/channel/UC0TgypOLHt2fXboVw34SKVQ)

## License

Copyright (C) 2026 我是艾文喵

本项目基于 [GNU General Public License v3.0](LICENSE) 开源。你可以在遵守 GPL-3.0 条款的前提下使用、修改和分发本项目；分发修改版本时必须保留相同的开源许可并提供相应源代码。
