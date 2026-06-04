// QGHWDMP4OpenGLView.m
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

#import "QGHWDMP4OpenGLView.h"
#import <QuartzCore/QuartzCore.h>
#import <AVFoundation/AVUtilities.h>
#import <mach/mach_time.h>
#import <GLKit/GLKit.h>
#import <string.h>
#import "VAPMacros.h"
#import "QGVAPConfigModel.h"

// Uniform index.
enum {
    HWD_UNIFORM_Y,
    HWD_UNIFORM_UV,
    HWD_UNIFORM_COLOR_CONVERSION_MATRIX,
    HWD_UNIFORM_ALPHA_CONVERSION,
    HWD_NUM_UNIFORMS
};
GLint hwd_uniforms[HWD_NUM_UNIFORMS];

// Attribute index.
enum {
    ATTRIB_VERTEX,
    ATTRIB_TEXCOORD_RGB,
    ATTRIB_TEXCOORD_ALPHA,
    NUM_ATTRIBUTES
};

// BT.709-HDTV.
static const GLfloat kQGColorConversion709[] = {
    1.164,  1.164, 1.164,
    0.0, -0.213, 2.112,
    1.793, -0.533,   0.0,
};

// BT.601 full range-http://www.equasys.de/colorconversion.html
const GLfloat kQGColorConversion601FullRange[] = {
    1.0,    1.0,    1.0,
    0.0,    -0.343, 1.765,
    1.4,    -0.711, 0.0,
};

// BT.709 full range.
const GLfloat kQGColorConversion709FullRange[] = {
    1.0,       1.0,      1.0,
    0.0,      -0.18732,  1.8556,
    1.57481, -0.46813,  0.0,
};

static const GLfloat kQGAlphaConversionFullRange[] = {1.0, 0.0};
static const GLfloat kQGAlphaConversionVideoRange[] = {255.0 / 219.0, -16.0 / 219.0};

// texture coords for blend

const GLfloat textureCoordLeft[] =  { // 左侧
    0.5, 0.0,
    0.0, 0.0,
    0.5, 1.0,
    0.0, 1.0
};

const GLfloat textureCoordRight[] =  { // 右侧
    1.0, 0.0,
    0.5, 0.0,
    1.0, 1.0,
    0.5, 1.0
};

const GLfloat textureCoordTop[] =  { // 上侧
    1.0, 0.0,
    0.0, 0.0,
    1.0, 0.5,
    0.0, 0.5
};

const GLfloat textureCoordBottom[] =  { // 下侧
    1.0, 0.5,
    0.0, 0.5,
    1.0, 1.0,
    0.0, 1.0
};

#undef cos
#undef sin
NSString *const kVertexShaderSource = SHADER_STRING
(
 attribute vec4 position;
 attribute vec2 RGBTexCoord;
 attribute vec2 alphaTexCoord;

 varying vec2 RGBTexCoordVarying;
 varying vec2 alphaTexCoordVarying;

 void main()
{
    float preferredRotation = 3.14;
    mat4 rotationMatrix = mat4(cos(preferredRotation), -sin(preferredRotation), 0.0, 0.0,sin(preferredRotation),cos(preferredRotation), 0.0, 0.0,0.0,0.0,1.0,0.0,0.0,0.0, 0.0,1.0);
    gl_Position = rotationMatrix * position;
    RGBTexCoordVarying = RGBTexCoord;
    alphaTexCoordVarying = alphaTexCoord;
}
 );

NSString *const kFragmentShaderSource = SHADER_STRING
(
 varying highp vec2 RGBTexCoordVarying;
 varying highp vec2 alphaTexCoordVarying;
 precision mediump float;

 uniform sampler2D SamplerY;
 uniform sampler2D SamplerUV;
 uniform mat3 colorConversionMatrix;
 uniform vec2 alphaConversion;

 void main()
{
    mediump vec3 yuv_rgb;
    lowp vec3 rgb_rgb;

    lowp float alpha;

    // Subtract constants to map the video range start at 0
    yuv_rgb.x = (texture2D(SamplerY, RGBTexCoordVarying).r);// - (16.0/255.0));
    yuv_rgb.yz = (texture2D(SamplerUV, RGBTexCoordVarying).ra - vec2(0.5, 0.5));

    rgb_rgb = colorConversionMatrix * yuv_rgb;

    alpha = clamp(texture2D(SamplerY, alphaTexCoordVarying).r * alphaConversion.x + alphaConversion.y, 0.0, 1.0);
    gl_FragColor = vec4(rgb_rgb, alpha);
    //    gl_FragColor = vec4(1, 0, 0, 1);
}
 );


@interface QGHWDMP4OpenGLView() {

