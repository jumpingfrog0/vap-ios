//
//  FamVapWrapView.m
//  Famo
//
//  Created by huangdonghong on 2026/1/15.
//

#import "FamVapWrapView.h"
#import "QGVAPConfigModel.h"

@implementation FamVapWrapView

- (void)playHWDMP4:(NSString *)filePath
         playCount:(NSInteger)playCount
          delegate:(id<VAPWrapViewDelegate>)delegate {
    NSInteger repeatCount = playCount == -1 ? -1 : MAX(playCount - 1, 0);
    [self playHWDMP4:filePath repeatCount:repeatCount delegate:delegate];
}

- (void)playHWDMP4:(NSString *)filePath
         blendMode:(QGHWDTextureBlendMode)mode
         playCount:(NSInteger)playCount
          delegate:(id<VAPWrapViewDelegate>)delegate {
    NSInteger repeatCount = playCount == -1 ? -1 : MAX(playCount - 1, 0);
    [self playHWDMP4:filePath blendMode:mode repeatCount:repeatCount delegate:delegate];
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

    // 文字资源不能返回空字符串，否则底层无法生成贴图，这里用空白字符兜底。
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

    if (urlStr.length == 0 ||
        ![self.delegate respondsToSelector:@selector(vapWrapView_loadVapImageWithURL:context:completion:)]) {
        completionBlock([self transparentFallbackImage], nil, urlStr);
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
            return;
        }

        NSError *loadError = error ?: [NSError errorWithDomain:NSURLErrorDomain
                                                          code:-1
                                                      userInfo:@{@"msg" : @"vap image load completed without image"}];
        completionBlock(nil, loadError, imageURL ?: urlStr);
    };

    [self.delegate vapWrapView_loadVapImageWithURL:urlStr context:context completion:completeOnce];
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
