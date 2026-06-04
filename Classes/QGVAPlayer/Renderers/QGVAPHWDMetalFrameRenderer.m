// QGVAPHWDMetalFrameRenderer.m
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

#import "QGVAPFrameRenderer.h"
#import "QGHWDMetalView.h"
#import "QGVAPConfigModel.h"

@interface QGHWDMetalView (QGVAPFrameRendererPrepare)
- (instancetype)initWithFrame:(CGRect)frame blendMode:(QGHWDTextureBlendMode)mode;
- (void)setBlendMode:(QGHWDTextureBlendMode)blendMode;
- (void)qgvap_prepareForRendering;
- (void)display:(CVPixelBufferRef)pixelBuffer;
@end

static void QGVAPAddRenderViewToContainer(UIView *renderView, UIView *container, NSString *name) {
    if (!renderView || !container || name.length == 0) {
        return;
    }
    [container addSubview:renderView];
    renderView.translatesAutoresizingMaskIntoConstraints = NO;
    NSDictionary *views = @{name: renderView};
    [container addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:[NSString stringWithFormat:@"V:|[%@]|", name] options:0 metrics:nil views:views]];
    [container addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:[NSString stringWithFormat:@"H:|[%@]|", name] options:0 metrics:nil views:views]];
}

@interface QGVAPHWDMetalFrameRenderer : NSObject <QGVAPFrameRenderer, QGHWDMetelViewDelegate>

@property (nonatomic, strong) QGHWDMetalView *metalView;
@property (nonatomic, weak) id<QGVAPFrameRendererDelegate> delegate;
@property (nonatomic, assign) QGHWDTextureBlendMode blendMode;

@end

@implementation QGVAPHWDMetalFrameRenderer

- (instancetype)initWithConfiguration:(QGVAPFrameRendererConfiguration *)configuration {
    self = [super init];
    if (self) {
        UIView *container = configuration.container;
        _metalView = [[QGHWDMetalView alloc] initWithFrame:container.bounds blendMode:configuration.blendMode];
        _metalView.delegate = self;
        _delegate = configuration.delegate;
        [self applyConfiguration:configuration];
        QGVAPAddRenderViewToContainer(_metalView, container, @"metalView");
    }
    return self;
}

- (QGVAPFrameRendererType)rendererType {
    return QGVAPFrameRendererTypeHWDMetal;
}

- (UIView *)renderView {
    return self.metalView;
}

- (void)applyConfiguration:(QGVAPFrameRendererConfiguration *)configuration {
    self.blendMode = configuration.blendMode;
    self.metalView.blendMode = self.blendMode;
    self.metalView.delegate = self;
    self.delegate = configuration.delegate;
}

- (void)prepareResources {}

- (void)prepareForRendering {
    [self.metalView qgvap_prepareForRendering];
}

- (void)renderWithContext:(QGVAPFrameRenderContext *)context {
    [self.metalView display:context.pixelBuffer];
}

- (void)pause {}

- (void)resume {}

- (void)dispose {
    [self.metalView dispose];
}

- (void)qgvap_renderViewDidBecomeUnavailable {
    [self.delegate frameRendererDidBecomeUnavailable:self];
}

@end
