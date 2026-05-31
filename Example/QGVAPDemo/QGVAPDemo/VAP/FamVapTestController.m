//
//  FamVapTestController.m
//  ObjcDemo
//
//  Created by Codex on 2026/5/18.
//

#import "FamVapTestController.h"
#import "FamVapWrapView.h"
#import "JFVapDebugConfig.h"
#import "JFVapImageCacheHelper.h"
#import "JFVapResourceDownloader.h"
#import "QGVAPConfigModel.h"
#import "QGVAPWrapView.h"
#import "UIView+VAP.h"
#import <AVFoundation/AVFoundation.h>
#import <Masonry/Masonry.h>

static NSString *const kJFVapDemoAvatarURL = @"https://o-sg.taddaapp.com/appres/f644a138-3520-40f3-9778-0f8b65ce4a05.jpg";

@interface FamVapTestController () <UITableViewDataSource, UITableViewDelegate, VAPWrapViewDelegate, HWDMP4PlayDelegate>

@property (nonatomic, strong) NSMutableArray<JFVapDebugConfigModel *> *dataList;
@property (nonatomic, weak) UITableView *debugTableView;
@property (nonatomic, weak) UISwitch *pauseGestureSwitch;
@property (nonatomic, weak) UISegmentedControl *backgroundOperationSegmentedControl;
@property (nonatomic, weak) UIView *currentEffectContainerView;
@property (nonatomic, assign) BOOL enablePauseGestureForFamVapWrapView;
@property (nonatomic, assign) HWDMP4EBOperationType enterBackgroundOperationType;
@property (nonatomic, assign) BOOL isTencentVap;
@property (nonatomic, assign) BOOL isBigoVap;

@end

@implementation FamVapTestController

void QG_VAP_Logger_handler(VAPLogLevel level, const char *file, int line, const char *func, NSString *module, NSString *format, ...) {
    if (format.UTF8String == nil) {
        NSLog(@"VAP log contains non-UTF8 characters");
        return;
    }
    if (level > VAPLogLevelDebug) {
        va_list argList;
        va_start(argList, format);
        NSString *message = [[NSString alloc] initWithFormat:format arguments:argList];
        file = [NSString stringWithUTF8String:file].lastPathComponent.UTF8String;
        NSLog(@"<%@> %s(%@):%s [%@] - %@", @(level), file, @(line), func, module, message);
        va_end(argList);
    }
}

- (void)dealloc
{
    [self dispose];
}

- (void)viewDidLoad
{
    [super viewDidLoad];

    [self initData];
    [self initDebugItems];
    [self initViews];
    [self setupAudioSession];
    [UIView registerHWDLog:QG_VAP_Logger_handler];
}

- (void)initData
{
    self.dataList = [NSMutableArray array];
    self.enablePauseGestureForFamVapWrapView = NO;
    self.enterBackgroundOperationType = HWDMP4EBOperationTypeStop;
}

- (void)initDebugItems
{
    __weak typeof(self) weakSelf = self;

    [self addTestItem:@"非Vap资源（退后台结束）" clickCallback:^{
        [weakSelf playNotVapResource];
    }];
    [self addTestItem:@"融合特效（退后台暂停/恢复）" clickCallback:^{
        [weakSelf playVapWithTencentResource2];
    }];
    [self addTestItem:@"WrapView-ContentMode" clickCallback:^{
        [weakSelf playVapWithWrapView];
    }];
    [self addTestItem:@"腾讯 vap 资源" clickCallback:^{
        [weakSelf playTencentVapResource];
    }];
    [self addTestItem:@"Bigo vap 资源" clickCallback:^{
        [weakSelf playBigoVapResource];
    }];
    [self addTestItem:@"Famo 座驾 资源" clickCallback:^{
        [weakSelf playFamoVehicleResource];
    }];
    [self addTestItem:@"famo 资源" clickCallback:^{
        [weakSelf playFamoResource];
    }];
    [self addTestItem:@"火箭动画" clickCallback:^{
        [weakSelf playRocketResource];
    }];
    [self addTestItem:@"mp4-左Alpha" clickCallback:^{
        [weakSelf playMP4_LeftAlpha];
    }];
    [self addTestItem:@"mp4-左Alpha2" clickCallback:^{
        [weakSelf playMP4_LeftAlpha2];
    }];
    [self addTestItem:@"mp4-右Alpha" clickCallback:^{
        [weakSelf playMP4_RightAlpha];
    }];
    [self addTestItem:@"mp4-右Alpha2" clickCallback:^{
        [weakSelf playMP4_RightAlpha2];
    }];
    [self addTestItem:@"mp4-右Alpha3" clickCallback:^{
        [weakSelf playMP4_RightAlpha3];
    }];
}

