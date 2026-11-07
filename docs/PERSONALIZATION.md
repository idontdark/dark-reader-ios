# Personalization and localization (0.4.0)

## First launch (skippable)

1. Choose Russian or English.
2. Choose books, audiobooks or both. Audio playback is not available yet, only the preference is stored.
3. Pick genres.
4. Pick favorite authors or enter a custom author name.
5. Finish and enter the library.

The sequence is shown when `onboardingSchemaVersion < 2`. Existing users who completed the old welcome view see the new questionnaire once after upgrading, but retain their library. Skipping a step never deletes previously saved choices.

Preferences persist with AppStorage:
- `appLanguage` (ru/en)
- `preferredBookLanguage` (auto/ru/en/all)
- `preferredAuthorsJSON` (JSON string array)
- `preferredGenresJSON` (JSON string array)
- `wantsBooks`, `wantsAudiobooks`
- `onboardingSchemaVersion`

## Language behavior

All major user-facing labels are localized with Russian and English `Localizable.strings` resources. `\.environment(\.locale, Locale(identifier: appLanguage))` updates SwiftUI labels when language changes in Settings. Native labels, system dialogs and some catalog-supplied metadata can still use the device language or original source language.

Book-language selection is independent from interface language. "Automatic" follows the app language. Gutendex supports `languages=ru` or `languages=en` as an API parameter. Flibusta, Gutenberg OPDS and arbitrary OPDS providers do not receive a fake language filter. A non-filtering notice appears in the catalog after searching.

## Favorite authors

Users can add or remove authors during onboarding and in Settings, including typing an author not present in recommendations. Tapping an author from the library or favorites editor opens the catalog with search mode set to "author". This is a shortcut to real search, not an invented recommendation feed.

Genres are stored as neutral identifiers and their display names switch with the chosen UI language.

## Short tips

The library, catalog and reader each have one short, dismissible first-visit tip. Separate keys ensure they do not keep reappearing.

## Cloud backup

The existing folder-based iCloud Drive sync includes the new preferences as part of settings metadata. iOS retains control over when folder data reaches iCloud servers.

## Release verification

Confirm the following on an actual iPhone:
- New installs and upgrades display the five-step guide.
- Selecting English updates all core settings and tab labels.
- Selecting English defaults Gutendex search to English if "Automatic" is selected.
- Selecting Russian + explicit English book language still fetches English on Gutendex.
- Favorite author tap opens author search.
- The form completes and doesn't reappear after relaunch.
- Other catalog sources explicitly warn when language filtering isn't supported.
- Saved preferences restore from iCloud Drive after selecting the existing folder again.
