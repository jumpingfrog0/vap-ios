//
//  JFVapDebugConfig.m
//  ObjcDemo
//
//  Created by Codex on 2026/5/18.
//

#import "JFVapDebugConfig.h"

@interface JFVapDebugConfigTableViewCell ()

@property (nonatomic, strong) JFVapDebugConfigModel *model;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *descLabel;
@property (nonatomic, strong) UISwitch *switchView;
@property (nonatomic, strong) UITextField *textfield;

@end

@implementation JFVapDebugConfigModel

@end

@implementation JFVapDebugConfigTableViewCell

- (instancetype)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier
{
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self) {
        _titleLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        _titleLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightRegular];
        _titleLabel.textColor = [UIColor colorWithWhite:0.12 alpha:1.0];
        _titleLabel.numberOfLines = 0;

        _descLabel = [[UILabel alloc] initWithFrame:CGRectZero];
        _descLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightRegular];
        _descLabel.textColor = [UIColor colorWithWhite:0.45 alpha:1.0];
        _descLabel.numberOfLines = 0;

        _switchView = [[UISwitch alloc] initWithFrame:CGRectZero];
        [_switchView addTarget:self action:@selector(onSwitchChanged:) forControlEvents:UIControlEventValueChanged];

        _textfield = [[UITextField alloc] initWithFrame:CGRectZero];
        _textfield.borderStyle = UITextBorderStyleRoundedRect;
        _textfield.font = [UIFont systemFontOfSize:14];
        [_textfield addTarget:self action:@selector(onTextFieldChanged:) forControlEvents:UIControlEventEditingChanged];

        [self.contentView addSubview:_titleLabel];
        [self.contentView addSubview:_descLabel];
        [self.contentView addSubview:_switchView];
        [self.contentView addSubview:_textfield];
        self.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    }
    return self;
}

- (void)layoutSubviews
{
    [super layoutSubviews];

    CGFloat width = CGRectGetWidth(self.contentView.bounds);
    CGFloat height = CGRectGetHeight(self.contentView.bounds);
    CGFloat contentLeft = 20.0;
    CGFloat controlWidth = 100.0;
    CGFloat labelWidth = width - contentLeft - controlWidth - 20.0;

    self.titleLabel.frame = CGRectMake(contentLeft, 8.0, labelWidth, height - 16.0);
    self.descLabel.frame = CGRectZero;

    self.switchView.frame = CGRectMake(width - 70.0, (height - CGRectGetHeight(self.switchView.bounds)) * 0.5, 51.0, 31.0);
    self.textfield.frame = CGRectMake(width - 118.0, 7.0, 96.0, height - 14.0);
}

- (void)setContent:(JFVapDebugConfigModel *)model
{
    self.model = model;
    self.titleLabel.text = model.title;
    self.descLabel.text = model.desc;

    self.textfield.text = model.defaultVal;
    self.textfield.hidden = !model.needTextfield;
    self.switchView.hidden = model.type != JFVapDebugConfigCellTypeSwitch;
    self.accessoryType = model.type == JFVapDebugConfigCellTypeNone ? UITableViewCellAccessoryDisclosureIndicator : UITableViewCellAccessoryNone;

    if (model.type == JFVapDebugConfigCellTypeSwitch) {
        [self.switchView setOn:model.isOn animated:NO];
    }
}

- (void)onSwitchChanged:(UISwitch *)switchView
{
    if (self.model.switchChangedCallback) {
        self.model.switchChangedCallback(switchView.isOn);
    }
}

- (void)onTextFieldChanged:(UITextField *)textField
{
    if (self.model.applyValCallback) {
        self.model.applyValCallback(textField.text ?: @"");
    }
}

@end
