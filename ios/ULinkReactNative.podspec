Pod::Spec.new do |s|
  s.name           = 'ULinkReactNative'
  s.version        = '0.1.0'
  s.summary        = 'React Native / Expo module wrapping the ULink iOS SDK'
  s.description    = 'Native Expo module that exposes ULinkSDK deep-linking, session management, and link creation to React Native applications.'
  s.author         = 'ULink Team'
  s.homepage       = 'https://github.com/FlywheelStudio/ulink-react-native'
  s.license        = { :type => 'MIT' }
  s.platforms      = { :ios => '13.0' }
  s.source         = { git: '' }
  s.static_framework = true

  s.dependency 'ExpoModulesCore'
  s.dependency 'ULinkSDK', '~> 1.1.1'

  # Swift/Objective-C compatibility
  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'SWIFT_VERSION' => '5.9',
  }

  s.source_files = "**/*.{h,m,mm,swift,hpp,cpp}"
end
