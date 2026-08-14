# Secrets for multiplatform test releases

Configure these as **Actions repository secrets in the private application repository**. Do not configure signing credentials in `wertyMSD/giramesa-beta`, commit them, place them in workflow inputs, or paste them into release notes.

## Public beta publication

| Secret | Required | Purpose |
|---|---:|---|
| `BETA_RELEASE_TOKEN` | When Android, web, or Windows is selected | Fine-grained GitHub personal access token used only to create Releases and upload assets in `wertyMSD/giramesa-beta`. |

Create the token for only `wertyMSD/giramesa-beta`, with repository permission **Contents: Read and write** and no account-wide or private-app-repository access. Give it the shortest practical expiration and rotate it before expiry. The workflow's default `GITHUB_TOKEN` is intentionally not used because it cannot write to another repository.

## Android signing

| Secret | Required | Content |
|---|---:|---|
| `ANDROID_KEYSTORE_BASE64` | Android | Base64 of the release `.jks` or `.keystore` file, as one uninterrupted value. |
| `ANDROID_KEYSTORE_PASSWORD` | Android | Keystore password. |
| `ANDROID_KEY_ALIAS` | Android | Alias of the release key inside the keystore. |
| `ANDROID_KEY_PASSWORD` | Android | Password for that key alias. |

Generate the base64 value offline from the existing production/test release keystore. Never create a new signing identity on a CI runner for an existing application. The private Gradle project must load `android/key.properties` and select that release signing config; the template fails if it still selects `Android Debug`.

## iOS signing and TestFlight

| Secret | Required | Content |
|---|---:|---|
| `IOS_DISTRIBUTION_CERTIFICATE_P12_BASE64` | iOS | Base64 of the Apple Distribution certificate and private key exported as `.p12`. |
| `IOS_DISTRIBUTION_CERTIFICATE_PASSWORD` | iOS | Password protecting the `.p12`. |
| `IOS_PROVISIONING_PROFILE_BASE64` | iOS | Base64 of the App Store distribution provisioning profile. |
| `IOS_EXPORT_OPTIONS_PLIST_BASE64` | iOS | Base64 of a reviewed `ExportOptions.plist` for App Store upload, with the real team and signing method. |
| `APP_STORE_CONNECT_ISSUER_ID` | iOS | Issuer ID for the App Store Connect API key. |
| `APP_STORE_CONNECT_KEY_ID` | iOS | Key ID for the App Store Connect API key. |
| `APP_STORE_CONNECT_PRIVATE_KEY_BASE64` | iOS | Base64 of the corresponding `AuthKey_*.p8` private key. |

Create an App Store Connect team API key with the minimum role that can upload builds for this app. Restrict app access where App Store Connect supports it. The Apple distribution certificate, provisioning profile, bundle identifier, Xcode team, and export options must all agree. CI installs them in a temporary keychain and deletes the keychain, API key, profile source, export options, and IPA in the cleanup step.

The workflow uploads the IPA directly to TestFlight and never uploads it as a GitHub Actions artifact or public GitHub Release asset. External TestFlight testing can still require Apple Beta App Review after upload and processing.

## Non-secret configuration

- `api_base_url` is an optional workflow input normally supplied by `release-all.ps1 -ApiBaseUrl`. It must be a public HTTPS URL and must never include credentials or private query parameters.
- `FLUTTER_VERSION` is pinned in the reviewed private workflow, not supplied at dispatch time. Upgrade it deliberately in a pull request after testing all four jobs.
- Release version and build number are not secrets or workflow inputs. Both are parsed exclusively from the checked-out `app/pubspec.yaml` value `version: X.Y.Z[-prerelease]+N`.
- Bundle identifiers, Android application IDs, Apple team selection, and signing integration belong in reviewed private repository files, not secrets when they are not confidential.
- GitHub environments may be added for approval gates. If used, place the same secrets in the protected environment and add `environment:` to the corresponding job.
