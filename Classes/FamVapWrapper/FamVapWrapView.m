//
//  FamVapWrapView.m
//  Famo
//
//  Created by huangdonghong on 2026/1/15.
//

#import "FamVapWrapView.h"
#import "QGVAPConfigModel.h"
#import "QGMP4HWDFileInfo.h"

static NSTimeInterval const kFamVapImageLoadFallbackTimeout = 3.0;

@implementation FamVapWrapView

- (void)playHWDMP4:(NSString *)filePath
         playCount:(NSInteger)playCount
          delegate:(id<VAPWrapViewDelegate>)delegate {
    NSInteger repeatCount = playCount == -1 ? -1 : MAX(playCount - 1, 0);
    [self playHWDMP4:filePath repeatCount:repeatCount delegate:delegate];
}

- (void)setupContentModeWithConfig:(QGVAPConfigModel *)config {
    CGFloat realWidth = 0.;
    CGFloat realHeight = 0.;

    if (!config || config.info.size.width <= 0 || config.info.size.height <= 0) {
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

- (void)setupContentModeWithVideoSize:(CGSize)videoSize {
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

- (BOOL)shouldStartPlayMP4:(UIView *)container config:(QGVAPConfigModel *)config {

    // 调试尺寸日志，排查 VAP 布局时使用
//    NSLog(@"VAP_SIZE_TRACE FamVapWrapView shouldStart enter wrapper:%@ inner:%@ container:%@ superview:%@ window:%@ configSize:%@",
//          NSStringFromCGRect(self.bounds),
//          NSStringFromCGRect(self.vapView.bounds),
//          NSStringFromCGRect(container.bounds),
//          self.superview,
//          self.window,
//          NSStringFromCGSize(config.info.size));

    if (config) {
        // vap 资源
        [self setupContentModeWithConfig:config];
//        NSLog(@"VAP_SIZE_TRACE FamVapWrapView shouldStart config afterContentMode wrapper:%@ inner:%@ container:%@",
//              NSStringFromCGRect(self.bounds),
//              NSStringFromCGRect(self.vapView.bounds),
//              NSStringFromCGRect(container.bounds));

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

        [self setupContentModeWithVideoSize:videoSize];
//        NSLog(@"VAP_SIZE_TRACE FamVapWrapView shouldStart oldVersion videoSize:%@ wrapper:%@ inner:%@ container:%@ blendMode:%@",
//              NSStringFromCGSize(videoSize),
//              NSStringFromCGRect(self.bounds),
//              NSStringFromCGRect(self.vapView.bounds),
//              NSStringFromCGRect(container.bounds),
//              @(blendMode));

        if ([self.delegate respondsToSelector:@selector(vapWrap_viewshouldStartPlayMP4:config:)]) {
            return [self.delegate vapWrap_viewshouldStartPlayMP4:container config:config];
        }
    }

    return YES;
}

#pragma mark - VAP 资源容错

- (NSString *)contentForVapTag:(NSString *)tag resource:(QGVAPSourceInfo *)info
{
    NSString *content = nil;
    if ([self.delegate respondsToSelector:@selector(vapWrapview_contentForVapTag:resource:)]) {
        content = [self.delegate vapWrapview_contentForVapTag:tag resource:info];
    }

    if (content.length > 0) {
        return content;
    }

    // 文字资源不能返回空字符串，否则底层无法生成贴图，这里用空白字符兜底
    if ([info.type isEqualToString:kQGAGAttachmentSourceTypeText]) {
        return @" ";
    }

    return @"";
}

- (void)loadVapImageWithURL:(NSString *)urlStr context:(NSDictionary *)context completion:(VAPImageCompletionBlock)completionBlock
{
    if (!completionBlock) {
        return;
    }

    UIImage *fallbackImage = [self transparentFallbackImage];
    if (urlStr.length == 0 ||
        ![self.delegate respondsToSelector:@selector(vapWrapView_loadVapImageWithURL:context:completion:)]) {
        completionBlock(fallbackImage, nil, urlStr);
        return;
    }

    NSObject *completionLock = [[NSObject alloc] init];
    __block BOOL didComplete = NO;

    void (^completeOnce)(UIImage *, NSError *, NSString *) = ^(UIImage *image, NSError *error, NSString *imageURL) {
        @synchronized (completionLock) {
            if (didComplete) {
                return;
            }
            didComplete = YES;
        }

        if (image) {
            completionBlock(image, nil, imageURL ?: urlStr);
        } else {
            completionBlock(fallbackImage, nil, imageURL ?: urlStr);
        }
    };

    [self.delegate vapWrapView_loadVapImageWithURL:urlStr context:context completion:completeOnce];

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kFamVapImageLoadFallbackTimeout * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        completeOnce(fallbackImage, nil, urlStr);
    });
}

- (UIImage *)transparentFallbackImage
{
    static UIImage *fallbackImage = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        UIGraphicsBeginImageContextWithOptions(CGSizeMake(1, 1), NO, 0);
        [[UIColor clearColor] setFill];
        UIRectFill(CGRectMake(0, 0, 1, 1));
        fallbackImage = UIGraphicsGetImageFromCurrentImageContext();
        UIGraphicsEndImageContext();
    });
    return fallbackImage;
}

@end