- (void)initViews
{
    self.navigationItem.title = @"VAP 测试";
    self.view.backgroundColor = UIColor.whiteColor;

    UIView *settingContainerView = [[UIView alloc] initWithFrame:CGRectZero];
    settingContainerView.backgroundColor = [UIColor colorWithWhite:0.96 alpha:1.0];
    settingContainerView.layer.cornerRadius = 12.0;
    settingContainerView.layer.masksToBounds = YES;
    [self.view addSubview:settingContainerView];
    [settingContainerView mas_makeConstraints:^(MASConstraintMaker *make) {
        make.top.equalTo(self.view.mas_safeAreaLayoutGuideTop).offset(12.0);
        make.leading.equalTo(self.view).offset(12.0);
        make.trailing.equalTo(self.view).offset(-12.0);
    }];

    UILabel *gestureTitleLabel = [self settingTitleLabelWithText:@"FamVapWrapView 播放暂停手势"];
    [settingContainerView addSubview:gestureTitleLabel];
    [gestureTitleLabel mas_makeConstraints:^(MASConstraintMaker *make) {
        make.top.equalTo(settingContainerView).offset(14.0);
        make.leading.equalTo(settingContainerView).offset(14.0);
        make.trailing.lessThanOrEqualTo(settingContainerView).offset(-72.0);
    }];

    UILabel *gestureDescLabel = [self settingDescLabelWithText:@"关闭后，FamVapWrapView 不再响应点击暂停/恢复，仅保留播放效果。"];
    [settingContainerView addSubview:gestureDescLabel];
    [gestureDescLabel mas_makeConstraints:^(MASConstraintMaker *make) {
        make.top.equalTo(gestureTitleLabel.mas_bottom).offset(6.0);
        make.leading.equalTo(gestureTitleLabel);
        make.trailing.equalTo(settingContainerView).offset(-14.0);
    }];

    UISwitch *pauseGestureSwitch = [[UISwitch alloc] initWithFrame:CGRectZero];
    pauseGestureSwitch.on = self.enablePauseGestureForFamVapWrapView;
    [pauseGestureSwitch addTarget:self action:@selector(onPauseGestureSwitchChanged:) forControlEvents:UIControlEventValueChanged];
    [settingContainerView addSubview:pauseGestureSwitch];
    [pauseGestureSwitch mas_makeConstraints:^(MASConstraintMaker *make) {
        make.centerY.equalTo(gestureTitleLabel);
        make.trailing.equalTo(settingContainerView).offset(-14.0);
    }];
    self.pauseGestureSwitch = pauseGestureSwitch;

    UIView *separatorView = [[UIView alloc] initWithFrame:CGRectZero];
    separatorView.backgroundColor = [UIColor colorWithWhite:0.9 alpha:1.0];
    [settingContainerView addSubview:separatorView];
    [separatorView mas_makeConstraints:^(MASConstraintMaker *make) {
        make.top.equalTo(gestureDescLabel.mas_bottom).offset(14.0);
        make.leading.equalTo(settingContainerView).offset(14.0);
        make.trailing.equalTo(settingContainerView).offset(-14.0);
        make.height.equalTo(@1);
    }];

    UILabel *backgroundTitleLabel = [self settingTitleLabelWithText:@"退后台行为（HWDMP4EBOperationType）"];
    [settingContainerView addSubview:backgroundTitleLabel];
    [backgroundTitleLabel mas_makeConstraints:^(MASConstraintMaker *make) {
        make.top.equalTo(separatorView.mas_bottom).offset(14.0);
        make.leading.equalTo(settingContainerView).offset(14.0);
        make.trailing.equalTo(settingContainerView).offset(-14.0);
    }];

    UILabel *backgroundDescLabel = [self settingDescLabelWithText:@"支持 Stop、PauseAndResume、DoNothing 三种模式，作用于当前测试页的 VAP 播放视图。"];
    [settingContainerView addSubview:backgroundDescLabel];
    [backgroundDescLabel mas_makeConstraints:^(MASConstraintMaker *make) {
        make.top.equalTo(backgroundTitleLabel.mas_bottom).offset(6.0);
        make.leading.equalTo(backgroundTitleLabel);
        make.trailing.equalTo(settingContainerView).offset(-14.0);
    }];

    UISegmentedControl *segmentedControl = [[UISegmentedControl alloc] initWithItems:@[@"Stop", @"PauseAndResume", @"DoNothing"]];
    segmentedControl.selectedSegmentIndex = self.enterBackgroundOperationType;
    [segmentedControl addTarget:self action:@selector(onBackgroundOperationSegmentChanged:) forControlEvents:UIControlEventValueChanged];
    [settingContainerView addSubview:segmentedControl];
    [segmentedControl mas_makeConstraints:^(MASConstraintMaker *make) {
        make.top.equalTo(backgroundDescLabel.mas_bottom).offset(10.0);
        make.leading.equalTo(settingContainerView).offset(14.0);
        make.trailing.equalTo(settingContainerView).offset(-14.0);
        make.bottom.equalTo(settingContainerView).offset(-14.0);
    }];
    self.backgroundOperationSegmentedControl = segmentedControl;

    UITableView *tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStylePlain];
    tableView.delegate = self;
    tableView.dataSource = self;
    tableView.rowHeight = 56.0;
    [tableView registerClass:JFVapDebugConfigTableViewCell.class forCellReuseIdentifier:NSStringFromClass(JFVapDebugConfigTableViewCell.class)];
    [self.view addSubview:tableView];
    [tableView mas_makeConstraints:^(MASConstraintMaker *make) {
        make.top.equalTo(settingContainerView.mas_bottom).offset(12.0);
        make.leading.trailing.bottom.equalTo(self.view);
    }];
    self.debugTableView = tableView;
}

