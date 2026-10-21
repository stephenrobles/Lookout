# Lookout

A status board for Apple TV, with an iPhone and iPad companion that feeds it.

| Target | Bundle ID | What it does |
| --- | --- | --- |
| `Lookout` (iOS 26+) | `fm.beard.Lookout` | Reads Calendar, Reminders and HomeKit on the phone; publishes a board description through CloudKit. |
| `LookoutTV` (tvOS 26+) | `fm.beard.Lookout.tv` | Shows the board. Reads WeatherKit and HomeKit directly on the Apple TV. |
| `Shared/` | | SwiftData models (`BoardConfig`, `AgendaEvent`, `ReminderItem`), the CloudKit-backed store, demo data. |

## How data flows

- The iPhone app is the only writer. It upserts one `BoardConfig` record plus one `AgendaEvent` per calendar occurrence in the published window and one `ReminderItem` per due reminder.
- Records sync through the CloudKit private database `iCloud.fm.beard.Lookout`. The TV registers for silent pushes so changes land while the board is on screen.
- Weather (WeatherKit) and HomeKit (cameras, locks, doors, sensors) are read on the Apple TV itself. The phone only chooses which cameras and accessories to show.
- The TV keeps its own small settings in `UserDefaults`: weather location, temperature units, 12/24-hour clock, and a wallpaper override.

## Demo mode

Both apps accept the `-LookoutDemo` launch argument. It swaps in an in-memory store with sample events, reminders, weather, cameras and accessories, and never touches CloudKit. Useful for screenshots and for working on layout without a paired phone:

```bash
xcrun simctl launch booted fm.beard.Lookout.tv -LookoutDemo
```

## One-time Apple Developer setup

Automatic signing adds the iCloud, Push and HomeKit capabilities to both App IDs. Two things still need a visit to developer.apple.com:

1. **WeatherKit** – under Certificates, Identifiers & Profiles → Identifiers → `fm.beard.Lookout.tv` → *App Services*, enable WeatherKit. Weather calls fail with an authentication error until this is on (it can take up to half an hour to propagate).
2. **CloudKit schema** – run the iPhone app once in the Development environment with calendar access granted, then deploy the schema to Production from CloudKit Console before shipping. Debug builds use `Development`, Release builds use `Production` (see `LOOKOUT_CLOUDKIT_ENVIRONMENT` in the project).

## Building

```bash
xcodebuild -project Lookout.xcodeproj -scheme Lookout   -destination 'generic/platform=iOS Simulator'  build
xcodebuild -project Lookout.xcodeproj -scheme LookoutTV -destination 'generic/platform=tvOS Simulator' build
```
