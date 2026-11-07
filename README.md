# Dark Reader - Books & Audiobooks

iOS SwiftUI reader built with Readium Swift Toolkit 3.11.1. The current release supports EPUB reading and an OPDS book catalog. Audiobook source integration and playback remain planned, not yet implemented.

## What's new in 0.4.0

- A five-step first-launch guide (language, reading/listening preference, genres, authors, ready). Each step is skippable.
- Russian and English interface localization, selectable again in Settings > App language.
- Independent book-language preference, defaulting to the chosen app language.
- Actual Gutendex API language filtering using the documented \`languages=ru\` or \`languages=en\` parameter.
- The Flibusta and OPDS sources cannot guarantee language filtering; the app explains the limitation instead of inventing a filter.
- Favorite authors and genres remain editable in Settings and favorite author names open a catalog author search.
- Short one-time hints in library, catalog and reading screen.
- Existing library, EPUB downloads, iCloud Drive folder backup and settings, theme HEX picker, donation screen and app icon retained.

## First launch

The new onboarding appears once on installation or upgrade from the old welcome view. Preferences are saved locally via UserDefaults and included in the app's existing iCloud Drive metadata backup when cloud synchronization is connected.

## Installing the IPA

Go to **Releases** and download **DarkReader-unsigned.ipa** directly from **Assets**. This is the actual IPA containing \`Payload/DarkReader.app\`, not a renamed ZIP. It requires signing before installation. An Actions artifact download is still an outer ZIP; extract it first.

## Project structure

- \`Sources/\`: app code, SwiftUI screens, Readium reader, OPDS, settings and backup
- \`Resources/en.lproj/Localizable.strings\`, \`ru.lproj\`: English / Russian interface translations
- \`Tests/\`: migration, preferences, locale and restore tests
- \`scripts/generate_icon.swift\`: creates the black-purple book icon in the build
- \`docs/\`: catalog API and iCloud Drive notes
- \`.github/workflows/ipa.yml\`: compiles and publishes a directly downloadable IPA
- \`.github/workflows/cloud-tests.yml\`: builds and tests on an iOS Simulator

## Limits

This app is not published in the App Store. Audio content discovery/playback and Google Drive sync are not completed in v0.4.0. Background iCloud Drive uploading is managed by iOS; saving a file locally does not prove the cloud has received it. Third-party catalog rights and server availability vary.
