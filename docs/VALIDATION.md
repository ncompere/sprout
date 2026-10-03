# Validation records

These reports were moved from the README. They record checks reported during development, rather than a guarantee for the current checkout. No tests were rerun as part of this documentation reorganization.

See [Developing Sprout](DEVELOPMENT.md#building-and-testing) for build and test instructions. Add future reports here only when they capture useful validation evidence, such as a release check, a migration, or a new supported environment.

## October 1, 2026

Verified on October 1, 2026 with Xcode 27: all 29 tests (26 logic/persistence tests and 3 UI tests) pass on iPhone SE (3rd generation), iOS 18.2. UI flows also pass on iPhone 17, iOS 26.2. An additional check on iPhone SE with the largest system text size passes, with light, dark, and enlarged-text screenshots inspected. Debug and Release builds for the simulator succeed. The iOS 17 runtime was not installed, so the minimum supported version was not run here.

## October 2, 2026 — Undoing a watering

On October 2, 2026, all 32 tests (29 logic/persistence tests and 3 UI tests) pass on iPhone SE, iOS 18.2, after adding the ability to uncheck a watering. The UI flow also checks the return to scheduled status in the calendar, persistence of the undo after restarting, and the ability to check a watering again.

## October 3, 2026 — Watering checkbox

On October 3, 2026, the watering button is replaced with a checkbox. All 29 logic/persistence tests and 3 UI flows pass on iPhone SE, iOS 18.2. The flows check the checkbox's accessible state, its touch target of at least 44 points, tapping both the checkbox and its label, and persistence after restarting. Plant detail screenshots in light mode, dark mode, and at the largest text size have been inspected.

## October 3, 2026 — Rooms

On October 3, 2026, organization by room is added. All 35 logic/persistence tests and 4 UI flows pass on iPhone SE (3rd generation), iOS 18.2. Migration from the previous storage schema preserves plants and their waterings. The full room flow also passes on iPhone 17, iOS 26.0. Room screenshots in light mode, dark mode, and at the largest text size have been inspected; the room selector displays long names over multiple lines at accessibility sizes. Debug and Release builds for the simulator succeed.

## October 3, 2026 — Localization

On October 3, 2026, English/French localization is verified with Xcode 27: all 41 logic, persistence, and localization tests and 10 UI flows pass on iPhone SE (3rd generation), iOS 18.2. An eleventh flow on iPhone 17, iOS 26.0, checks the `fr_FR` and `en_US` configurations, English with a French region, calendar weekday alignment, and translated validation errors. The flows also cover restarting in another language without losing the plant or its watering. Light, dark, and largest-text screenshots have been inspected; form titles were adjusted, and both largest-text flows were rerun successfully. Debug and Release builds succeed. The iOS 17 runtime remains unavailable for running the minimum supported version.
