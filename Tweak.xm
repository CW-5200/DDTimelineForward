#import <UIKit/UIKit.h>
#import <objc/runtime.h>

// 插件管理器接口
@interface WCPluginsMgr : NSObject
+ (instancetype)sharedInstance;
- (void)registerControllerWithTitle:(NSString *)title version:(NSString *)version controller:(NSString *)controller;
@end

// 微信相关类声明
@interface WCDataItem : NSObject
@property(retain, nonatomic) NSString *username;
- (id)getMediaWraps; // 获取媒体数组
@end

@interface WCMediaItem : NSObject
@property(retain, nonatomic) NSString *mid;
- (id)getMediaWrapUrl; // 获取媒体URL
- (_Bool)hasData; // 是否有数据
- (_Bool)hasPreview; // 是否有预览
@end

@interface WCOperateFloatView : UIView
@property(readonly, nonatomic) UIButton *m_likeBtn;
@property(readonly, nonatomic) WCDataItem *m_item;
@property(nonatomic) __weak UINavigationController *navigationController;
- (void)showWithItemData:(id)arg1 tipPoint:(struct CGPoint)arg2;
- (double)buttonWidth:(id)arg1;
@end

@interface WCForwardViewController : UIViewController
- (id)initWithDataItem:(WCDataItem *)arg1;
@end

@interface WCFacade : NSObject
+ (instancetype)sharedInstance;
- (void)downloadMedia:(id)arg1 downloadType:(long long)arg2; // 下载媒体
- (_Bool)IsMediaItemInDownloadQueue:(id)arg1; // 检查是否在下载队列
@end

// 微信媒体下载器
@interface WCMediaDownloader : NSObject
@property(readonly, nonatomic) WCMediaItem *mediaItem;
@property(readonly, nonatomic) WCDataItem *dataItem;
- (id)initWithDataItem:(id)arg1 mediaItem:(id)arg2;
- (void)startDownloadWithCompletionHandler:(void(^)(void))arg1;
- (_Bool)hasDownloaded;
@end

// 进度缓存管理器
@interface DDProgressCacheManager : NSObject
+ (instancetype)sharedInstance;
- (void)saveProgress:(float)progress forKey:(NSString *)key;
- (float)getProgressForKey:(NSString *)key;
- (void)clearProgressForKey:(NSString *)key;
- (void)clearAllProgress;
@end

@implementation DDProgressCacheManager {
    NSMutableDictionary *_progressCache;
}

+ (instancetype)sharedInstance {
    static DDProgressCacheManager *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[self alloc] init];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _progressCache = [NSMutableDictionary dictionary];
    }
    return self;
}

- (void)saveProgress:(float)progress forKey:(NSString *)key {
    _progressCache[key] = @(progress);
}

- (float)getProgressForKey:(NSString *)key {
    NSNumber *progressNum = _progressCache[key];
    return progressNum ? [progressNum floatValue] : 0.0f;
}

- (void)clearProgressForKey:(NSString *)key {
    [_progressCache removeObjectForKey:key];
}

- (void)clearAllProgress {
    [_progressCache removeAllObjects];
}

@end

// 插件配置类
@interface DDTimelineForwardConfig : NSObject
@property (class, nonatomic, assign, getter=isTimelineForwardEnabled) BOOL timelineForwardEnabled;
+ (void)setupDefaults;
@end

@implementation DDTimelineForwardConfig

static NSString *const kTimelineForwardEnabledKey = @"DDTimelineForwardEnabled";

+ (BOOL)isTimelineForwardEnabled {
    return [[NSUserDefaults standardUserDefaults] boolForKey:kTimelineForwardEnabledKey];
}

