Pod::Spec.new do |s|
  s.name             = 'Mebius'
  s.version          = '0.2.1'
  s.summary          = 'Native iOS SDK for Mebius live video — broadcast and watch.'
  s.description      = <<-DESC
    Mebius is a native Swift SDK for live video on iOS. Broadcast from the
    camera and microphone, and watch streams in low-latency or scale modes.
    The transport details are fully abstracted behind a clean Mebius API.
  DESC
  s.homepage         = 'https://github.com/russimobiledroidx/mebius-ios-sdk'
  s.license          = { :type => 'MIT', :file => 'LICENSE' }
  s.author           = { 'Mebius' => 'dev@mebius.io' }
  # The tag carries a leading `v` (v0.2.1), matching the other Mebius SDKs. Writing
  # `s.version.to_s` here asked git for a tag named `0.2.1`, which does not exist —
  # `pod trunk push` failed with "Remote branch 0.2.0 not found in upstream origin".
  # SwiftPM tolerates either form; CocoaPods clones the exact string.
  s.source           = { :git => 'https://github.com/russimobiledroidx/mebius-ios-sdk.git', :tag => "v#{s.version}" }

  s.ios.deployment_target = '13.0'
  s.swift_version = '5.9'

  s.source_files = 'Sources/Mebius/**/*.swift'
  s.frameworks   = 'AVFoundation', 'UIKit'

  # The CocoaPods distribution enables the concrete real-time transport, which
  # depends on the libwebrtc binary. The MEBIUS_RTC compilation condition turns
  # on the concrete transport code (otherwise the documented stub is used).
  #
  # libwebrtc binaries ship via CocoaPods (not SPM). WebRTC-SDK is the maintained
  # community binary that vends `import WebRTC`. Repin if your provider differs:
  #   s.dependency 'GoogleWebRTC'        # legacy / unmaintained
  #   s.dependency 'WebRTC-lib'          # alternate community binary
  s.dependency 'WebRTC-SDK', '~> 125.6422'

  s.pod_target_xcconfig = {
    'OTHER_SWIFT_FLAGS' => '-D MEBIUS_RTC'
  }
end
