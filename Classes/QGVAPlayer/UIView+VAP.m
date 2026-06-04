// UIView+VAP.m
// Tencent is pleased to support the open source community by making vap available.
//
// Copyright (C) 2020 Tencent.  All rights reserved.
//
// Licensed under the MIT License (the "License"); you may not use this file except in
// compliance with the License. You may obtain a copy of the License at
//
// http://opensource.org/licenses/MIT
//
// Unless required by applicable law or agreed to in writing, software distributed under the License is
// distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND,
// either express or implied. See the License for the specific language governing permissions and
// limitations under the License.

#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <TargetConditionals.h>
#import "UIView+VAP.h"
#import "QGAnimatedImageDecodeManager.h"
#import "QGMP4HWDFileInfo.h"
#import "QGMP4FrameHWDecoder.h"
#import "QGBaseAnimatedImageFrame+Displaying.h"
#import "QGVAPWeakProxy.h"
#import "NSNotificationCenter+VAPThreadSafe.h"
#import "QGMP4AnimatedImageFrame.h"
#import "QGBaseAnimatedImageFrame+Displaying.h"
#import "QGVAPConfigManager.h"
#import "QGVAPFrameRenderer.h"
#import "UIGestureRecognizer+VAPUtil.h"

NSInteger const kQGHWDMP4DefaultFPS = 20;
NSInteger const kQGHWDMP4MinFPS = 1;
NSInteger const QGHWDMP4MaxFPS = 60;
NSInteger const VapMaxCompatibleVersion = 2;
static void *kQGVAPRenderQueueSpecificKey = &kQGVAPRenderQueueSpecificKey;

@interface QGVAPPreparedPlayContext : NSObject

@property (nonatomic, strong) QGMP4HWDFileInfo *fileInfo;
@property (nonatomic, strong) QGVAPConfigManager *configManager;
@property (nonatomic, strong) QGAnimatedImageDecodeManager *decodeManager;
@property (nonatomic, strong) NSError *error;

@end

@implementation QGVAPPreparedPlayContext

@end

@interface QGVAPPlaybackRuntime : NSObject

@property (nonatomic, assign) NSInteger token;
@property (nonatomic, assign) NSInteger fps;
@property (atomic, assign) BOOL finishRequested;
@property (atomic, assign) BOOL pauseRequested;
@property (atomic, assign) BOOL seekRequested;
@property (nonatomic, assign) BOOL didStart;
@property (nonatomic, assign) NSInteger nextFrameIndex;
@property (nonatomic, strong) QGMP4HWDFileInfo *fileInfo;
@property (nonatomic, strong) QGVAPConfigManager *configManager;
@property (nonatomic, strong) QGAnimatedImageDecodeManager *decodeManager;
@property (atomic, strong) QGMP4AnimatedImageFrame *currentFrame;
@property (nonatomic, weak) VAPView *container;
@property (nonatomic, strong) NSOperationQueue *callbackQueue;
@property (nonatomic, strong) id<HWDMP4PlayDelegate> playDelegate;
@property (nonatomic, strong) id<QGVAPFrameRenderer> frameRenderer;

@end

@implementation QGVAPPlaybackRuntime

@end

@interface UIView () <QGAnimatedImageDecoderDelegate, QGVAPFrameRendererDelegate, QGVAPConfigDelegate>

@property (nonatomic, assign) QGHWDTextureBlendMode         hwd_blendMode;              //alpha通道混合模式
@property (nonatomic, strong) QGMP4AnimatedImageFrame       *hwd_currentFrameInstance;  //store the frame value
@property (nonatomic, strong) QGMP4HWDFileInfo              *hwd_fileInfo;              //MP4文件信息
@property (nonatomic, strong) QGAnimatedImageDecodeManager  *hwd_decodeManager;         //解码逻辑
@property (nonatomic, strong) QGAnimatedImageDecodeConfig   *hwd_decodeConfig;          //线程数与buffer数
@property (nonatomic, strong) NSOperationQueue              *hwd_callbackQueue;         //回调执行队列
@property (nonatomic, assign) BOOL                          hwd_onPause;                //标记是否暂停中
@property (nonatomic, assign) BOOL                          hwd_onSeek;                 //正在seek当中，此时继续播放会导致时序混乱
@property (nonatomic, assign) BOOL                          hwd_isFinish;               //标记是否结束
@property (nonatomic, assign) NSInteger                     hwd_repeatCount;            //播放次数；-1 表示无限循环
@property (nonatomic, strong) QGVAPConfigManager            *hwd_configManager;         //额外的配置信息
@property (nonatomic, strong) dispatch_queue_t              vap_renderQueue;            //播放队列
@property (nonatomic, strong) dispatch_queue_t              vap_prepareQueue;           //播放准备队列
@property (nonatomic, assign) NSInteger                     vap_playToken;              //播放请求标记，用于丢弃过期prepare
@property (nonatomic, strong) QGVAPPlaybackRuntime          *vap_playbackRuntime;       //当前播放运行态
@property (nonatomic, strong) id<QGVAPFrameRenderer>        vap_frameRenderer;          //当前渲染后端
@property (nonatomic, assign) BOOL                          vap_enableOldVersion;       //标记是否兼容不含vapc box的素材播放
@property (nonatomic, assign) BOOL                          vap_isMute;                 //标记是否禁止音频播放

