Pod::Spec.new do |spec|
  spec.name         = "QGVAPlayer"
  spec.version      = "1.0.19"
  spec.summary      = "video animation player."
  spec.description  = "video animation player - 高效的特效动画播放组件."
  spec.homepage     = "https://github.com/jumpingfrog0/vap-ios.git"
  spec.author       = { "huangdonghong" => "jumpingfrog0@gmail.com" }

  spec.platform     = :ios, "12.0"
  spec.source       = { :git => "https://github.com/jumpingfrog0/vap-ios.git", :tag => spec.version.to_s }

  spec.source_files = "Classes/**/*.{h,m}"
  spec.public_header_files = "Classes/**/*.h"
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
