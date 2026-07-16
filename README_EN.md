# Mac Gaming Toolbox

[简体中文](README.md) | [English](README_EN.md)

Mac Gaming Toolbox is a native SwiftUI macOS app that brings common Mac gaming utilities together in one place. Version 3.0.5 supports both Chinese and English interfaces and is compatible with Intel and Apple Silicon Macs.

## Features

- Enable or disable MetalHUD globally, or use the Recent Apps launcher to enable MetalHUD only for the selected app's next launch.
- Assist with launching HoYo games after a configurable 10-, 15-, or 20-second delay, then restore the hosts entries managed by the app when the task finishes or is canceled.
- Automatically detect CrossOver/Wine processes, or select a process manually and raise its priority.
- Mount an external disk at a specified path, save presets, and automatically or manually restore the previous mount.
- Clear caches and logs in one click. By default, only user caches and user logs are removed; sensitive-file exclusions can be disabled for a complete, high-risk cleanup.
- Switch to or restore a Steam Deck hostname mode for compatibility testing.
- Import a custom interface wallpaper, export diagnostic information, and access Mac gaming and CrossOver tutorials.

## System Requirements

- macOS 14 or later.
- An Intel or Apple Silicon Mac.
- Building from source requires Swift 6, Xcode 16 or a compatible version, and Xcode Command Line Tools.
- Administrator authorization is required for disk mounting, cache cleanup, process priority, hosts, and hostname operations.

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

You can run the app directly or copy it to the Applications folder. The first time you use a feature that requires system privileges, macOS registers the privileged helper bundled with the app. If macOS asks for approval, go to System Settings > General > Login Items & Extensions and allow the corresponding background item.

You can also create a debug build with Swift Package Manager:

```bash
swift build
```

## Usage

1. Launch Mac Gaming Toolbox.
2. Select the feature you need from the main interface and read its instructions.
3. When a feature changes system settings, follow the macOS prompts to grant administrator authorization.
4. After enabling the HoYoGames launch helper, start the game before the countdown ends. Canceling the task will attempt to restore the hosts entries added by this project.
5. Before using custom disk mounting, select the external disk and destination directory. To restore the mount at login, save a preset, enable automatic restoration, and add the app to Login Items.

Video tutorial: [Mac Gaming Toolbox major release—MetalHUD, HoYo game launching, disk mounting, and more](https://b23.tv/qnJBcbk) · [YouTube](https://youtu.be/Y9g4F0_6ipI?si=i3G9dxiXMbk2NSzY)

## Testing

```bash
swift test --disable-sandbox
```

## Release Signing and Notarization

For release distribution, developers must provide their own Apple Developer ID Application certificate and save a notarization profile in the local Keychain with `notarytool`. The repository does not include certificates, private keys, keychains, Team IDs, or notarization credentials.

```bash
export DEVELOPER_ID_APPLICATION='Developer ID Application: Your Name (TEAMID)'
export NOTARY_KEYCHAIN_PROFILE='your-notary-profile'
./Scripts/sign-and-notarize.sh '/path/to/Mac 游戏工具箱.app' 'MacGameToolbox-3.0.5.dmg'
```

Never commit real certificates, notarization passwords, App Store Connect API keys, or environment-variable files to the repository.

## Important Notes

- Cache and log cleanup is irreversible and may remove login state, game caches, and diagnostic logs. Quit games and other apps and back up important data before continuing.
- Custom disk mounting, hosts changes, hostname switching, and process-priority adjustments modify system state. Verify the target disk and path, and avoid using these features during system updates, disk activity, or other important tasks.
- Steam Deck mode is intended only for compatibility testing and is not guaranteed to bypass or work with any game's anti-cheat system. Follow the game's terms of service.
- This project is not an official product of Apple, CodeWeavers, HoYoverse, or Valve. All related names and trademarks belong to their respective owners.
- Author's public profiles: [Bilibili](https://b23.tv/dV7YBJQ) · [YouTube](https://youtube.com/channel/UC0TgypOLHt2fXboVw34SKVQ)

## License

Copyright (C) 2026 我是艾文喵

This project is licensed under the [GNU General Public License v3.0](LICENSE). You may use, modify, and distribute it under the terms of GPL-3.0. Modified distributions must retain the same open-source license and make the corresponding source code available.
