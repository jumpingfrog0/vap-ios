Pod::Spec.new do |spec|
  spec.name         = "QGVAPlayer"
  spec.version      = "1.0.19"
  spec.summary      = "video animation player."
  spec.description  = "video animation player - 高效的特效动画播放组件."
  spec.homepage     = "https://git.duowan.com/voicetech/ios/vap-ios"
  spec.author       = { "Bigo" => "huangdonghong@bigo.sg" }

  spec.platform     = :ios, "12.0"
  spec.source       = { :git => "https://git.duowan.com/voicetech/ios/vap-ios.git", :tag => spec.version.to_s }

  spec.source_files = "Classes/**/*.{h,m}"
  spec.public_header_files = [
    "Classes/QGVAPlayer/QGVAPlayer.h",
    "Classes/QGVAPlayer/UIView+VAP.h",
    "Classes/QGVAPlayer/QGVAPWrapView.h",
    "Classes/QGVAPlayer/VAPMacros.h",
    "Classes/QGVAPlayer/Controllers/**/*.h",
    "Classes/QGVAPlayer/MP4Parser/**/*.h",
    "Classes/QGVAPlayer/Models/**/*.h",
    "Classes/QGVAPlayer/Utils/**/*.h",
    "Classes/QGVAPlayer/Views/**/*.h",
    "Classes/FamVapWrapper/**/*.h",
    "Classes/Shaders/**/*.h"
  ]
  spec.private_header_files = "Classes/QGVAPlayer/Renderers/*.h"
  spec.resource_bundles = {
    "QGVAPlayer" => ["Classes/Shaders/*.metal"]
  }

  spec.frameworks = [
    "UIKit",
    "Foundation",
    "AVFoundation",
    "CoreMedia",
    "CoreVideo",
    "VideoToolbox",
    "QuartzCore",
    "OpenGLES",
    "GLKit",
    "Metal",
    "MetalKit"
  ]

  spec.requires_arc = true
end
