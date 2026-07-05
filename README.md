# International Draughts

An iOS implementation of International Draughts (10x10), written with UIKit and Swift. The app supports local play against an AI opponent and nearby two-player matches over MultipeerConnectivity.

## Features

- 10x10 International Draughts board with playable-square coordinates.
- Standard move generation with mandatory captures, maximum-capture selection, multi-jump sequences, flying kings, and promotion.
- AI opponent for Black with easy, medium, and hard difficulty levels.
- Nearby two-player mode using local peer discovery, without an internet connection.
- Rotated board for the Black player in nearby matches.
- Portrait and landscape adaptive layout.
- UI tests for core gameplay, layout, and nearby-match automation hooks.

## Requirements

- Xcode 26.6 or newer.
- iOS 17.6 or newer.
- A simulator or device capable of running the `InternationalDraughts` scheme.

Nearby matches use local network peer discovery. On real devices, allow the local network permission prompt when creating or joining a room.

## Run

Open the project in Xcode:

```sh
open InternationalDraughts.xcodeproj
```

Select the `InternationalDraughts` scheme, choose a simulator or connected device, then run.

From the command line:

```sh
xcodebuild \
  -project InternationalDraughts.xcodeproj \
  -scheme InternationalDraughts \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  build
```

## Test

Compile the app and test targets:

```sh
xcodebuild \
  -project InternationalDraughts.xcodeproj \
  -scheme InternationalDraughts \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  build-for-testing
```

Run the standard test suite:

```sh
xcodebuild \
  -project InternationalDraughts.xcodeproj \
  -scheme InternationalDraughts \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  test
```

The nearby-match UI tests are designed to run with a host test on one simulator and a joiner test on another simulator at the same time:

- `testNearbyMatchHost`
- `testNearbyMatchJoin`

Those tests use launch arguments (`-mpAutoHost` and `-mpAutoJoin`) to create and join a local MultipeerConnectivity session automatically.

## Project Layout

- `InternationalDraughts/Engine.swift`: rules engine, legal move generation, board updates, and AI search.
- `InternationalDraughts/BoardView.swift`: board rendering and tap-to-square mapping.
- `InternationalDraughts/ViewController.swift`: main game UI, AI mode, nearby-match flow, and game state.
- `InternationalDraughts/MultipeerService.swift`: local peer discovery, connection lifecycle, and JSON message transport.
- `InternationalDraughtsUITests/`: UI tests for gameplay and nearby-match flows.

## Notes

The app uses `NSLocalNetworkUsageDescription` and Bonjour service declarations in `Info.plist` for local peer discovery. The Bonjour service type is `_intl-draughts._tcp` / `_intl-draughts._udp`, matching `MultipeerService.serviceType`.

---

# 国际跳棋

这是一个使用 UIKit 和 Swift 编写的 iOS 国际跳棋（10x10）应用。应用支持本地人机对战，也支持通过 MultipeerConnectivity 进行附近双人对战。

## 功能

- 10x10 国际跳棋棋盘，并显示可行棋格的坐标。
- 标准走法生成：强制吃子、最大吃子数优先、连续跳吃、王棋长距离移动和升王。
- 黑方 AI 对手，支持简单、中等、困难三档难度。
- 附近双人对战，通过本地设备发现建立连接，无需互联网。
- 附近对战中，执黑玩家看到旋转后的棋盘。
- 支持竖屏和横屏自适应布局。
- 包含核心对局、布局和附近对战自动化钩子的 UI 测试。

## 运行要求

- Xcode 26.6 或更新版本。
- iOS 17.6 或更新版本。
- 可运行 `InternationalDraughts` scheme 的模拟器或真机。

附近对战依赖本地网络设备发现。在真机上创建或加入房间时，需要允许系统弹出的本地网络权限。

## 运行

用 Xcode 打开项目：

```sh
open InternationalDraughts.xcodeproj
```

选择 `InternationalDraughts` scheme，再选择模拟器或连接的真机运行。

也可以从命令行构建：

```sh
xcodebuild \
  -project InternationalDraughts.xcodeproj \
  -scheme InternationalDraughts \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  build
```

## 测试

编译应用和测试 target：

```sh
xcodebuild \
  -project InternationalDraughts.xcodeproj \
  -scheme InternationalDraughts \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  build-for-testing
```

运行标准测试套件：

```sh
xcodebuild \
  -project InternationalDraughts.xcodeproj \
  -scheme InternationalDraughts \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  test
```

附近对战 UI 测试需要在两个模拟器上同时运行：一个运行房主测试，一个运行加入者测试。

- `testNearbyMatchHost`
- `testNearbyMatchJoin`

这两个测试通过启动参数（`-mpAutoHost` 和 `-mpAutoJoin`）自动创建和加入本地 MultipeerConnectivity 会话。

## 项目结构

- `InternationalDraughts/Engine.swift`：规则引擎、合法走法生成、棋盘更新和 AI 搜索。
- `InternationalDraughts/BoardView.swift`：棋盘绘制和点击坐标映射。
- `InternationalDraughts/ViewController.swift`：主游戏界面、人机模式、附近对战流程和游戏状态。
- `InternationalDraughts/MultipeerService.swift`：本地设备发现、连接生命周期和 JSON 消息传输。
- `InternationalDraughtsUITests/`：对局流程和附近对战流程的 UI 测试。

## 说明

应用在 `Info.plist` 中声明了 `NSLocalNetworkUsageDescription` 和 Bonjour 服务，用于本地设备发现。Bonjour 服务类型是 `_intl-draughts._tcp` / `_intl-draughts._udp`，与 `MultipeerService.serviceType` 保持一致。
