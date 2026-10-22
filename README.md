# Lookout

A status board for Apple TV, with an iPhone and iPad companion that feeds it.

| Target | Bundle ID | What it does |
| --- | --- | --- |
| `Lookout` (iOS 26+) | `fm.beard.Lookout` | Reads Calendar, Reminders and HomeKit on the phone; publishes a board description through CloudKit. |
| `LookoutTV` (tvOS 26+) | `fm.beard.Lookout` (same ID, one App Store record) | Shows the board. Reads WeatherKit and HomeKit directly on the Apple TV. |
| `Shared/` | | SwiftData models (`BoardConfig`, `AgendaEvent`, `ReminderItem`), the CloudKit-backed store, demo data. |

## How data flows

- The iPhone app is the only writer. It upserts one `BoardConfig` record plus one `AgendaEvent` per calendar occurrence in the published window and one `ReminderItem` per due reminder.
- Records sync through the CloudKit private database `iCloud.fm.beard.Lookout`. The TV registers for silent pushes so changes land while the board is on screen.
- Weather (WeatherKit) and HomeKit (cameras, locks, doors, sensors) are read on the Apple TV itself. The phone only chooses which cameras and accessories to show.
- The TV keeps its own small settings in `UserDefaults`: weather location, temperature units, 12/24-hour clock, and a wallpaper override.

## Demo mode

Both apps accept the `-LookoutDemo` launch argument. It swaps in an in-memory store with sample events, reminders, weather, cameras and accessories, and never touches CloudKit. Useful for screenshots and for working on layout without a paired phone:

```bash
xcrun simctl launch booted fm.beard.Lookout -LookoutDemo
```

## Apple Developer setup (done 2026-10-21)

- App Store Connect record "Lookout: Apple TV Dashboard", bundle ID `fm.beard.Lookout`, SKU `lookout`, platforms iOS and tvOS.
- App ID capabilities: Push Notifications, HomeKit, iCloud with container `iCloud.fm.beard.Lookout`, WeatherKit (Capabilities tab and App Services tab).
- **CloudKit schema** – run the iPhone app once in Debug with calendar access granted, then deploy the schema from Development to Production in CloudKit Console before relying on a TestFlight build. Debug builds use `Development`, Release builds use `Production` (`LOOKOUT_CLOUDKIT_ENVIRONMENT`).

## Uploading to TestFlight

`Tools/release.sh` archives both targets and uploads them. It is deliberately not the usual automatic-signing flow: on this Mac xcodebuild can neither use Xcode's account nor provision through the API key, so it archives unsigned, ad-hoc signs with Production entitlements, and exports with manual signing against the App Store profiles "Lookout App Store iOS" and "Lookout App Store tvOS" (created through the App Store Connect API, installed under `~/Library/Developer/Xcode/UserData/Provisioning Profiles`). The upload step authenticates with the shared API key in `~/.appstoreconnect/private_keys`.

Bump `CURRENT_PROJECT_VERSION` in the project before each upload. If App ID capabilities change, recreate the two profiles first (the profiles embed the capability list).

## Building for the simulator

```bash
xcodebuild -project Lookout.xcodeproj -scheme Lookout   -destination 'generic/platform=iOS Simulator'  build
xcodebuild -project Lookout.xcodeproj -scheme LookoutTV -destination 'generic/platform=tvOS Simulator' build
```
