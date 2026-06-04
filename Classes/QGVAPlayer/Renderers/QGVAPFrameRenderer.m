// QGVAPFrameRenderer.m
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
#import "QGHWDMetalView.h"
#import "QGVAPMetalView.h"
#import "QGVAPMaskInfo.h"

@implementation QGVAPFrameRenderContext

@end

@implementation QGVAPFrameRendererConfiguration

@end

@interface QGVAPOpenGLFrameRenderer : NSObject <QGVAPFrameRenderer>
- (instancetype)initWithConfiguration:(QGVAPFrameRendererConfiguration *)configuration;
@end

@interface QGVAPHWDMetalFrameRenderer : NSObject <QGVAPFrameRenderer>
- (instancetype)initWithConfiguration:(QGVAPFrameRendererConfiguration *)configuration;
@end

@interface QGVAPVAPMetalFrameRenderer : NSObject <QGVAPFrameRenderer>
- (instancetype)initWithConfiguration:(QGVAPFrameRendererConfiguration *)configuration;
@end

id<QGVAPFrameRenderer> QGVAPCreateFrameRenderer(QGVAPFrameRendererConfiguration *configuration) {
    switch (configuration.rendererType) {
        case QGVAPFrameRendererTypeOpenGL:
            return [[QGVAPOpenGLFrameRenderer alloc] initWithConfiguration:configuration];
        case QGVAPFrameRendererTypeHWDMetal:
            return [[QGVAPHWDMetalFrameRenderer alloc] initWithConfiguration:configuration];
        case QGVAPFrameRendererTypeVAPMetal:
            return [[QGVAPVAPMetalFrameRenderer alloc] initWithConfiguration:configuration];
    }
}