@end

@interface UIView (VAPFrameRendererPrivate)

- (QGVAPFrameRendererConfiguration *)hwd_currentFrameRendererConfiguration;

@end

@implementation UIView (VAP)

#pragma mark - private methods

- (void)hwd_registerNotification {

    [[NSNotificationCenter defaultCenter] hwd_addSafeObserver:self selector:@selector(hwd_didReceiveEnterBackgroundNotification:) name:UIApplicationDidEnterBackgroundNotification object:nil];
    [[NSNotificationCenter defaultCenter] hwd_addSafeObserver:self selector:@selector(hwd_didReceiveWillEnterForegroundNotification:) name:UIApplicationWillEnterForegroundNotification object:nil];

    [[NSNotificationCenter defaultCenter] hwd_addSafeObserver:self selector:@selector(hwd_didReceiveSeekStartNotification:) name:kQGVAPDecoderSeekStart object:nil];
    [[NSNotificationCenter defaultCenter] hwd_addSafeObserver:self selector:@selector(hwd_didReceiveSeekFinishNotification:) name:kQGVAPDecoderSeekFinish object:nil];
}

- (void)hwd_didReceiveEnterBackgroundNotification:(NSNotification *)notification {
    switch (self.hwd_enterBackgroundOP) {
        case HWDMP4EBOperationTypePauseAndResume:
            [self pauseHWDMP4];
            break;
        case HWDMP4EBOperationTypeDoNothing:
            break;

        default:
            [self stopHWDMP4];
    }
}

- (void)hwd_didReceiveWillEnterForegroundNotification:(NSNotification *)notification {
    switch (self.hwd_enterBackgroundOP) {
        case HWDMP4EBOperationTypePauseAndResume:
            [self resumeHWDMP4];
            break;

        default:
            break;
    }

}

- (void)hwd_didReceiveSeekStartNotification:(NSNotification *)notification {
    if ([self.hwd_decodeManager containsThisDeocder:notification.object]) {
        self.hwd_onSeek = YES;
        self.vap_playbackRuntime.seekRequested = YES;
    }
}

- (void)hwd_didReceiveSeekFinishNotification:(NSNotification *)notification {
    if ([self.hwd_decodeManager containsThisDeocder:notification.object]) {
        self.hwd_onSeek = NO;
        self.vap_playbackRuntime.seekRequested = NO;
    }
}

//结束播放
- (void)hwd_stopHWDMP4 {

    VAP_Info(kQGVAPModuleCommon, @"hwd stop playing");
    self.vap_playToken += 1;
    self.hwd_repeatCount = 0;
    if (self.hwd_isFinish) {
        VAP_Info(kQGVAPModuleCommon, @"isFinish already set");
        return ;
    }
    self.hwd_isFinish = YES;
    self.hwd_onPause = YES;

    QGVAPPlaybackRuntime *runtime = self.vap_playbackRuntime;
    runtime.finishRequested = YES;
    self.vap_playbackRuntime = nil;
    NSInteger lastFrameIndex = runtime.currentFrame ? runtime.currentFrame.frameIndex : self.hwd_currentFrame.frameIndex;

    QGAnimatedImageDecodeManager *decodeManager = runtime.decodeManager ?: self.hwd_decodeManager;
    id<QGVAPFrameRenderer> frameRenderer = runtime.frameRenderer ?: self.vap_frameRenderer;

    [frameRenderer pause];

    if (runtime && self.vap_renderQueue) {
        dispatch_async(self.vap_renderQueue, ^{
            [decodeManager tryToStopAudioPlay];
            [frameRenderer dispose];
        });
    } else {
        [decodeManager tryToStopAudioPlay];
        if (self.vap_renderQueue) {
            dispatch_async(self.vap_renderQueue, ^{
                [frameRenderer dispose];
            });
        } else {
            [frameRenderer dispose];
        }
    }

    [self.hwd_callbackQueue addOperationWithBlock:^{
        //此处必须延迟释放，避免野指针
        if ([self.hwd_Delegate respondsToSelector:@selector(viewDidStopPlayMP4:view:)]) {
            [self.hwd_Delegate viewDidStopPlayMP4:lastFrameIndex view:self];
        }
    }];
    self.hwd_decodeManager = nil;
    self.hwd_decodeConfig = nil;
    self.hwd_currentFrameInstance = nil;
    self.hwd_fileInfo = nil;
    self.hwd_configManager = nil;
}

//播放完成
- (void)hwd_didFinishDisplay {

    VAP_Info(kQGVAPModuleCommon, @"hwd didFinishDisplay");
    [self.hwd_callbackQueue addOperationWithBlock:^{
        //此处必须延迟释放，避免野指针
        if ([self.hwd_Delegate respondsToSelector:@selector(viewDidFinishPlayMP4:view:)]) {
            [self.hwd_Delegate viewDidFinishPlayMP4:self.hwd_currentFrame.frameIndex+1 view:self];
        }
    }];
    NSInteger currentCount = self.hwd_repeatCount;
    if (currentCount == -1 || currentCount-- > 0) {
        //continuing
        VAP_Info(kQGVAPModuleCommon, @"continue to display. currentCount:%@", @(currentCount));
        [self p_playHWDMP4:self.hwd_fileInfo.filePath
                       fps:self.hwd_fps
                 blendMode:self.hwd_blendMode
               repeatCount:currentCount
                  delegate:self.hwd_Delegate];
        return ;
    }
    [self hwd_stopHWDMP4];
}