- (UILabel *)settingTitleLabelWithText:(NSString *)text
{
    UILabel *label = [[UILabel alloc] initWithFrame:CGRectZero];
    label.font = [UIFont systemFontOfSize:14.0 weight:UIFontWeightMedium];
    label.textColor = [UIColor colorWithWhite:0.11 alpha:1.0];
    label.text = text;
    label.numberOfLines = 0;
    return label;
}

- (UILabel *)settingDescLabelWithText:(NSString *)text
{
    UILabel *label = [[UILabel alloc] initWithFrame:CGRectZero];
    label.font = [UIFont systemFontOfSize:12.0 weight:UIFontWeightRegular];
    label.textColor = [UIColor colorWithWhite:0.4 alpha:1.0];
    label.text = text;
    label.numberOfLines = 0;
    return label;
}

- (void)onPauseGestureSwitchChanged:(UISwitch *)sender
{
    self.enablePauseGestureForFamVapWrapView = sender.isOn;
}

- (void)onBackgroundOperationSegmentChanged:(UISegmentedControl *)sender
{
    self.enterBackgroundOperationType = (HWDMP4EBOperationType)sender.selectedSegmentIndex;
}

- (JFVapDebugConfigModel *)addTestItem:(NSString *)title clickCallback:(dispatch_block_t)callback
{
    JFVapDebugConfigModel *model = [JFVapDebugConfigModel new];
    model.title = title;
    model.clickCallback = callback;
    model.type = JFVapDebugConfigCellTypeNone;
    [self.dataList addObject:model];
    return model;
}

- (HWDMP4EBOperationType)currentEnterBackgroundOperationType
{
    return self.enterBackgroundOperationType;
}

- (UIView *)effectContainerView
{
    return self.view.window ?: self.navigationController.view.window ?: self.view;
}

- (void)clearData
{
    self.isTencentVap = NO;
    self.isBigoVap = NO;
}

- (void)dispose
{
    UIView *containerView = self.currentEffectContainerView ?: self.effectContainerView;
    for (UIView *view in containerView.subviews.copy) {
        if ([view isKindOfClass:FamVapWrapView.class]) {
            FamVapWrapView *wrapView = (FamVapWrapView *)view;
            [wrapView stopHWDMP4];
            [wrapView removeFromSuperview];
        }
    }
}

- (void)setupAudioSession
{
    AVAudioSession *session = AVAudioSession.sharedInstance;
    NSError *error = nil;
    if (![session setCategory:AVAudioSessionCategoryPlayback withOptions:0 error:&error]) {
        NSLog(@"AVAudioSession setCategory failed: %@", error.localizedDescription);
        return;
    }
    if (![session setActive:YES error:&error]) {
        NSLog(@"AVAudioSession setActive failed: %@", error.localizedDescription);
    }
}

