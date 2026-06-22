# @ulinkly/react-native

Official ULink deep linking SDK for React Native and Expo. Bridges the native iOS (`ULinkSDK 1.1.1`) and Android (`ly.ulink:ulink-sdk 1.1.0`) SDKs via the Expo Modules API, delivering full feature parity with the Flutter SDK: dynamic links, deferred deep linking, install attribution, reinstall detection, session tracking, and MAU dedup via persistent device ID.

## Requirements

- iOS 13.0+, Android minSdk 24
- React Native 0.73+ or Expo SDK 50+
- **Not supported in Expo Go** — this is a native module and requires a [dev client](#expo-dev-clientprebuild) or `expo prebuild`.

## AI-Assisted Setup

Using Claude Code, Cursor, Codex, or another AI coding agent? Install the ULink onboarding skill in one command:

```bash
npx skills add https://ulink.ly
```

Then ask your assistant to **"setup ulink"** — it'll detect your React Native project, configure your ULink dashboard, edit your native files, and verify the integration. Works with 50+ AI agents via the [open agent-skills CLI](https://github.com/vercel-labs/skills). [Learn more →](https://docs.ulink.ly/getting-started/ai-setup)

---

## Installation

### Expo (managed workflow / dev client / prebuild) — recommended

```bash
npx expo install @ulinkly/react-native
```

Add the config plugin to `app.json` (see [Config Plugin](#config-plugin) below), then rebuild:

```bash
# Expo dev client
npx expo run:ios
npx expo run:android

# Or prebuild + native build
npx expo prebuild
```

> **Expo Go is not supported.** This package uses native modules that are not available in the Expo Go sandbox. You must use a [development build](https://docs.expo.dev/develop/development-builds/introduction/) or `expo prebuild`.

### Bare React Native

```bash
npm install @ulinkly/react-native
npx install-expo-modules@latest   # one-time: wires Expo Modules into your existing RN project
cd ios && pod install
```

Bare RN users must also complete the [manual native setup](#manual-native-setup-bare-rn) below (no config plugin).

---

## Config Plugin

> Expo / managed workflow only. Bare RN users: see [Manual Native Setup](#manual-native-setup-bare-rn).

Add the plugin to your `app.json`:

```json
{
  "expo": {
    "plugins": [
      ["@ulinkly/react-native", {
        "scheme": "myapp",
        "domains": ["myapp.shared.ly"]
      }]
    ]
  }
}
```

| Prop | Type | Required | Description |
|------|------|----------|-------------|
| `scheme` | `string` | Yes | Your app's custom URL scheme (without `://`). Must match what you registered in the ULink dashboard. |
| `domains` | `string[]` | No | One or more Associated Domains / App Link hosts (e.g. `["myapp.shared.ly"]`). |

**What the plugin configures during `expo prebuild`:**

- **iOS** — Adds `CFBundleURLTypes` entry for `scheme` in `Info.plist`; adds `applinks:<domain>` entries to the Associated Domains entitlement.
- **Android** — Adds a custom-scheme `<intent-filter>` to your main activity; adds an `android:autoVerify="true"` HTTPS host `<intent-filter>` for each domain.

Run `npx expo prebuild` after updating the plugin config.

---

## Manual Native Setup (Bare RN)

Skip this section if you are using the config plugin.

### ULink Dashboard

Before configuring native files, register your app in the [ULink dashboard](https://ulink.ly):

1. Create a project and note your **API key**.
2. Under **Configure → iOS**: enter your Bundle ID, URL scheme, and Apple Team ID.
3. Under **Configure → Android**: enter your package name, URL scheme, and SHA-256 signing fingerprint.
4. Reserve your subdomain on `shared.ly`. ULink automatically serves the `.well-known/` files needed for Universal Links / App Links verification.

### iOS

**1. URL Scheme — `ios/<YourApp>/Info.plist`**

```xml
<key>CFBundleURLTypes</key>
<array>
  <dict>
    <key>CFBundleURLSchemes</key>
    <array>
      <string>myapp</string>  <!-- your scheme, without :// -->
    </array>
  </dict>
</array>
```

**2. Associated Domains — Xcode Signing & Capabilities**

In Xcode, go to your target → **Signing & Capabilities** → **+ Capability** → **Associated Domains**. Add:

```
applinks:myapp.shared.ly
```

Or directly in `ios/<YourApp>/<YourApp>.entitlements`:

```xml
<key>com.apple.developer.associated-domains</key>
<array>
  <string>applinks:myapp.shared.ly</string>
</array>
```

**3. AppDelegate wiring**

The SDK module ships an **Expo Module AppDelegate subscriber** that automatically intercepts Universal Link continuations (`application(_:continue:restorationHandler:)`) and custom-scheme opens (`application(_:open:options:)`) when running with `install-expo-modules`. No manual `AppDelegate` edits are required for bare RN projects that have run `npx install-expo-modules@latest`.

If for any reason you need to wire manually, forward both callbacks through `RCTLinkingManager` (standard RN practice) — the native module listens on the same URL delivery path.

### Android

**`android/app/src/main/AndroidManifest.xml`** — add inside your main `<activity>`:

```xml
<!-- Custom scheme deep links -->
<intent-filter>
    <action android:name="android.intent.action.VIEW" />
    <category android:name="android.intent.category.DEFAULT" />
    <category android:name="android.intent.category.BROWSABLE" />
    <!-- Replace with your registered scheme (without ://) -->
    <data android:scheme="myapp" />
</intent-filter>

<!-- HTTPS App Links (auto-verified) -->
<intent-filter android:autoVerify="true">
    <action android:name="android.intent.action.VIEW" />
    <category android:name="android.intent.category.DEFAULT" />
    <category android:name="android.intent.category.BROWSABLE" />
    <!-- Replace with your subdomain on shared.ly -->
    <data android:scheme="https" android:host="myapp.shared.ly" />
</intent-filter>
```

Note: ULink automatically serves the `.well-known/assetlinks.json` file for your registered domain — no manual hosting required.

---

## Quick Start

```tsx
import { useEffect } from 'react';
import ULink from '@ulinkly/react-native';

async function initULink() {
  // Always await initialize() before calling any other method.
  // On Android, calls made before init resolves are rejected with an error.
  await ULink.initialize({
    apiKey: 'YOUR_API_KEY',
    debug: __DEV__,
  });
}

// Call once at app startup — before mounting any screen that needs deep links.
initULink().catch(console.error);

// In a component or navigation root:
function App() {
  useEffect(() => {
    // Subscribe to incoming deep links (cold-start and foreground).
    const dynSub = ULink.onDynamicLink((data) => {
      console.log('Dynamic link received:', data.parameters);
      // Navigate based on data.parameters, e.g. router.push(data.parameters?.screen)
    });

    const uniSub = ULink.onUnifiedLink((data) => {
      console.log('Unified link received:', data);
      // Unified links are platform redirects — open externally if needed.
    });

    return () => {
      dynSub.remove();
      uniSub.remove();
      // Do NOT call ULink.dispose() here — see Caveats below.
    };
  }, []);

  return <YourNavigator />;
}

// Create a shareable link
async function shareLink() {
  const response = await ULink.createLink({
    domain: 'shadd.shared.ly',   // required: your registered ULink subdomain
    type: 'dynamic',
    slug: 'my-promo',
    // externalId deduplicates repeat calls — if a link with this ID already exists
    // on the domain, the existing link is returned instead of creating a new one.
    externalId: 'promo-launch-2024',
    iosFallbackUrl: 'https://apps.apple.com/app/id123456789',
    androidFallbackUrl: 'https://play.google.com/store/apps/details?id=com.myapp',
    fallbackUrl: 'https://myapp.com/promo',
    parameters: { screen: 'promo', campaign: 'launch' },
    socialMediaTags: {
      ogTitle: 'Check out MyApp!',
      ogDescription: 'Download and get 20% off your first order.',
      ogImage: 'https://myapp.com/og-promo.jpg',
    },
  });

  if (response.success) {
    console.log('Share URL:', response.url);
  }
}

// Manually resolve a link URL
async function openLink(url: string) {
  const response = await ULink.resolveLink(url);
  if (response.success && response.data) {
    console.log('Link data:', response.data.parameters);
  }
}
```

---

## API Reference

### `ULink.initialize(config: ULinkConfig): Promise<void>`

Initializes the native SDK. **Must be called and awaited before any other method.**

- On Android, calls made before `initialize()` resolves are rejected with a `ULinkError`.
- On iOS, calls are queued and flushed after init completes — but always `await` init first for predictable behavior.
- `initialize()` is idempotent: subsequent calls are no-ops.

```ts
await ULink.initialize({
  apiKey: 'YOUR_API_KEY',
  debug: true,
});
```

### `ULink.createLink(parameters: ULinkParameters): Promise<ULinkResponse>`

Creates a shareable deep link on the ULink platform.

### `ULink.resolveLink(url: string): Promise<ULinkResponse>`

Resolves a ULink URL to its stored data (parameters, fallback URLs, social tags).

### `ULink.processULink(url: string): Promise<ULinkResolvedData | null>`

Processes a raw ULink URL and returns resolved data, or `null` if the URL is not a ULink.

### `ULink.checkDeferredLink(): Promise<void>`

Explicitly triggers a deferred deep link check. Normally called once after `initialize()` when `autoCheckDeferredLink` is not set. Results are delivered via the `onDynamicLink` or `onUnifiedLink` event.

### `ULink.getInitialDeepLink(): Promise<ULinkResolvedData | null>`

Returns the deep link that launched the app in the current session, or `null` if the app was opened normally. Note: cold-start links are also delivered via `onDynamicLink`/`onUnifiedLink` events (the preferred pattern).

### `ULink.getInitialUri(): Promise<string | null>`

Returns the raw URI string that opened the app, if any.

### `ULink.setInitialUri(uri: string): Promise<void>`

Override the initial URI — primarily a testing aid.

### `ULink.getLastLinkData(): Promise<ULinkResolvedData | null>`

Returns the most recently resolved link data, optionally persisted across launches (see `persistLastLinkData` in `ULinkConfig`).

### `ULink.getInstallationId(): Promise<string | null>`

Returns this device's ULink installation ID (a UUID generated on first launch and persisted).

### `ULink.getInstallationInfo(): Promise<ULinkInstallationInfo | null>`

Returns full installation metadata including `persistentDeviceId`, `isReinstall`, and `previousInstallationId`.

### `ULink.isReinstall(): Promise<boolean>`

Returns `true` if the current install was detected as a reinstall.

### `ULink.getCurrentSessionId(): Promise<string | null>`

Returns the active session ID, or `null` if no session is active.

### `ULink.hasActiveSession(): Promise<boolean>`

Returns `true` if a session is currently active.

### `ULink.getSessionState(): Promise<SessionState>`

Returns the current session lifecycle state.

### `ULink.endSession(): Promise<void>`

Explicitly ends the current session.

### `ULink.dispose(): Promise<void>`

Tears down the native SDK singleton. **Advanced/teardown only** — see [Caveats](#caveats).

---

### Events

Event listeners return an `EventSubscription` with a `.remove()` method. Always call `.remove()` in your cleanup to prevent memory leaks.

#### `ULink.onDynamicLink(callback: (data: ULinkResolvedData) => void): EventSubscription`

Fires when a dynamic link is received — cold-start, warm (foreground), or deferred install. This is the primary channel for deep link navigation.

#### `ULink.onUnifiedLink(callback: (data: ULinkResolvedData) => void): EventSubscription`

Fires when a unified (simple redirect) link is received. Unified links are platform-based redirects — the SDK does not auto-navigate; inspect `data` and open externally if appropriate.

#### `ULink.onReinstallDetected(callback: (info: ULinkInstallationInfo) => void): EventSubscription`

Fires once when a reinstall is detected, carrying the `ULinkInstallationInfo` payload (includes `previousInstallationId`).

#### `ULink.onLog(callback: (entry: ULinkLogEntry) => void): EventSubscription`

Debug-only. Forwards native SDK log entries to JS. Use to inspect SDK internals during development; remove or gate behind `__DEV__` in production.

---

### Types

#### `ULinkConfig`

```ts
interface ULinkConfig {
  apiKey: string;                          // required
  baseUrl?: string;                        // default: https://api.ulink.ly
  debug?: boolean;
  persistLastLinkData?: boolean;
  lastLinkTimeToLiveSeconds?: number;
  clearLastLinkOnRead?: boolean;
  redactAllParametersInLastLink?: boolean;
  redactedParameterKeysInLastLink?: string[];
  autoCheckDeferredLink?: boolean;
  // enableDeepLinkIntegration is intentionally NOT exposed:
  // the module forces it false on Android and owns link delivery on both platforms.
}
```

#### `ULinkParameters`

```ts
interface ULinkParameters {
  domain: string;                          // Required. Your registered ULink subdomain (e.g. "myapp.shared.ly").
  type?: 'dynamic' | 'unified';
  slug?: string;
  name?: string;                           // Optional display label shown in the ULink dashboard.
  externalId?: string;                     // Optional idempotency key — dedupes repeat createLink calls on the same domain.
  iosUrl?: string;
  androidUrl?: string;
  iosFallbackUrl?: string;
  androidFallbackUrl?: string;
  fallbackUrl?: string;
  parameters?: Record<string, unknown>;   // arbitrary JSON-serializable map
  socialMediaTags?: SocialMediaTags;
  metadata?: Record<string, unknown>;     // arbitrary JSON-serializable map
}
```

#### `ULinkResponse`

```ts
interface ULinkResponse {
  success: boolean;
  url?: string;
  data?: ULinkResolvedData;
  error?: string;
}
```

#### `ULinkResolvedData`

```ts
interface ULinkResolvedData {
  type: string;
  slug?: string;
  fallbackUrl?: string;
  iosFallbackUrl?: string;
  androidFallbackUrl?: string;
  parameters?: Record<string, unknown>;
  metadata?: Record<string, unknown>;
  socialMediaTags?: SocialMediaTags;
  isDeferred?: boolean;
  matchType?: string;
  rawData?: Record<string, unknown>;
}
```

#### `ULinkInstallationInfo`

```ts
interface ULinkInstallationInfo {
  installationId: string;
  isReinstall: boolean;
  previousInstallationId?: string;
  reinstallDetectedAt?: string;
  persistentDeviceId?: string;  // iOS: Keychain UUID; Android: OS ANDROID_ID
}
```

#### `SessionState`

```ts
enum SessionState {
  IDLE         = 'idle',
  INITIALIZING = 'initializing',
  ACTIVE       = 'active',
  ENDING       = 'ending',
  FAILED       = 'failed',
}
```

#### `SocialMediaTags`

```ts
interface SocialMediaTags {
  ogTitle?: string;
  ogDescription?: string;
  ogImage?: string;
}
```

#### `ULinkLogEntry`

```ts
interface ULinkLogEntry {
  level: string;
  message: string;
  timestamp?: number;  // epoch milliseconds
  tag?: string;
}
```

---

## Caveats

### Always `await ULink.initialize(...)` first

`initialize()` is async. Call it at app startup (before mounting any screen that handles deep links) and always `await` it. On Android, any method called before `initialize()` resolves will reject with a `ULinkError`. On iOS, calls are queued, but order is undefined — `await` init for reliable behavior on both platforms.

### iOS deferred deep linking is probabilistic

iOS deferred linking uses fingerprint matching (IP, user-agent, timestamp). It does **not** use IDFA, SKAdNetwork, pasteboard, or ATT — no tracking permission prompts or extra entitlements are required. Because matching is fingerprint-based, a 100% match rate cannot be guaranteed on iOS (network/VPN conditions can reduce accuracy). Android deferred linking uses the Play Install Referrer (deterministic) with a fingerprint fallback.

### `persistentDeviceId` is platform-specific

`getInstallationInfo()` returns a `persistentDeviceId` field that is used for MAU dedup:

- **iOS**: a UUID stored in the Keychain, survives app reinstalls.
- **Android**: the OS `ANDROID_ID`, which is scoped to the app's signing key and user profile. It may be `null` on some older or heavily customized devices.

This is not a ULink-generated ID on Android; it is the system-level device identifier.

### Do not call `dispose()` on component unmount

`ULink.dispose()` tears down the native SDK singleton (stops session tracking, unsubscribes Combine/SharedFlow streams). Calling it on React component unmount or fast-refresh will break the SDK for the lifetime of the process. Use it only for intentional full teardown (e.g., user logout in an app that needs to reinitialize with a different API key).

### Not supported in Expo Go

`@ulinkly/react-native` is a native module. It cannot run in the Expo Go sandbox. Use a [development build](https://docs.expo.dev/develop/development-builds/introduction/) (`npx expo run:ios` / `npx expo run:android`) or `expo prebuild` with your native toolchain.

### Client telemetry reports as native SDK

In v0.1.0, traffic from `@ulinkly/react-native` is reported in ULink analytics as `sdk-ios` / `sdk-android` (the same identifiers the native SDKs use). React Native-specific tagging is planned for a future release.

---

## Link Types

### Dynamic Links

In-app deep links with custom parameters, fallback URLs, and smart app store redirects. Use for navigating users to specific in-app screens. Delivered via `onDynamicLink`.

### Unified Links

Simple platform-based redirects (e.g. iOS App Store URL, Android Play Store URL, web fallback). The SDK does **not** auto-redirect — inspect the data in `onUnifiedLink` and open externally if appropriate.

### Query Parameter Passthrough

When a link has `allowQueryPassthrough` enabled (configured via the ULink dashboard or REST API), query parameters appended to the link URL at click time (e.g. `?orderId=123`) are merged into `data.parameters` before delivery. Passthrough values always arrive as strings and override stored params with the same key. No SDK changes needed.

```ts
ULink.onDynamicLink((data) => {
  const orderId = data.parameters?.orderId; // e.g. "123" (string)
});
```

---

## License

MIT — see [LICENSE](LICENSE).

Repository: [https://github.com/FlywheelStudio/ulink-react-native](https://github.com/FlywheelStudio/ulink-react-native)