+ (void)setTimelineForwardEnabled:(BOOL)enabled {
    [[NSUserDefaults standardUserDefaults] setBool:enabled forKey:kTimelineForwardEnabledKey];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

+ (void)setupDefaults {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    if (![defaults objectForKey:kTimelineForwardEnabledKey]) {
        [defaults setBool:YES forKey:kTimelineForwardEnabledKey];
        [defaults synchronize];
    }
}

@end

// 进度显示窗口（转圈+百分比效果）
@interface DDProgressWindow : UIWindow
- (instancetype)initWithFrame:(CGRect)frame title:(NSString *)title;
- (void)updateProgress:(float)progress withStatus:(NSString *)status;
- (void)show;
- (void)hide;
@end

@implementation DDProgressWindow {
    UIActivityIndicatorView *_activityIndicator;
    UILabel *_titleLabel;
    UILabel *_percentLabel;
    UILabel *_statusLabel;
    UIView *_progressBar;
    UIView *_progressBarFill;
    NSString *_currentTitle;
    UIVisualEffectView *_blurView;
}

- (instancetype)initWithFrame:(CGRect)frame title:(NSString *)title {
    self = [super initWithFrame:frame];
    if (self) {
        _currentTitle = title;
        self.windowLevel = UIWindowLevelAlert + 1;
        self.backgroundColor = [UIColor clearColor];
        
        // 创建毛玻璃效果背景
        [self setupBlurBackground];
        
        [self setupUI];
    }
    return self;
}

- (void)setupBlurBackground {
    UIBlurEffect *blurEffect;
    if (@available(iOS 13.0, *)) {
        blurEffect = [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemUltraThinMaterial];
    } else {
        blurEffect = [UIBlurEffect effectWithStyle:UIBlurEffectStyleLight];
    }
    
    _blurView = [[UIVisualEffectView alloc] initWithEffect:blurEffect];
    _blurView.frame = self.bounds;
    _blurView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _blurView.alpha = 0.95;
    
    UIView *overlayView = [[UIView alloc] initWithFrame:_blurView.bounds];
    overlayView.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.2];
    overlayView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [_blurView.contentView addSubview:overlayView];
    
    [self addSubview:_blurView];
}

