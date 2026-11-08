# Unified library redesign

Implementation follows the approved three-screen library and bookmark reference.

- Bottom tabs: Library, Search, Settings. Catalog content is inside Library.
- Library scope: Books / Audiobooks. Empty-reading banners remain; started items show a continue card.
- Books: All books, Reading, Want to read, My bookmarks.
- Audiobooks: All audiobooks, Listening, Downloaded, My bookmarks.
- Discover: For you (personalized ranking), Popular, New releases, Genres. Source shortcuts open Search directly with the selected source and media type.
- Bookmarks are grouped by book. Book entries use their saved Readium locator; audio entries use chapter ID and position. Rename/delete update the existing storage format. Favorite data is retained independently.
- RU/EN interface localization includes new views, dynamic controls, download states, accessibility labels and navigation. User titles and catalog metadata remain verbatim. Book-language filtering stays separate from interface language.

## Validation

- Parsed 54 Swift source/test files with tree-sitter-swift: no syntax errors. This does not check Swift types, SDK overloads or native rendering.
- 567 keys per language; equal key sets; no duplicates or format-placeholder mismatches.
- Added LibraryBookmarkTests for old audio bookmark JSON, user-supplied titles, locator presentation and plural forms. XCTest has not been run.
- No Xcode/IPA build, simulator, installation or native visual verification was performed, per user instruction.
- IPA workflow remains manual-only. Next native verification should cover both locales, bookmark navigation, long titles and large text on a physical iPhone.
