# SENSTA iOS working agreement

## Product context

SENSTA iOS is the native iPhone client for the SENSTA photo community. It shares users, posts, comments,
messages, achievements, uploads, and moderation behavior with SENSTA Android and the NUBO/GOAPI backend.
The iOS app should feel native to Apple platforms while preserving the product behavior users already know.

## Collaboration and workflow

- The product owner is learning iOS development through this project and performs final product QA. Explain
  unfamiliar Swift, SwiftUI, Xcode, signing, and App Store concepts in relation to the existing Android app
  when that helps understanding.
- Codex critically reviews, implements, tests, commits, and pushes agreed changes.
- Work directly on `main` by default. After a coherent work unit passes proportional validation, commit and
  push `main` immediately. Preserve unrelated user changes and avoid destructive Git operations.
- Read `docs/PROJECT_STATUS.md` at the beginning of work and keep it concise and current at meaningful
  milestones.
- Check the sibling `sensta.git`, `goapi.git`, and `nubo.git` repositories whenever API, authentication,
  upload, download, notification, account deletion, or moderation behavior is involved.
- Use focused commits. Never commit Apple signing keys, APNs keys, provisioning profiles, Firebase private
  credentials, tokens, or local environment files.
- New or meaning-correcting code comments should be written in Korean.

## Technical direction

- Build a native SwiftUI app with Swift concurrency and Apple frameworks first. Add third-party packages only
  when they clearly reduce risk or maintenance cost.
- Keep access and refresh tokens in Keychain. Store only non-sensitive preferences in UserDefaults.
- Treat GOAPI API contract v1 and the Android DTO contract tests as the initial interoperability reference.
  Add iOS decoding and request-contract regression tests before relying on an endpoint.
- Preserve anonymous access to public content. Do not weaken authorization, blocked-user, account-deletion,
  or cross-board resource checks for client compatibility.
- Strip precise location metadata from public photo uploads. Test HEIC/JPEG orientation, EXIF preservation,
  memory use, multipart limits, cancellation, and temporary-file cleanup on a physical iPhone.
- Use accessibility labels, Dynamic Type, reduced motion, VoiceOver-friendly controls, and light/dark themes
  as baseline requirements rather than release polish.

## Toolchain and validation

- During the macOS 27 beta period, use `/Applications/Xcode-beta.app` through `scripts/xcode-env.sh` instead
  of changing the machine-wide developer directory implicitly.
- Revalidate the accepted stable Xcode and SDK requirement before TestFlight or App Store submission; a beta
  toolchain is not a permanent release baseline.
- Run `scripts/check-environment.sh` before project work. Once the Xcode project exists, run relevant unit/UI
  tests and both Debug and Release builds for meaningful changes.
- Test photo selection, HEIC/JPEG processing, Sign in with Apple, Google login, Keychain session restoration,
  APNs/FCM delivery, notification deep links, and account deletion on a physical iPhone before release.

## Current scope

Application development has started. Preserve the approved immersive photo browsing experience while
adding public feed pagination and subsequent small, tested feature units.
