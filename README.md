# Rafiqi

Personal iOS app (prayer times, Hijri calendar, widgets, Quran, radio and TV, files, scanner).
This repository only exists to build the app with GitHub Actions. It is sideloaded on one device; it is not on the App Store.

## Layout

| Path | What |
|---|---|
| `App/` | Main app target (`Hilal`, iOS 17+) |
| `Widgets/` | Widget extension (`HilalWidgets`, iOS 18+); also compiled into the app |
| `Shared/` | Code shared by app and widgets (settings, prayer times, calendar, notifications) |
| `UnitTests/` | `HilalTests` — reference tests with external sources cited in each file |
| `UITests/` | `HilalUITests` — screenshot and crawl tests |
| `Resources/` | Fonts (+ OFL licenses), calligraphy, sounds, privacy manifest; the vocal-separation model is fetched in CI |
| `project.yml` | XcodeGen spec (dependencies pinned to exact versions) |
| `ci/`, `tools/review/` | CI helpers, string generation (`gen_strings.py`) and static checks (`check1.py`) |

## Build

All builds run on GitHub Actions (`.github/workflows/build.yml`) on Apple-silicon runners only (`macos-15` / `macos-26`; Xcode 26 is required for AlarmKit).

1. `xcodegen generate`
2. `xcodebuild -scheme Hilal -configuration Release` (unsigned; the IPA is signed when sideloaded)
3. Unit tests run at the end of the same workflow; UI, launch and crawl tests have their own workflows.

Build number = `300 + run_number`, so every IPA is distinguishable. `MARKETING_VERSION` is in `project.yml`.

Before committing UI text: add English strings to `tools/review/en_files.py`, run `python3 tools/review/gen_strings.py write`, then `python3 tools/review/check1.py`.

## Release rules

1. No IPA is installed unless the build, unit tests, UI tests and the Release launch test all pass.
2. Screenshots from the run are reviewed and approved before the IPA is installed.
3. Commits that should not trigger CI carry `[skip ci]`.
4. Workflows push nothing readable: output branches contain only encrypted data.

## Rollback

- Run outputs (IPA, screenshots, logs) are never published readable. `ci/seal.sh` encrypts them (AES-256 with a random key, wrapped by the RSA public key in `ci/transport_pub.pem`) and pushes only the ciphertext to the output branch. The private key is not in the repository; without it the branch is unreadable. Note the commit hash of every installed IPA.
- **Do not downgrade below the version that introduced the locked-folder vault** (one-time migration flag `files_vault_v1`). Older builds do not know `Application Support/LockedVault`, so files in locked folders would disappear from the list (they are not deleted, and reappear when a newer build is installed again).
- Data migrations are flagged in `UserDefaults` (`files_vault_v1`) and must stay additive: never delete the old location until the new one is verified.

## Data locations

| Data | Where |
|---|---|
| Shared settings (prayer, widgets, notifications) | App Group `group.app.hilal.widgets` UserDefaults |
| Secrets (server passwords, channel headers, TLS identity) | Keychain via `Shared/SecureStore.swift` |
| User files | `Documents/` (visible in the Files app); locked folders in `Application Support/LockedVault` |
| Scan projects | `Application Support/ScanProjects` |
| Quran downloads | excluded from backup |
