# Sprout

A native iOS app in English and French for tracking indoor plants and their watering schedules. Built with SwiftUI and SwiftData, for iOS 17+, with no external dependencies.

## Running the app

1. Open `Sprout.xcodeproj` in Xcode and select the shared **Sprout** scheme.
2. Choose an iPhone simulator running iOS 17 or later. Install an iOS runtime from Xcode settings if needed.
3. Run with **⌘R**. For a physical iPhone, select your team under **Signing & Capabilities** and use your own bundle identifier.

The repository includes the project and scheme: no project generator or package manager is required.

## Using Sprout

- **My plants**: add plants with a name, optional photo and room, first due date, and watering interval in days (7 days by default). Switch between **By room** and **By watering**; Sprout remembers your choice. The watering view shows overdue plants first.
- **Rooms**: use **Manage rooms** to create, rename, or delete rooms. You can also create a room from the plant form. Deleting a room moves its plants to **No room** and preserves their watering history.
- **Plant details**: edit a plant's name, photo, room, or schedule. Choose a photo from your library or take one with the camera; replace or remove it from the plant form. Photos appear in the plant list, calendar agenda, and plant details. Check **Watered today** to record a watering, or uncheck it to undo today's record. Deleting a plant also deletes its watering history.
- **Calendar**: browse months and tap a day to view scheduled, completed, and overdue waterings across all rooms. Tap **Today** to return to the current day.
- **Settings**: enable watering reminders and choose a daily time (9 am by default). Allow alerts and sounds when iOS asks; if permission is denied, open iOS notification settings from this screen. Each reminder groups due and overdue plants, and overdue plants remain included until you record a watering. Use **Include in reminders** in a plant's form to exclude it. Tapping a notification opens today's calendar.

The first due date applies until the first watering. After that, the next due date is the last watering date plus the interval, so watering early or late shifts the schedule. Undoing today's watering restores the schedule based on the previous record, or the first due date if none remains. An overdue watering stays a single pending task, without accumulating missed tasks.

Reminders are off initially and work offline, even with Sprout closed. The app prepares the next 60 daily reminders, starting with the next eligible date, and replenishes them whenever you open it. There are no reminders on days without participating plants due. If today's chosen time has passed, reminders start tomorrow. After the reserve runs out, reopen Sprout to resume reminders. Saves, waterings, undos, and changes to reminder settings update the reserve. Disabling reminders cancels pending and displayed watering notifications. Reminder delivery follows your iOS notification settings, including Focus and Scheduled Summary.

## Languages and data

Sprout supports English and French. iOS chooses the language from your preferences; you can also choose it in Sprout's system settings. Dates follow the active language, and the first day of the week follows your regional preferences. Watering schedules use calendar days in the iPhone's time zone.

Plants, photos, rooms, and watering history are stored locally on the device. Photos are resized before storage and are saved only when you confirm the plant form. Camera access is requested when taking a photo; if denied, you can enable it in Settings. Changing the language preserves your data. The app requires no account and has no CloudKit synchronization.

The current app does not include plant identification and is not yet published on the App Store.

## Development

Run **⌘U** in Xcode to run the tests. See the [development guide](docs/DEVELOPMENT.md) for architecture, translation guidelines, command-line builds, and test coverage, and the [validation records](docs/VALIDATION.md) for past checks and their environments.

User-facing changes are tracked in the [changelog](CHANGELOG.md). Day-to-day implementation details belong in commits and pull requests.

## License

Sprout is licensed under the [Apache License 2.0](LICENSE).
