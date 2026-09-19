# Mac Gaming Toolbox

[简体中文](README.md) | [English](README_EN.md)

Mac Gaming Toolbox is a native SwiftUI macOS app that brings common Mac gaming utilities together in one place. Version 3.2.1 updates the built-in ClickFlow integration to 1.0.1 while remaining compatible with Intel and Apple Silicon Macs.

## Features

- Select the application language in Settings, and edit dashboard cards to hide features you do not need.
- Use the built-in ClickFlow 1.0.1 auto clicker, mouse macros, and combined macros. Experimental XInput proxies can replay controller macros in CrossOver games with per-game installation, diagnostics, backup, and safe restore. After accepting the first-use notice, global shortcuts remain available on the Toolbox page, while preferences, macro files, and adapter records stay completely isolated from the standalone ClickFlow app.
- Enable or disable MetalHUD globally, or use the Recent Apps launcher to enable MetalHUD only for the selected app's next launch. Save parameter presets and apply them when you next launch a game.
- Apply MetalHUD parameter presets to CrossOver bottles, or enable MetalHUD for games on a connected iOS device.
- Assist with launching HoYo games after a configurable 10-, 15-, or 20-second delay, then restore the hosts entries managed by the app when the task finishes or is canceled.
- Automatically detect CrossOver/Wine processes, with improved manual search and selection, favorite processes, and priority raising or lowering.
- Mount an external disk at a specified path, save presets, and automatically or manually restore the previous mount.
- Clear caches and logs in one click. By default, only user caches and user logs are removed; sensitive-file exclusions can be disabled for a complete, high-risk cleanup.
- Switch to or restore a Steam Deck hostname mode for compatibility testing.
- Import a custom interface wallpaper, export diagnostic information, and access Mac gaming and CrossOver tutorials. GitHub update checks can run automatically.

## System Requirements

- macOS 14 or later.
- An Intel or Apple Silicon Mac.
- Building from source requires Swift 6, Xcode 16 or a compatible version, and Xcode Command Line Tools.
- Administrator authorization is required for disk mounting, cache cleanup, process priority, hosts, and hostname operations.
- ClickFlow global input features require Accessibility and Input Monitoring permissions to be granted separately to Mac Gaming Toolbox.

## Installation

### Build the App from Source

```bash
git clone https://github.com/aiwentongxue/mac-gaming-toolbox.git
cd mac-gaming-toolbox
./Scripts/build-release.sh
```

After the build finishes, the app is located at:

```text
build/DerivedData/Build/Products/Release/Mac 游戏工具箱.app
```

Copy the app to the Applications folder; Mac Gaming Toolbox must run from `/Applications/Mac 游戏工具箱.app`. The first time you use a feature that requires system privileges, macOS registers the privileged helper bundled with the app. If macOS asks for approval, go to System Settings > General > Login Items & Extensions and allow the corresponding background item.

You can also create a debug build with Swift Package Manager:

```bash
swift build
```

## Usage

1. If macOS blocks the app from opening, enable “Anywhere” in System Settings > Privacy & Security (if the option is available), then click “Open Anyway” on that same page. Alternatively, run the following complete command in Terminal to remove the download quarantine attribute:

   ```bash
   sudo xattr -dr com.apple.quarantine "/Applications/Mac 游戏工具箱.app"
   ```

2. Launch Mac Gaming Toolbox.
3. Select the feature you need from the main interface and read its instructions.
4. When a feature changes system settings, follow the macOS prompts to grant administrator authorization.
5. After enabling the HoYoGames launch helper, start the game before the countdown ends. Canceling the task will attempt to restore the hosts entries added by this project.
6. Before using custom disk mounting, select the external disk and destination directory. To restore the mount at login, save a preset, enable automatic restoration, and add the app to Login Items.

Video tutorial: [Mac Gaming Toolbox major release—MetalHUD, HoYo game launching, disk mounting, and more](https://b23.tv/qnJBcbk) · [YouTube](https://youtu.be/Y9g4F0_6ipI?si=i3G9dxiXMbk2NSzY)

## Testing

```bash
swift test --disable-sandbox
```

## Important Notes

- Cache and log cleanup is irreversible and may remove login state, game caches, and diagnostic logs. Quit games and other apps and back up important data before continuing.
- Custom disk mounting, hosts changes, hostname switching, and process-priority adjustments modify system state. Verify the target disk and path, and avoid using these features during system updates, disk activity, or other important tasks.
- Steam Deck mode is intended only for compatibility testing and is not guaranteed to bypass or work with any game's anti-cheat system. Follow the game's terms of service.
- ClickFlow's CrossOver XInput proxy is not a system-wide virtual controller and applies only to selected CrossOver/Wine XInput games. Anti-cheat, DirectInput, raw HID, GameInput, or direct SDL games may reject or bypass the proxy; back up the game and confirm its rules before installation.
- This project is not an official product of Apple, CodeWeavers, HoYoverse, or Valve. All related names and trademarks belong to their respective owners.
- Author's public profiles: [Bilibili](https://b23.tv/dV7YBJQ) · [YouTube](https://youtube.com/channel/UC0TgypOLHt2fXboVw34SKVQ)

## License

Copyright (C) 2026 我是艾文喵

This project is licensed under the [GNU General Public License v3.0](LICENSE). You may use, modify, and distribute it under the terms of GPL-3.0. Modified distributions must retain the same open-source license and make the corresponding source code available.

The integrated ClickFlow 1.0.1 feature is derived from the GPL-3.0 ClickFlow project maintained by the same author, with its copyright and license requirements preserved.
