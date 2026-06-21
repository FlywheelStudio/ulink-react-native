import { NativeModule, requireNativeModule } from 'expo';

declare class ULinkReactNativeModule extends NativeModule<{}> {}

export default requireNativeModule<ULinkReactNativeModule>('ULinkReactNative');
