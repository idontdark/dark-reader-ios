# iPhone diagnosis and fixes

## Confirmed on the user's physical iPhone, 2026-11-08

- Installed app build: 12. No offline audio index entries or saved audiobook files. Disk had ample available space.
- Selected remote MP3 is reachable from iPhone: HTTP 206, audio/mpeg, requested 4096 bytes received. Server reports total size 126880958 bytes.
- Same 1 MiB beginning of that file passed through the device's AVFoundation: AVURLAsset audio track count was 0 with a .tmp suffix and 1 with a .mp3 suffix. This isolates the validation bug; it is not a complete offline-playback test. Diagnostic files were created in an isolated temporary directory and removed. Existing app data was not modified.
- User-created ZIP backup passes zipfile CRC testing; it has a library.json manifest and one EPUB. No backup content or personal titles were exported.

## Changes

- Downloaded audio is moved to an isolated file with its real media extension before AVFoundation validation; only validated audio is published in the offline index. Failed stages are cleaned up. Byte progress is shown in addition to completed chapters.
- Backup selection uses a retained UIKit document-picker delegate, imports a copy, accepts file-provider data types, and reads the archive after dismissal. Controls are disabled individually during work; the picker no longer inherits a disabled card state. Archive contents remain strictly validated.
- Educational alerts replaced by dismissible inline cards, with RU/EN copy and Reduce Motion support. Destructive confirmations/errors remain explicit.
- Search accumulates unique matches instead of returning the first successful variant. Love/inflected Russian variants are combined for the specific Любовь title query; author search remains literal. Cap is 100 and is shown in the UI. Language filtering still applies; English results require English or All languages.
- Added Audioknigi Club and Kniga v Ukhe as clearly labeled WEB catalogs in Search's source menu. These open the actual query on the site; they are not native playback or offline-download providers. Both site home pages returned HTTP 200. Akniga's Любовь search and a book page were inspected.

## Public query observations

LibriVox collection: title любовь* => 0, title love* => 211. Broader Archive audio scope: любовь* => 14, любв* => 6, love* => 310. These are upstream counts with no language restriction, not guaranteed playable-book counts. Language restrictions can substantially reduce them. JSON report: outputs/audio-source-tests/love-query.json in the local workspace.

## Verification limits

No simulator, IPA build, or install was performed. Swift syntax and localization checks passed. The fixes need a new signed installation and physical testing of the complete download and picker callback. No claim is made that the currently installed binary has been patched.
