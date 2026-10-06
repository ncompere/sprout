# Developing Sprout

See the [README](../README.md) for requirements, setup, and an overview of the app.

## Data and architecture

Plants, their rooms, and their waterings are kept in local SwiftData storage, with no account or CloudKit synchronization. Deleting a plant also deletes its associated waterings. Saves are explicit: a failure rolls back the mutation and displays an error; the form stays open with its entries preserved. A storage initialization failure presents a retry action without replacing the data with temporary storage.

- `Models.swift`: plants, rooms, and waterings, with inverse relationships. Waterings are cascade-deleted with their plant; deleting a room only removes its assignments. Adding rooms uses an automatic lightweight migration: existing plants become **No room** without changing their data or history.
- `WateringSchedule.swift`: calendar calculations independent of the interface and storage.
- `WateringReminders.swift`: immutable plant snapshots, daily summary planning, and local reminder preferences. The planner uses the real next due date, not calendar projections, and produces at most 60 requests, including daily overdue follow-ups. It starts at the earliest participating deadline, even for dates more than 60 days away. Missing DST times advance to the next available time; repeated times use the first occurrence.
- `ReminderService.swift`: injectable notification-center adapter, permission handling, serialized queue reconciliation, and early installation of the notification delegate. Successful explicit saves publish `PlantStore.didCommit`; failed saves publish nothing. The coordinator updates only `Sprout.watering.*` requests, replaces same-date identifiers, and discards obsolete dates before adding new ones. A change during an asynchronous operation invalidates the snapshot and triggers another reconciliation. Errors leave stored garden data intact and expose a retry action in Settings.
- `PlantStore.swift`: validation, saving, room assignment, watering, and deletion.
- `PlantPhoto.swift`: photo resizing/encoding and form-local drafts. Photos are optional SwiftData external-storage data, migrated automatically for existing plants. Library images are downsampled with ImageIO; camera images are normalized before JPEG encoding (1,600 pixels maximum, quality 0.8). Processing happens off the main thread; failed or obsolete imports preserve the draft. Camera permission copy is translated in `InfoPlist.xcstrings`.
- `Views/`: list, details, plant and room forms, room management, and monthly calendar, with surfaces adapted to light and dark modes, Dynamic Type, and VoiceOver labels.
- `Localization.swift` and `Localizable.xcstrings`: shared phrases and plurals, English/French translations, and the presentation calendar based on iOS preferences.

The seven-column grid limits the scaling of its day numbers to the first accessibility size to keep dates distinct. The agenda and other text support the largest sizes. At accessibility sizes, form titles can occupy two lines in the navigation bar to display their full text. Launch arguments used for presentation tests are only active in Debug builds.

Reminder opt-in and hour/minute are stored in UserDefaults separately from iOS authorization. `Plant.remindersIncluded` defaults to true, including for migrated plants; legacy store callers preserve the value and failed edits restore it. There is no background refresh task or push server. Requests use Gregorian calendar components at a floating local time; opening/foregrounding the app, regional and significant-time changes, and a new day while the app is active renew the reserve. The delegate replays a calendar navigation request even when it arrives before the root view exists.

## Adding or maintaining a translation

1. Open `Sprout/Localizable.xcstrings` in Xcode. The catalog contains interface text, errors, and VoiceOver announcements, with their English and French translations.
2. To add a language, add it to the project's localizations and to the catalog, then translate every entry and its plural variants. Comments explain the numeric arguments.
3. Write new SwiftUI text as localizable literals. For text created outside views, use `String(localized:)`. Reuse `LocalizedCopy` for counts and intervals; do not construct plurals by appending a suffix. Keep accessibility identifiers and stored values independent of translations.
4. Build in Xcode to extract strings and update the catalog, then check for missing translations. Command-line extraction produces `.stringsdata` files in the build intermediates; use `xcrun xcstringstool sync Sprout/Localizable.xcstrings --stringsdata <stringsdata-files>` to synchronize the catalog.
5. Run the tests and inspect translated screens, especially forms, confirmations, dates, plurals, and large text sizes. UI tests share the same flows in English and French and also cover English with a French region and changing the language after a watering.

## Building and testing

Run **⌘U** in Xcode. The scheme includes schedule tests, persistence tests, and UI flows. UI tests add plants and rooms with unique names, then delete them; other plants and rooms are not modified. Light and dark screenshots are attached to the Xcode test report.

Run the following commands from the repository root. If `xcode-select -p` points to Command Line Tools, prefix the commands with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` to use the installed Xcode without changing the system configuration:

```sh
xcrun simctl list devices available
xcodebuild -project Sprout.xcodeproj -scheme Sprout \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  -derivedDataPath /tmp/sprout-build \
  -parallel-testing-enabled NO CODE_SIGNING_ALLOWED=NO test
```

Adjust the simulator name to an installed device. The photo UI flows require at least one image in the simulator photo library. With your selected simulator booted, seed it using the included fixture (replace `DEVICE-UUID` with its identifier from `simctl list`):

```sh
xcrun simctl addmedia DEVICE-UUID SproutUITests/Fixtures/plant.png
```

Photo tests cover normalization, resizing, obsolete/failed imports, saving, rollback, persistence, and migration from the schema with rooms but no photos. UI flows cover choosing/replacing/removing a photo, cancelling changes, and persistence while retaining watering history, in French, English dark mode, and the largest text size. Camera capture and permission refusal need a physical iPhone or iPad; the camera action is hidden on simulators.

To build only:

```sh
xcodebuild -project Sprout.xcodeproj -scheme Sprout \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /tmp/sprout-build CODE_SIGNING_ALLOWED=NO build
```

Tests cover early and late waterings, duplicates, interval changes, month and year boundaries, February 29, daylight saving time transitions, projections, disk persistence, cascade deletion, and rollback after a save failure. Undoing a watering is checked with and without earlier waterings, after reopening storage, and when saving fails. UI tests check adding, watering, unchecking, editing, restarting, the calendar, and deletion. Room tests cover names, assignments and their inverse relationships, renaming, deleting an occupied room, persistence, save failures, and migration from storage created with the previous schema. UI flows also check room creation from the plant form, changing and removing assignments, deletion without losing waterings, and remembering the display mode.

Reminder tests cover summaries and exclusions, far-future deadlines, the 60-request cap, past reminder times, DST and time-zone changes, localized notification content, opt-in and denied permissions, retries, reserve replacement, concurrent updates, successful store events, rollback, and migration from the schema with photos. The reminder UI flows use a Debug-only notification adapter and an isolated UserDefaults suite, so they do not change real notification permission or reminder preferences. They cover French, English dark mode, the largest text size, refusal, error recovery, cold-start calendar routing, and cancelled/persisted plant exclusions.

On a physical iPhone, also verify actual authorization, receiving a local reminder with Sprout closed, and tapping it to open today's calendar. Test Focus/Scheduled Summary behavior, changing the device time zone, and disabling permission in system settings. UI-test permission simulations are not a substitute for these device checks.

`testReminderActualDeliveryAndTapOnPhysicalDevice` skips on simulators. On an unlocked physical device, it chooses a time one to two minutes ahead, requests real notification permission, closes Sprout, and checks reception and cold-start calendar navigation. It cleans up its uniquely named plant and temporary reminder preferences, then relaunches normally. It requires app and UI-test runner provisioning profiles, plus notification delivery enabled in the device's Focus/Summary settings.

For past test environments and results, see the [validation records](VALIDATION.md). These records are historical; run the tests to validate your current checkout.
