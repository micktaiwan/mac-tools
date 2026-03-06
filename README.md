# Mac Tools

macOS menu bar app (13+) built with SwiftUI.

## Features

- Next calendar event displayed in the menu bar with relative time
- List of today's events (current / upcoming)
- Calendar filtering
- Gmail unread emails count in the menu bar (via [gws](https://github.com/nicholasgasior/gws) CLI)
- Unread emails list with trash action
- Launch at startup
- No Dock icon (LSUIElement)

## Build

Requires [xcodegen](https://github.com/yonaskolb/XcodeGen):

```bash
brew install xcodegen
xcodegen generate
open MacTools.xcodeproj
```

Or build from command line:

```bash
xcodegen generate
xcodebuild -scheme MacTools -configuration Debug build
```

## Install

Copy the built app to `/Applications`:

```bash
cp -R ~/Library/Developer/Xcode/DerivedData/MacTools-*/Build/Products/Debug/MacTools.app /Applications/
```

## Stack

Swift, SwiftUI, EventKit, ServiceManagement
