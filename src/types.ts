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
  persistLastLinkData?: boolean;
  lastLinkTimeToLiveSeconds?: number;
  clearLastLinkOnRead?: boolean;
  redactAllParametersInLastLink?: boolean;
  redactedParameterKeysInLastLink?: string[];
  autoCheckDeferredLink?: boolean;
  // NOTE: enableDeepLinkIntegration is intentionally NOT exposed; the module
  // forces it false on Android and owns link delivery on both platforms.
}

export interface ULinkParameters {
  type?: ULinkLinkType;
  slug?: string;
  iosUrl?: string;
  androidUrl?: string;
  iosFallbackUrl?: string;
  androidFallbackUrl?: string;
  fallbackUrl?: string;
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
}

export type ULinkEventsMap = {
  onDynamicLink: (data: ULinkResolvedData) => void;
  onUnifiedLink: (data: ULinkResolvedData) => void;
  onReinstallDetected: (info: ULinkInstallationInfo) => void;
  onLog: (entry: ULinkLogEntry) => void;
};