- (QGVAPFrameRendererType)hwd_preferredFrameRendererType {
    if (self.hwd_renderByOpenGL) {
        return QGVAPFrameRendererTypeOpenGL;
    }
    return self.useVapMetalView ? QGVAPFrameRendererTypeVAPMetal : QGVAPFrameRendererTypeHWDMetal;
}

- (void)hwd_resetFrameRenderer {
    [self.vap_frameRenderer dispose];
    [self.vap_frameRenderer.renderView removeFromSuperview];
    self.vap_frameRenderer = nil;
}

- (QGVAPFrameRendererConfiguration *)hwd_currentFrameRendererConfiguration {
    QGVAPFrameRendererConfiguration *configuration = [QGVAPFrameRendererConfiguration new];
    configuration.rendererType = [self hwd_preferredFrameRendererType];
    configuration.container = self;
    configuration.blendMode = self.hwd_blendMode;
    configuration.commonInfo = self.hwd_configManager.model.info;
    configuration.maskInfo = self.vap_maskInfo;
    configuration.configManager = self.hwd_configManager;
    configuration.delegate = self;
    return configuration;
}

- (void)hwd_loadFrameRendererIfNeed {
    QGVAPFrameRendererConfiguration *configuration = [self hwd_currentFrameRendererConfiguration];
    QGVAPFrameRendererType rendererType = [self hwd_preferredFrameRendererType];
    id<QGVAPFrameRenderer> currentRenderer = self.vap_frameRenderer;
    if (currentRenderer && currentRenderer.rendererType != rendererType) {
        [self hwd_resetFrameRenderer];
        currentRenderer = nil;
    }

    if (currentRenderer) {
        [currentRenderer applyConfiguration:configuration];
        [self hwd_registerNotification];
        return;
    }

    id<QGVAPFrameRenderer> renderer = QGVAPCreateFrameRenderer(configuration);
    self.vap_frameRenderer = renderer;
    [self hwd_registerNotification];
}

//fps策略：优先使用调用者指定的fps；若不合法则使用mp4中的数据；若还是不合法则使用默认18
- (NSTimeInterval)hwd_appropriateDurationForFrame:(QGMP4AnimatedImageFrame *)frame {
    return [self hwd_appropriateDurationForFrame:frame fps:self.hwd_fps];
}

- (NSTimeInterval)hwd_appropriateDurationForFrame:(QGMP4AnimatedImageFrame *)frame fps:(NSInteger)fps {
    NSInteger targetFPS = fps;
    if (targetFPS < kQGHWDMP4MinFPS || targetFPS > QGHWDMP4MaxFPS) {
        if (frame.defaultFps >= kQGHWDMP4MinFPS && frame.defaultFps <= QGHWDMP4MaxFPS) {
            targetFPS = frame.defaultFps;
        }else {
            targetFPS = kQGHWDMP4DefaultFPS;
        }
    }
    return 1000/(double)targetFPS;
}

#pragma mark - main

/**
 播放一遍，alpha数据在左边，不需要回调
 */
- (void)playHWDMp4:(NSString *)filePath {
    [self playHWDMP4:filePath delegate:nil];
}

/**
 播放一遍，alpha数据在左边,设置回调
 */
- (void)playHWDMP4:(NSString *)filePath delegate:(id<HWDMP4PlayDelegate>)delegate {
    [self p_playHWDMP4:filePath fps:0 blendMode:QGHWDTextureBlendMode_AlphaLeft repeatCount:0 delegate:delegate];
}

/**
 alpha数据在左边
 */
- (void)playHWDMP4:(NSString *)filePath repeatCount:(NSInteger)repeatCount delegate:(id<HWDMP4PlayDelegate>)delegate {
    [self p_playHWDMP4:filePath fps:0 blendMode:QGHWDTextureBlendMode_AlphaLeft repeatCount:repeatCount delegate:delegate];
}

- (void)playHWDMP4:(NSString *)filePath blendMode:(QGHWDTextureBlendMode)mode delegate:(id<HWDMP4PlayDelegate>)delegate {
    [self p_playHWDMP4:filePath fps:0 blendMode:mode repeatCount:0 delegate:delegate];
}

- (void)playHWDMP4:(NSString *)filePath blendMode:(QGHWDTextureBlendMode)mode repeatCount:(NSInteger)repeatCount delegate:(id<HWDMP4PlayDelegate>)delegate {
    [self p_playHWDMP4:filePath fps:0 blendMode:mode repeatCount:repeatCount delegate:delegate];
}

