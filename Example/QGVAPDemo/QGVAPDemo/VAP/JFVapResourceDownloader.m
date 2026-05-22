//
//  JFVapResourceDownloader.m
//  ObjcDemo
//
//  Created by Codex on 2026/5/18.
//

#import "JFVapResourceDownloader.h"
#import <CommonCrypto/CommonDigest.h>

@implementation JFVapResourceDownloader

+ (instancetype)sharedDownloader
{
    static JFVapResourceDownloader *downloader;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        downloader = [[JFVapResourceDownloader alloc] init];
    });
    return downloader;
}

- (void)downloadMP4WithURLString:(NSString *)urlString completion:(JFVapResourceDownloadCompletion)completion
{
    NSURL *url = [NSURL URLWithString:urlString];
    if (urlString.length == 0 || !url) {
        NSError *error = [NSError errorWithDomain:@"com.objcdemo.vap.downloader"
                                             code:-1
                                         userInfo:@{NSLocalizedDescriptionKey: @"URL 为空或非法"}];
        if (completion) {
            completion(NO, nil, error);
        }
        return;
    }

    NSString *filePath = [self cachedFilePathForURLString:urlString];
    if ([[NSFileManager defaultManager] fileExistsAtPath:filePath]) {
        if (completion) {
            completion(YES, filePath, nil);
        }
        return;
    }

    NSURLSessionDownloadTask *task = [[NSURLSession sharedSession] downloadTaskWithURL:url completionHandler:^(NSURL *location, NSURLResponse *response, NSError *error) {
        if (error || !location) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (completion) {
                    completion(NO, nil, error);
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
                completion(fileError == nil, fileError ? nil : filePath, fileError);
            }
        });
    }];
    [task resume];
}

- (NSString *)cachedFilePathForURLString:(NSString *)urlString
{
    NSString *directory = [NSTemporaryDirectory() stringByAppendingPathComponent:@"ObjcDemoVAP"];
    NSString *extension = [urlString pathExtension].length > 0 ? [urlString pathExtension] : @"mp4";
    NSString *filename = [NSString stringWithFormat:@"%@.%@", [self md5:urlString], extension];
    return [directory stringByAppendingPathComponent:filename];
}

- (NSString *)md5:(NSString *)string
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
