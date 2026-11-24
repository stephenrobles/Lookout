# Lookout — App Store listing

Everything entered in App Store Connect for 1.0, kept here as the source of truth.

## App Information

- **Name:** Lookout: TV Dashboard (renamed 2026-10-25; "Lookout: Apple TV Dashboard" was rejected under guideline 5.2.5 for using an Apple product name in the app name)
- **Apple ID:** 6825536782
- **Subtitle (30):** Your day on the big screen
- **Bundle ID:** fm.beard.Lookout (iOS + tvOS, universal purchase)
- **Primary category:** Utilities
- **Secondary category:** Lifestyle
- **Content rights:** Does not contain, show, or access third-party content
- **Age rating:** 4+ (no questionnaire items apply)
- **Price:** Free, all territories
- **Copyright:** 2026 Stephen Robles

## Version Information (1.1)

**Promotional text (170):**
Turn an Apple TV into a glanceable status board: clock, agenda, reminders, weather and your HomeKit cameras, locks and sensors. Set it up from your iPhone.

**Description (4000):**
Lookout turns your Apple TV into a status board for the whole household. Glance up and see the time, what's next on the calendar, reminders that are due, the weather, and the cameras, locks and sensors from your home, all over a wallpaper you choose.

Set it up once from the iPhone app. Pick which calendars and reminder lists feed the board, which panels appear, which cameras and accessories to show, and a photo or gradient for the background. The Apple TV app reads that setup through your own iCloud account and keeps itself current as your calendar changes.

ON THE APPLE TV
• A large clock, today's date and a one-line "next up" from your calendar
• Agenda for today, tomorrow and the days ahead, in your calendar colors, with a line marking where now is
• Due reminders from the lists you choose, with overdue items called out
• Current conditions, the next six hours and the week ahead from Apple Weather
• Camera stills from HomeKit that refresh on their own. Click one with the remote to watch it live, full screen
• Lights, smart plugs, switches, locks, doors, garage, sensors and temperatures from HomeKit, with an orange banner under the clock when a door is left unlocked
• Keeps the TV awake while the board is showing

ON THE IPHONE AND IPAD
• Choose calendars, reminder lists and how many days to show
• Turn panels on or off and reorder the right-hand column
• Pick a wallpaper photo or gradient, then dim and blur it until the text reads from across the room
• Choose which HomeKit cameras and accessories the board shows

PRIVATE BY DESIGN
Lookout has no account, no analytics and no servers of its own. The iPhone app publishes a small snapshot of upcoming items to the private CloudKit database of your iCloud account, and only your Apple TV reads it. Cameras and accessories are read by the Apple TV directly through HomeKit and are never recorded or forwarded.

REQUIREMENTS
Apple TV 4K running tvOS 26 or later, and an iPhone or iPad running iOS 26 or later, signed in to the same iCloud account. Weather needs a location set once on the Apple TV. Home panels need a HomeKit home with the Apple TV as a home hub.

**Keywords (100):**
dashboard,status board,apple tv,calendar,agenda,reminders,weather,homekit,camera,wall display,clock

**Support URL:** https://beardfm.app/support/?app=lookout
**Marketing URL:** https://beardfm.app/lookout/
**Privacy Policy URL:** https://beardfm.app/lookout/privacy/

**What's New (1.5.1):**
Calendar and reminder changes picked up in the background now reach your Apple TV more reliably: Lookout keeps going until the upload to iCloud has finished instead of stopping as soon as the change is saved on the iPhone. The same goes for a setting you change just before leaving the app. After reinstalling Lookout, or moving to a new iPhone from a backup, the app takes up publishing again right away instead of waiting up to a day and a half for its earlier self, and the status card says so when it does.

**What's New (1.5):**
Sync between iPhone and Apple TV is more dependable. The Apple TV now also reads your board straight from iCloud, so it keeps up even when its saved copy falls behind or is cleared by tvOS, and it repairs that copy on its own. It remembers your layout and chosen cameras instead of falling back to showing everything while it catches up. Settings on the Apple TV shows when iCloud was last checked, says what is wrong if something is, and has a Reload from iCloud button. On the iPhone, reinstalling Lookout or adding a second device no longer replaces your board with a blank one, and the status card now tells you when the upload to iCloud succeeded or why it did not.

