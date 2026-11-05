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

**What's New (1.3):**
Picking cameras and accessories on your iPhone now works the way you'd expect: turning off All clears every item, tapping an item leaves just that one out, and unchecking the last one keeps the panel empty instead of showing everything again. The same applies to calendars and reminder lists. If more than one iPhone or iPad on your account runs Lookout, the one you last changed settings on does the publishing, so two phones no longer overwrite each other's agenda. Camera pictures keep their true proportions instead of being stretched, and cameras that don't provide stills now show a live picture on the board.

**What's New (1.2):**
The Home panel now shows your lights, smart plugs and switches alongside locks, doors, garage, sensors and temperatures. Lights show their brightness when dimmed. If your account has more than one home, the iPhone picker names the home for each camera and accessory and keeps each home's accessories together.

**What's New (1.1):**
Choosing specific cameras or home accessories on your iPhone now works on the Apple TV. The TV matches your picks by name, so the Cameras and Home panels show exactly what you chose instead of going empty. Changes made in the Home picker also reach the TV right away.

**What to Test:**
Build 6 (1.3) fixes the pickers, multi-device publishing and camera tiles. Pickers: on the iPhone open Home, turn off All under Cameras and confirm every checkmark disappears and the Apple TV's Cameras panel reads "No cameras chosen"; tap one camera and confirm only it comes back on the TV; with All on, tap one camera and confirm the others stay checked and the TV drops just that one. Do the same under Accessories, Calendars and Reminder lists. Multi-device: if you run Lookout on two iPhones or iPads, change a setting on one; the main screen on the other should read "Published … by iPhone XXXX" with a note that the first device publishes, and the agenda on the TV should stop flipping between the two devices' calendars. Cameras: tiles should show the camera's own proportions (cropped, not stretched), the full-screen view letterboxes, and a camera that never gave a still before should show a live picture with a red dot after a few seconds.

Build 5 (1.2) adds lights, smart plugs and switches to the Home panel and to the Accessories list in the iPhone Home picker. Lights read On, Off or On with a brightness percentage when dimmed; plugs and switches read On or Off. None of them trigger the orange alert banner. With more than one home on the account, the iPhone picker shows the home name under each camera and accessory and lists each home's items together. To test: confirm your lights and plugs appear on the Apple TV and that toggling one in the Home app updates the chip within a few seconds, then pick a few under Accessories on the iPhone and confirm the TV shows only those.

Build 4 (1.1) fixes camera and accessory selection. Before, turning off "All" and picking a few cameras or accessories on the iPhone left the Cameras and Home panels on the Apple TV empty, because HomeKit gives every device its own identifiers. The TV now matches your picks by home and accessory name, and if a saved selection matches nothing it shows everything rather than a blank panel.

To test: on the iPhone open Home, turn off All under Cameras and keep one or two, then confirm the Apple TV shows only those within a minute. Do the same under Accessories. Turn All back on and confirm everything returns. Everything from 1.0 still applies: calendars, reminder lists, panels, wallpaper, weather location on the TV, camera stills and live view.

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
- 1.3 (6): picker "none" fix (David Hunter's report), one publishing device per account (Don Brown's calendars report), camera proportions and stream fallback (Don Brown's cameras report). Built 2026-11-05 on branch 1.3; not yet uploaded.
- Managed with `node Tools/appstore.mjs` (status, metadata, screenshots, attach, prepare, testflight, submit).
