//
//  JFVapResourceDownloader.h
//  ObjcDemo
//
//  Created by Codex on 2026/5/18.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef void (^JFVapResourceDownloadCompletion)(BOOL success, NSString *_Nullable filePath, NSError *_Nullable error);

@interface JFVapResourceDownloader : NSObject

+ (instancetype)sharedDownloader;
- (void)downloadMP4WithURLString:(NSString *)urlString completion:(JFVapResourceDownloadCompletion)completion;

@end

NS_ASSUME_NONNULL_END