- (void)setupUI {
    // 内容视图
    UIView *contentView = [[UIView alloc] init];
    if (@available(iOS 13.0, *)) {
        contentView.backgroundColor = [[UIColor tertiarySystemBackgroundColor] colorWithAlphaComponent:0.9];
    } else {
        contentView.backgroundColor = [[UIColor colorWithRed:0.95 green:0.95 blue:0.97 alpha:1.0] colorWithAlphaComponent:0.9];
    }
    contentView.layer.cornerRadius = 16.0;
    contentView.layer.borderWidth = 0.5;
    contentView.layer.borderColor = [UIColor separatorColor].CGColor;
    contentView.translatesAutoresizingMaskIntoConstraints = NO;
    
    // 标题
    _titleLabel = [[UILabel alloc] init];
    _titleLabel.text = _currentTitle;
    _titleLabel.font = [UIFont systemFontOfSize:18 weight:UIFontWeightSemibold];
    _titleLabel.textColor = [UIColor labelColor];
    _titleLabel.textAlignment = NSTextAlignmentCenter;
    _titleLabel.numberOfLines = 0;
    _titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    
    // 活动指示器
    _activityIndicator = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleLarge];
    _activityIndicator.color = [UIColor labelColor];
    _activityIndicator.translatesAutoresizingMaskIntoConstraints = NO;
    [_activityIndicator startAnimating];
    
    // 百分比标签
    _percentLabel = [[UILabel alloc] init];
    _percentLabel.text = @"0%";
    _percentLabel.font = [UIFont monospacedDigitSystemFontOfSize:24 weight:UIFontWeightBold];
    _percentLabel.textColor = [UIColor labelColor];
    _percentLabel.textAlignment = NSTextAlignmentCenter;
    _percentLabel.translatesAutoresizingMaskIntoConstraints = NO;
    
    // 状态标签
    _statusLabel = [[UILabel alloc] init];
    _statusLabel.text = @"准备下载...";
    _statusLabel.font = [UIFont systemFontOfSize:14];
    _statusLabel.textColor = [UIColor secondaryLabelColor];
    _statusLabel.textAlignment = NSTextAlignmentCenter;
    _statusLabel.numberOfLines = 0;
    _statusLabel.translatesAutoresizingMaskIntoConstraints = NO;
    
    // 进度条背景
    _progressBar = [[UIView alloc] init];
    _progressBar.backgroundColor = [UIColor systemGray5Color];
    _progressBar.layer.cornerRadius = 4;
    _progressBar.translatesAutoresizingMaskIntoConstraints = NO;
    
    // 进度条填充
    _progressBarFill = [[UIView alloc] init];
    _progressBarFill.backgroundColor = [UIColor systemBlueColor];
    _progressBarFill.layer.cornerRadius = 4;
    _progressBarFill.translatesAutoresizingMaskIntoConstraints = NO;
    
    [_progressBar addSubview:_progressBarFill];
    
    [contentView addSubview:_titleLabel];
    [contentView addSubview:_activityIndicator];
    [contentView addSubview:_percentLabel];
    [contentView addSubview:_statusLabel];
    [contentView addSubview:_progressBar];
    
    [self addSubview:contentView];
    
    // 布局约束
    [NSLayoutConstraint activateConstraints:@[
        // 内容视图
        [contentView.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
        [contentView.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
        [contentView.widthAnchor constraintEqualToConstant:280],
        [contentView.heightAnchor constraintEqualToConstant:260],
        
        // 标题
        [_titleLabel.topAnchor constraintEqualToAnchor:contentView.topAnchor constant:25],
        [_titleLabel.leadingAnchor constraintEqualToAnchor:contentView.leadingAnchor constant:20],
        [_titleLabel.trailingAnchor constraintEqualToAnchor:contentView.trailingAnchor constant:-20],
        
        // 活动指示器
        [_activityIndicator.topAnchor constraintEqualToAnchor:_titleLabel.bottomAnchor constant:20],
        [_activityIndicator.centerXAnchor constraintEqualToAnchor:contentView.centerXAnchor],
        
        // 百分比标签
        [_percentLabel.topAnchor constraintEqualToAnchor:_activityIndicator.bottomAnchor constant:10],
        [_percentLabel.centerXAnchor constraintEqualToAnchor:contentView.centerXAnchor],
        
        // 状态标签
        [_statusLabel.topAnchor constraintEqualToAnchor:_percentLabel.bottomAnchor constant:10],
        [_statusLabel.leadingAnchor constraintEqualToAnchor:contentView.leadingAnchor constant:20],
        [_statusLabel.trailingAnchor constraintEqualToAnchor:contentView.trailingAnchor constant:-20],
        
        // 进度条
        [_progressBar.topAnchor constraintEqualToAnchor:_statusLabel.bottomAnchor constant:20],
        [_progressBar.leadingAnchor constraintEqualToAnchor:contentView.leadingAnchor constant:20],
        [_progressBar.trailingAnchor constraintEqualToAnchor:contentView.trailingAnchor constant:-20],
        [_progressBar.heightAnchor constraintEqualToConstant:8],
        [_progressBar.bottomAnchor constraintLessThanOrEqualToAnchor:contentView.bottomAnchor constant:-25],
        
        // 进度条填充
        [_progressBarFill.leadingAnchor constraintEqualToAnchor:_progressBar.leadingAnchor],
        [_progressBarFill.topAnchor constraintEqualToAnchor:_progressBar.topAnchor],
        [_progressBarFill.bottomAnchor constraintEqualToAnchor:_progressBar.bottomAnchor],
        [_progressBarFill.widthAnchor constraintEqualToConstant:0]
    ]];
}

- (void)updateProgress:(float)progress withStatus:(NSString *)status {
    dispatch_async(dispatch_get_main_queue(), ^{
        int percent = (int)(progress * 100);
        _percentLabel.text = [NSString stringWithFormat:@"%d%%", percent];
        _statusLabel.text = status;
        
        // 更新进度条宽度
        CGFloat barWidth = _progressBar.frame.size.width * progress;
        _progressBarFill.frame = CGRectMake(0, 0, barWidth, _progressBar.frame.size.height);
        
        // 颜色变化
        if (progress >= 1.0) {
            _percentLabel.textColor = [UIColor systemGreenColor];
            _progressBarFill.backgroundColor = [UIColor systemGreenColor];
            [_activityIndicator stopAnimating];
        }
    });
}

- (void)show {
    self.hidden = NO;
    [self makeKeyAndVisible];
}

- (void)hide {
    self.hidden = YES;
    [_activityIndicator stopAnimating];
    
    UIWindow *mainWindow = [[[UIApplication sharedApplication] delegate] window];
    [mainWindow makeKeyAndVisible];
}

@end

// 设置界面控制器
@interface DDTimelineForwardSettingsController : UIViewController
@property (nonatomic, strong) UISwitch *forwardSwitch;
@end

@implementation DDTimelineForwardSettingsController

- (void)viewDidLoad {
    [super viewDidLoad];
    
    self.title = @"朋友圈转发设置";
    self.view.backgroundColor = [UIColor systemBackgroundColor];
    
    if ([self respondsToSelector:@selector(sheetPresentationController)]) {
        UISheetPresentationController *sheet = self.sheetPresentationController;
        if (sheet) {
            sheet.detents = @[UISheetPresentationControllerDetent.mediumDetent];
            sheet.prefersGrabberVisible = YES;
            sheet.preferredCornerRadius = 20.0;
        }
    }
    
    [self setupUI];
}

- (void)setupUI {
    UIStackView *mainStack = [[UIStackView alloc] init];
    mainStack.axis = UILayoutConstraintAxisVertical;
    mainStack.spacing = 24;
    mainStack.alignment = UIStackViewAlignmentFill;
    mainStack.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:mainStack];
    
    // 开关控件
    UIView *switchContainer = [[UIView alloc] init];
    switchContainer.translatesAutoresizingMaskIntoConstraints = NO;
    
    UILabel *titleLabel = [[UILabel alloc] init];
    titleLabel.text = @"启用朋友圈转发";
    titleLabel.font = [UIFont systemFontOfSize:17 weight:UIFontWeightSemibold];
    titleLabel.textColor = [UIColor labelColor];
    titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [switchContainer addSubview:titleLabel];
    
    self.forwardSwitch = [[UISwitch alloc] init];
    [self.forwardSwitch setOn:[DDTimelineForwardConfig isTimelineForwardEnabled]];
    [self.forwardSwitch addTarget:self action:@selector(switchChanged:) forControlEvents:UIControlEventValueChanged];
    self.forwardSwitch.translatesAutoresizingMaskIntoConstraints = NO;
    [switchContainer addSubview:self.forwardSwitch];
    
    [NSLayoutConstraint activateConstraints:@[
        [titleLabel.leadingAnchor constraintEqualToAnchor:switchContainer.leadingAnchor],
        [titleLabel.centerYAnchor constraintEqualToAnchor:switchContainer.centerYAnchor],
        [self.forwardSwitch.trailingAnchor constraintEqualToAnchor:switchContainer.trailingAnchor],
        [self.forwardSwitch.centerYAnchor constraintEqualToAnchor:switchContainer.centerYAnchor]
    ]];
    
    [mainStack addArrangedSubview:switchContainer];
    
    // 说明文字
    UILabel *descriptionLabel = [[UILabel alloc] init];
    descriptionLabel.text = @"启用后在朋友圈菜单中添加「转发」按钮，可快速转发朋友圈内容（包含媒体文件下载）";
    descriptionLabel.font = [UIFont systemFontOfSize:14];
    descriptionLabel.textColor = [UIColor secondaryLabelColor];
    descriptionLabel.numberOfLines = 0;
    descriptionLabel.textAlignment = NSTextAlignmentCenter;
    [mainStack addArrangedSubview:descriptionLabel];
    
    // 版本信息
    UILabel *versionLabel = [[UILabel alloc] init];
    versionLabel.text = @"DD朋友圈转发 v1.5.0";
    versionLabel.font = [UIFont systemFontOfSize:12];
    versionLabel.textColor = [UIColor tertiaryLabelColor];
    versionLabel.textAlignment = NSTextAlignmentCenter;
    [mainStack addArrangedSubview:versionLabel];
    
    // 布局约束
    [NSLayoutConstraint activateConstraints:@[
        [mainStack.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:32],
        [mainStack.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:20],
        [mainStack.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-20],
        [switchContainer.heightAnchor constraintEqualToConstant:44]
    ]];
}

