# Changelog

This file tracks notable user-facing changes by release. Changes awaiting the first release are grouped under **Unreleased**; implementation details and daily progress belong in Git history.

## Unreleased

### Added

- Offline daily watering reminders with a configurable time, overdue follow-ups, per-plant exclusions, and a Settings tab. The next 60 reminders are replenished whenever Sprout opens; tapping a reminder opens today's calendar.
- An optional plant photo from the photo library or camera, with previews in the plant list, calendar agenda, and details and the ability to replace or remove it.
- Plant tracking with configurable watering intervals and a monthly calendar showing scheduled, completed, and overdue waterings.
- A **Watered today** checkbox to record or undo today's watering, with changes preserved after restarting the app.
- Room management and plant organization by room or watering date, with a remembered display preference. Deleting a room preserves its plants and watering history.
- English and French localization, with dates and calendar layout following iOS language and regional preferences.
- Local storage for plants, rooms, and watering history, without requiring an account.
- Support for light and dark modes, Dynamic Type, and VoiceOver labels.

### Fixed

- The next watering date, status, and checkbox stay together in one card when recording or undoing a watering.