    GLint _backingWidth;
    GLint _backingHeight;
    CVOpenGLESTextureRef _lumaTexture;
    CVOpenGLESTextureRef _chromaTexture;
    CVOpenGLESTextureCacheRef _textureCache;
    GLuint _fallbackLumaTextureName;
    GLuint _fallbackChromaTextureName;
    BOOL _usesTextureUploadFallback;
    GLuint _frameBufferHandle;
    GLuint _colorBufferHandle;
    const GLfloat *_preferredConversion;
    const GLfloat *_preferredAlphaConversion;
    GLfloat _vapRGBTextureCoordinates[8];
    GLfloat _vapAlphaTextureCoordinates[8];
}

@property GLuint program;
@property (nonatomic, assign) QGHWDTextureBlendMode blendMode;
@property (nonatomic, strong) QGVAPCommonInfo *commonInfo;
@property (nonatomic, assign) BOOL pause;
@property (atomic, assign) BOOL renderable;
@property (atomic, assign) BOOL backingSizeNeedsUpdate;
@property (atomic, assign) BOOL renderingPrepared;
@property (atomic, assign) BOOL surfaceSizeUpdateScheduled;

- (void)setupBuffers;
- (void)cleanupTextures;
- (void)updatePixelBufferProperties:(CVPixelBufferRef)pixelBuffer;
- (BOOL)updateTexturesWithPixelBuffer:(CVPixelBufferRef)pixelBuffer;
- (BOOL)updateTexturesFromCacheWithPixelBuffer:(CVPixelBufferRef)pixelBuffer;
- (BOOL)uploadTexturesWithPixelBuffer:(CVPixelBufferRef)pixelBuffer;

- (BOOL)isValidateProgram:(GLuint)prog;

- (BOOL)loadShaders;
- (BOOL)compileShader:(GLuint *)shader type:(GLenum)type URL:(NSURL *)URL;
- (BOOL)linkProgram:(GLuint)prog;
- (void)qgvap_applyCommonInfo:(QGVAPCommonInfo *)commonInfo blendMode:(QGHWDTextureBlendMode)blendMode;
- (BOOL)qgvap_prepareForRendering;
- (void)qgvap_renderPixelBuffer:(CVPixelBufferRef)pixelBuffer;
- (void)qgvap_updateSurfaceSizeIfNeeded;
- (void)qgvap_updateDrawableState;
- (void)qgvap_notifyViewUnavailable;

@end

@implementation QGHWDMP4OpenGLView

+ (Class)layerClass {

    return [CAEAGLLayer class];
}

- (id)initWithCoder:(NSCoder *)aDecoder {
    if ((self = [super initWithCoder:aDecoder])) {
        if (![self commonInit]) {
            return  nil;
        }
    }
    return self;
}

- (instancetype)init {

    if (self = [super init]) {
        if (![self commonInit]) {
            return  nil;
        }
    }
    return self;
}

- (instancetype)initWithFrame:(CGRect)frame {

    if (self = [super initWithFrame:frame]) {
        if (![self commonInit]) {
            return  nil;
        }
    }
    return self;
}

- (BOOL)commonInit {

    self.contentScaleFactor = [[UIScreen mainScreen] scale];
    CAEAGLLayer *eaglLayer = (CAEAGLLayer *)self.layer;
    eaglLayer.opaque = NO;
    eaglLayer.drawableProperties = @{ kEAGLDrawablePropertyRetainedBacking :[NSNumber numberWithBool:NO],
                                      kEAGLDrawablePropertyColorFormat : kEAGLColorFormatRGBA8};
    _preferredConversion = kQGColorConversion601FullRange;
    _preferredAlphaConversion = kQGAlphaConversionFullRange;
    _backingSizeNeedsUpdate = YES;
    [self qgvap_updateDrawableState];
    return YES;
}

- (void)dealloc {

    [self dispose];
}

- (void)didMoveToWindow {

    [super didMoveToWindow];
    [self qgvap_updateDrawableState];
}

# pragma mark - OpenGL setup
- (void)qgvap_applyCommonInfo:(QGVAPCommonInfo *)commonInfo blendMode:(QGHWDTextureBlendMode)blendMode {
    self.commonInfo = commonInfo;
    self.blendMode = blendMode;
    self.pause = NO;
}

