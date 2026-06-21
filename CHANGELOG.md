# Changelog

All notable changes to `@ulinkly/react-native` will be documented in this file.

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
