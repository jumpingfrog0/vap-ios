// QGHWDMetalView.m
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

#import "QGHWDMetalView.h"
#import "QGVAPLogger.h"
#import "QGHWDMetalRenderer.h"

@interface QGHWDMetalView ()

@property (nonatomic, strong) CAMetalLayer          *metalLayer;
@property (nonatomic, strong) QGHWDMetalRenderer    *renderer;
@property (nonatomic, assign) QGHWDTextureBlendMode blendMode;
@property (atomic, assign) BOOL                     renderable;

@end

#if TARGET_OS_SIMULATOR && defined(QGVAP_DISABLE_METAL_ON_SIMULATOR)//模拟器

@implementation QGHWDMetalView

- (instancetype)initWithFrame:(CGRect)frame blendMode:(QGHWDTextureBlendMode)mode {
    return [self initWithFrame:frame];
}

- (void)display:(CVPixelBufferRef)pixelBuffer {}

-(void)dispose {}

- (void)qgvap_prepareForRendering {}

@end

#else

@implementation QGHWDMetalView

#pragma mark - override

+ (Class)layerClass {
    return [CAMetalLayer class];
}

- (instancetype)initWithCoder:(NSCoder *)aDecoder {
    NSAssert(0, @"initWithCoder: has not been implemented");
    return nil;
}

- (instancetype)initWithFrame:(CGRect)frame {
    
    if (self = [super initWithFrame:frame]) {
        _blendMode = QGHWDTextureBlendMode_AlphaLeft;
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

#pragma mark - main

- (instancetype)initWithFrame:(CGRect)frame blendMode:(QGHWDTextureBlendMode)mode {
    
    if (self = [super initWithFrame:frame]) {
        _blendMode = QGHWDTextureBlendMode_AlphaLeft;
        _metalLayer = (CAMetalLayer *)self.layer;
        _metalLayer.frame = self.frame;
        _metalLayer.opaque = NO;
        _blendMode = mode;
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

- (void)display:(CVPixelBufferRef)pixelBuffer {
    if (!self.renderable) {
        VAP_Event(kQGVAPModuleCommon, @"quit display pixelbuffer, cuz window is nil!");
        return ;
    }
    [self qgvap_prepareForRendering];
    self.renderer.blendMode = self.blendMode;
    [self.renderer renderPixelBuffer:pixelBuffer metalLayer:self.metalLayer];
}

/**
 资源回收
 */
- (void)dispose {
    [self.renderer dispose];
}

#pragma mark - private

- (void)qgvap_notifyViewUnavailable {
    
    id<QGHWDMetelViewDelegate> delegate = self.delegate;
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
        return;
    }
    @synchronized (self) {
        if (!self.renderer) {
            self.renderer = [[QGHWDMetalRenderer alloc] initWithMetalLayer:self.metalLayer blendMode:self.blendMode];
        }
    }
}

@end

#endif
