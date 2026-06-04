# vap-ios

`vap-ios` 是 iOS 端的视频动画播放组件，Pod 名称为 `QGVAPlayer`。组件基于 MP4 素材播放带透明通道的特效动画，支持 Metal / OpenGL 渲染、VAP 动态资源替换、手势事件、静音播放、后台行为控制，以及旧版左右 / 上下 Alpha 采样素材兼容。

## 环境要求

- iOS 12.0+
- Objective-C / ARC
- CocoaPods
- 系统框架：UIKit、Foundation、AVFoundation、CoreMedia、CoreVideo、VideoToolbox、QuartzCore、OpenGLES、GLKit、Metal、MetalKit

## 安装

在 `Podfile` 中添加：

```ruby
pod 'QGVAPlayer', '1.0.19'
```

如果使用内部 Git 仓库源：

```ruby
pod 'QGVAPlayer',
    :git => 'https://github.com/jumpingfrog0/vap-ios.git',
```

然后执行：

```bash
pod install
```

### Metal 着色器接入

CocoaPods 会通过 `resource_bundles` 将 `Classes/Shaders/QGHWDShaders.metal` 自动打包进 `QGVAPlayer.bundle/default.metallib`，业务方不需要手动引用或拷贝 `.metal` 文件到宿主 App 工程。

运行时组件会从 `QGVAPlayer.bundle/default.metallib` 加载 shader function；如果资源 bundle 或 metallib 缺失，会回退到内置 shader source 进行运行时编译。

## 基础用法

### 直接在 UIView 上播放

导入头文件：

```objc
#import <QGVAPlayer/QGVAPlayer.h>
```

播放本地 MP4 素材：

```objc
NSString *filePath = [[NSBundle mainBundle] pathForResource:@"gift" ofType:@"mp4"];

self.vapContainer.hwd_Delegate = self;
self.vapContainer.hwd_renderByOpenGL = NO; // 默认使用 Metal，必要时可切换 OpenGL
self.vapContainer.hwd_enterBackgroundOP = HWDMP4EBOperationTypeStop;

[self.vapContainer playHWDMP4:filePath repeatCount:0 delegate:self];
```

常用控制：

```objc
[self.vapContainer pauseHWDMP4];
[self.vapContainer resumeHWDMP4];
[self.vapContainer stopHWDMP4];
[self.vapContainer setMute:YES];
```

`repeatCount` 表示额外重复次数：

- `0`：播放 1 次
- `1`：播放 2 次
- `-1`：无限循环

### 使用 QGVAPWrapView

`QGVAPWrapView` 封装了内部真实播放用的 `VAPView`，并提供 `contentMode`、自动销毁内部播放视图、手势透传等能力。外层 `QGVAPWrapView` 本身不响应手势，手势需要通过包装接口添加到内部 `vapView`。

```objc
#import <QGVAPlayer/QGVAPWrapView.h>

QGVAPWrapView *vapWrapView = [[QGVAPWrapView alloc] initWithFrame:self.view.bounds];
vapWrapView.contentMode = QGVAPWrapViewContentModeAspectFit;
vapWrapView.autoDestoryAfterFinish = YES;
[self.view addSubview:vapWrapView];

[vapWrapView playHWDMP4:filePath repeatCount:0 delegate:self];
```

支持的内容模式：

- `QGVAPWrapViewContentModeScaleToFill`
- `QGVAPWrapViewContentModeAspectFit`
- `QGVAPWrapViewContentModeAspectFill`

旧版素材如果不包含 `vapc` box，包装视图会自动开启旧版兼容；需要指定 Alpha 采样方向时可使用：

```objc
[vapWrapView playHWDMP4:filePath
              blendMode:QGHWDTextureBlendMode_AlphaLeft
            repeatCount:0
               delegate:self];
```

### 使用 FamVapWrapView

`FamVapWrapView` 继承自 `QGVAPWrapView`，提供按总播放次数表达的接口：

```objc
#import <QGVAPlayer/FamVapWrapView.h>

[famVapWrapView playHWDMP4:filePath playCount:1 delegate:self];
```

`playCount` 语义：

- `1`：播放 1 次
- `2`：播放 2 次
- `-1`：无限循环

## 播放回调

直接使用 `UIView (VAP)` 时实现 `HWDMP4PlayDelegate`：

