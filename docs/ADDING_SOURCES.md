# Adding a source

1. Create a SourceDescriptor with a unique `books:<domain>` or `audio:<domain>` identity. Do not group domains as mirrors without evidence. Keep a new source disabled by default.
2. Implement BookSourceAdapter or AudiobookSourceAdapter. Route the instance in the relevant factory. Configured HTML sources may share HTMLSourceParser while retaining independent routes, settings, health, and identity.
3. Use SourceHTTPClient for bounded timeouts, cache and per-host pacing. Keep normal API/OPDS/HTML requests separate from website-only playback. Preserve cancellation and emit progressive batches.
4. Read metadata from the source: title, author, edition language, subjects, actual publication date, cover and real file anchors. Audio also needs narrator, durations and chapter order. Do not substitute a query or page-added timestamp for metadata.
5. Return BookOffer entries for actual available files. Keep distinct AudioEdition values so the user can choose a recording. If no supported direct media exists, open the ordinary page with SourceWebScreen.
6. Validate downloaded files and import through the existing library/audio import path. Never interpret a site error page as a book. Keep archives bounded and extract only known entry names into generated destinations.
7. Add parser fixtures and source-specific regressions. Run the core CLI tests on macOS; run `ReaderCoreRegressions --live-audit` for real-source checks. Record at least five works, available formats, file checks, first/middle/last audio assets and limitations. Document actual physical-device playback separately from asset inspection.
8. Add all user-visible strings to Russian and English Localizable.strings. Keep source names, book titles and authors verbatim.
9. Enable by default only after successful reproducible validation. Failed runtime health checks must never modify enabled-source preferences.

The iPhone validation workflow compiles for generic/platform=iOS. It never launches a simulator. IPA publication remains a separate explicit workflow.
