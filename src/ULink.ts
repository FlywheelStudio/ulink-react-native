import ULinkModule from './ULinkModule';
import {
  ULinkConfig, ULinkParameters, ULinkResponse, ULinkResolvedData,
  ULinkInstallationInfo, SessionState, ULinkEventsMap,
} from './types';
import type { EventSubscription } from 'expo-modules-core';

function toSessionState(value: string): SessionState {
  const match = (Object.values(SessionState) as string[]).includes(value);
  return match ? (value as SessionState) : SessionState.IDLE;
}

export class ULinkSDK {
  initialize(config: ULinkConfig): Promise<void> { return ULinkModule.initialize(config); }
  createLink(parameters: ULinkParameters): Promise<ULinkResponse> { return ULinkModule.createLink(parameters); }
  resolveLink(url: string): Promise<ULinkResponse> { return ULinkModule.resolveLink(url); }
  processULink(url: string): Promise<ULinkResolvedData | null> { return ULinkModule.processULink(url); }
  checkDeferredLink(): Promise<void> { return ULinkModule.checkDeferredLink(); }
  getInitialDeepLink(): Promise<ULinkResolvedData | null> { return ULinkModule.getInitialDeepLink(); }
  getInitialUri(): Promise<string | null> { return ULinkModule.getInitialUri(); }
  setInitialUri(uri: string): Promise<void> { return ULinkModule.setInitialUri(uri); }
  getLastLinkData(): Promise<ULinkResolvedData | null> { return ULinkModule.getLastLinkData(); }
  getInstallationId(): Promise<string | null> { return ULinkModule.getInstallationId(); }
  getInstallationInfo(): Promise<ULinkInstallationInfo | null> { return ULinkModule.getInstallationInfo(); }
  isReinstall(): Promise<boolean> { return ULinkModule.isReinstall(); }
  getCurrentSessionId(): Promise<string | null> { return ULinkModule.getCurrentSessionId(); }
  hasActiveSession(): Promise<boolean> { return ULinkModule.hasActiveSession(); }
  async getSessionState(): Promise<SessionState> { return toSessionState(await ULinkModule.getSessionState()); }
  endSession(): Promise<void> { return ULinkModule.endSession(); }
  /** Advanced/teardown only. Do NOT call on component unmount or fast-refresh. */
  dispose(): Promise<void> { return ULinkModule.dispose(); }

  onDynamicLink(listener: ULinkEventsMap['onDynamicLink']): EventSubscription {
    return ULinkModule.addListener('onDynamicLink', listener);
  }
  onUnifiedLink(listener: ULinkEventsMap['onUnifiedLink']): EventSubscription {
    return ULinkModule.addListener('onUnifiedLink', listener);
  }
  onReinstallDetected(listener: ULinkEventsMap['onReinstallDetected']): EventSubscription {
    return ULinkModule.addListener('onReinstallDetected', listener);
  }
  onLog(listener: ULinkEventsMap['onLog']): EventSubscription {
    return ULinkModule.addListener('onLog', listener);
  }
}

const ULink = new ULinkSDK();
export default ULink;