- (void)p_playHWDMP4:(NSString *)filePath
               fps:(NSInteger)fps
         blendMode:(QGHWDTextureBlendMode)mode
       repeatCount:(NSInteger)repeatCount
          delegate:(id<HWDMP4PlayDelegate>)delegate {

    VAP_Info(kQGVAPModuleCommon, @"try to display mp4:%@ blendMode:%@ fps:%@ repeatCount:%@", filePath, @(mode), @(fps), @(repeatCount));
    NSAssert([NSThread isMainThread], @"HWDMP4 needs to be accessed on the main thread.");
    //filePath check
    if (!filePath || filePath.length == 0) {
        VAP_Error(kQGVAPModuleCommon, @"playHWDMP4 error! has no filePath!");
        return ;
    }
    NSInteger playToken = self.vap_playToken + 1;
    self.vap_playToken = playToken;
    self.vap_playbackRuntime.finishRequested = YES;
    self.vap_playbackRuntime = nil;
    self.hwd_isFinish = NO;
    self.hwd_blendMode = mode;
    self.hwd_fps = fps;
    self.hwd_repeatCount = repeatCount;
    self.hwd_Delegate = delegate;
    if (self.hwd_Delegate && !self.hwd_callbackQueue) {
        NSOperationQueue *queue = [[NSOperationQueue alloc] init];
        queue.maxConcurrentOperationCount = 1;
        self.hwd_callbackQueue = queue;
    }

    //reset
    self.hwd_currentFrameInstance = nil;
    self.hwd_decodeManager = nil;
    self.hwd_onPause = NO;

    if (!self.hwd_decodeConfig) {
        self.hwd_decodeConfig = [QGAnimatedImageDecodeConfig defaultConfig];
    }

    if (!self.vap_renderQueue) {
        self.vap_renderQueue = dispatch_queue_create("com.qgame.vap.render", DISPATCH_QUEUE_SERIAL);
        dispatch_queue_set_specific(self.vap_renderQueue, kQGVAPRenderQueueSpecificKey, kQGVAPRenderQueueSpecificKey, NULL);
    }
    if (!self.vap_prepareQueue) {
        self.vap_prepareQueue = dispatch_queue_create("com.qgame.vap.prepare", DISPATCH_QUEUE_SERIAL);
    }

    BOOL enableOldVersion = self.vap_enableOldVersion;
    QGAnimatedImageDecodeConfig *decodeConfig = self.hwd_decodeConfig;
    __weak typeof(self) weakSelf = self;
    dispatch_async(self.vap_prepareQueue, ^{
        __strong typeof(weakSelf) prepareSelf = weakSelf;
        if (!prepareSelf) {
            return;
        }
        QGVAPPreparedPlayContext *context = [QGVAPPreparedPlayContext new];
        NSFileManager *fileMgr = [NSFileManager defaultManager];
        if (![fileMgr fileExistsAtPath:filePath]) {
            VAP_Error(kQGVAPModuleCommon, @"playHWDMP4 error! fileNotExistsAtPath filePath:%#", filePath);
            context.error = [NSError errorWithDomain:@"QGMP4HWDErrorDomain"
                                                code:QGMP4HWDErrorCode_FileNotExist
                                            userInfo:@{@"location": filePath ?: @""}];
        } else {
            QGMP4HWDFileInfo *fileInfo = [[QGMP4HWDFileInfo alloc] init];
            fileInfo.filePath = filePath;
            fileInfo.mp4Parser = [[QGMP4ParserProxy alloc] initWithFilePath:fileInfo.filePath];
            [fileInfo.mp4Parser parse];

            QGVAPConfigManager *configManager = [[QGVAPConfigManager alloc] initWith:fileInfo];
            if (configManager.model.info.version > VapMaxCompatibleVersion) {
                VAP_Error(kQGVAPModuleCommon, @"playHWDMP4 error! not compatible vap version:%@!", @(configManager.model.info.version));
                context.error = [NSError errorWithDomain:@"QGMP4HWDErrorDomain"
                                                    code:QGMP4HWDErrorCode_InvalidMP4File
                                                userInfo:@{@"location": filePath ?: @""}];
            } else if (!configManager.hasValidConfig && !enableOldVersion) {
                VAP_Error(kQGVAPModuleCommon, @"playHWDMP4 error! don't has vapc box and enableOldVersion is false!");
                context.error = [NSError errorWithDomain:@"QGMP4HWDErrorDomain"
                                                    code:QGMP4HWDErrorCode_InvalidMP4File
                                                userInfo:@{@"location": filePath ?: @""}];
            } else {
                QGAnimatedImageDecodeManager *decodeManager = [[QGAnimatedImageDecodeManager alloc] initWith:fileInfo config:decodeConfig delegate:prepareSelf];
                context.fileInfo = fileInfo;
                context.configManager = configManager;
                context.decodeManager = decodeManager;
            }
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf || strongSelf.vap_playToken != playToken || strongSelf.hwd_isFinish) {
                return;
            }
            if (context.error) {
                [strongSelf hwd_stopHWDMP4];
                [strongSelf.hwd_callbackQueue addOperationWithBlock:^{
                    if ([strongSelf.hwd_Delegate respondsToSelector:@selector(viewDidFailPlayMP4:)]) {
                        [strongSelf.hwd_Delegate viewDidFailPlayMP4:context.error];
                    }
                }];
                return;
            }

            context.configManager.delegate = strongSelf;
            strongSelf.hwd_fileInfo = context.fileInfo;
            strongSelf.hwd_configManager = context.configManager;
            strongSelf.hwd_decodeManager = context.decodeManager;

            [strongSelf hwd_loadFrameRendererIfNeed];

            [strongSelf.hwd_configManager loadConfigResources]; //必须按先加载必要资源才能播放 - onVAPConfigResourcesLoaded
        });
    });
}

#pragma mark - play run

