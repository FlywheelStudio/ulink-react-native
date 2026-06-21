import { registerWebModule, NativeModule } from 'expo';

// ULinkReactNativeModule is not available on the web platform.
class ULinkReactNativeModule extends NativeModule<{}> {}

export default registerWebModule(ULinkReactNativeModule, 'ULinkReactNativeModule');