- (BOOL)qgvap_prepareForRendering {

    if (!self.renderable) {
        return NO;
    }

    if (self.renderingPrepared) {
        if ([EAGLContext currentContext] != _glContext) {
            [EAGLContext setCurrentContext:_glContext];
        }
        [self qgvap_updateSurfaceSizeIfNeeded];
        return YES;
    }

    @synchronized (self) {
        if (self.renderingPrepared) {
            if ([EAGLContext currentContext] != _glContext) {
                [EAGLContext setCurrentContext:_glContext];
            }
            [self qgvap_updateSurfaceSizeIfNeeded];
            return YES;
        }

        VAP_Info(kQGVAPModuleCommon, @"prepare OpenGL renderer");
        _glContext = [[EAGLContext alloc] initWithAPI:kEAGLRenderingAPIOpenGLES2];
        if (!_glContext || ![EAGLContext setCurrentContext:_glContext] || ![self loadShaders]) {
            return NO;
        }
        [self setupBuffers];
        glUseProgram(self.program);
        glUniform1i(hwd_uniforms[HWD_UNIFORM_Y], 0);
        glUniform1i(hwd_uniforms[HWD_UNIFORM_UV], 1);
        glUniformMatrix3fv(hwd_uniforms[HWD_UNIFORM_COLOR_CONVERSION_MATRIX], 1, GL_FALSE, _preferredConversion);
        glUniform2fv(hwd_uniforms[HWD_UNIFORM_ALPHA_CONVERSION], 1, _preferredAlphaConversion);
        // Create CVOpenGLESTextureCacheRef for optimal CVPixelBufferRef to GLES texture conversion.
        if (!_textureCache) {
            CVReturn err = CVOpenGLESTextureCacheCreate(kCFAllocatorDefault, NULL, _glContext, NULL, &_textureCache);
            if (err != noErr) {
                VAP_Event(kQGVAPModuleCommon, @"Error at CVOpenGLESTextureCacheCreate %d", err);
                return NO;
            }
        }
        glClearColor(0.0f, 0.0f, 0.0f, 0.0f);
        self.renderingPrepared = YES;
    }
    return YES;
}

- (void)qgvap_updateSurfaceSizeIfNeeded {

    if (!self.backingSizeNeedsUpdate && _backingWidth > 0 && _backingHeight > 0) {
        return;
    }
    if (!self.renderable) {
        return;
    }
    if (!_glContext || _colorBufferHandle == 0) {
        return;
    }
    if (![NSThread isMainThread]) {
        if (self.surfaceSizeUpdateScheduled) {
            return;
        }
        self.surfaceSizeUpdateScheduled = YES;
        __weak typeof(self) weakSelf = self;
        dispatch_async(dispatch_get_main_queue(), ^{
            [weakSelf qgvap_updateSurfaceSizeIfNeeded];
        });
        return;
    }
    self.surfaceSizeUpdateScheduled = NO;
    [EAGLContext setCurrentContext:_glContext];
    glBindRenderbuffer(GL_RENDERBUFFER, _colorBufferHandle);
    [_glContext renderbufferStorage:GL_RENDERBUFFER fromDrawable:(CAEAGLLayer *)self.layer];
    glGetRenderbufferParameteriv(GL_RENDERBUFFER, GL_RENDERBUFFER_WIDTH, &_backingWidth);
    glGetRenderbufferParameteriv(GL_RENDERBUFFER, GL_RENDERBUFFER_HEIGHT, &_backingHeight);
    glBindFramebuffer(GL_FRAMEBUFFER, _frameBufferHandle);
    glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_RENDERBUFFER, _colorBufferHandle);
    if (glCheckFramebufferStatus(GL_FRAMEBUFFER) != GL_FRAMEBUFFER_COMPLETE) {
        VAP_Event(kQGVAPModuleCommon, @"Failed to make complete framebuffer object %x", glCheckFramebufferStatus(GL_FRAMEBUFFER));
    }
    self.backingSizeNeedsUpdate = NO;
}

#pragma mark - Utilities

- (void)setupBuffers {

    glDisable(GL_DEPTH_TEST);
    glEnableVertexAttribArray(ATTRIB_VERTEX);
    glVertexAttribPointer(ATTRIB_VERTEX, 2, GL_FLOAT, GL_FALSE, 2 * sizeof(GLfloat), 0);
    glEnableVertexAttribArray(ATTRIB_TEXCOORD_RGB);
    glVertexAttribPointer(ATTRIB_TEXCOORD_RGB, 2, GL_FLOAT, GL_FALSE, 2 * sizeof(GLfloat), 0);
    glEnableVertexAttribArray(ATTRIB_TEXCOORD_ALPHA);
    glVertexAttribPointer(ATTRIB_TEXCOORD_ALPHA, 2, GL_FLOAT, GL_FALSE, 2 * sizeof(GLfloat), 0);
    glGenFramebuffers(1, &_frameBufferHandle);
    glBindFramebuffer(GL_FRAMEBUFFER, _frameBufferHandle);
    glGenRenderbuffers(1, &_colorBufferHandle);
    glBindRenderbuffer(GL_RENDERBUFFER, _colorBufferHandle);
    self.backingSizeNeedsUpdate = YES;
}

- (void)layoutSubviews {

    [super layoutSubviews];
    [self qgvap_updateDrawableState];
}


- (void)cleanupTextures {

    if (_lumaTexture) {
        CFRelease(_lumaTexture);
        _lumaTexture = NULL;
    }
    if (_chromaTexture) {
        CFRelease(_chromaTexture);
        _chromaTexture = NULL;
    }
    if (_textureCache) {
        CVOpenGLESTextureCacheFlush(_textureCache, 0);
    }
}

