# Reader, search and backup repair

The local backup screen has two actions: create a complete ZIP and restore a file.
There is no separate JSON export. Older metadata-only JSON copies remain readable.
The ZIP contains a versioned manifest and EPUBs. Audio files are excluded.

Primary source comparisons inspected on 2026-11-08:

- [2FAS file picker](https://github.com/twofas/2fas-ios/blob/main/TwoFAS/TwoFAS/Root/Modules/Settings/Backup/Importer/ImporterOpenFile/ImporterOpenFileViewController.swift): native picker, explicit selection and cancellation, separate parsing.
- [Workout Tracker settings](https://github.com/AlexMihalache99/Workout-Tracker-iOS/blob/main/WorkoutTracker/Views/Settings/SettingsView.swift): export/import pair, scoped file access, validation and confirmation.
- [Apple document picker](https://developer.apple.com/documentation/uikit/uidocumentpickerviewcontroller): imported copies, coordinated access and document providers.

The previous picker used open-in-place with `.item` and began reading during sheet dismissal. This is a fragile path, not proof of the exact device failure. The new independent UIKit presenter imports a copy of a regular file, stages it and delivers the result after dismissal. Validation uses file bytes rather than filename or provider UTI.

Read-only SSH inspection confirmed build 82. Two converted EPUBs had one HTML resource each (960,837 and 11,362,120 bytes) and no embedded images. Both were at progress zero with no bookmarks. Device files were not modified. Covers discarded by the old converter cannot be reconstructed from those EPUBs alone.

Initial Readium preferences now include theme and font. Position counting no longer blocks presentation twice. New conversions split text into approximately 64 KiB resources and preserve embedded FB2 covers, title and author. Existing imported EPUBs can recover embedded covers locally. Only recognized old converter output with no progress or bookmarks may be optimized; the original file remains on disk.

Validation runs production catalog regressions, macOS import/backup round trips and generic iPhone compilation. No simulator or IPA publication. Native picker interaction, theme transitions and font changes still need verification on an iPhone running the updated binary.
