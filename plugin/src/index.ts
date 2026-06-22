import {
  ConfigPlugin,
  withInfoPlist,
  withEntitlementsPlist,
  withAndroidManifest,
  AndroidConfig,
} from '@expo/config-plugins';

export interface ULinkPluginProps {
  scheme: string;
  domains?: string[];
}

const withULink: ConfigPlugin<ULinkPluginProps> = (config, props) => {
  if (!props?.scheme) throw new Error('@ulinkly/react-native: `scheme` is required');
  const domains = props.domains ?? [];

  // iOS: custom URL scheme
  config = withInfoPlist(config, (c) => {
    const types: { CFBundleURLSchemes: string[] }[] =
      Array.isArray(c.modResults.CFBundleURLTypes) ? (c.modResults.CFBundleURLTypes as any) : [];
    types.push({ CFBundleURLSchemes: [props.scheme] });
    c.modResults.CFBundleURLTypes = types as any;
    return c;
  });

  // iOS: associated domains (applinks:)
  config = withEntitlementsPlist(config, (c) => {
    const existing: string[] =
      (c.modResults['com.apple.developer.associated-domains'] as unknown as string[]) ?? [];
    c.modResults['com.apple.developer.associated-domains'] = [
      ...existing, ...domains.map((d) => `applinks:${d}`),
    ] as unknown as (typeof c.modResults)[string];
    return c;
  });

  // Android: intent filters (custom scheme + autoVerify https hosts)
  config = withAndroidManifest(config, (c) => {
    const activity = AndroidConfig.Manifest.getMainActivityOrThrow(c.modResults);
    activity['intent-filter'] ??= [];
    activity['intent-filter'].push({
      action: [{ $: { 'android:name': 'android.intent.action.VIEW' } }],
      category: [
        { $: { 'android:name': 'android.intent.category.DEFAULT' } },
        { $: { 'android:name': 'android.intent.category.BROWSABLE' } },
      ],
      data: [{ $: { 'android:scheme': props.scheme } }],
    });
    for (const host of domains) {
      activity['intent-filter'].push({
        $: { 'android:autoVerify': 'true' } as any,
        action: [{ $: { 'android:name': 'android.intent.action.VIEW' } }],
        category: [
          { $: { 'android:name': 'android.intent.category.DEFAULT' } },
          { $: { 'android:name': 'android.intent.category.BROWSABLE' } },
        ],
        data: [{ $: { 'android:scheme': 'https', 'android:host': host } }],
      });
    }
    return c;
  });

  return config;
};

export default withULink;
