//
//  FamVapWrapView.h
//  Famo
//
//  Created by huangdonghong on 2026/1/15.
//

#import <UIKit/UIKit.h>
#import "QGVAPWrapView.h"

NS_ASSUME_NONNULL_BEGIN


/*
 封装VAPView，本身不响应手势
 提供ContentMode功能
 播放完成后会自动移除内部的VAPView（可选）
 */
@interface FamVapWrapView : QGVAPWrapView

/// 按总播放次数播放，playCount 为 1 表示只播放一次，-1 表示无限循环
- (void)playHWDMP4:(NSString *)filePath
         playCount:(NSInteger)playCount
          delegate:(id<VAPWrapViewDelegate>)delegate;

- (void)playHWDMP4:(NSString *)filePath
         blendMode:(QGHWDTextureBlendMode)mode
         playCount:(NSInteger)playCount
          delegate:(id<VAPWrapViewDelegate>)delegate;

@end

NS_ASSUME_NONNULL_END
