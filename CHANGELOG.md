# Changelog

All notable changes to `@ulinkly/react-native` will be documented in this file.

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
