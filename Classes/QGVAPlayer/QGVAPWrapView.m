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

#import "QGVAPWrapView.h"
#import "QGVAPConfigModel.h"
#import "QGMP4HWDFileInfo.h"

@interface QGVAPWrapView()<VAPWrapViewDelegate, HWDMP4PlayDelegate>

@end

@implementation QGVAPWrapView

- (instancetype)init {
    if (self = [super init]) {
        [self commonInit];
    }
    return self;
}

- (instancetype)initWithFrame:(CGRect)frame {
    if (self = [super initWithFrame:frame]) {
        [self commonInit];
    }
    return self;
}

- (void)commonInit {
    _autoDestoryAfterFinish = YES;
}

// 因为播放停止后可能移除VAPView，这里需要加回来
- (void)initVAPViewIfNeed {
    if (!_vapView) {
        _vapView = [[VAPView alloc] initWithFrame:self.bounds];
        [self addSubview:_vapView];
    }
}

- (void)playHWDMP4:(NSString *)filePath
                   repeatCount:(NSInteger)repeatCount
                      delegate:(id<VAPWrapViewDelegate>)delegate {
    
    self.delegate = delegate;
    
    // 调试尺寸日志，排查 VAP 布局时使用
//    NSLog(@"VAP_SIZE_TRACE QGVAPWrapView play repeat beforeInit wrapper:%@ inner:%@ superview:%@ window:%@ repeatCount:%@",
//          NSStringFromCGRect(self.bounds),
//          NSStringFromCGRect(self.vapView.bounds),
//          self.superview,
//          self.window,
//          @(repeatCount));
    [self initVAPViewIfNeed];
//    NSLog(@"VAP_SIZE_TRACE QGVAPWrapView play repeat beforePlay wrapper:%@ inner:%@ innerSuperview:%@",
//          NSStringFromCGRect(self.bounds),
//          NSStringFromCGRect(self.vapView.bounds),
//          self.vapView.superview);
    [self.vapView enableOldVersion:YES]; // 启用旧版本支持
    [self.vapView playHWDMP4:filePath repeatCount:repeatCount delegate:self];
//    NSLog(@"VAP_SIZE_TRACE QGVAPWrapView play repeat afterCall wrapper:%@ inner:%@",
//          NSStringFromCGRect(self.bounds),
//          NSStringFromCGRect(self.vapView.bounds));
}

- (void)playHWDMP4:(NSString *)filePath
         blendMode:(QGHWDTextureBlendMode)mode
       repeatCount:(NSInteger)repeatCount
          delegate:(id<VAPWrapViewDelegate>)delegate {
    self.delegate = delegate;

    // 调试尺寸日志，排查 VAP 布局时使用
//    NSLog(@"VAP_SIZE_TRACE QGVAPWrapView play blend beforeInit wrapper:%@ inner:%@ superview:%@ window:%@ blendMode:%@ repeatCount:%@",
//          NSStringFromCGRect(self.bounds),
//          NSStringFromCGRect(self.vapView.bounds),
//          self.superview,
//          self.window,
//          @(mode),
//          @(repeatCount));
    [self initVAPViewIfNeed];
//    NSLog(@"VAP_SIZE_TRACE QGVAPWrapView play blend beforePlay wrapper:%@ inner:%@ innerSuperview:%@",
//          NSStringFromCGRect(self.bounds),
//          NSStringFromCGRect(self.vapView.bounds),
//          self.vapView.superview);
    [self.vapView enableOldVersion:YES]; // 启用旧版本支持，兼容不带 vapc box 的旧素材
    [self.vapView playHWDMP4:filePath blendMode:mode repeatCount:repeatCount delegate:self];
//    NSLog(@"VAP_SIZE_TRACE QGVAPWrapView play blend afterCall wrapper:%@ inner:%@",
//          NSStringFromCGRect(self.bounds),
//          NSStringFromCGRect(self.vapView.bounds));
}

- (void)stopHWDMP4 {
    [self.vapView stopHWDMP4];
}

- (void)pauseHWDMP4 {
    [self.vapView pauseHWDMP4];
}

- (void)resumeHWDMP4 {
    [self.vapView resumeHWDMP4];
}

#pragma mark - Setters

- (void)setHwd_enterBackgroundOP:(HWDMP4EBOperationType)hwd_enterBackgroundOP {
    [super setHwd_enterBackgroundOP:hwd_enterBackgroundOP];
    [self initVAPViewIfNeed];
    
    // 外层包装视图配置变化后，立即透传给内部真实播放视图
    self.vapView.hwd_enterBackgroundOP = hwd_enterBackgroundOP;
}

- (void)setMute:(BOOL)isMute {
    [self initVAPViewIfNeed];
    [self.vapView setMute:isMute];
}

