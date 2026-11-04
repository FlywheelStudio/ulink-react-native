export type ULinkLinkType = 'dynamic' | 'unified';

export interface SocialMediaTags {
  ogTitle?: string;
  ogDescription?: string;
  ogImage?: string;
}

export interface ULinkConfig {
  apiKey: string;
  baseUrl?: string;            // default https://api.ulink.ly
  debug?: boolean;
  /**
   * Persist the last resolved link across app launches (read via getLastLinkData()).
   * Platform defaults differ when omitted: false on iOS, true on Android.
   * Set it explicitly for consistent behaviour on both platforms.
   */
  persistLastLinkData?: boolean;
  lastLinkTimeToLiveSeconds?: number;
  clearLastLinkOnRead?: boolean;
  redactAllParametersInLastLink?: boolean;
  redactedParameterKeysInLastLink?: string[];
  /**
   * Check for a deferred deep link automatically after initialize(). Default true.
   * Deferred deep linking requires a paid plan (Starter or higher); on the Free plan
   * the server returns success:false and no deferred link is delivered.
   */
  autoCheckDeferredLink?: boolean;
  // NOTE: enableDeepLinkIntegration is intentionally NOT exposed; the module
  // forces it false on Android and owns link delivery on both platforms.
}

export interface ULinkParameters {
  /** The ULink domain to create the link on (e.g. "shadd.shared.ly"). Required. */
  domain: string;
  type?: ULinkLinkType;
  slug?: string;
  /** Optional display label shown in the ULink dashboard. */
  name?: string;
  /**
   * Idempotency key, scoped to the project (not the domain). If a link with this
   * externalId already exists anywhere in the project, that link is returned as-is
   * instead of creating a duplicate; the rest of the payload, including domain, is ignored.
   */
  externalId?: string;
  iosUrl?: string;
  androidUrl?: string;
  iosFallbackUrl?: string;
  androidFallbackUrl?: string;
  /** Web fallback URL. Required by the server for both dynamic and unified links. */
  fallbackUrl?: string;
  /** Arbitrary JSON-serializable map. Supported on both dynamic and unified links. */
  parameters?: Record<string, unknown>;
  socialMediaTags?: SocialMediaTags;
  metadata?: Record<string, unknown>;
}

export interface ULinkResponse {
  success: boolean;
  url?: string;
  data?: ULinkResolvedData;
  error?: string;
}

export interface ULinkResolvedData {
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

export interface ULinkInstallationInfo {
  installationId: string;
  isReinstall: boolean;
  previousInstallationId?: string;
  reinstallDetectedAt?: string;
  persistentDeviceId?: string;   // iOS: Keychain UUID; Android: ANDROID_ID
}

export enum SessionState {
  IDLE = 'idle',
  INITIALIZING = 'initializing',
  ACTIVE = 'active',
  ENDING = 'ending',
  FAILED = 'failed',
}

export interface ULinkLogEntry {
  level: string;
  message: string;
  timestamp?: number;   // epoch milliseconds (Int64 from native, serialised as JS number)
  tag?: string;
}

export type ULinkEventsMap = {
  onDynamicLink: (data: ULinkResolvedData) => void;
  onUnifiedLink: (data: ULinkResolvedData) => void;
  onReinstallDetected: (info: ULinkInstallationInfo) => void;
  onLog: (entry: ULinkLogEntry) => void;
};
