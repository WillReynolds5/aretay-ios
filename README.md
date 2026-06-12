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
│   ├── App/                 # @main entry point + auth routing (RootView)
│   ├── Features/
│   │   ├── Auth/            # Sign in with Apple
│   │   ├── Courses/         # CoursesHomeView (the home page), Explore grid, course detail
│   │   ├── Profile/         # Profile sheet (opened from the home header avatar)
│   │   ├── Session/         # Full-screen TikTok-style study session
│   │   └── Shared/          # Shared course UI (artwork, progress rows)
│   ├── Models/              # Course, Card, Curriculum, LearnerStats, study rows
│   ├── Services/            # Supabase REST clients, FSRS scheduler, config
│   ├── Preview/             # Canvas preview fixtures
│   └── Resources/           # Assets, fonts
├── AretayTests/             # Unit tests (Swift Testing)
└── AretayUITests/           # UI tests (XCTest)
```

## Navigation

There are no tabs. `CoursesHomeView` is the single home page; Profile is a
sheet behind the avatar in its header, and the Explore catalog (search +
category chips over a two-column grid) / course detail push onto its
navigation stack. My Courses lives entirely on the home page — no see-all. On a fresh launch the app routes
once: cards due → straight into the top-due review session; nothing due but
a course unfinished → back into that course; otherwise it rests on the
courses page. Closing a session always lands back on the courses page.

## Common tasks

```bash
# Regenerate the Xcode project after editing project.yml
xcodegen generate

# Build from the command line
xcodebuild -project Aretay.xcodeproj -scheme Aretay -destination 'platform=iOS Simulator,name=iPhone 16' build

# Run tests
xcodebuild -project Aretay.xcodeproj -scheme Aretay -destination 'platform=iOS Simulator,name=iPhone 16' test
```
