// QGVAPFrameRenderer.h
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
#import "UIView+VAP.h"

@class QGVAPCommonInfo;
@class QGVAPMaskInfo;
@class QGVAPMergedInfo;
@class QGVAPConfigManager;
@protocol QGVAPFrameRenderer;

typedef NS_ENUM(NSInteger, QGVAPFrameRendererType) {
    QGVAPFrameRendererTypeOpenGL,
    QGVAPFrameRendererTypeHWDMetal,
    QGVAPFrameRendererTypeVAPMetal,
};

@interface QGVAPFrameRenderContext : NSObject

@property (nonatomic, assign) CVPixelBufferRef pixelBuffer;
@property (nonatomic, copy) NSArray<QGVAPMergedInfo *> *mergeInfos;

@end

@interface QGVAPFrameRendererConfiguration : NSObject

@property (nonatomic, assign) QGVAPFrameRendererType rendererType;
@property (nonatomic, weak) UIView *container;
@property (nonatomic, assign) QGHWDTextureBlendMode blendMode;
@property (nonatomic, strong) QGVAPCommonInfo *commonInfo;
@property (nonatomic, strong) QGVAPMaskInfo *maskInfo;
@property (nonatomic, strong) QGVAPConfigManager *configManager;
@property (nonatomic, weak) id delegate;

@end

@protocol QGVAPFrameRendererDelegate <NSObject>

- (void)frameRendererDidBecomeUnavailable:(id<QGVAPFrameRenderer>)renderer;

@end

@protocol QGVAPFrameRenderer <NSObject>

@property (nonatomic, assign, readonly) QGVAPFrameRendererType rendererType;
@property (nonatomic, strong, readonly) UIView *renderView;

- (void)applyConfiguration:(QGVAPFrameRendererConfiguration *)configuration;
- (void)prepareResources;
- (void)prepareForRendering;
- (void)renderWithContext:(QGVAPFrameRenderContext *)context;
- (void)pause;
- (void)resume;
- (void)dispose;

@end

FOUNDATION_EXPORT id<QGVAPFrameRenderer> QGVAPCreateFrameRenderer(QGVAPFrameRendererConfiguration *configuration);