- (void)switchChanged:(UISwitch *)sender {
    [DDTimelineForwardConfig setTimelineForwardEnabled:sender.isOn];
}

@end

// Hook实现 - 修复媒体下载问题
%hook WCOperateFloatView

- (void)showWithItemData:(id)arg1 tipPoint:(struct CGPoint)arg2 {
    %orig(arg1, arg2);
    
    if ([DDTimelineForwardConfig isTimelineForwardEnabled]) {
        UIButton *forwardButton = [UIButton buttonWithType:UIButtonTypeCustom];
        [forwardButton setTitle:@"转发" forState:UIControlStateNormal];
        [forwardButton setTitleColor:self.m_likeBtn.currentTitleColor forState:UIControlStateNormal];
        forwardButton.titleLabel.font = self.m_likeBtn.titleLabel.font;
        [forwardButton addTarget:self action:@selector(dd_forwardTimeline:) forControlEvents:UIControlEventTouchUpInside];
        
        CGFloat buttonWidth = [self buttonWidth:self.m_likeBtn];
        CGRect likeBtnFrame = self.m_likeBtn.frame;
        
        forwardButton.frame = CGRectMake(
            CGRectGetMaxX(likeBtnFrame) + buttonWidth,
            likeBtnFrame.origin.y,
            buttonWidth,
            likeBtnFrame.size.height
        );
        
        [self addSubview:forwardButton];
        
        // 调整容器宽度
        CGRect containerFrame = self.m_likeBtn.superview.frame;
        containerFrame.size.width += buttonWidth;
        self.m_likeBtn.superview.frame = containerFrame;
        
        CGRect selfFrame = self.frame;
        selfFrame.size.width += buttonWidth;
        self.frame = selfFrame;
    }
}

