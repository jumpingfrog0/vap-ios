// QGVAPOpenGLFrameRenderer.m
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
#import "QGHWDMP4OpenGLView.h"
#import "QGVAPConfigModel.h"

@interface QGHWDMP4OpenGLView (QGVAPFrameRendererPrepare)
- (void)qgvap_applyCommonInfo:(QGVAPCommonInfo *)commonInfo blendMode:(QGHWDTextureBlendMode)blendMode;
- (BOOL)qgvap_prepareForRendering;
- (void)qgvap_renderPixelBuffer:(CVPixelBufferRef)pixelBuffer;
- (void)setPause:(BOOL)pause;
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

@interface QGVAPOpenGLFrameRenderer : NSObject <QGVAPFrameRenderer, QGHWDMP4OpenGLViewDelegate>

@property (nonatomic, strong) QGHWDMP4OpenGLView *openGLView;
@property (nonatomic, weak) id<QGVAPFrameRendererDelegate> delegate;
@property (nonatomic, assign) QGHWDTextureBlendMode blendMode;

@end

@implementation QGVAPOpenGLFrameRenderer

- (instancetype)initWithConfiguration:(QGVAPFrameRendererConfiguration *)configuration {
    self = [super init];
    if (self) {
        UIView *container = configuration.container;
        _openGLView = [[QGHWDMP4OpenGLView alloc] initWithFrame:container.bounds];
        _openGLView.displayDelegate = self;
        _delegate = configuration.delegate;
        _openGLView.userInteractionEnabled = NO;
        [self applyConfiguration:configuration];
        QGVAPAddRenderViewToContainer(_openGLView, container, @"openGLView");
    }
    return self;
}

- (QGVAPFrameRendererType)rendererType {
    return QGVAPFrameRendererTypeOpenGL;
}

- (UIView *)renderView {
    return self.openGLView;
}

- (void)applyConfiguration:(QGVAPFrameRendererConfiguration *)configuration {
    self.delegate = configuration.delegate;
    self.openGLView.displayDelegate = self;
    self.blendMode = configuration.blendMode;
    [self.openGLView qgvap_applyCommonInfo:configuration.commonInfo blendMode:self.blendMode];
}

- (void)prepareResources {}

- (void)prepareForRendering {
    [self.openGLView qgvap_prepareForRendering];
}

- (void)renderWithContext:(QGVAPFrameRenderContext *)context {
    [self.openGLView qgvap_renderPixelBuffer:context.pixelBuffer];
}

- (void)pause {
    self.openGLView.pause = YES;
}

- (void)resume {
    self.openGLView.pause = NO;
}

- (void)dispose {
    [self.openGLView dispose];
}

- (void)qgvap_renderViewDidBecomeUnavailable {
    [self.delegate frameRendererDidBecomeUnavailable:self];
}

@end