- (QGVAPPlaybackRuntime *)hwd_createPlaybackRuntime {

    QGVAPPlaybackRuntime *runtime = [QGVAPPlaybackRuntime new];
    runtime.token = self.vap_playToken;
    runtime.fps = self.hwd_fps;
    runtime.pauseRequested = self.hwd_onPause;
    runtime.seekRequested = self.hwd_onSeek;
    runtime.nextFrameIndex = 0;
    runtime.fileInfo = self.hwd_fileInfo;
    runtime.configManager = self.hwd_configManager;
    runtime.decodeManager = self.hwd_decodeManager;
    runtime.container = self;
    runtime.callbackQueue = self.hwd_callbackQueue;
    runtime.playDelegate = self.hwd_Delegate;
    runtime.frameRenderer = self.vap_frameRenderer;
    return runtime;
}

- (void)hwd_renderVideoRun {

    static NSTimeInterval durationForWaitingFrame = 16/1000.0;
    static NSTimeInterval minimumDurationForLoop = 1/1000.0;
    __block NSTimeInterval lastRenderingInterval = 0;
    __block NSTimeInterval lastRenderingDuration = 0;
    QGVAPPlaybackRuntime *runtime = [self hwd_createPlaybackRuntime];
    self.vap_playbackRuntime = runtime;

    __weak typeof(self) weakSelf = self;
    dispatch_async(self.vap_renderQueue, ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf || runtime.pauseRequested || runtime.finishRequested) {
            return ;
        }
        [runtime.frameRenderer prepareForRendering];
        //不能将self.hwd_onPause判断加到while语句中！会导致releasepool不断上涨
        while (YES) {
            @autoreleasepool {
                if (runtime.finishRequested) {
                    break ;
                }
                if (runtime.pauseRequested || runtime.seekRequested) {
                    lastRenderingInterval = NSDate.timeIntervalSinceReferenceDate;
                    [NSThread sleepForTimeInterval:durationForWaitingFrame];
                    continue;
                }
                QGMP4AnimatedImageFrame *nextFrame = [strongSelf hwd_displayNextForRuntime:runtime];
                NSTimeInterval duration = nextFrame.duration/1000.0;
                if (duration == 0) {
                    duration = durationForWaitingFrame;
                }
                NSTimeInterval currentTimeInterval = NSDate.timeIntervalSinceReferenceDate;
                if (nextFrame && nextFrame.frameIndex != 0) {
                    duration -= ((currentTimeInterval-lastRenderingInterval) - lastRenderingDuration); //追回时间
                }
                duration = MAX(minimumDurationForLoop, duration);
                lastRenderingInterval = currentTimeInterval;
                lastRenderingDuration = duration;
                [NSThread sleepForTimeInterval:duration];
            }
        }
    });
}

- (QGMP4AnimatedImageFrame *)hwd_displayNextForRuntime:(QGVAPPlaybackRuntime *)runtime {

    if (runtime.pauseRequested || runtime.finishRequested) {
        return nil;
    }
    NSInteger nextIndex = runtime.nextFrameIndex;

    QGMP4AnimatedImageFrame *nextFrame = (QGMP4AnimatedImageFrame *)[runtime.decodeManager consumeDecodedFrame:nextIndex];
    //没取到预期的帧
    if (!nextFrame || nextFrame.frameIndex != nextIndex || ![nextFrame isKindOfClass:[QGMP4AnimatedImageFrame class]]) {
        return nil;
    }
    //音频播放
    if (nextIndex == 0) {
        [runtime.decodeManager tryToStartAudioPlay];
    }
    nextFrame.duration = [self hwd_appropriateDurationForFrame:nextFrame fps:runtime.fps];
    //VAP_Debug(kQGVAPModuleCommon, @"display frame:%@, has frameBuffer:%@",@(nextIndex),@(nextFrame.pixelBuffer != nil));
    QGVAPFrameRenderContext *renderContext = [QGVAPFrameRenderContext new];
    renderContext.pixelBuffer = nextFrame.pixelBuffer;
    renderContext.mergeInfos = runtime.configManager.model.mergedConfig[@(nextFrame.frameIndex)];
    [runtime.frameRenderer renderWithContext:renderContext];
    runtime.currentFrame = nextFrame;
    runtime.nextFrameIndex = nextIndex + 1;

    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf || strongSelf.vap_playToken != runtime.token || strongSelf.vap_playbackRuntime != runtime || runtime.finishRequested) {
            return;
        }
        strongSelf.hwd_currentFrameInstance = nextFrame;
    });

    __weak VAPView *weakContainer = runtime.container;
    id<HWDMP4PlayDelegate> playDelegate = runtime.playDelegate;
    BOOL shouldSendStart = (nextIndex == 0 && !runtime.didStart);
    runtime.didStart = YES;
    [runtime.callbackQueue addOperationWithBlock:^{
        VAPView *container = weakContainer;
        if (!container) {
            return;
        }
        if (shouldSendStart && [playDelegate respondsToSelector:@selector(viewDidStartPlayMP4:)]) {
            [playDelegate viewDidStartPlayMP4:container];
        }
        //此处必须延迟释放，避免野指针
        if ([playDelegate respondsToSelector:@selector(viewDidPlayMP4AtFrame:view:)]) {
            [playDelegate viewDidPlayMP4AtFrame:nextFrame view:container];
        }
    }];
    return nextFrame;
}