- (void)updatePixelBufferProperties:(CVPixelBufferRef)pixelBuffer {

    _preferredConversion = kQGColorConversion601FullRange;
    CFTypeRef yCbCrMatrixType = CVBufferGetAttachment(pixelBuffer, kCVImageBufferYCbCrMatrixKey, NULL);
    if (yCbCrMatrixType && CFStringCompare(yCbCrMatrixType, kCVImageBufferYCbCrMatrix_ITU_R_709_2, 0) == kCFCompareEqualTo) {
        _preferredConversion = kQGColorConversion709FullRange;
    }

    _preferredAlphaConversion = kQGAlphaConversionFullRange;
    OSType pixelFormat = CVPixelBufferGetPixelFormatType(pixelBuffer);
    if (pixelFormat == kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange ||
        pixelFormat == kCVPixelFormatType_420YpCbCr8Planar) {
        _preferredAlphaConversion = kQGAlphaConversionVideoRange;
    }
}

- (BOOL)updateTexturesWithPixelBuffer:(CVPixelBufferRef)pixelBuffer {

#if TARGET_OS_SIMULATOR
    _usesTextureUploadFallback = YES;
    return [self uploadTexturesWithPixelBuffer:pixelBuffer];
#else
    if (_usesTextureUploadFallback) {
        return [self uploadTexturesWithPixelBuffer:pixelBuffer];
    }
    if ([self updateTexturesFromCacheWithPixelBuffer:pixelBuffer]) {
        _usesTextureUploadFallback = NO;
        return YES;
    }
    if (!_usesTextureUploadFallback) {
        VAP_Event(kQGVAPModuleCommon, @"CVOpenGLESTextureCacheCreateTextureFromImage failed, fallback to pixel buffer plane upload");
    }
    _usesTextureUploadFallback = YES;
    [self cleanupTextures];
    return [self uploadTexturesWithPixelBuffer:pixelBuffer];
#endif
}

- (BOOL)updateTexturesFromCacheWithPixelBuffer:(CVPixelBufferRef)pixelBuffer {

    if (CVPixelBufferGetPlaneCount(pixelBuffer) < 2) {
        return NO;
    }
    size_t yWidth = CVPixelBufferGetWidthOfPlane(pixelBuffer, 0);
    size_t yHeight = CVPixelBufferGetHeightOfPlane(pixelBuffer, 0);
    size_t uvWidth = CVPixelBufferGetWidthOfPlane(pixelBuffer, 1);
    size_t uvHeight = CVPixelBufferGetHeightOfPlane(pixelBuffer, 1);
    if (yWidth == 0 || yHeight == 0 || uvWidth == 0 || uvHeight == 0) {
        return NO;
    }

    glActiveTexture(GL_TEXTURE0);
    CVReturn yErr = CVOpenGLESTextureCacheCreateTextureFromImage(kCFAllocatorDefault,
                                                                 _textureCache,
                                                                 pixelBuffer,
                                                                 NULL,
                                                                 GL_TEXTURE_2D,
                                                                 GL_LUMINANCE,
                                                                 (GLsizei)yWidth,
                                                                 (GLsizei)yHeight,
                                                                 GL_LUMINANCE,
                                                                 GL_UNSIGNED_BYTE,
                                                                 0,
                                                                 &_lumaTexture);
    if (yErr || !_lumaTexture) {
        VAP_Event(kQGVAPModuleCommon, @"Error at CVOpenGLESTextureCacheCreateTextureFromImage y:%d", yErr);
        return NO;
    }

    glBindTexture(CVOpenGLESTextureGetTarget(_lumaTexture), CVOpenGLESTextureGetName(_lumaTexture));
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
    glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);

    glActiveTexture(GL_TEXTURE1);
    CVReturn uvErr = CVOpenGLESTextureCacheCreateTextureFromImage(kCFAllocatorDefault,
                                                                  _textureCache,
                                                                  pixelBuffer,
                                                                  NULL,
                                                                  GL_TEXTURE_2D,
                                                                  GL_LUMINANCE_ALPHA,
                                                                  (GLsizei)uvWidth,
                                                                  (GLsizei)uvHeight,
                                                                  GL_LUMINANCE_ALPHA,
                                                                  GL_UNSIGNED_BYTE,
                                                                  1,
                                                                  &_chromaTexture);
    if (uvErr || !_chromaTexture) {
        VAP_Error(kQGVAPModuleCommon, @"Error at CVOpenGLESTextureCacheCreateTextureFromImage uv:%d", uvErr);
        return NO;
    }

    glBindTexture(CVOpenGLESTextureGetTarget(_chromaTexture), CVOpenGLESTextureGetName(_chromaTexture));
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
    glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
    return YES;
}

- (void)configureFallbackTexture:(GLuint *)textureName textureUnit:(GLenum)textureUnit {

    glActiveTexture(textureUnit);
    if (*textureName == 0) {
        glGenTextures(1, textureName);
    }
    glBindTexture(GL_TEXTURE_2D, *textureName);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
    glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
}