**What's New (1.4):**
Lookout now speaks German on iPhone, iPad and Apple TV. A new "Show lists separately" switch in the Reminders settings puts up to three reminder lists side by side under the agenda, each with its own heading, and includes reminders without a due date. Use it for to-dos, a meal plan and groceries.

**What's New (1.3):**
Picking cameras and accessories on your iPhone now works the way you'd expect: turning off All clears every item, tapping an item leaves just that one out, and unchecking the last one keeps the panel empty instead of showing everything again. The same applies to calendars and reminder lists. If more than one iPhone or iPad on your account runs Lookout, the one you last changed settings on does the publishing, so two phones no longer overwrite each other's agenda. Camera pictures keep their true proportions instead of being stretched, and cameras that don't provide stills now show a live picture on the board.

**What's New (1.2):**
The Home panel now shows your lights, smart plugs and switches alongside locks, doors, garage, sensors and temperatures. Lights show their brightness when dimmed. If your account has more than one home, the iPhone picker names the home for each camera and accessory and keeps each home's accessories together.

**What's New (1.1):**
Choosing specific cameras or home accessories on your iPhone now works on the Apple TV. The TV matches your picks by name, so the Cameras and Home panels show exactly what you chose instead of going empty. Changes made in the Home picker also reach the TV right away.

**What to Test:**
Build 12 (1.5.1) is two fixes on the iPhone and iPad; the Apple TV app is unchanged apart from its version. Background updates: leave Lookout closed on the iPhone, add or move a calendar event on another device, and check the Apple TV shows it within an hour or two without opening the iPhone app (before, it could stay stale until the app was opened). Then change a setting on the iPhone, go to the Home Screen straight away, and confirm the board follows within a minute. Reinstall: open build 12 once so it publishes, delete Lookout from the iPhone, install it again and open it. Once your board has come back the status card should read "Lookout was reinstalled, so this iPhone took over publishing from its earlier name, iPhone XXXX", and Settings on the Apple TV should show the new name under "Published by" within a minute or two. A reinstall straight from 1.5, without opening 1.5.1 first, is not recognized and still needs Publish now. If you move to a new iPhone from a backup, the card should read "This iPhone replaced iPhone XXXX and took over publishing from it." With an iPhone and an iPad both in use, the publisher should not change unless you change a setting or tap Publish now.