%new
- (void)dd_allDownloadsCompletedWithProgressWindow:(DDProgressWindow *)progressWindow dataItem:(WCDataItem *)dataItem {
    __weak typeof(self) weakSelf = self;
    
    // 延迟关闭进度窗口并跳转
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [progressWindow hide];
        [weakSelf dd_showForwardViewControllerWithDataItem:dataItem];
    });
}

%new
- (void)dd_showForwardViewControllerWithDataItem:(WCDataItem *)dataItem {
    // 进入转发界面
    WCForwardViewController *forwardVC = [[objc_getClass("WCForwardViewController") alloc] initWithDataItem:dataItem];
    if (self.navigationController) {
        [self.navigationController pushViewController:forwardVC animated:YES];
    }
}

%new
- (void)dd_forwardTimeline:(UIButton *)sender {
    __weak typeof(self) weakSelf = self;
    WCDataItem *dataItem = self.m_item;
    
    // 获取媒体数组
    NSArray *mediaItems = nil;
    if ([dataItem respondsToSelector:@selector(getMediaWraps)]) {
        mediaItems = [dataItem getMediaWraps];
    }
    
    // 创建进度窗口
    CGRect screenBounds = [UIScreen mainScreen].bounds;
    DDProgressWindow *progressWindow = [[DDProgressWindow alloc] initWithFrame:screenBounds title:@"正在下载媒体文件"];
    [progressWindow show];
    
    // 如果没有媒体文件，直接跳转
    if (!mediaItems || mediaItems.count == 0) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [progressWindow hide];
            [weakSelf dd_showForwardViewControllerWithDataItem:dataItem];
        });
        return;
    }
    
    // 使用WCMediaDownloader下载媒体文件
    __block NSUInteger completedCount = 0;
    __block NSUInteger totalCount = mediaItems.count;
    __block NSMutableArray *downloaders = [NSMutableArray array];
    
    for (WCMediaItem *mediaItem in mediaItems) {
        // 检查是否已经下载
        if ([mediaItem hasData] || [mediaItem hasPreview]) {
            completedCount++;
            [progressWindow updateProgress:(float)completedCount/totalCount 
                               withStatus:[NSString stringWithFormat:@"跳过已下载文件 (%lu/%lu)", (unsigned long)completedCount, (unsigned long)totalCount]];
            
            if (completedCount == totalCount) {
                [self dd_allDownloadsCompletedWithProgressWindow:progressWindow dataItem:dataItem];
            }
            continue;
        }
        
        // 检查是否已经在下载队列中
        WCFacade *facade = [objc_getClass("WCFacade") sharedInstance];
        if ([facade IsMediaItemInDownloadQueue:mediaItem]) {
            completedCount++;
            [progressWindow updateProgress:(float)completedCount/totalCount 
                               withStatus:[NSString stringWithFormat:@"已在下载队列 (%lu/%lu)", (unsigned long)completedCount, (unsigned long)totalCount]];
            
            if (completedCount == totalCount) {
                [self dd_allDownloadsCompletedWithProgressWindow:progressWindow dataItem:dataItem];
            }
            continue;
        }
        
        // 创建下载器
        WCMediaDownloader *downloader = [[objc_getClass("WCMediaDownloader") alloc] initWithDataItem:dataItem mediaItem:mediaItem];
        if (downloader) {
            [downloaders addObject:downloader];
            
            // 开始下载
            [downloader startDownloadWithCompletionHandler:^{
                dispatch_async(dispatch_get_main_queue(), ^{
                    completedCount++;
                    
                    [progressWindow updateProgress:(float)completedCount/totalCount 
                                       withStatus:[NSString stringWithFormat:@"下载完成 (%lu/%lu)", 
                                                  (unsigned long)completedCount, (unsigned long)totalCount]];
                    
                    // 所有下载完成
                    if (completedCount == totalCount) {
                        [self dd_allDownloadsCompletedWithProgressWindow:progressWindow dataItem:dataItem];
                    }
                });
            }];
        } else {
            // 无法创建下载器，视为完成
            completedCount++;
            [progressWindow updateProgress:(float)completedCount/totalCount 
                               withStatus:[NSString stringWithFormat:@"跳过无法下载的文件 (%lu/%lu)", (unsigned long)completedCount, (unsigned long)totalCount]];
            
            if (completedCount == totalCount) {
                [self dd_allDownloadsCompletedWithProgressWindow:progressWindow dataItem:dataItem];
            }
        }
    }
    
    // 如果所有文件都已跳过（已下载或在队列中）
    if (completedCount == totalCount && downloaders.count == 0) {
        [self dd_allDownloadsCompletedWithProgressWindow:progressWindow dataItem:dataItem];
    }
}

%end

// 插件初始化
%ctor {
    @autoreleasepool {
        [DDProgressCacheManager sharedInstance];
        [DDTimelineForwardConfig setupDefaults];
        
        if (NSClassFromString(@"WCPluginsMgr")) {
            [[objc_getClass("WCPluginsMgr") sharedInstance] 
                registerControllerWithTitle:@"DD朋友圈转发" 
                                   version:@"1.5.0" 
                               controller:@"DDTimelineForwardSettingsController"];
        }
        
        NSLog(@"DD朋友圈转发插件已加载 v1.5.0");
    }
}