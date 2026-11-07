# Dark Reader
iOS 17+ book reader built with SwiftUI, Readium 3.11.1 and an OPDS 1.x catalog client.

## Features in the starter
- Local EPUB import and offline library.
- Configurable HTTPS OPDS search endpoint.
- Download and open EPUB.
- Local reading progress, adjustable theme and font.
- iPhone and iPad interface.

## GitHub Actions
The workflow `.github/workflows/ipa.yml` builds an **unsigned** IPA on a macOS runner on every push to `main`, or manually via **Actions → Build unsigned IPA → Run workflow**. Download the IPA from workflow artifacts, then sign it using your own certificate before installation.

## Important
This project is an initial prototype, not a tested production build. OPDS server availability and supported search modes must be tested. EPUB support comes first; FB2 and PDF support are not finished. No DRM circumvention is included.

## Development
Install XcodeGen on macOS, run `xcodegen generate`, open `DarkReader.xcodeproj`, and resolve Swift packages in Xcode.