Build 11 (1.5) is about sync (Sven H.'s report: the Apple TV showed "Last update from iPhone: Never" and went back to all cameras). Apple TV: open Settings (gear, top right) and check the Sync section shows a recent "Last check with iCloud" time and no orange message; change something on the iPhone and confirm the board follows within a minute or two; try Reload from iCloud. If you chose specific cameras, confirm the others never appear, including right after launching the app. iPhone: the status card should read "Uploaded to iCloud" shortly after Publish now. If you can, delete Lookout from the iPhone, reinstall it, and confirm your panels, wallpaper and selections come back instead of defaults.

Build 9 (1.4) adds German and separate reminder lists. German: set the iPhone and Apple TV language to German and look for anything left in English or awkwardly worded. Lists: on the iPhone open Reminders › Lists and choose two or three lists, then turn on "Show lists separately"; the Apple TV should move Reminders under the agenda with one column per list, including items without a due date. Turn it off and confirm the single Reminders panel returns to the right column.

Build 7 (1.3) fixes the pickers, multi-device publishing and camera tiles. Pickers: on the iPhone open Home, turn off All under Cameras and confirm every checkmark disappears and the Apple TV's Cameras panel reads "No cameras chosen"; tap one camera and confirm only it comes back on the TV; with All on, tap one camera and confirm the others stay checked and the TV drops just that one. Do the same under Accessories, Calendars and Reminder lists. Multi-device: if you run Lookout on two iPhones or iPads, change a setting on one; the main screen on the other should read "Published … by iPhone XXXX" with a note that the first device publishes, and the agenda on the TV should stop flipping between the two devices' calendars. Cameras: tiles should show the camera's own proportions (cropped, not stretched), the full-screen view letterboxes, and a camera that never gave a still before should show a live picture with a red dot after a few seconds.
## App Privacy

- **Data collection:** Data Not Collected
- Privacy policy URL as above

## App Review Information

- **Contact:** Stephen Robles, steve@beard.fm
- **Sign-in required:** No
- **Notes:**
  Lookout has two parts under one bundle ID: an iPhone/iPad app that chooses what to show and publishes a snapshot of upcoming calendar events and reminders to the user's private CloudKit database, and an Apple TV app that displays the board. No account or server of ours is involved. To review without a paired phone, launch either app with the launch argument -LookoutDemo (Xcode scheme or a test harness); it then shows sample events, reminders, weather, cameras and accessories without touching iCloud. On a real Apple TV signed in to the same iCloud account as an iPhone running the app with Calendar access granted, the agenda appears within a minute. Weather requires a location set on the Apple TV in Settings (gear in the top-right corner of the board). Home panels show "No HomeKit cameras in this home" when the Apple TV is not part of a HomeKit home, which is expected.

## Export compliance

Uses only standard HTTPS/no custom encryption: `ITSAppUsesNonExemptEncryption = NO` in both Info.plists.

## Screenshots

- iPhone 6.9" (1320×2868): main screen, panels, wallpaper, home picker, staged with `-LookoutDemo -LookoutScreen <panels|wallpaper|home>`
- iPad 13" (2064×2752): the same four
- Apple TV (1920×1080): board with the Forest gradient, board with Midnight, TV settings

Files live in `AppStore/screenshots/` as `iphone-*.png`, `ipad-*.png`, `tv-*.png`.

## TestFlight

- External group "Primary Tech" with a public link; beta description and What to Test come from this file.

## Submitted

- 1.0 (1) for iOS and tvOS uploaded 2026-10-21; superseded by build 2 (TV settings backdrop fix).
- 1.0 (2) for iOS and tvOS submitted for App Review on 2026-10-21, and to Beta App Review for the external "Primary Tech" group (public link https://testflight.apple.com/join/tvsynyw7). 1.0 (3) replaces build 2 on 2026-10-22: picker text fix, schema seed, settings backdrop.
- 1.0 (3) rejected on 2026-10-25 (guideline 5.2.5: "Apple TV" in the app name). Renamed to "Lookout: TV Dashboard" and resubmitted both platforms with the same build.
- 1.0 (3) approved and released on 2026-10-27 as "Lookout: TV Dashboard" (https://apps.apple.com/us/app/lookout-tv-dashboard/id6825536782).
- 1.1 (4) for iOS and tvOS uploaded 2026-10-27: HomeKit camera and accessory selection fix. Submitted for App Review (automatic release) and to the "Primary Tech" TestFlight group. Live on 2026-10-30.
- 1.2 (5): lights, smart plugs and switches in the Home panel, plus home names in the picker for accounts with several homes (requested by a listener). Uploaded 2026-11-01, submitted for App Review (automatic release) and to the "Primary Tech" TestFlight group.
- 1.3 (7): picker "none" fix (David Hunter's report), one publishing device per account (Don Brown's calendars report), camera proportions and stream fallback (Don Brown's cameras report). Build 6 was built locally only; build 7 uploaded 2026-11-05, submitted for App Review (automatic release) and to the "Primary Tech" TestFlight group.
- 1.4 (9): German localization and separate reminder lists (Rodney Holinger's requests). Build 8 was built locally only; build 9 uploaded 2026-11-10, submitted for App Review (automatic release) and to the "Primary Tech" TestFlight group. App Store listing stays English only.
- 1.5 (11): sync rework after Sven H.'s report (Apple TV showed "Never" and reverted to defaults): direct CloudKit read on the TV, self-repairing store, remembered layout, config ranking by last edit, upload status on the iPhone. Build 10 was built locally only; build 11 uploaded 2026-11-19, submitted for App Review (automatic release) and to the "Primary Tech" TestFlight group.
- 1.5.1 (12): background publishes held until iCloud has them, and publishing taken over at once after a reinstall or a move to a new phone. Uploaded 2026-11-24, submitted for App Review (automatic release) and to the "Primary Tech" TestFlight group.
- **iCloud schema, 2026-11-24, at Stephen's instruction:** `CD_wallpaperImageData_ckAsset` (Asset) was missing from `CD_BoardConfig` in both Development and Production, although the README's seeding step expects it; the seed's 1×1 JPEG is too small to be stored as an asset, so the field was never created. A photo wallpaper large enough to be stored as an asset could therefore not upload, which stops the whole board record. Added the field in Development in CloudKit Console and deployed it to Production (one new field, no index or security-role changes). Production now lists 26 fields on `CD_BoardConfig`. No app change was needed.
- Managed with `node Tools/appstore.mjs` (status, metadata, screenshots, attach, prepare, testflight, submit).
