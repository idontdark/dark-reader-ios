# GitHub deployment

Repository: https://github.com/idontdark/dark-reader-ios

## CI
The workflow runs on every push to main. It can also be started with the **Run workflow** button in GitHub Actions.

1. Open Actions > Build unsigned IPA.
2. Open the latest successful run.
3. Download artifact `DarkReader-unsigned-ipa`.
4. Unzip the artifact to obtain `DarkReader-unsigned.ipa`.
5. Sign IPA with a valid iOS development/distribution certificate before installation.

## Development
- Minimum iOS: 17
- Bundle ID: `com.ipadark.reader`
- Source: `Sources/`
- Build specification: `project.yml`
- Dependency: Readium Swift Toolkit 3.11.1 via SwiftPM

The test catalog URL is not guaranteed to respond. Use an authorized HTTPS OPDS endpoint, and test search/acquisition independently.

## Troubleshooting
- If XcodeGen fails, inspect `project.yml`.
- If Swift compilation fails, inspect the Build app step and correct breaking changes in the Readium APIs.
- Never upload certificate private keys to the source repository.
