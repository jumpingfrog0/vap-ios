// QGVAPVAPMetalFrameRenderer.m
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
#import "QGVAPMetalView.h"
#import "QGVAPMaskInfo.h"
#import "QGVAPConfigManager.h"
#import "QGHWDMetalRenderer.h"

@interface QGVAPConfigManager (QGVAPRendererResources)
- (void)loadMTLTextures:(id<MTLDevice>)device;
- (void)loadMTLBuffers:(id<MTLDevice>)device;
@end

@interface QGVAPMetalView (QGVAPFrameRendererPrepare)
@property (nonatomic, strong) QGVAPCommonInfo *commonInfo;
@property (nonatomic, strong) QGVAPMaskInfo *maskInfo;
- (void)qgvap_prepareForRendering;
- (void)display:(CVPixelBufferRef)pixelBuffer mergeInfos:(NSArray<QGVAPMergedInfo *> *)infos;
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

@interface QGVAPVAPMetalFrameRenderer : NSObject <QGVAPFrameRenderer, QGVAPMetalViewDelegate>

@property (nonatomic, strong) QGVAPMetalView *metalView;
@property (nonatomic, strong) QGVAPConfigManager *configManager;
@property (nonatomic, weak) id<QGVAPFrameRendererDelegate> delegate;

@end

@implementation QGVAPVAPMetalFrameRenderer

- (instancetype)initWithConfiguration:(QGVAPFrameRendererConfiguration *)configuration {
    self = [super init];
    if (self) {
        UIView *container = configuration.container;
        _metalView = [[QGVAPMetalView alloc] initWithFrame:container.bounds];
        _metalView.commonInfo = configuration.commonInfo;
        _metalView.maskInfo = configuration.maskInfo;
        _metalView.delegate = self;
        _configManager = configuration.configManager;
        _delegate = configuration.delegate;
        QGVAPAddRenderViewToContainer(_metalView, container, @"vapMetalView");
    }
    return self;
}

- (QGVAPFrameRendererType)rendererType {
    return QGVAPFrameRendererTypeVAPMetal;
}

- (UIView *)renderView {
    return self.metalView;
}

- (void)applyConfiguration:(QGVAPFrameRendererConfiguration *)configuration {
    self.configManager = configuration.configManager;
    self.metalView.commonInfo = configuration.commonInfo;
    self.metalView.maskInfo = configuration.maskInfo;
    self.metalView.delegate = self;
    self.delegate = configuration.delegate;
}

- (void)prepareResources {
    [self.configManager loadMTLTextures:kQGHWDMetalRendererDevice];
    [self.configManager loadMTLBuffers:kQGHWDMetalRendererDevice];
}

- (void)prepareForRendering {
    [self.metalView qgvap_prepareForRendering];
}

- (void)renderWithContext:(QGVAPFrameRenderContext *)context {
    [self.metalView display:context.pixelBuffer mergeInfos:context.mergeInfos];
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
