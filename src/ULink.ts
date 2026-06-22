import ULinkModule from './ULinkModule';
import {
  ULinkConfig, ULinkParameters, ULinkResponse, ULinkResolvedData,
  ULinkInstallationInfo, SessionState, ULinkEventsMap,
} from './types';
import type { EventSubscription } from 'expo-modules-core';

export class ULinkError extends Error {
  constructor(message: string, public code?: string) {
    super(message);
    this.name = 'ULinkError';
  }
}

/** Wraps a native promise so any rejection is re-thrown as ULinkError. */
async function wrap<T>(p: Promise<T>): Promise<T> {
  try { return await p; }
  catch (e: any) { throw new ULinkError(e?.message ?? String(e), e?.code ?? e?.name); }
}

function toSessionState(value: string): SessionState {
  const match = (Object.values(SessionState) as string[]).includes(value);
  return match ? (value as SessionState) : SessionState.IDLE;
}

export class ULinkSDK {
  initialize(config: ULinkConfig): Promise<void> { return wrap(ULinkModule.initialize(config)); }
  createLink(parameters: ULinkParameters): Promise<ULinkResponse> { return wrap(ULinkModule.createLink(parameters)); }
  resolveLink(url: string): Promise<ULinkResponse> { return wrap(ULinkModule.resolveLink(url)); }
  processULink(url: string): Promise<ULinkResolvedData | null> { return wrap(ULinkModule.processULink(url)); }
  checkDeferredLink(): Promise<void> { return wrap(ULinkModule.checkDeferredLink()); }
  getInitialDeepLink(): Promise<ULinkResolvedData | null> { return wrap(ULinkModule.getInitialDeepLink()); }
  getInitialUri(): Promise<string | null> { return wrap(ULinkModule.getInitialUri()); }
  setInitialUri(uri: string): Promise<void> { return wrap(ULinkModule.setInitialUri(uri)); }
  getLastLinkData(): Promise<ULinkResolvedData | null> { return wrap(ULinkModule.getLastLinkData()); }
  getInstallationId(): Promise<string | null> { return wrap(ULinkModule.getInstallationId()); }
  getInstallationInfo(): Promise<ULinkInstallationInfo | null> { return wrap(ULinkModule.getInstallationInfo()); }
  isReinstall(): Promise<boolean> { return wrap(ULinkModule.isReinstall()); }
  getCurrentSessionId(): Promise<string | null> { return wrap(ULinkModule.getCurrentSessionId()); }
  hasActiveSession(): Promise<boolean> { return wrap(ULinkModule.hasActiveSession()); }
  async getSessionState(): Promise<SessionState> { return toSessionState(await wrap(ULinkModule.getSessionState())); }
  endSession(): Promise<void> { return wrap(ULinkModule.endSession()); }
  /** Advanced/teardown only. Do NOT call on component unmount or fast-refresh. */
  dispose(): Promise<void> { return wrap(ULinkModule.dispose()); }

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
