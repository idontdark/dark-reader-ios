# Dark Reader for iOS

A SwiftUI ebook reader styled in the ipa_dark palette. Built with Readium Swift Toolkit 3.11.1. iOS 17+, iPhone and iPad.

## Features

- EPUB library with covers (when available from catalog), favorites, bookmarks and reading progress.
- Flibusta OPDS, Project Gutenberg, Gutendex and configurable HTTPS OPDS catalogs.
- Real EPUB download progress, completion card and button to open the library.
- Import from Files, iCloud Drive, Safari Share Sheet and direct HTTPS EPUB link.
- Native iOS first-launch guide and import instructions.
- Reader customization: system/light/sepia/dark/OLED, font, size and vertical scroll.
- Theme accent color presets, system color picker and six-digit HEX entry.
- Optional automatic backup to a user-selected iCloud Drive folder, independent of the signing team. Requires the user to select the folder again after reinstalling the app.
- Separate donations page with network-aware USDT and wallet copy. Developer: https://t.me/ipa_dark
- App icon created during the build from a native vector drawing.

## How to download an actual IPA

**Easiest:** open the repository's **Releases** tab and download the file
**DarkReader-unsigned.ipa** directly from **Assets**.

**GitHub Actions:** the "Download artifact" button always returns an outer
**ZIP archive**. You must **extract** it and then use the \`.ipa\` file inside.
Never rename the outer ZIP to \`.ipa\`, because it contains an IPA file, not
the required \`Payload/DarkReader.app\` folder.

Each IPA is validated during the workflow to contain
\`Payload/DarkReader.app/Info.plist\`, \`Payload/DarkReader.app/DarkReader\`,
and \`Assets.car\`.

The IPA is **unsigned** and must be signed with a valid certificate/profile
before installing on an iPhone or iPad.

## Build

GitHub Actions on \`main\` runs:

1. \`swift scripts/generate_icon.swift\`
2. \`xcodegen generate --spec project.yml\`
3. \`xcodebuild ... CODE_SIGNING_ALLOWED=NO build\`
4. Package IPA and validate its payload.
5. Publish the real IPA in GitHub Releases.

On a Mac, run \`swift scripts/generate_icon.swift\` and
\`xcodegen generate\`, then open \`DarkReader.xcodeproj\`.

## Known limits

- EPUB is the supported format; FB2/PDF conversion is not part of this release.
- Real iCloud Drive transfer, permissions across different signing identities
  and device-to-device conflict resolution require testing on physical devices.
- Background upload scheduling is best effort and managed by iOS.
- Books from online catalogs may be restricted by source availability and
  local copyright rules.
- Some catalog links may not return downloadable EPUB files.
- The crypto addresses on the donation screen are supplied by the developer.

## Notes

- \`Sources/\`: all app logic is Swift/SwiftUI.
- \`Tests/\`: simulator regression tests.
- \`docs/ICLOUD_SYNC.md\`: restore and device-test checklist.
