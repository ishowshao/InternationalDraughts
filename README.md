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