- (void *)copyPlane:(CVPixelBufferRef)pixelBuffer
              index:(size_t)planeIndex
         bytesPerRow:(size_t)bytesPerRow
            rowBytes:(size_t)rowBytes
              height:(size_t)height {

    void *baseAddress = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, planeIndex);
    if (!baseAddress || rowBytes == 0 || height == 0) {
        return NULL;
    }
    if (bytesPerRow == rowBytes) {
        return baseAddress;
    }
    uint8_t *packedData = malloc(rowBytes * height);
    if (!packedData) {
        return NULL;
    }
    uint8_t *source = baseAddress;
    for (size_t row = 0; row < height; row++) {
        memcpy(packedData + row * rowBytes, source + row * bytesPerRow, rowBytes);
    }
    return packedData;
}

- (BOOL)uploadTexturesWithPixelBuffer:(CVPixelBufferRef)pixelBuffer {

    if (CVPixelBufferGetPlaneCount(pixelBuffer) < 2) {
        VAP_Error(kQGVAPModuleCommon, @"uploadTexturesWithPixelBuffer fail, plane count:%@", @(CVPixelBufferGetPlaneCount(pixelBuffer)));
        return NO;
    }

    CVReturn lockStatus = CVPixelBufferLockBaseAddress(pixelBuffer, kCVPixelBufferLock_ReadOnly);
    if (lockStatus != kCVReturnSuccess) {
        VAP_Error(kQGVAPModuleCommon, @"CVPixelBufferLockBaseAddress fail:%d", lockStatus);
        return NO;
    }

    size_t yWidth = CVPixelBufferGetWidthOfPlane(pixelBuffer, 0);
    size_t yHeight = CVPixelBufferGetHeightOfPlane(pixelBuffer, 0);
    size_t yBytesPerRow = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 0);
    size_t uvWidth = CVPixelBufferGetWidthOfPlane(pixelBuffer, 1);
    size_t uvHeight = CVPixelBufferGetHeightOfPlane(pixelBuffer, 1);
    size_t uvBytesPerRow = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, 1);
    size_t yRowBytes = yWidth;
    size_t uvRowBytes = uvWidth * 2;

    void *yData = [self copyPlane:pixelBuffer index:0 bytesPerRow:yBytesPerRow rowBytes:yRowBytes height:yHeight];
    void *uvData = [self copyPlane:pixelBuffer index:1 bytesPerRow:uvBytesPerRow rowBytes:uvRowBytes height:uvHeight];
    if (!yData || !uvData) {
        if (yData && yData != CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0)) {
            free(yData);
        }
        if (uvData && uvData != CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 1)) {
            free(uvData);
        }
        CVPixelBufferUnlockBaseAddress(pixelBuffer, kCVPixelBufferLock_ReadOnly);
        VAP_Error(kQGVAPModuleCommon, @"uploadTexturesWithPixelBuffer fail, invalid plane data");
        return NO;
    }

    glPixelStorei(GL_UNPACK_ALIGNMENT, 1);
    [self configureFallbackTexture:&_fallbackLumaTextureName textureUnit:GL_TEXTURE0];
    glTexImage2D(GL_TEXTURE_2D, 0, GL_LUMINANCE, (GLsizei)yWidth, (GLsizei)yHeight, 0, GL_LUMINANCE, GL_UNSIGNED_BYTE, yData);
    [self configureFallbackTexture:&_fallbackChromaTextureName textureUnit:GL_TEXTURE1];
    glTexImage2D(GL_TEXTURE_2D, 0, GL_LUMINANCE_ALPHA, (GLsizei)uvWidth, (GLsizei)uvHeight, 0, GL_LUMINANCE_ALPHA, GL_UNSIGNED_BYTE, uvData);

    if (yData != CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0)) {
        free(yData);
    }
    if (uvData != CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 1)) {
        free(uvData);
    }
    CVPixelBufferUnlockBaseAddress(pixelBuffer, kCVPixelBufferLock_ReadOnly);
    return YES;
}

#pragma mark - OpenGLES drawing

