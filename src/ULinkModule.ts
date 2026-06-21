import { requireNativeModule, NativeModule } from 'expo-modules-core';
import type {
  ULinkConfig, ULinkParameters, ULinkResponse, ULinkResolvedData,
  ULinkInstallationInfo, ULinkEventsMap,
} from './types';

// Native method surface. Events come via NativeModule's addListener.
// Use declare class (not interface) so NativeModule instance members (addListener) are inherited.
export declare class ULinkNativeModule extends NativeModule<ULinkEventsMap> {
  initialize(config: ULinkConfig): Promise<void>;
  createLink(parameters: ULinkParameters): Promise<ULinkResponse>;
  resolveLink(url: string): Promise<ULinkResponse>;
  processULink(url: string): Promise<ULinkResolvedData | null>;
  checkDeferredLink(): Promise<void>;
  getInitialDeepLink(): Promise<ULinkResolvedData | null>;
  getInitialUri(): Promise<string | null>;
  setInitialUri(uri: string): Promise<void>;
  getLastLinkData(): Promise<ULinkResolvedData | null>;
  getInstallationId(): Promise<string | null>;
  getInstallationInfo(): Promise<ULinkInstallationInfo | null>;
  isReinstall(): Promise<boolean>;
  getCurrentSessionId(): Promise<string | null>;
  hasActiveSession(): Promise<boolean>;
  getSessionState(): Promise<string>;
  endSession(): Promise<void>;
  dispose(): Promise<void>;
}

export default requireNativeModule<ULinkNativeModule>('ULinkReactNative');
