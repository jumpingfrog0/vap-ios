//
//  JFVapImageCacheHelper.m
//  ObjcDemo
//
//  Created by Codex on 2026/5/18.
//

#import "JFVapImageCacheHelper.h"
#import <CommonCrypto/CommonDigest.h>

@implementation JFVapImageCacheHelper

+ (void)getLocalImageURLForURL:(NSURL *)imageURL completion:(JFVapImageLocalURLCompletion)completion
{
    if (!imageURL) {
        NSError *error = [NSError errorWithDomain:@"com.objcdemo.vap.image"
                                             code:-1
                                         userInfo:@{NSLocalizedDescriptionKey: @"图片 URL 为空"}];
        if (completion) {
            completion(nil, error);
        }
        return;
    }

    NSString *filePath = [self cachedFilePathForURL:imageURL];
    if ([[NSFileManager defaultManager] fileExistsAtPath:filePath]) {
        if (completion) {
            completion([NSURL fileURLWithPath:filePath], nil);
        }
        return;
    }

    NSURLSessionDownloadTask *task = [[NSURLSession sharedSession] downloadTaskWithURL:imageURL completionHandler:^(NSURL *location, NSURLResponse *response, NSError *error) {
        if (error || !location) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (completion) {
                    completion(nil, error);
                }
            });
            return;
        }

        NSError *fileError = nil;
        NSString *directoryPath = [filePath stringByDeletingLastPathComponent];
        [[NSFileManager defaultManager] createDirectoryAtPath:directoryPath withIntermediateDirectories:YES attributes:nil error:&fileError];
        if (!fileError) {
            [[NSFileManager defaultManager] moveItemAtURL:location toURL:[NSURL fileURLWithPath:filePath] error:&fileError];
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            if (completion) {
                completion(fileError ? nil : [NSURL fileURLWithPath:filePath], fileError);
            }
        });
    }];
    [task resume];
}

+ (NSString *)cachedFilePathForURL:(NSURL *)url
{
    NSString *directory = [NSTemporaryDirectory() stringByAppendingPathComponent:@"ObjcDemoVAPImages"];
    NSString *extension = url.pathExtension.length > 0 ? url.pathExtension : @"jpg";
    NSString *filename = [NSString stringWithFormat:@"%@.%@", [self md5:url.absoluteString], extension];
    return [directory stringByAppendingPathComponent:filename];
}

+ (NSString *)md5:(NSString *)string
{
    const char *utf8String = string.UTF8String;
    unsigned char digest[CC_MD5_DIGEST_LENGTH];
    CC_MD5(utf8String, (CC_LONG)strlen(utf8String), digest);

    NSMutableString *result = [NSMutableString stringWithCapacity:CC_MD5_DIGEST_LENGTH * 2];
    for (NSInteger index = 0; index < CC_MD5_DIGEST_LENGTH; index++) {
        [result appendFormat:@"%02x", digest[index]];
    }
    return result;
}

@end
