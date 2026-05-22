//
//  JFVapDebugConfig.h
//  ObjcDemo
//
//  Created by Codex on 2026/5/18.
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSUInteger, JFVapDebugConfigCellType) {
    JFVapDebugConfigCellTypeNone,
    JFVapDebugConfigCellTypeSwitch,
    JFVapDebugConfigCellTypeSetValue,
};

typedef void (^JFVapDebugSwitchCallback)(BOOL isOn);
typedef void (^JFVapDebugApplyValueCallback)(NSString *value);

@interface JFVapDebugConfigModel : NSObject

@property (nonatomic, copy) NSString *title;
@property (nonatomic, copy, nullable) NSString *desc;
@property (nonatomic, copy, nullable) NSString *defaultVal;
@property (nonatomic, assign) BOOL isOn;
@property (nonatomic, assign) BOOL needTextfield;
@property (nonatomic, assign) JFVapDebugConfigCellType type;
@property (nonatomic, copy, nullable) dispatch_block_t clickCallback;
@property (nonatomic, copy, nullable) JFVapDebugSwitchCallback switchChangedCallback;
@property (nonatomic, copy, nullable) JFVapDebugApplyValueCallback applyValCallback;

@end

@interface JFVapDebugConfigTableViewCell : UITableViewCell

- (void)setContent:(JFVapDebugConfigModel *)model;

@end

NS_ASSUME_NONNULL_END
