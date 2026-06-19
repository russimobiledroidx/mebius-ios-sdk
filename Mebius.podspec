Pod::Spec.new do |s|
  s.name             = 'Mebius'
  s.version          = '0.1.0'
  s.summary          = 'Native iOS SDK for Mebius live video — broadcast and watch.'
  s.description      = <<-DESC
    Mebius is a native Swift SDK for live video on iOS. Broadcast from the
    camera and microphone, and watch streams in low-latency or scale modes.
    The transport details are fully abstracted behind a clean Mebius API.
  DESC
  s.homepage         = 'https://github.com/russimobiledroidx/mebius-ios-sdk'
  s.license          = { :type => 'MIT', :file => 'LICENSE' }
  s.author           = { 'Mebius' => 'support@mebius.io' }
  s.source           = { :git => 'https://github.com/russimobiledroidx/mebius-ios-sdk.git', :tag => s.version.to_s }

  s.ios.deployment_target = '13.0'
  s.swift_version = '5.9'

  s.source_files = 'Sources/Mebius/**/*.swift'
  s.frameworks   = 'AVFoundation', 'UIKit'

  # The CocoaPods distribution enables the concrete real-time transport, which
  # depends on the libwebrtc binary. The MEBIUS_RTC compilation condition turns
  # on the concrete transport code (otherwise the documented stub is used).
  #
  # Uncomment the dependency and the compiler flag below once the libwebrtc pod
  # of your choice is pinned (libwebrtc binaries are distributed via CocoaPods,
  # not Swift Package Manager). Example pins, depending on your provider:
  #   s.dependency 'GoogleWebRTC'        # legacy
  #   s.dependency 'WebRTC-lib'          # community libwebrtc binary
  #
  # s.pod_target_xcconfig = {
  #   'OTHER_SWIFT_FLAGS' => '-D MEBIUS_RTC'
  # }
end