- (void)addVapGesture:(UIGestureRecognizer *)gestureRecognizer callback:(VAPGestureEventBlock)handler {
    [self initVAPViewIfNeed];
    [self.vapView addVapGesture:gestureRecognizer callback:handler];
}

- (void)addVapTapGesture:(VAPGestureEventBlock)handler {
    [self initVAPViewIfNeed];
    [self.vapView addVapTapGesture:handler];
}

#pragma mark - UIView
// 自身不响应，仅子视图响应。
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    if (!self.isUserInteractionEnabled || self.isHidden || self.alpha < 0.01) {
        return nil;
    }
    if ([self pointInside:point withEvent:event]) {
        for (UIView *subview in [self.subviews reverseObjectEnumerator]) {
            CGPoint convertedPoint = [self convertPoint:point toView:subview];
            UIView *hitView = [subview hitTest:convertedPoint withEvent:event];
            if (hitView) {
                return hitView;
            }
        }
        return nil;
    }
    return nil;
}

#pragma mark - Private

- (void)p_setupContentModeWithConfig:(QGVAPConfigModel *)config {
    CGFloat realWidth = 0.;
    CGFloat realHeight = 0.;
    
    if (!config) {
        return;
    }
    
    CGFloat layoutWidth = self.bounds.size.width;
    CGFloat layoutHeight = self.bounds.size.height;
    
    CGFloat layoutRatio = self.bounds.size.width / self.bounds.size.height;
    CGFloat videoRatio = config.info.size.width / config.info.size.height;
    
    switch (self.contentMode) {
        case QGVAPWrapViewContentModeScaleToFill: {

        }
            break;
        case QGVAPWrapViewContentModeAspectFit: {
            if (layoutRatio < videoRatio) {
                realWidth = layoutWidth;
                realHeight = realWidth / videoRatio;
            } else {
                realHeight = layoutHeight;
                realWidth = videoRatio * realHeight;
            }
            
            self.vapView.frame = CGRectMake(0, 0, realWidth, realHeight);
            self.vapView.center = self.center;
        }
            break;;
        case QGVAPWrapViewContentModeAspectFill: {
            if (layoutRatio > videoRatio) {
                realWidth = layoutWidth;
                realHeight = realWidth / videoRatio;
            } else {
                realHeight = layoutHeight;
                realWidth = videoRatio * realHeight;
            }
            
            self.vapView.frame = CGRectMake(0, 0, realWidth, realHeight);
            self.vapView.center = self.center;
        }
            break;;
        default:
            break;
    }
}

- (void)p_setupContentModeWithVideoSize:(CGSize)videoSize {
    CGFloat realWidth = 0.;
    CGFloat realHeight = 0.;
    
    if (videoSize.width <= 0 || videoSize.height <= 0) {
        return;
    }
    
    CGFloat layoutWidth = self.bounds.size.width;
    CGFloat layoutHeight = self.bounds.size.height;
    
    CGFloat layoutRatio = self.bounds.size.width / self.bounds.size.height;
    CGFloat videoRatio = videoSize.width / videoSize.height;
    
    switch (self.contentMode) {
        case QGVAPWrapViewContentModeScaleToFill: {

        }
            break;
        case QGVAPWrapViewContentModeAspectFit: {
            if (layoutRatio < videoRatio) {
                realWidth = layoutWidth;
                realHeight = realWidth / videoRatio;
            } else {
                realHeight = layoutHeight;
                realWidth = videoRatio * realHeight;
            }
            
            self.vapView.frame = CGRectMake(0, 0, realWidth, realHeight);
            self.vapView.center = self.center;
        }
            break;;
        case QGVAPWrapViewContentModeAspectFill: {
            if (layoutRatio > videoRatio) {
                realWidth = layoutWidth;
                realHeight = realWidth / videoRatio;
            } else {
                realHeight = layoutHeight;
                realWidth = videoRatio * realHeight;
            }
            
            self.vapView.frame = CGRectMake(0, 0, realWidth, realHeight);
            self.vapView.center = self.center;
        }
            break;;
        default:
            break;
    }
}

#pragma mark -  mp4 hwd delegate

#pragma mark -- 播放流程
- (void)viewDidStartPlayMP4:(VAPView *)container {
    if ([self.delegate respondsToSelector:@selector(vapWrap_viewDidStartPlayMP4:)]) {
        [self.delegate vapWrap_viewDidStartPlayMP4:container];
    }
}

- (void)viewDidFinishPlayMP4:(NSInteger)totalFrameCount view:(UIView *)container {
    //note:在子线程被调用
    if ([self.delegate respondsToSelector:@selector(vapWrap_viewDidFinishPlayMP4:view:)]) {
        [self.delegate vapWrap_viewDidFinishPlayMP4:totalFrameCount view:container];
    }
}

