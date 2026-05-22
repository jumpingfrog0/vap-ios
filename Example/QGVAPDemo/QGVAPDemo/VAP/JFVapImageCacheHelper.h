//
//  JFVapImageCacheHelper.h
//  ObjcDemo
//
//  Created by Codex on 2026/5/18.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef void (^JFVapImageLocalURLCompletion)(NSURL *_Nullable localURL, NSError *_Nullable error);

@interface JFVapImageCacheHelper : NSObject

+ (void)getLocalImageURLForURL:(NSURL *)imageURL completion:(JFVapImageLocalURLCompletion)completion;

@end

NS_ASSUME_NONNULL_END
