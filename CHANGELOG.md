# Changelog

All notable changes to `@ulinkly/react-native` will be documented in this file.

## 0.1.6

- iOS: a failed startup request no longer rejects `initialize()` or leaves other calls hanging. When `POST /sdk/bootstrap` returned a non-2xx status (a 503 under load, a 403 at a plan limit) or the network was unavailable, `initialize()` rejected with `INITIALIZATION_ERROR`, and every call made before it settled (including a second `initialize()`) stayed queued and its Promise never settled.
  - `initialize()` now resolves in that case, as on Android. Event subscriptions are set up and queued calls run.
  - If initialization fails without creating the native SDK instance (an invalid configuration), `initialize()` still rejects, and queued calls are now rejected with the same error instead of hanging.
- iOS: rejected Promises now carry the native error message. On recent Expo versions every rejection reached JS as `<CODE>: undefined reason`, because Expo builds the message from `Exception.reason`, which `Promise.reject(code, description)` does not set. Error codes are unchanged.
- Raise the pinned native iOS SDK from `ULinkSDK ~> 1.2.0` to `~> 1.2.3`. After a failed startup request, 1.2.3 retries:
  - when the app returns to the foreground;
  - before resolving a link, creating a link or checking for a deferred link (previously these failed until the next foreground).

  It also honours the server's `Retry-After`, and runs the automatic deferred-link check once a retry succeeds. It includes 1.2.2's fix for a crash when a deep link arrives before initialization finishes.

## 0.1.5

- Bump the pinned native Android SDK from `ly.ulink:ulink-sdk:1.2.2` to `1.2.3`. iOS is unaffected.
  - The Android library manifest no longer declares `<application>` attributes (`android:theme`, `allowBackup`, `dataExtractionRules`, `fullBackupContent`), and the library no longer packages template theme, color, `app_name` string or backup-rule resources. A host app that did not set these itself inherited the SDK's values.
- 0.1.4 was tagged but never published to npm; 0.1.5 includes its changes.

## 0.1.4

- Bump the pinned native Android SDK from `ly.ulink:ulink-sdk:1.2.0` to `1.2.2`. iOS is unaffected.
  - The SDK no longer replaces the host app's launcher icon. The 1.2.0 and 1.2.1 AARs shipped Android Studio template launcher icons, including a `mipmap-anydpi-v26/ic_launcher` adaptive icon. Hosts without their own adaptive icon showed the SDK's icon on Android 8+ (1.2.2).
  - Bootstrap is retried as soon as the device regains a network, instead of waiting for the next foreground (1.2.1).
  - Foregrounding the app while the cold-start bootstrap is still in flight no longer fires a duplicate bootstrap (1.2.1).

## 0.1.3

- Bump the pinned native iOS SDK to `ULinkSDK` 1.2.0. Android is unaffected.
  - Deep links are no longer lost on iOS when they arrive while the SDK is still starting up. A host launched by a universal link hands the link to the SDK moments after initialization begins, and link resolution rejected anything arriving before bootstrap finished — the error was swallowed into a log line, so the launch link was dropped silently.
  - A bootstrap that failed at cold start now always reaches a terminal state, so later links fail fast instead of waiting for a completion that never comes.
  - Note: the CocoaPods constraint was `~> 1.1.1`, which resolves to `>= 1.1.1, < 1.2.0` — iOS hosts could not pick up 1.2.0 until this bump.

## 0.1.2

- Bump the pinned native Android SDK from `ly.ulink:ulink-sdk:1.1.4` to `1.2.0`. iOS is unaffected.
  - Deep links are no longer lost when they arrive while the SDK is still starting up. A link reaching the SDK before bootstrap finished was rejected outright, and because the intent had already been marked as handled nothing retried it — so cold starts launched by tapping a link, the most common case, dropped the link. Measured on a device: intent processed 0.9s after process start, bootstrap completed 2.2s later, listener never fired.
  - The deferred-link check had the same race. It runs once per install, so losing it lost the install's attribution permanently.
  - A failure while the SDK was setting up could leave bootstrap in a non-terminal state, parking every later deep link for the life of the process.
  - Shutting the SDK down is no longer reported as a deep-link failure, and no longer silently stops delivery to the log stream.
  - Disposing the SDK now actually ends the active session; the request was previously cancelled before it was sent.
  - Re-initialising after disposing returns a working instance instead of the disposed one, whose background work silently did nothing.

## 0.1.1

- Bump the pinned native Android SDK from `ly.ulink:ulink-sdk:1.1.0` to `1.1.4`, picking up four releases of Android-only fixes. iOS is unaffected.
  - Correct `X-ULink-Client-Version` in backend telemetry; the 1.1.0 artifact reported `1.0.11` on every call (1.1.1).
  - Dynamic links are no longer emitted twice when the app is already installed (1.1.2).
  - The deferred-match endpoint honours the configured `baseUrl` instead of always calling `https://api.ulink.ly` (1.1.3).
  - The "retry bootstrap on next foreground" recovery is now reachable, so a single transient network error at cold start no longer leaves the SDK degraded for the whole process lifetime (1.1.3).
  - Transient pre-send network failures (DNS, connect, no route) are retried with exponential backoff; failures that may already have reached the server, such as read timeouts, are deliberately not retried so sessions and installations cannot be duplicated (1.1.4).
  - The deferred-link check is re-attempted once bootstrap recovers, serialized against overlapping foregrounds, and retried until the request completes (1.1.4).

## 0.1.0 — 2026-06-21

Initial release.

- Expo Module bridging the native iOS (`ULinkSDK ~> 1.1.1`) and Android (`ly.ulink:ulink-sdk:1.1.0`) SDKs via the Expo Modules API.
- Full Flutter SDK parity: dynamic links, deferred deep linking, sessions, installation/reinstall detection, and persistent-device-ID MAU dedup.
- Event-based link delivery (`onDynamicLink`, `onUnifiedLink`, `onReinstallDetected`, `onLog`) via native Combine (iOS) and SharedFlow (Android) streams.
- Async `initialize()` with native-side pending queue — method calls and incoming links arriving before init resolves are buffered and flushed after init completes.
- iOS AppDelegate subscriber (Universal Links + custom schemes) shipped as an Expo Module AppDelegate extension — no manual `AppDelegate` edits required.
- Android intent capture (`OnNewIntent`) with `enableDeepLinkIntegration=false` to prevent double-handling by the native SDK.
- Expo config plugin (`["@ulinkly/react-native", { "scheme": "...", "domains": ["..."] }]`) that automates `Info.plist` URL types, Associated Domains entitlement, and Android `<intent-filter>` setup during `expo prebuild`.
- Supports bare React Native and Expo (dev client / prebuild). Not supported in Expo Go.
- Supports both New (Fabric/TurboModule) and Old RN architectures automatically via the Expo Modules API.
