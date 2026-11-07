# iCloud Drive synchronization (Dark Reader 0.2.0)

## What is implemented

Dark Reader uses **user-selected iCloud Drive directories**, not a CloudKit container.
This design is intentional for unsigned IPA distribution where users can re-sign
with different provisioning profiles.

The SwiftUI screen is at Settings -> Синхронизация iCloud.

1. Choose a directory in **iCloud Drive** through Apple's Files picker.
2. Dark Reader creates a nested `Dark Reader` folder.
3. Automatic synchronization is enabled by default after selecting a folder.
4. The app writes book files and a per-installation manifest on local changes,
   when returning to the foreground, and when iOS grants background refresh.
5. On a fresh installation, choose the **same directory** again to restore.

Choosing a directory in "On My iPhone" or a third-party File Provider does not
guarantee iCloud backup. The app intentionally does not guess a folder's cloud
account or claim that writing a file means it has finished uploading.

## Folder layout

```text
iCloud Drive / <the directory chosen by the reader> /
  Dark Reader /
    Books/
      <stable-book-UUID>.epub
    Devices/
      <installation-UUID>.json
      <another-installation-UUID>.json
```

- EPUBs are stored separately, so a bookmark change does not upload the book again.
- Each device writes only its own manifest, avoiding competing overwrites of
  one central `books.json`.
- A manifest includes books, progress locators, favorites, bookmarks, deletion
  markers and supported reader appearance preferences.
- The newest per-book update wins when resolving conflicts, while bookmarks
  are merged by union. This uses device clocks, so incorrect clock settings
  can affect conflict ordering.
- A deleted book is represented by a tombstone. Remote EPUB files are
  intentionally not automatically erased as a recovery safeguard.
- Files and metadata are **not additionally encrypted** by Dark Reader.
  They are stored in the user's chosen account/folder.
- Local imports, downloading and reader progress changes queue a save.
- Data is restored only after the user selects the directory. The Files
  sandbox bookmark itself does not survive removing the app.

## Important limitations

- This uses **iCloud Drive**, not automatic CloudKit account-based discovery.
- Users must explicitly grant folder access when setting up or reinstalling.
- iOS controls when Files uploads its local changes to iCloud and whether
  the BGTaskScheduler background refresh will run. The status "saved to folder"
  is **not** proof of remote cloud upload.
- A background task can be delayed, suspended or not launched.
- A book may temporarily be unavailable while iCloud downloads it; retry later.
- In this version each EPUB is limited to 50 MiB.
- The filesystem test workflow checks migration and merge logic, but
  **real iCloud upload, cross-device restore and signer changes require device QA**.
- A different certificate or Bundle ID can isolate local app data, but it
  cannot remove files already stored in an accessible user-selected iCloud Drive folder.
- An expired/revoked certificate can stop the old application launching. The
  user can still select the backup folder when a working new installation opens.

## Manual acceptance tests (two real devices)

1. On phone A, choose a folder under iCloud Drive. Download a valid EPUB,
   open it, navigate, add a bookmark and close it.
2. In Files, confirm a `Dark Reader/Books/*.epub` and a matching device
   snapshot in `Dark Reader/Devices` exist.
3. Allow the iCloud Drive upload to finish, then check the actual cloud copy
   from another device or the Files app.
4. On phone B with the same iCloud Drive folder, open settings, select that
   folder and tap restore. Confirm the book and saved position appear.
5. Read and bookmark on both devices in sequence. Refresh both after cloud
   convergence and confirm the newest position and all bookmarks survive.
6. Turn on Airplane Mode, read a little, restore connectivity, reopen the
   app and confirm the updated metadata is written and later uploaded.
7. Delete and reinstall the app (including a differently signed version).
   Select the same directory again and confirm restoration.
8. Revoke the app's folder access under Privacy > Files and Folders.
   Confirm that sync shows an understandable error and never claims success.

## Source files

- `Sources/CloudFolderWorker.swift`: bookmarks, security scope,
  coordinated reads/writes, per-device snapshots, EPUB restoration.
- `Sources/CloudSyncManager.swift`: queue, status, settings and background task.
- `Sources/CloudSyncScreen.swift`: SwiftUI setup / restore interface.
- `Sources/BookshelfStore.swift`: backwards-compatible local store and merges.
- `Tests/CloudLibraryTests.swift`: automated migration and merge checks.

## Apple references

- Directory access: https://developer.apple.com/documentation/uikit/providing-access-to-directories
- File coordinator: https://developer.apple.com/documentation/foundation/nsfilecoordinator
- Background tasks: https://developer.apple.com/documentation/uikit/using-background-tasks-to-update-your-app
