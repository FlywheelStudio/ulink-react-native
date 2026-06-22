jest.mock('../ULinkModule', () => ({
  __esModule: true,
  default: {
    initialize: jest.fn().mockResolvedValue(undefined),
    createLink: jest.fn().mockResolvedValue({ success: true, url: 'https://x.ulink.ly/abc' }),
    resolveLink: jest.fn().mockResolvedValue({ success: true, data: { type: 'dynamic', slug: 'abc' } }),
    getInstallationId: jest.fn().mockResolvedValue('inst-1'),
    getSessionState: jest.fn().mockResolvedValue('active'),
    addListener: jest.fn(),
    removeListeners: jest.fn(),
  },
}));

import ULink from '../ULink';
import { SessionState } from '../types';
import type { ULinkNativeModule } from '../ULinkModule';

const mockModule = jest.mocked(
  // eslint-disable-next-line @typescript-eslint/no-require-imports
  (require('../ULinkModule') as { default: ULinkNativeModule }).default
);

describe('ULink methods', () => {
  beforeEach(() => jest.clearAllMocks());

  it('forwards initialize with config', async () => {
    await ULink.initialize({ apiKey: 'k' });
    expect(mockModule.initialize).toHaveBeenCalledWith({ apiKey: 'k' });
  });

  it('returns createLink response', async () => {
    const res = await ULink.createLink({ domain: 'shadd.shared.ly', slug: 'abc' });
    expect(res.url).toBe('https://x.ulink.ly/abc');
  });

  it('returns resolveLink data', async () => {
    const res = await ULink.resolveLink('https://x.ulink.ly/abc');
    expect(res.data?.slug).toBe('abc');
  });

  it('maps getSessionState string to enum value', async () => {
    const s = await ULink.getSessionState();
    expect(s).toBe(SessionState.ACTIVE);
  });
});
