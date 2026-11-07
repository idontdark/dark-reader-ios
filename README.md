# Dark Reader - Books & Audiobooks

A free SwiftUI reading and listening app for iOS 17+ (ipa_dark design). Source distribution supports a user-signed, unsigned IPA. The current release is **0.5.0**.

## Reading and importing

- EPUB: Readium Swift Toolkit.
- FB2 and classic DRM-free MOBI (PalmDOC): converted locally to EPUB for Readium. MOBI DRM, HuffDic and KF8-only variants are rejected, not silently imported.
- ZIP containing EPUB, FB2 or classic MOBI: extract the first supported book, then import.
- Import from Files / Share Sheet and direct HTTPS link to supported formats.
- Book covers and descriptions where available from OPDS. Missing descriptions are clearly labeled.
- A genre-based "For you" shelf from Gutendex where matching public-domain records exist. No fabricated recommendations.
- Multiple named custom HTTPS OPDS catalogs with editable title, URL and search parameter.

## Audiobooks

Two independently selectable sources:
1. [LibriVox official audiobooks and audiotracks API](https://librivox.org/api/info)
2. [Internet Archive advancedsearch and metadata API](https://archive.org/developers/index-apis.html)

The audio tab has search, sources, chapters and an AVPlayer-based player with background audio, lock-screen controls, position saving, speed control and optional individual chapter downloads for offline playback. Not every Archive item contains MP3 chapters.

Network smoke checks run independently in GitHub Actions. They need to pass before live connectivity can be claimed verified. Network restrictions, content availability and licenses vary. Do not claim every file is downloadable or legally reusable.

## Text and interface

- Russian / English UI, genre preferences, onboarding and concise first-use tips
- Search cancellation on source switch and a user-initiated Cancel action
- VPN suggestion after a slow search, without modal interruptions
- Compact native design; hex/palette appearance controls
- Donation screen with centered wallet addresses and short currency tickers
- iCloud Drive folder backup with book state/settings. An iCloud folder write is not proof of remote upload.

## Build and download

Go to GitHub **Releases**, open the latest version, and download
**DarkReader-0.5.0-unsigned.ipa** under Assets. Do not rename the GitHub Actions artifact ZIP to IPA. The unsigned IPA must be signed before installing on an iPhone.

The build checks \`Payload/DarkReader.app/Info.plist\` and the application executable. GitHub Actions also runs simulator tests and a separate audiobook API smoke workflow.

## Caveats

- FB2 formatting and legacy MOBI may lose some advanced layout features during conversion.
- DRM-protected or unsupported Kindle compression is not handled.
- No rights are granted to redistribute copyrighted book content. Users select the source; only legally available content should be downloaded.
- Google Drive support is not part of 0.5.0.
- Cloud synchronization of downloaded audio is not yet included; playback positions are saved locally.
- Background activity and cloud transfers are controlled by iOS.