- (void)qgvap_renderPixelBuffer:(CVPixelBufferRef)pixelBuffer {

    if (!self.renderable) {
        [self qgvap_notifyViewUnavailable];
        return ;
    }

    if (![self qgvap_prepareForRendering]) {
        VAP_Event(kQGVAPModuleCommon, @"quit display pixelbuffer, cuz OpenGL prepare failed");
        return;
    }
    if ([EAGLContext currentContext] != _glContext) {
        [EAGLContext setCurrentContext:_glContext];
    }
    [self qgvap_updateSurfaceSizeIfNeeded];
    if (_backingWidth <= 0 || _backingHeight <= 0) {
        return;
    }

    if (pixelBuffer != NULL) {
        if (!_textureCache) {
            VAP_Event(kQGVAPModuleCommon, @"No video texture cache");
            return;
        }
        [self cleanupTextures];

        [self updatePixelBufferProperties:pixelBuffer];
        if (![self updateTexturesWithPixelBuffer:pixelBuffer]) {
            return;
        }

        glBindFramebuffer(GL_FRAMEBUFFER, _frameBufferHandle);

        // Set the view port to the entire view.
        glViewport(0, 0, _backingWidth, _backingHeight);
    }

    //    glClearColor(0.1f, 0.0f, 0.0f, 1.0f);
    glClear(GL_COLOR_BUFFER_BIT);

    glUseProgram(self.program);
    glUniformMatrix3fv(hwd_uniforms[HWD_UNIFORM_COLOR_CONVERSION_MATRIX], 1, GL_FALSE, _preferredConversion);
    glUniform2fv(hwd_uniforms[HWD_UNIFORM_ALPHA_CONVERSION], 1, _preferredAlphaConversion);

    // 根据视频的方向和高宽比设置四个顶点。
    CGRect vertexRect = AVMakeRectWithAspectRatioInsideRect(CGSizeMake(_backingWidth, _backingHeight), self.layer.bounds);

    // 计算归一化四坐标来绘制坐标系。
    CGSize normalizedSamplingSize = CGSizeMake(0.0, 0.0);
    CGSize cropScaleAmount = CGSizeMake(vertexRect.size.width/self.layer.bounds.size.width, vertexRect.size.height/self.layer.bounds.size.height);

    if (cropScaleAmount.width > cropScaleAmount.height) {
        normalizedSamplingSize.width = 1.0;
        normalizedSamplingSize.height = cropScaleAmount.height/cropScaleAmount.width;
    } else {
        normalizedSamplingSize.width = 1.0;
        normalizedSamplingSize.height = cropScaleAmount.width/cropScaleAmount.height;
    }

    GLfloat quadVertexData [] = {
        -1 * normalizedSamplingSize.width, -1 * normalizedSamplingSize.height,
        normalizedSamplingSize.width, -1 * normalizedSamplingSize.height,
        -1 * normalizedSamplingSize.width, normalizedSamplingSize.height,
        normalizedSamplingSize.width, normalizedSamplingSize.height,
    };

    // 更新顶点数据
    glVertexAttribPointer(ATTRIB_VERTEX, 2, GL_FLOAT, 0, 0, quadVertexData);
    glEnableVertexAttribArray(ATTRIB_VERTEX);
    glVertexAttribPointer(ATTRIB_TEXCOORD_RGB, 2, GL_FLOAT, 0, 0, [self quadTextureRGBData]);
    glEnableVertexAttribArray(ATTRIB_TEXCOORD_RGB);
    glVertexAttribPointer(ATTRIB_TEXCOORD_ALPHA, 2, GL_FLOAT, 0, 0, [self quedTextureAlphaData]);
    glEnableVertexAttribArray(ATTRIB_TEXCOORD_ALPHA);
    glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);
    glBindRenderbuffer(GL_RENDERBUFFER, _colorBufferHandle);
    if ([EAGLContext currentContext] == _glContext && !self.pause && self.renderable && [UIApplication sharedApplication].applicationState != UIApplicationStateBackground) {
        [_glContext presentRenderbuffer:GL_RENDERBUFFER];
    }
}

- (void)qgvap_updateDrawableState {

    CGSize drawableSize = CGSizeMake(CGRectGetWidth(self.bounds) * self.contentScaleFactor, CGRectGetHeight(self.bounds) * self.contentScaleFactor);
    self.renderable = (self.window != nil && drawableSize.width > 0 && drawableSize.height > 0);
    self.backingSizeNeedsUpdate = YES;
}

- (void)qgvap_notifyViewUnavailable {

    id<QGHWDMP4OpenGLViewDelegate> delegate = self.displayDelegate;
    if ([delegate respondsToSelector:@selector(qgvap_renderViewDidBecomeUnavailable)]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [delegate qgvap_renderViewDidBecomeUnavailable];
        });
    }
}

- (BOOL)hasVAPTextureLayout {

    QGVAPCommonInfo *commonInfo = self.commonInfo;
    return commonInfo.videoSize.width > 0 &&
           commonInfo.videoSize.height > 0 &&
           commonInfo.rgbAreaRect.size.width > 0 &&
           commonInfo.rgbAreaRect.size.height > 0 &&
           commonInfo.alphaAreaRect.size.width > 0 &&
           commonInfo.alphaAreaRect.size.height > 0;
}

- (void)fillTextureCoordinates:(GLfloat *)coordinates rect:(CGRect)rect containerSize:(CGSize)containerSize {

    if (!coordinates || containerSize.width <= 0 || containerSize.height <= 0) {
        return;
    }
    GLfloat minX = rect.origin.x / containerSize.width;
    GLfloat minY = rect.origin.y / containerSize.height;
    GLfloat maxX = CGRectGetMaxX(rect) / containerSize.width;
    GLfloat maxY = CGRectGetMaxY(rect) / containerSize.height;
    GLfloat values[] = {
        maxX, minY,
        minX, minY,
        maxX, maxY,
        minX, maxY
    };
    memcpy(coordinates, values, sizeof(values));
}