//结束播放
- (void)stopHWDMP4 {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self stopHWDMP4];
        });
        return;
    }
    [self hwd_stopHWDMP4];
}

- (void)pauseHWDMP4 {

    VAP_Info(kQGVAPModuleCommon, @"pauseHWDMP4");
    self.hwd_onPause = YES;
    self.vap_playbackRuntime.pauseRequested = YES;
    [self.vap_playbackRuntime.frameRenderer pause];
    [self.hwd_decodeManager tryToPauseAudioPlay];
// pause回调stop会导致一般使用场景将view移除，无法resume，因此暂时去掉该回调触发
//    [self.hwd_callbackQueue addOperationWithBlock:^{
//        //此处必须延迟释放，避免野指针
//        if ([self.hwd_Delegate respondsToSelector:@selector(viewDidStopPlayMP4:view:)]) {
//            [self.hwd_Delegate viewDidStopPlayMP4:self.hwd_currentFrame.frameIndex view:self];
//        }
//    }];
}

- (void)resumeHWDMP4 {

    VAP_Info(kQGVAPModuleCommon, @"resumeHWDMP4");
    self.hwd_onPause = NO;
    self.vap_playbackRuntime.pauseRequested = NO;
    [self.vap_playbackRuntime.frameRenderer resume];
    // 目前音频和视频没有同步逻辑，多次暂停恢复会使音视频差距越来越大
    [self.hwd_decodeManager tryToResumeAudioPlay];
}

+ (void)registerHWDLog:(QGVAPLoggerFunc)logger {
    [QGVAPLogger registerExternalLog:logger];
}

- (void)enableOldVersion:(BOOL)enable {
    self.vap_enableOldVersion = enable;
}

- (void)setMute:(BOOL)isMute {
    self.vap_isMute = isMute;
}
#pragma mark - delegate

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wobjc-protocol-method-implementation"
//decoder
- (Class)decoderClassForManager:(QGAnimatedImageDecodeManager *)manager {
    return [QGMP4FrameHWDecoder class];
}

- (BOOL)shouldSetupAudioPlayer {
    return !self.vap_isMute;
}

- (void)decoderDidFinishDecode:(QGBaseDecoder *)decoder {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self decoderDidFinishDecode:decoder];
        });
        return;
    }
    if (decoder && ![self.hwd_decodeManager containsThisDeocder:decoder]) {
        return;
    }
    VAP_Info(kQGVAPModuleCommon, @"decoderDidFinishDecode.");
    [self hwd_didFinishDisplay];
}

- (void)decoderDidFailDecode:(QGBaseDecoder *)decoder error:(NSError *)error{
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self decoderDidFailDecode:decoder error:error];
        });
        return;
    }
    if (decoder && ![self.hwd_decodeManager containsThisDeocder:decoder]) {
        return;
    }
    VAP_Error(kQGVAPModuleCommon, @"decoderDidFailDecode:%@", error);
    [self hwd_stopHWDMP4];
    [self.hwd_callbackQueue addOperationWithBlock:^{
        //此处必须延迟释放，避免野指针
        if ([self.hwd_Delegate respondsToSelector:@selector(viewDidFailPlayMP4:)]) {
            [self.hwd_Delegate viewDidFailPlayMP4:error];
        }
    }];
}

- (void)frameRendererDidBecomeUnavailable:(id<QGVAPFrameRenderer>)renderer {
    VAP_Error(kQGVAPModuleCommon, @"frameRendererDidBecomeUnavailable:%@", renderer);
    [self stopHWDMP4];
}

//config resources loaded
- (void)onVAPConfigResourcesLoaded:(QGVAPConfigModel *)config error:(NSError *)error {

    NSInteger playToken = self.vap_playToken;
    QGVAPConfigManager *configManager = self.hwd_configManager;
    __weak typeof(self) weakSelf = self;
    dispatch_async(self.vap_prepareQueue ?: dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf || strongSelf.hwd_isFinish || strongSelf.vap_playToken != playToken) {
            return;
        }
        if (error) {
            dispatch_async(dispatch_get_main_queue(), ^{
                __strong typeof(weakSelf) mainSelf = weakSelf;
                if (!mainSelf || mainSelf.hwd_isFinish || mainSelf.vap_playToken != playToken) {
                    return;
                }
                [mainSelf hwd_stopHWDMP4];
                [mainSelf.hwd_callbackQueue addOperationWithBlock:^{
                    if ([mainSelf.hwd_Delegate respondsToSelector:@selector(viewDidFailPlayMP4:)]) {
                        [mainSelf.hwd_Delegate viewDidFailPlayMP4:error];
                    }
                }];
            });
            return;
        }
        id<QGVAPFrameRenderer> frameRenderer = strongSelf.vap_frameRenderer;
        [frameRenderer prepareResources];
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) mainSelf = weakSelf;
            if (!mainSelf || mainSelf.hwd_isFinish || mainSelf.vap_playToken != playToken) {
                return;
            }
            if (mainSelf.hwd_configManager != configManager || mainSelf.vap_frameRenderer != frameRenderer) {
                return;
            }
            if ([mainSelf.hwd_Delegate respondsToSelector:@selector(shouldStartPlayMP4:config:)]) {
                BOOL shouldStart = [mainSelf.hwd_Delegate shouldStartPlayMP4:mainSelf config:mainSelf.hwd_configManager.model];
                if (!shouldStart) {
                    VAP_Event(kQGVAPModuleCommon, @"shouldStartPlayMP4 return no!");
                    [mainSelf hwd_stopHWDMP4];
                    return ;
                }
            }
            [mainSelf hwd_renderVideoRun];
        });
    });
}