- (void)download:(NSString *)mp4URL callback:(void (^)(NSString *filePath))callback
{
    [[JFVapResourceDownloader sharedDownloader] downloadMP4WithURLString:mp4URL completion:^(BOOL success, NSString *filePath, NSError *error) {
        if (!success || filePath.length == 0) {
            NSLog(@"VAP resource download failed: %@", error.localizedDescription);
            return;
        }
        if (callback) {
            callback(filePath);
        }
    }];
}

#pragma mark - Play Items

- (void)playNotVapResource
{
    [self download:@"https://o-sg.famoapp.com/appres/50994475-6bfd-4904-831d-e2fc62baeaf5.mp4" callback:^(NSString *filePath) {
        [self playNotVap:filePath];
    }];
}

- (void)playVapWithTencentResource2
{
    [self download:@"https://o-sg.famoapp.com/appres/afb41aa6-0593-4ff9-9e41-7d70a8f79356.mp4" callback:^(NSString *filePath) {
        [self playVapx:filePath];
    }];
}

- (void)playTencentVapResource
{
    [self download:@"https://o-sg.famoapp.com/appres/afb41aa6-0593-4ff9-9e41-7d70a8f79356.mp4" callback:^(NSString *filePath) {
        self.isTencentVap = YES;
        [self playVap:filePath contentMode:QGVAPWrapViewContentModeAspectFill];
    }];
}

- (void)playBigoVapResource
{
    [self download:@"https://o-sg.famoapp.com/appres/98badf48-1d3c-4c6b-cd3e-877add1df312.mp4" callback:^(NSString *filePath) {
        self.isBigoVap = YES;
        [self playVap:filePath contentMode:QGVAPWrapViewContentModeAspectFit];
    }];
}

- (void)playFamoVehicleResource
{
    [self download:@"https://o-sg.famoapp.com/universal/bb4b9390-f64e-4957-df12-0ccee8e3e802.mp4" callback:^(NSString *filePath) {
        self.isBigoVap = YES;
        [self playVap:filePath contentMode:QGVAPWrapViewContentModeAspectFit];
    }];
}

- (void)playFamoResource
{
    [self download:@"https://o-sg.famoapp.com/turnover/3101831a-21a9-4288-ed96-9471e65be0c3.mp4" callback:^(NSString *filePath) {
        [self playVap:filePath contentMode:QGVAPWrapViewContentModeAspectFill];
    }];
}

- (void)playMP4_LeftAlpha
{
    [self download:@"https://o-sg.famoapp.com/turnover/a28152ee-1d84-4364-e097-141938099156.mp4" callback:^(NSString *filePath) {
        [self playVap:filePath contentMode:QGVAPWrapViewContentModeAspectFit];
    }];
}

- (void)playMP4_LeftAlpha2
{
    [self download:@"https://o-sg.famoapp.com/turnover/4554f07d-f600-4e00-f7a8-965cb9f5a4b8.mp4" callback:^(NSString *filePath) {
        [self playVap:filePath contentMode:QGVAPWrapViewContentModeAspectFit];
    }];
}

- (void)playMP4_RightAlpha
{
    [self download:@"https://o-sg.famoapp.com/turnover/e4bbab7d-72d0-4711-d551-f25d287e10e7.mp4" callback:^(NSString *filePath) {
        [self playVap:filePath contentMode:QGVAPWrapViewContentModeAspectFit blendMode:QGHWDTextureBlendMode_AlphaRight];
    }];
}

- (void)playMP4_RightAlpha2
{
    [self download:@"https://o-sg.famoapp.com/universal/b0ca8bf8-0150-4991-8cb4-987abe4e48a7.mp4" callback:^(NSString *filePath) {
        [self playVap:filePath contentMode:QGVAPWrapViewContentModeAspectFit blendMode:QGHWDTextureBlendMode_AlphaRight];
    }];
}

- (void)playMP4_RightAlpha3
{
    [self download:@"https://cdn.mejiaoyou.com/uploadSource/bc613130-4021-11f0-9e18-35f1e4498b57.mp4" callback:^(NSString *filePath) {
        [self playVap:filePath contentMode:QGVAPWrapViewContentModeAspectFit blendMode:QGHWDTextureBlendMode_AlphaRight];
    }];
}

- (void)playRocketResource
{
    [self download:@"https://o-sg.famoapp.com/universal/b1702b45-e239-4ec8-d8fc-a15b927615ae.mp4" callback:^(NSString *filePath) {
        [self playVap:filePath contentMode:QGVAPWrapViewContentModeAspectFit blendMode:QGHWDTextureBlendMode_AlphaRight];
    }];
}