- (const void *)quedTextureAlphaData {

    if ([self hasVAPTextureLayout]) {
        [self fillTextureCoordinates:_vapAlphaTextureCoordinates rect:self.commonInfo.alphaAreaRect containerSize:self.commonInfo.videoSize];
        return _vapAlphaTextureCoordinates;
    }

    switch (self.blendMode) {
        case QGHWDTextureBlendMode_AlphaLeft:
            return textureCoordLeft;
        case QGHWDTextureBlendMode_AlphaRight:
            return textureCoordRight;
        case QGHWDTextureBlendMode_AlphaTop:
            return textureCoordTop;
        case QGHWDTextureBlendMode_AlphaBottom:
            return textureCoordBottom;
        default:
            return textureCoordLeft;
    }
}

- (const void *)quadTextureRGBData {

    if ([self hasVAPTextureLayout]) {
        [self fillTextureCoordinates:_vapRGBTextureCoordinates rect:self.commonInfo.rgbAreaRect containerSize:self.commonInfo.videoSize];
        return _vapRGBTextureCoordinates;
    }

    switch (self.blendMode) {
        case QGHWDTextureBlendMode_AlphaLeft:
            return textureCoordRight;
        case QGHWDTextureBlendMode_AlphaRight:
            return textureCoordLeft;
        case QGHWDTextureBlendMode_AlphaTop:
            return textureCoordBottom;
        case QGHWDTextureBlendMode_AlphaBottom:
            return textureCoordTop;
        default:
            return textureCoordRight;
    }
}

#pragma mark -  OpenGL ES 2 shader compilation

- (BOOL)loadShaders {

    GLuint vShader, fShader;
    self.program = glCreateProgram();
    // Create and compile the vertex shader.
    if (![self compileShader:&vShader type:GL_VERTEX_SHADER source:kVertexShaderSource]) {
        VAP_Error(kQGVAPModuleCommon, @"Failed to compile vertex shader");
        return NO;
    }
    // Create and compile fragment shader.
    if (![self compileShader:&fShader type:GL_FRAGMENT_SHADER source:kFragmentShaderSource]) {
        VAP_Error(kQGVAPModuleCommon, @"Failed to compile fragment shader");
        return NO;
    }
    // Attach vertex shader to program.
    glAttachShader(self.program, vShader);
    // Attach fragment shader to program.
    glAttachShader(self.program, fShader);
    // Bind attribute locations. This needs to be done prior to linking.
    glBindAttribLocation(self.program, ATTRIB_VERTEX, "position");
    glBindAttribLocation(self.program, ATTRIB_TEXCOORD_RGB, "RGBTexCoord");
    glBindAttribLocation(self.program, ATTRIB_TEXCOORD_ALPHA, "alphaTexCoord");
    // Link the program.
    if (![self linkProgram:self.program]) {
        VAP_Event(kQGVAPModuleCommon, @"Failed to link program: %d", self.program);
        if (vShader) {
            glDeleteShader(vShader);
            vShader = 0;
        }
        if (fShader) {
            glDeleteShader(fShader);
            fShader = 0;
        }
        if (self.program) {
            glDeleteProgram(self.program);
            self.program = 0;
        }
        return NO;
    }

    // Get uniforms' location.
    hwd_uniforms[HWD_UNIFORM_Y] = glGetUniformLocation(self.program, "SamplerY");
    hwd_uniforms[HWD_UNIFORM_UV] = glGetUniformLocation(self.program, "SamplerUV");
    hwd_uniforms[HWD_UNIFORM_COLOR_CONVERSION_MATRIX] = glGetUniformLocation(self.program, "colorConversionMatrix");
    hwd_uniforms[HWD_UNIFORM_ALPHA_CONVERSION] = glGetUniformLocation(self.program, "alphaConversion");

    // Release vertex and fragment shaders.
    if (vShader) {
        glDetachShader(self.program, vShader);
        glDeleteShader(vShader);
    }
    if (fShader) {
        glDetachShader(self.program, fShader);
        glDeleteShader(fShader);
    }
    return YES;
}

- (BOOL)compileShader:(GLuint *)shader type:(GLenum)type source:(const NSString *)sourceString {

    GLint status;
    const GLchar *source;
    source = (GLchar *)[sourceString UTF8String];
    *shader = glCreateShader(type);
    glShaderSource(*shader, 1, &source, NULL);
    glCompileShader(*shader);
#if defined(DEBUG)
    GLint lengthOfLog;
    glGetShaderiv(*shader, GL_INFO_LOG_LENGTH, &lengthOfLog);
    if (lengthOfLog > 0) {
        GLchar *log = (GLchar *)malloc(lengthOfLog);
        glGetShaderInfoLog(*shader, lengthOfLog, &lengthOfLog, log);
        VAP_Info(kQGVAPModuleCommon, @"MODULE_DECODE Shader compile log:\n%s", log)
        free(log);
    }
#endif
    glGetShaderiv(*shader, GL_COMPILE_STATUS, &status);
    if (status == 0) {
        glDeleteShader(*shader);
        return NO;
    }
    return YES;
}