- (NSString *)vap_contentForTag:(NSString *)tag resource:(QGVAPSourceInfo *)info {

    if ([self.hwd_Delegate respondsToSelector:@selector(contentForVapTag:resource:)]) {
        return [self.hwd_Delegate contentForVapTag:tag resource:info];
    }
    return nil;
}

- (void)vap_loadImageWithURL:(NSString *)urlStr context:(NSDictionary *)context completion:(VAPImageCompletionBlock)completionBlock {
    if ([self.hwd_Delegate respondsToSelector:@selector(loadVapImageWithURL:context:completion:)]) {
        [self.hwd_Delegate loadVapImageWithURL:urlStr context:context completion:completionBlock];
    } else if (completionBlock) {
        NSError *error = [NSError errorWithDomain:NSURLErrorDomain code:-1 userInfo:@{@"msg" : @"hwd_Delegate doesn't responds to selector loadVapImageWithURL:context:completion:"}];
        completionBlock(nil, error, nil);
    }
}

#pragma clang diagnostic pop

#pragma mark - setters&getters

- (BOOL)useVapMetalView {
    return self.hwd_configManager.hasValidConfig;
}

- (QGMP4AnimatedImageFrame *)hwd_currentFrame {
    return self.hwd_currentFrameInstance;
}

- (id<HWDMP4PlayDelegate>)hwd_Delegate {
    return objc_getAssociatedObject(self, @"MP4PlayDelegate");
}

- (void)setHwd_Delegate:(id<HWDMP4PlayDelegate>)MP4PlayDelegate {
    //解决循环播放问题，本身已经是一个weakproxy对象，就不再处理
    id weakDelegate = MP4PlayDelegate;
    if (![MP4PlayDelegate isKindOfClass:[QGVAPWeakProxy class]]) {
        weakDelegate = [QGVAPWeakProxy proxyWithTarget:MP4PlayDelegate];
    }
    return objc_setAssociatedObject(self, @"MP4PlayDelegate", weakDelegate, OBJC_ASSOCIATION_RETAIN);
}

//category methods
HWDSYNTH_DYNAMIC_PROPERTY_CTYPE(hwd_onPause, setHwd_onPause, BOOL)
HWDSYNTH_DYNAMIC_PROPERTY_CTYPE(hwd_onSeek, setHwd_onSeek, BOOL)
HWDSYNTH_DYNAMIC_PROPERTY_CTYPE(hwd_enterBackgroundOP, setHwd_enterBackgroundOP, HWDMP4EBOperationType)
HWDSYNTH_DYNAMIC_PROPERTY_CTYPE(hwd_renderByOpenGL, setHwd_renderByOpenGL, BOOL)
HWDSYNTH_DYNAMIC_PROPERTY_CTYPE(hwd_isFinish, setHwd_isFinish, BOOL)
HWDSYNTH_DYNAMIC_PROPERTY_CTYPE(hwd_fps, setHwd_fps, NSInteger)
HWDSYNTH_DYNAMIC_PROPERTY_CTYPE(hwd_blendMode, setHwd_blendMode, NSInteger)
HWDSYNTH_DYNAMIC_PROPERTY_CTYPE(hwd_repeatCount, setHwd_repeatCount, NSInteger)
HWDSYNTH_DYNAMIC_PROPERTY_OBJECT(hwd_currentFrameInstance, setHwd_currentFrameInstance, OBJC_ASSOCIATION_RETAIN)
HWDSYNTH_DYNAMIC_PROPERTY_OBJECT(hwd_MP4FilePath, setHwd_MP4FilePath, OBJC_ASSOCIATION_RETAIN)
HWDSYNTH_DYNAMIC_PROPERTY_OBJECT(hwd_decodeManager, setHwd_decodeManager, OBJC_ASSOCIATION_RETAIN)
HWDSYNTH_DYNAMIC_PROPERTY_OBJECT(hwd_fileInfo, setHwd_fileInfo, OBJC_ASSOCIATION_RETAIN)
HWDSYNTH_DYNAMIC_PROPERTY_OBJECT(hwd_decodeConfig, setHwd_decodeConfig, OBJC_ASSOCIATION_RETAIN)
HWDSYNTH_DYNAMIC_PROPERTY_OBJECT(hwd_callbackQueue, setHwd_callbackQueue, OBJC_ASSOCIATION_RETAIN)
HWDSYNTH_DYNAMIC_PROPERTY_OBJECT(hwd_attachmentsModel, setHwd_attachmentsModel, OBJC_ASSOCIATION_RETAIN)
HWDSYNTH_DYNAMIC_PROPERTY_OBJECT(hwd_configManager, setHwd_configManager, OBJC_ASSOCIATION_RETAIN)
HWDSYNTH_DYNAMIC_PROPERTY_OBJECT(vap_renderQueue, setVap_renderQueue, OBJC_ASSOCIATION_RETAIN)
HWDSYNTH_DYNAMIC_PROPERTY_OBJECT(vap_prepareQueue, setVap_prepareQueue, OBJC_ASSOCIATION_RETAIN)
HWDSYNTH_DYNAMIC_PROPERTY_CTYPE(vap_playToken, setVap_playToken, NSInteger)
HWDSYNTH_DYNAMIC_PROPERTY_OBJECT(vap_playbackRuntime, setVap_playbackRuntime, OBJC_ASSOCIATION_RETAIN)
HWDSYNTH_DYNAMIC_PROPERTY_OBJECT(vap_frameRenderer, setVap_frameRenderer, OBJC_ASSOCIATION_RETAIN)
HWDSYNTH_DYNAMIC_PROPERTY_CTYPE(vap_enableOldVersion, setVap_enableOldVersion, BOOL)
HWDSYNTH_DYNAMIC_PROPERTY_CTYPE(vap_isMute, setVap_isMute, BOOL)
@end