```objc
@interface ViewController () <HWDMP4PlayDelegate>
@end

- (BOOL)shouldStartPlayMP4:(VAPView *)container config:(QGVAPConfigModel *)config {
    return YES;
}

- (void)viewDidStartPlayMP4:(VAPView *)container {
}

- (void)viewDidFinishPlayMP4:(NSInteger)totalFrameCount view:(VAPView *)container {
}

- (void)viewDidStopPlayMP4:(NSInteger)lastFrameIndex view:(VAPView *)container {
}

- (void)viewDidFailPlayMP4:(NSError *)error {
}
```

使用 `QGVAPWrapView` / `FamVapWrapView` 时实现 `VAPWrapViewDelegate`，对应回调方法名以 `vapWrap_` 开头：

```objc
@interface ViewController () <VAPWrapViewDelegate>
@end

- (BOOL)vapWrap_viewshouldStartPlayMP4:(VAPView *)container config:(QGVAPConfigModel *)config {
    return YES;
}

- (void)vapWrap_viewDidFinishPlayMP4:(NSInteger)totalFrameCount view:(VAPView *)container {
}

- (void)vapWrap_viewDidFailPlayMP4:(NSError *)error {
}
```

注意：播放过程中的部分回调会在子线程执行，需要更新 UI 时请切回主线程。

## VAP 动态资源

组件本身不包含网络图片加载能力。素材配置中需要动态替换文本、图片或其他资源时，由业务侧通过 delegate 提供内容和图片加载实现。

```objc
- (NSString *)contentForVapTag:(NSString *)tag resource:(QGVAPSourceInfo *)info {
    if ([tag isEqualToString:@"nickname"]) {
        return @"Joyy";
    }
    return tag;
}

- (void)loadVapImageWithURL:(NSString *)urlStr
                    context:(NSDictionary *)context
                 completion:(VAPImageCompletionBlock)completionBlock {
    // 使用业务自己的图片加载库加载 UIImage，再回调 completionBlock。
}
```

包装视图中对应方法为：

```objc
- (NSString *)vapWrapview_contentForVapTag:(NSString *)tag resource:(QGVAPSourceInfo *)info;

- (void)vapWrapView_loadVapImageWithURL:(NSString *)urlStr
                                context:(NSDictionary *)context
                             completion:(VAPImageCompletionBlock)completionBlock;
```

## 手势事件

可以为 VAP 资源区域添加点击或自定义手势：

```objc
[vapWrapView addVapTapGesture:^(UIGestureRecognizer *gestureRecognizer,
                                BOOL insideSource,
                                QGVAPSourceDisplayItem *source) {
    if (insideSource) {
        // 点击命中了素材中的资源区域
    }
}];
```

## 后台行为

通过 `hwd_enterBackgroundOP` 控制退后台时的处理方式：

- `HWDMP4EBOperationTypeStop`：退后台时停止播放，默认行为
- `HWDMP4EBOperationTypePauseAndResume`：退后台暂停、回前台自动恢复
- `HWDMP4EBOperationTypeDoNothing`：组件不主动处理，由业务自行控制

`PauseAndResume` 需要从关键帧解码恢复到当前帧，低端机型上可能有额外 CPU 开销和恢复耗时。

## 日志

可以注册业务日志回调：

```objc
static void VAPExternalLogger(VAPLogLevel level,
                              const char *file,
                              int line,
                              const char *func,
                              NSString *module,
                              NSString *format,
                              ...) {
    va_list args;
    va_start(args, format);
    NSString *message = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);

    NSLog(@"[VAP][%@][%d] %@", module, level, message);
}

[UIView registerHWDLog:VAPExternalLogger];
```

## 目录结构

```text
Classes/
  FamVapWrapper/        FamVapWrapView 包装层
  QGVAPlayer/           播放器核心、解码、渲染、MP4 解析、工具类
  Shaders/              Metal shader 与 shader 类型定义
QGVAPlayer.podspec      CocoaPods 规格文件
```

## 注意事项

- 仅支持本地 MP4 文件路径播放，远程素材请先由业务侧下载到本地。
- 默认使用 Metal 渲染；需要兼容特殊环境时可设置 `hwd_renderByOpenGL = YES`。
- 旧版不含 `vapc` box 的素材需要启用旧版兼容。`QGVAPWrapView` 播放时已默认启用；直接使用 `UIView (VAP)` 时可在播放前调用 `enableOldVersion:YES`。
- 静音设置需要在播放开始前调用；播放过程中修改通常要到下一次循环或下一次播放才生效。
- `QGVAPWrapView.autoDestoryAfterFinish` 默认为 `YES`，播放停止后会移除内部 `vapView`。如果外部需要复用内部播放视图，可设置为 `NO`。