- (BOOL)compileShader:(GLuint *)shader type:(GLenum)type URL:(NSURL *)URL {

    VAP_Info(kQGVAPModuleCommon, @"compileShader");
    NSError *error;
    NSString *sourceString = [[NSString alloc] initWithContentsOfURL:URL encoding:NSUTF8StringEncoding error:&error];
    if (sourceString == nil) {
        VAP_Event(kQGVAPModuleCommon, @"Failed to load vertex shader: %@", [error localizedDescription]);
        return NO;
    }

    const GLchar *source;
    source = (GLchar *)[sourceString UTF8String];
    *shader = glCreateShader(type);
    glShaderSource(*shader, 1, &source, NULL);
    glCompileShader(*shader);

#if defined(DEBUG)
    GLint lengthOfLog;
    glGetShaderiv(*shader, GL_INFO_LOG_LENGTH, &lengthOfLog);
    if (lengthOfLog > 0) {
        GLchar *log = (GLchar *)malloc(lengthOfLog);
        glGetShaderInfoLog(*shader, lengthOfLog, &lengthOfLog, log);
        VAP_Info(kQGVAPModuleCommon, @"Shader compile log:\n%s", log);
        free(log);
    }
#endif

    GLint status;
    glGetShaderiv(*shader, GL_COMPILE_STATUS, &status);
    if (status == 0) {
        glDeleteShader(*shader);
        return NO;
    }

    return YES;
}

- (BOOL)linkProgram:(GLuint)prog {

    GLint status;
    glLinkProgram(prog);

#if defined(DEBUG)
    GLint lengthOfLog;
    glGetProgramiv(prog, GL_INFO_LOG_LENGTH, &lengthOfLog);
    if (lengthOfLog > 0) {
        GLchar *log = (GLchar *)malloc(lengthOfLog);
        glGetProgramInfoLog(prog, lengthOfLog, &lengthOfLog, log);
        VAP_Info(kQGVAPModuleCommon, @"Program link log:\n%s", log);
        free(log);
    }
#endif

    glGetProgramiv(prog, GL_LINK_STATUS, &status);
    if (status == 0) {
        return NO;
    }

    return YES;
}

- (BOOL)isValidateProgram:(GLuint)prog {

    GLint logLength, status;
    glValidateProgram(prog);
    glGetProgramiv(prog, GL_INFO_LOG_LENGTH, &logLength);
    if (logLength > 0) {
        GLchar *log = (GLchar *)malloc(logLength);
        glGetProgramInfoLog(prog, logLength, &logLength, log);
        VAP_Info(kQGVAPModuleCommon, @"Program validate log:\n%s", log);
        free(log);
    }

    glGetProgramiv(prog, GL_VALIDATE_STATUS, &status);
    if (status == 0) {
        VAP_Event(kQGVAPModuleCommon, @"program is not valid:%@",@(status));
        return NO;
    }
    VAP_Info(kQGVAPModuleCommon, @"programe is valid");
    return YES;
}

- (void)dispose {

    if (!_glContext) {
        return;
    }
    if ([EAGLContext currentContext] != _glContext) {
        [EAGLContext setCurrentContext:_glContext];
    }
    [self cleanupTextures];
    if (_fallbackLumaTextureName) {
        glDeleteTextures(1, &_fallbackLumaTextureName);
        _fallbackLumaTextureName = 0;
    }
    if (_fallbackChromaTextureName) {
        glDeleteTextures(1, &_fallbackChromaTextureName);
        _fallbackChromaTextureName = 0;
    }
    if (_textureCache) {
        CFRelease(_textureCache);
        _textureCache = NULL;
    }
    if (self.program) {
        glDeleteProgram(self.program);
        self.program = 0;
    }
    if (_frameBufferHandle) {
        glDeleteFramebuffers(1, &_frameBufferHandle);
        _frameBufferHandle = 0;
    }
    if (_colorBufferHandle) {
        glDeleteRenderbuffers(1, &_colorBufferHandle);
        _colorBufferHandle = 0;
    }
    glDisableVertexAttribArray(ATTRIB_VERTEX);
    glDisableVertexAttribArray(ATTRIB_TEXCOORD_RGB);
    glDisableVertexAttribArray(ATTRIB_TEXCOORD_ALPHA);
    glFinish();
    if ([EAGLContext currentContext] == _glContext) {
        [EAGLContext setCurrentContext:nil];
    }
    _glContext = nil;
    _backingWidth = 0;
    _backingHeight = 0;
    self.backingSizeNeedsUpdate = YES;
    self.renderingPrepared = NO;
}

@end