/// vap 增加手势识别的能力
@implementation  UIView (VAPGesture)

/// 手势识别通用接口
/// @param gestureRecognizer 需要的手势识别器
/// @param handler 手势识别事件回调，按照gestureRecognizer回调时机回调
/// @note 例：[mp4View addVapGesture:[UILongPressGestureRecognizer new] callback:^(UIGestureRecognizer *gestureRecognizer, BOOL insideSource,QGVAPSourceDisplayItem *source) { NSLog(@"long press"); }];
- (void)addVapGesture:(UIGestureRecognizer *)gestureRecognizer callback:(VAPGestureEventBlock)handler {

    if (!gestureRecognizer) {
        VAP_Event(kQGVAPModuleCommon, @"addVapTapGesture with empty gestureRecognizer!");
        return ;
    }
    if (!handler) {
        VAP_Event(kQGVAPModuleCommon, @"addVapTapGesture with empty handler!");
        return ;
    }
    __weak __typeof(self) weakSelf = self;
    [gestureRecognizer addVapActionBlock:^(UITapGestureRecognizer *sender) {

        QGVAPSourceDisplayItem *diplaySource = [weakSelf displayingSourceAt:[sender locationInView:weakSelf]];
        if (diplaySource) {
            handler(sender, YES, diplaySource);
        } else {
            handler(sender, NO, nil);
        }
    }];
    [self addGestureRecognizer:gestureRecognizer];
}

/// 增加点击的手势识别
/// @param handler 点击事件回调
- (void)addVapTapGesture:(VAPGestureEventBlock)handler {

    UITapGestureRecognizer *tapGesture = [[UITapGestureRecognizer alloc] init];
    [self addVapGesture:tapGesture callback:handler];
}

/// 获取当前视图中point位置最近的一个source，没有的话返回nil
/// @param point 当前view坐标系下的某一个位置
- (QGVAPSourceDisplayItem *)displayingSourceAt:(CGPoint)point {

    NSArray<QGVAPMergedInfo *> *mergeInfos = self.hwd_configManager.model.mergedConfig[@(self.hwd_currentFrame.frameIndex)];
    mergeInfos = [mergeInfos sortedArrayUsingComparator:^NSComparisonResult(QGVAPMergedInfo *obj1, QGVAPMergedInfo *obj2) {
        return [@(obj2.renderIndex) compare:@(obj1.renderIndex)];
    }];
    CGSize renderingPixelSize = self.hwd_configManager.model.info.size;
    if (renderingPixelSize.width <= 0 || renderingPixelSize.height <= 0) {
        return nil;
    }
    __block QGVAPMergedInfo *targetMergeInfo = nil;
    __block CGRect targetSourceFrame = CGRectZero;

    CGSize viewSize = self.frame.size;
    CGFloat xRatio =  viewSize.width / renderingPixelSize.width;
    CGFloat yRatio = viewSize.height / renderingPixelSize.height;
    [mergeInfos enumerateObjectsUsingBlock:^(QGVAPMergedInfo * mergeInfo, NSUInteger idx, BOOL * _Nonnull stop) {
        CGRect sourceRenderingRect = mergeInfo.renderRect;
        CGRect sourceRenderingFrame = CGRectMake(CGRectGetMinX(sourceRenderingRect) * xRatio, CGRectGetMinY(sourceRenderingRect) * yRatio, CGRectGetWidth(sourceRenderingRect) * xRatio, CGRectGetHeight(sourceRenderingRect) * yRatio);
        BOOL inside = CGRectContainsPoint(sourceRenderingFrame, point);
        if (inside) {
            targetMergeInfo = mergeInfo;
            targetSourceFrame = sourceRenderingFrame;
            *stop = YES;
        }
    }];

    if (!targetMergeInfo) {
        return nil;
    }

    QGVAPSourceDisplayItem *diplayItem = [QGVAPSourceDisplayItem new];
    diplayItem.sourceInfo = targetMergeInfo.source;
    diplayItem.frame = targetSourceFrame;
    return diplayItem;
}

@end

@implementation UIView (VAPMask)

- (void)setVap_maskInfo:(QGVAPMaskInfo *)vap_maskInfo {
    objc_setAssociatedObject(self, @"VAPMaskInfo", vap_maskInfo, OBJC_ASSOCIATION_RETAIN);
    [self.vap_frameRenderer applyConfiguration:[self hwd_currentFrameRendererConfiguration]];
}

- (QGVAPMaskInfo *)vap_maskInfo {
    return objc_getAssociatedObject(self, @"VAPMaskInfo");
}

@end
