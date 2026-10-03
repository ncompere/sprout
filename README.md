# Sprout

A native iOS app in English and French for tracking indoor plants and their watering schedules. Built with SwiftUI and SwiftData, for iOS 17+, with no external dependencies.

## Running the app

1. Open `Sprout.xcodeproj` in Xcode and select the shared **Sprout** scheme.
2. Choose an iPhone simulator running iOS 17 or later. Install an iOS runtime from Xcode settings if needed.
3. Run with **⌘R**. For a physical iPhone, select your team under **Signing & Capabilities** and use your own bundle identifier.

The repository includes the project and scheme: no project generator or package manager is required.

## Using Sprout

- **My plants**: add plants with a name, optional room, first due date, and watering interval in days (7 days by default). Switch between **By room** and **By watering**; Sprout remembers your choice. The watering view shows overdue plants first.
- **Rooms**: use **Manage rooms** to create, rename, or delete rooms. You can also create a room from the plant form. Deleting a room moves its plants to **No room** and preserves their watering history.
- **Plant details**: edit a plant's name, room, or schedule. Check **Watered today** to record a watering, or uncheck it to undo today's record. Deleting a plant also deletes its watering history.
- **Calendar**: browse months and tap a day to view scheduled, completed, and overdue waterings across all rooms. Tap **Today** to return to the current day.

The first due date applies until the first watering. After that, the next due date is the last watering date plus the interval, so watering early or late shifts the schedule. Undoing today's watering restores the schedule based on the previous record, or the first due date if none remains. An overdue watering stays a single pending task, without accumulating missed tasks.

## Languages and data

Sprout supports English and French. iOS chooses the language from your preferences; you can also choose it in Sprout's system settings. Dates follow the active language, and the first day of the week follows your regional preferences. Watering schedules use calendar days in the iPhone's time zone.

Plants, rooms, and watering history are stored locally on the device. Changing the language preserves your data. The app requires no account and has no CloudKit synchronization.

The current app does not include notifications, photos, or plant identification, and is not yet published on the App Store.

## Development

Run **⌘U** in Xcode to run the tests. See the [development guide](docs/DEVELOPMENT.md) for architecture, translation guidelines, command-line builds, and test coverage, and the [validation records](docs/VALIDATION.md) for past checks and their environments.

User-facing changes are tracked in the [changelog](CHANGELOG.md). Day-to-day implementation details belong in commits and pull requests.

## License

Sprout is licensed under the [Apache License 2.0](LICENSE).
