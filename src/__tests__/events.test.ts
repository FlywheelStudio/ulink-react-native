jest.mock('../ULinkModule', () => {
  const sub = { remove: jest.fn() };
  return {
    __esModule: true,
    default: {
      addListener: jest.fn().mockReturnValue(sub),
      removeListeners: jest.fn(),
    },
  };
});

import ULink from '../ULink';
import type { ULinkNativeModule } from '../ULinkModule';

const mockModule = jest.mocked(
  // eslint-disable-next-line @typescript-eslint/no-require-imports
  (require('../ULinkModule') as { default: ULinkNativeModule }).default
);

describe('ULink events', () => {
  beforeEach(() => jest.clearAllMocks());

  it('subscribes to onDynamicLink and returns a removable subscription', () => {
    const sub = { remove: jest.fn() };
    mockModule.addListener.mockReturnValueOnce(sub);

    const cb = jest.fn();
    const subscription = ULink.onDynamicLink(cb);
    expect(mockModule.addListener).toHaveBeenCalledWith('onDynamicLink', cb);
    subscription.remove();
    expect(sub.remove).toHaveBeenCalled();
  });

  it('subscribes to onReinstallDetected', () => {
    const cb = jest.fn();
    ULink.onReinstallDetected(cb);
    expect(mockModule.addListener).toHaveBeenCalledWith('onReinstallDetected', cb);
  });
});