#pragma mark - Play Helpers

- (void)playNotVap:(NSString *)resPath
{
    VAPView *mp4View = [[VAPView alloc] initWithFrame:self.view.bounds];
    mp4View.center = CGPointMake(CGRectGetMidX(self.view.bounds), CGRectGetMidY(self.view.bounds));
    mp4View.userInteractionEnabled = YES;
    mp4View.hwd_enterBackgroundOP = [self currentEnterBackgroundOperationType];
    [self.view addSubview:mp4View];
    [mp4View enableOldVersion:YES];
    [mp4View playHWDMP4:resPath repeatCount:0 delegate:self];
}

- (void)playVapx:(NSString *)resPath
{
    VAPView *mp4View = [[VAPView alloc] initWithFrame:self.view.bounds];
    mp4View.center = CGPointMake(CGRectGetMidX(self.view.bounds), CGRectGetMidY(self.view.bounds));
    mp4View.userInteractionEnabled = YES;
    mp4View.hwd_enterBackgroundOP = [self currentEnterBackgroundOperationType];
    [self.view addSubview:mp4View];
    [mp4View setMute:NO];
    [mp4View playHWDMP4:resPath repeatCount:0 delegate:self];
}

- (void)playVapWithWrapView
{
    [self download:@"https://o-sg.famoapp.com/appres/afb41aa6-0593-4ff9-9e41-7d70a8f79356.mp4" callback:^(NSString *filePath) {
        __block BOOL pause = NO;
        QGVAPWrapView *wrapView = [[QGVAPWrapView alloc] initWithFrame:self.view.bounds];
        wrapView.center = CGPointMake(CGRectGetMidX(self.view.bounds), CGRectGetMidY(self.view.bounds));
        wrapView.contentMode = QGVAPWrapViewContentModeAspectFit;
        wrapView.autoDestoryAfterFinish = YES;
        wrapView.hwd_enterBackgroundOP = [self currentEnterBackgroundOperationType];
        [self.view addSubview:wrapView];
        [wrapView setMute:NO];
        [wrapView playHWDMP4:filePath repeatCount:0 delegate:self];

        UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(doNothingonImageviewTap:)];
        __weak typeof(wrapView) weakWrapView = wrapView;
        [wrapView addVapGesture:tap callback:^(UIGestureRecognizer *gestureRecognizer, BOOL insideSource, QGVAPSourceDisplayItem *source) {
            pause = !pause;
            pause ? [weakWrapView pauseHWDMP4] : [weakWrapView resumeHWDMP4];
        }];
    }];
}

- (void)playVap:(NSString *)resPath contentMode:(QGVAPWrapViewContentMode)contentMode
{
    [self playVap:resPath contentMode:contentMode blendMode:QGHWDTextureBlendMode_AlphaLeft];
}

- (void)playVap:(NSString *)resPath contentMode:(QGVAPWrapViewContentMode)contentMode blendMode:(QGHWDTextureBlendMode)blendMode
{
    UIView *containerView = self.effectContainerView;
    FamVapWrapView *wrapView = [[FamVapWrapView alloc] initWithFrame:containerView.bounds];
    wrapView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    wrapView.contentMode = contentMode;
    wrapView.autoDestoryAfterFinish = YES;
    wrapView.hwd_enterBackgroundOP = [self currentEnterBackgroundOperationType];
    self.currentEffectContainerView = containerView;
    [containerView addSubview:wrapView];
    [wrapView setMute:NO];

    if (blendMode == QGHWDTextureBlendMode_AlphaRight) {
        [wrapView playHWDMP4:resPath blendMode:blendMode repeatCount:0 delegate:self];
    } else {
        [wrapView playHWDMP4:resPath playCount:1 delegate:self];
    }

    [self bindPauseGestureForFamVapWrapView:wrapView];
    wrapView.userInteractionEnabled = NO;
    wrapView.vapView.userInteractionEnabled = NO;
}

- (void)bindPauseGestureForFamVapWrapView:(FamVapWrapView *)wrapView
{
    if (!self.enablePauseGestureForFamVapWrapView) {
        return;
    }

    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(doNothingonImageviewTap:)];
    __block BOOL pause = NO;
    __weak typeof(wrapView) weakWrapView = wrapView;
    [wrapView addVapGesture:tap callback:^(UIGestureRecognizer *gestureRecognizer, BOOL insideSource, QGVAPSourceDisplayItem *source) {
        pause = !pause;
        pause ? [weakWrapView pauseHWDMP4] : [weakWrapView resumeHWDMP4];
    }];
}

