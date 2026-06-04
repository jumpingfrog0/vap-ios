// QGVAPMetalView.m
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

#import "QGVAPMetalView.h"
#import "QGVAPMetalRenderer.h"
#import "QGHWDMetalRenderer.h"
#import "QGVAPLogger.h"

@interface QGVAPMetalRenderer (QGVAPRenderRuntime)
- (void)qgvap_prepareForRendering;
@end

@interface QGVAPMetalView ()

@property (nonatomic, strong) QGVAPCommonInfo *commonInfo;
@property (nonatomic, strong) QGVAPMaskInfo *maskInfo;
@property (nonatomic, strong) CAMetalLayer       *metalLayer;
@property (nonatomic, strong) QGVAPMetalRenderer *renderer;
@property (atomic, assign) BOOL                  renderable;
@property (nonatomic, strong) QGVAPCommonInfo    *pendingCommonInfo;
@property (nonatomic, strong) QGVAPMaskInfo      *pendingMaskInfo;

@end

#if TARGET_OS_SIMULATOR && defined(QGVAP_DISABLE_METAL_ON_SIMULATOR)//模拟器

@implementation QGVAPMetalView

- (void)display:(CVPixelBufferRef)pixelBuffer mergeInfos:(NSArray<QGVAPMergedInfo *> *)infos {}

- (void)dispose {}

- (void)qgvap_prepareForRendering {}

@end

#else

@implementation QGVAPMetalView

#pragma mark - override

+ (Class)layerClass {
    return [CAMetalLayer class];
}

- (instancetype)initWithCoder:(NSCoder *)aDecoder {
    NSAssert(0, @"initWithCoder: has not been implemented");
    if (self = [super initWithCoder:aDecoder]) {
    }
    return self;
}

- (instancetype)initWithFrame:(CGRect)frame {
    
    if (self = [super initWithFrame:frame]) {
        _metalLayer = (CAMetalLayer *)self.layer;
        _metalLayer.frame = self.frame;
        _metalLayer.opaque = NO;
        if (!kQGHWDMetalRendererDevice) {
            kQGHWDMetalRendererDevice = MTLCreateSystemDefaultDevice();
        }
        _metalLayer.device = kQGHWDMetalRendererDevice;
        _metalLayer.contentsScale = [UIScreen mainScreen].scale;
        _metalLayer.pixelFormat = MTLPixelFormatBGRA8Unorm;
        _metalLayer.framebufferOnly = YES;
        [self updateMetalDrawableState];
    }
    return self;
}

- (void)didMoveToWindow {
    [super didMoveToWindow];
    [self updateMetalDrawableState];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    [self updateMetalDrawableState];
}

- (void)dealloc {
    [self dispose];
}

#pragma mark - getter&setter

- (QGVAPCommonInfo *)commonInfo {
    return self.pendingCommonInfo;
}

- (void)setCommonInfo:(QGVAPCommonInfo *)commonInfo {
    self.pendingCommonInfo = commonInfo;
    [self.renderer setCommonInfo:commonInfo];
}

- (void)setMaskInfo:(QGVAPMaskInfo *)maskInfo {
    self.pendingMaskInfo = maskInfo;
    [self.renderer setMaskInfo:maskInfo];
}

#pragma mark - main

- (void)display:(CVPixelBufferRef)pixelBuffer mergeInfos:(NSArray<QGVAPMergedInfo *> *)infos {
    
    if (!self.renderable) {
        VAP_Event(kQGVAPModuleCommon, @"quit display pixelbuffer, cuz window is nil!");
        return ;
    }
    [self qgvap_prepareForRendering];
    [self.renderer renderPixelBuffer:pixelBuffer metalLayer:self.metalLayer mergeInfos:infos];
}

- (void)dispose {
    [self.renderer dispose];
}

#pragma mark - private

- (void)qgvap_notifyViewUnavailable {
    
    id<QGVAPMetalViewDelegate> delegate = self.delegate;
    if ([delegate respondsToSelector:@selector(qgvap_renderViewDidBecomeUnavailable)]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [delegate qgvap_renderViewDidBecomeUnavailable];
        });
    }
}

- (void)updateMetalDrawableState {
    CGFloat nativeScale = [UIScreen mainScreen].nativeScale;
    CGSize drawableSize = CGSizeMake(CGRectGetWidth(self.bounds) * nativeScale, CGRectGetHeight(self.bounds) * nativeScale);
    BOOL renderable = (self.window != nil && drawableSize.width > 0 && drawableSize.height > 0);
    self.metalLayer.drawableSize = drawableSize;
    self.renderable = renderable;
    if (renderable) {
        VAP_Event(kQGVAPModuleCommon, @"update drawablesize :%@", [NSValue valueWithCGSize:drawableSize]);
    }
}

- (void)qgvap_prepareForRendering {
    if (self.renderer) {
        [self.renderer qgvap_prepareForRendering];
        return;
    }
    @synchronized (self) {
        if (!self.renderer) {
            self.renderer = [[QGVAPMetalRenderer alloc] initWithMetalLayer:self.metalLayer];
            self.renderer.commonInfo = self.pendingCommonInfo;
            self.renderer.maskInfo = self.pendingMaskInfo;
            [self.renderer qgvap_prepareForRendering];
        }
    }
}

@end

#endif
