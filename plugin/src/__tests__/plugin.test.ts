import { withInfoPlist, withEntitlementsPlist, withAndroidManifest } from '@expo/config-plugins';
import withULink from '../index';

jest.mock('@expo/config-plugins', () => {
  const actual = jest.requireActual('@expo/config-plugins');
  return { ...actual,
    withInfoPlist: jest.fn((c) => c),
    withEntitlementsPlist: jest.fn((c) => c),
    withAndroidManifest: jest.fn((c) => c),
  };
});

it('registers all three native mods with scheme + domains', () => {
  const config: any = { name: 'app', slug: 'app' };
  withULink(config, { scheme: 'myapp', domains: ['myapp.shared.ly'] });
  expect(withInfoPlist).toHaveBeenCalled();
  expect(withEntitlementsPlist).toHaveBeenCalled();
  expect(withAndroidManifest).toHaveBeenCalled();
});

it('throws when scheme is missing', () => {
  expect(() => withULink({ name: 'a', slug: 'a' } as any, { domains: [] } as any)).toThrow();
});
