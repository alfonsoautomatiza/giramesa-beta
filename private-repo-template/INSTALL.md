# Install the private release workflow

This template does nothing from this public repository. It must be reviewed, copied to the private application repository as `.github/workflows/release-test-builds.yml`, adapted to that repository's signing configuration, and committed there. GitHub requires a `workflow_dispatch` workflow to exist on the private repository's default branch; `--ref` may then select the reviewed branch version to run.

## Installation

1. Copy `private-repo-template/.github/workflows/release-test-builds.yml` to `.github/workflows/release-test-builds.yml` in the private app repository. Do not copy any signing file.
2. Confirm the Flutter application remains at `app/`. If it does not, update `APP_DIRECTORY` and all artifact paths in the private copy.
3. Replace the private Android project's debug release signing with a reviewed release `signingConfig` that reads `app/android/key.properties`. The public template deliberately does not guess Gradle Kotlin/Groovy configuration.
4. Confirm the iOS bundle identifier, development team, App Store record, distribution certificate, provisioning profile, and `ExportOptions.plist` agree.
5. Add only the repository secrets listed in [SECRETS.md](SECRETS.md) to the private repository.
6. Review the pinned `FLUTTER_VERSION` against `app/pubspec.lock`, then commit the workflow through the normal private-repository pull request process. Merge the workflow to the default branch before using `release-all.ps1 -Branch` for another ref.

## Repository controls

- Keep the application repository private and `wertyMSD/giramesa-beta` public. The controller verifies both and never changes visibility.
- Protect the dispatched branch, require pull requests and successful tests, and restrict who can modify `.github/workflows/**` and signing configuration with CODEOWNERS or equivalent review rules.
- Restrict Actions to approved actions. The template uses maintained GitHub actions plus `subosito/flutter-action`; pin action SHAs in the private copy if organization policy requires immutable action references.
- Consider a protected GitHub environment with required reviewers for TestFlight and public Release publication.
- Never allow pull-request workflows from forks to access these secrets.

## Validation and first dry run

Before enabling all platforms, validate the private workflow syntax and run each selected job from a reviewed branch. From this public controller repository, the operator dry run is:

```powershell
./release-all.ps1 -ReleaseNotesFile ./release-notes.md -WhatIf
```

`-WhatIf` reads the release identity only from the private worktree's `app/pubspec.yaml`, then performs read-only checks including worktree cleanliness, branch and commit synchronization, GitHub CLI authentication, repository visibility, workflow existence, and tag/Release uniqueness. It prints the parsed version/build and planned `gh workflow run` command without dispatching it.

The default private worktree is the `DONDE_COMER` directory beside this repository (`D:\py\@android\DONDE_COMER` for the standard layout). Override it only with `-AppRepository` when the same private repository is checked out elsewhere. Before every release, edit and commit the Flutter version in the private repository, for example:

```yaml
version: 0.1.1+2
```

`0.1.1` becomes the release version and tag `v0.1.1`; `2` becomes Android `versionCode`, iOS `CFBundleVersion`, and the shared platform build number. Neither the controller nor the workflow accepts version/build overrides.

For the first real execution, select one platform at a time if signing is still being commissioned. For example, exercise web while explicitly skipping mobile and Windows:

```powershell
./release-all.ps1 -ReleaseNotesFile ./release-notes.md -SkipAndroid -SkipWindows -SkipIos -Wait
```

This creates a real public Release. Use a deliberate prerelease SemVer if it must not be treated as stable. A live web deployment is not part of this workflow: the web output is a ZIP asset. If a separate website is wanted, create a separately reviewed deployment workflow and destination; do not overwrite the beta portal.

## Rollback

1. Disable the private workflow in GitHub Actions or remove it through a reviewed private-repository commit.
2. Revoke `BETA_RELEASE_TOKEN` and the App Store Connect API key if exposure is suspected.
3. Remove an unsafe public Release from the beta repository; never replace assets under the same tag. Correct the issue and increment `version:` in private `app/pubspec.yaml` before publishing again.
4. Expire or remove an affected TestFlight build in App Store Connect. Apple processing/upload cannot be undone by deleting the workflow run.
5. Restore the previous reviewed workflow version with a normal revert commit. Do not roll back signing identities unless platform migration procedures explicitly require it.
