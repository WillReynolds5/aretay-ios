# Aretay

An iOS app built with SwiftUI + SwiftData.

## Requirements

- macOS with Xcode **16.3** or later
- iOS **17.0+** deployment target
- Swift **6.0**
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)

## Getting started

The Xcode project is generated from `project.yml` so it isn't checked into git. After cloning:

```bash
brew install xcodegen          # one time
xcodegen generate              # creates Aretay.xcodeproj
open Aretay.xcodeproj
```

Then press ⌘R to run.

## Project layout

```
.
├── project.yml              # XcodeGen project definition
├── Aretay/                  # App sources
│   ├── AretayApp.swift      # @main entry point
│   ├── ContentView.swift
│   ├── Item.swift           # SwiftData model
│   └── Assets.xcassets
├── AretayTests/             # Unit tests (Swift Testing)
└── AretayUITests/           # UI tests (XCTest)
```

## Common tasks

```bash
# Regenerate the Xcode project after editing project.yml
xcodegen generate

# Build from the command line
xcodebuild -project Aretay.xcodeproj -scheme Aretay -destination 'platform=iOS Simulator,name=iPhone 16' build

# Run tests
xcodebuild -project Aretay.xcodeproj -scheme Aretay -destination 'platform=iOS Simulator,name=iPhone 16' test
```