- (void)viewDidPlayMP4AtFrame:(QGMP4AnimatedImageFrame *)frame view:(UIView *)container {
    //note:在子线程被调用
    if ([self.delegate respondsToSelector:@selector(vapWrap_viewDidPlayMP4AtFrame:view:)]) {
        [self.delegate vapWrap_viewDidPlayMP4AtFrame:frame view:container];
    }
}

- (void)viewDidStopPlayMP4:(NSInteger)lastFrameIndex view:(UIView *)container {
    //note:在子线程被调用
    if ([self.delegate respondsToSelector:@selector(vapWrap_viewDidStopPlayMP4:view:)]) {
        [self.delegate vapWrap_viewDidStopPlayMP4:lastFrameIndex view:container];
    }
    
    dispatch_async(dispatch_get_main_queue(), ^{
        if (self.autoDestoryAfterFinish) {
            [self.vapView removeFromSuperview];
            self.vapView = nil;
        }
    });
}

- (BOOL)shouldStartPlayMP4:(VAPView *)container config:(QGVAPConfigModel *)config {
    
    if (config) {
        // vap 资源
        [self p_setupContentModeWithConfig:config];
        
        if ([self.delegate respondsToSelector:@selector(vapWrap_viewshouldStartPlayMP4:config:)]) {
            return [self.delegate vapWrap_viewshouldStartPlayMP4:container config:config];
        }
    } else {
        // 非 vap 资源
        // 对于不含 vapc box 的视频，config 可能为 nil，需要从 VAPView 获取视频尺寸
        CGSize videoSize = CGSizeZero;
        
        if (config && config.info && config.info.size.width > 0 && config.info.size.height > 0) {
            // 如果有有效的 config，使用 config 中的尺寸
            videoSize = config.info.size;
        } else {
            // 对于不含 vapc box 的视频，使用 mp4Parser 中的尺寸信息
            QGMP4HWDFileInfo *fileInfo = [container valueForKey:@"hwd_fileInfo"];
            if (fileInfo && fileInfo.mp4Parser) {
                videoSize = CGSizeMake(fileInfo.mp4Parser.picWidth, fileInfo.mp4Parser.picHeight);
            }
        }
        
        // 根据 QGHWDTextureBlendMode 混合模式调整 videoSize
        // 对于左右采样模式，alpha 和 RGB 各占一半，实际有效内容宽度减半
        // 对于上下采样模式，alpha 和 RGB 各占一半，实际有效内容高度减半
        QGHWDTextureBlendMode blendMode = QGHWDTextureBlendMode_AlphaLeft;
        
        // 尝试从容器中获取当前设置的混合模式
        id blendModeValue = [container valueForKey:@"hwd_blendMode"];
        if (blendModeValue && [blendModeValue isKindOfClass:[NSNumber class]]) {
            blendMode = [blendModeValue integerValue];
        }
        
        // 根据混合模式调整视频尺寸
        if (blendMode == QGHWDTextureBlendMode_AlphaLeft ||
            blendMode == QGHWDTextureBlendMode_AlphaRight) {
            // 左右采样：alpha 在左/右，RGB 在右/左，各占一半宽度
            videoSize = CGSizeMake(videoSize.width / 2.0, videoSize.height);
        } else if (blendMode == QGHWDTextureBlendMode_AlphaTop ||
                   blendMode == QGHWDTextureBlendMode_AlphaBottom) {
            // 上下采样：alpha 在上/下，RGB 在下/上，各占一半高度
            videoSize = CGSizeMake(videoSize.width, videoSize.height / 2.0);
        }
        
        [self p_setupContentModeWithVideoSize:videoSize];
        
        if ([self.delegate respondsToSelector:@selector(vapWrap_viewshouldStartPlayMP4:config:)]) {
            return [self.delegate vapWrap_viewshouldStartPlayMP4:container config:config];
        }
    }
    
    return YES;
}

- (void)viewDidFailPlayMP4:(NSError *)error {
    if ([self.delegate respondsToSelector:@selector(vapWrap_viewDidFailPlayMP4:)]) {
        [self.delegate vapWrap_viewDidFailPlayMP4:error];
    }
}

#pragma mark -- 融合特效的接口 vapx

//provide the content for tags, maybe text or url string ...
- (NSString *)contentForVapTag:(NSString *)tag resource:(QGVAPSourceInfo *)info {
    if ([self.delegate respondsToSelector:@selector(vapWrapview_contentForVapTag:resource:)]) {
        return [self.delegate vapWrapview_contentForVapTag:tag resource:info];
    }
    
    return nil;
}

//provide image for url from tag content
- (void)loadVapImageWithURL:(NSString *)urlStr context:(NSDictionary *)context completion:(VAPImageCompletionBlock)completionBlock {
    if ([self.delegate respondsToSelector:@selector(vapWrapView_loadVapImageWithURL:context:completion:)]) {
        [self.delegate vapWrapView_loadVapImageWithURL:urlStr context:context completion:completionBlock];
    }
}

@end