#pragma mark - UITableViewDataSource & UITableViewDelegate

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    return self.dataList.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    JFVapDebugConfigTableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:NSStringFromClass(JFVapDebugConfigTableViewCell.class) forIndexPath:indexPath];
    [cell setContent:self.dataList[indexPath.row]];
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    JFVapDebugConfigModel *model = self.dataList[indexPath.row];
    if (model.clickCallback) {
        model.clickCallback();
    }
}

#pragma mark - VAPWrapViewDelegate

- (void)vapWrap_viewDidStopPlayMP4:(NSInteger)lastFrameIndex view:(VAPView *)container
{
    [self clearData];
    [self removeVAPContainerOnMainThread:container];
}

- (BOOL)vapWrap_viewshouldStartPlayMP4:(VAPView *)container config:(QGVAPConfigModel *)config
{
    return YES;
}

- (void)vapWrap_viewDidFailPlayMP4:(NSError *)error
{
    NSLog(@"VAP play failed: %@", error.userInfo);
}

- (void)viewDidStopPlayMP4:(NSInteger)lastFrameIndex view:(VAPView *)container
{
    [self clearData];
    [self removeVAPContainerOnMainThread:container];
}

- (BOOL)shouldStartPlayMP4:(VAPView *)container config:(QGVAPConfigModel *)config
{
    return YES;
}

- (void)viewDidFailPlayMP4:(NSError *)error
{
    NSLog(@"VAP play failed: %@", error.userInfo);
}

- (NSString *)contentForVapTag:(NSString *)tag resource:(QGVAPSourceInfo *)info
{
    return [self vapWrapview_contentForVapTag:tag resource:info];
}

- (void)loadVapImageWithURL:(NSString *)urlStr context:(NSDictionary *)context completion:(VAPImageCompletionBlock)completionBlock
{
    [self vapWrapView_loadVapImageWithURL:urlStr context:context completion:completionBlock];
}

- (void)removeVAPContainerOnMainThread:(VAPView *)container
{
    dispatch_async(dispatch_get_main_queue(), ^{
        UIView *superview = container.superview;
        if ([superview isKindOfClass:QGVAPWrapView.class]) {
            [superview removeFromSuperview];
        } else {
            [container removeFromSuperview];
        }
    });
}

- (NSString *)vapWrapview_contentForVapTag:(NSString *)tag resource:(QGVAPSourceInfo *)info
{
    NSLog(@"vap key-value = %@ : %@", info.contentTag, info.contentTagValue);

    if (self.isTencentVap) {
        NSDictionary *extraInfo = @{
            @"[imgUser]": kJFVapDemoAvatarURL,
            @"[imgAnchor]": kJFVapDemoAvatarURL,
            @"[textAnchor]": @"文字1",
            @"[textUser]": @"文字2"
        };
        return extraInfo[tag] ?: @"";
    }

    if (self.isBigoVap) {
        NSDictionary *extraInfo = @{
            @"p_img": kJFVapDemoAvatarURL,
            @"p_text": @"文字1",
            @"p_txt": @"文字1"
        };
        return extraInfo[tag] ?: @"";
    }

    return @"";
}

- (void)vapWrapView_loadVapImageWithURL:(NSString *)urlStr context:(NSDictionary *)context completion:(VAPImageCompletionBlock)completionBlock
{
    QGVAPSourceInfo *resource = context[@"resource"];
    if ([resource.type isEqualToString:kQGAGAttachmentSourceTypeImg] &&
        [resource.loadType isEqualToString:QGAGAttachmentSourceLoadTypeNet]) {
        [JFVapImageCacheHelper getLocalImageURLForURL:[NSURL URLWithString:urlStr] completion:^(NSURL *localURL, NSError *error) {
            if (error || !localURL) {
                return;
            }

            UIImage *image = [UIImage imageWithContentsOfFile:localURL.path];
            completionBlock(image, nil, urlStr);
        }];
    }
}

#pragma mark - Gesture

- (void)onImageviewTap:(UIGestureRecognizer *)gesture
{
    [gesture.view removeFromSuperview];
}

- (void)doNothingonImageviewTap:(UIGestureRecognizer *)gesture
{
}

@end
