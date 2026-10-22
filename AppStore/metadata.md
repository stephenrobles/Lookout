# Lookout — App Store listing

Everything entered in App Store Connect for 1.0, kept here as the source of truth.

## App Information

- **Name:** Lookout: Apple TV Dashboard (as created in App Store Connect)
- **Apple ID:** 6825536782
- **Subtitle (30):** Your day on the big screen
- **Bundle ID:** fm.beard.Lookout (iOS + tvOS, universal purchase)
- **Primary category:** Utilities
- **Secondary category:** Lifestyle
- **Content rights:** Does not contain, show, or access third-party content
- **Age rating:** 4+ (no questionnaire items apply)
- **Price:** Free, all territories
- **Copyright:** 2026 Stephen Robles

## Version Information (1.0)

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
• Locks, doors, garage, sensors and temperatures from HomeKit, with an orange banner under the clock when a door is left unlocked
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

**What's New (1.0):**
First release. A status board for your Apple TV: clock, agenda, reminders, weather, and your HomeKit cameras, locks and sensors, set up from your iPhone.

**What to Test:**
Build 3 changes: calendar, reminder list and Home picker rows now show plain black names (they picked up the amber tint before), reminder lists with no title read "Untitled", and the Apple TV settings screen has a solid backdrop instead of showing the board through it. Also new: the CloudKit schema is deployed, so sync between iPhone and Apple TV works on TestFlight builds for the first time.

To test: on the iPhone, allow Calendar and Reminders access, pick calendars and lists, toggle panels, choose a wallpaper photo and adjust dim and blur. Open Lookout on an Apple TV signed in to the same iCloud account and confirm the agenda and reminders appear within a minute and update when you change an event. On the TV, open Settings (gear, top right) to set a weather location. If the Apple TV is a home hub, check camera stills, the live view on click, and lock, door and sensor states. Report anything that overlaps, truncates or reads poorly from the couch.

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
- Managed with `node Tools/appstore.mjs` (status, metadata, screenshots, attach, prepare, testflight, submit).
