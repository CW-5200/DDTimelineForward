// Tweak.xm - 修复版本
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
@property(retain, nonatomic) id contentObj;
- (id)firstMediaItem;
@end

@interface WCMediaItem : NSObject
@property(nonatomic) int type;
- (BOOL)hasData;
- (NSString *)getMediaWrapUrl;
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

@interface WCMediaDownloader : NSObject
@property(readonly, nonatomic) WCDataItem *dataItem;
@property(readonly, nonatomic) WCMediaItem *mediaItem;
- (id)initWithDataItem:(WCDataItem *)arg1 mediaItem:(WCMediaItem *)arg2;
- (BOOL)hasDownloaded;
- (void)startDownloadWithCompletionHandler:(void (^)(BOOL success))completionHandler;
@end

@interface WCDownloadMgr : NSObject
+ (id)sharedInstance;
- (void)downloadMedia:(id)arg1 downloadType:(long long)arg2;
@end

// 进度缓存管理器
@interface DDProgressCacheManager : NSObject
+ (instancetype)sharedInstance;
- (void)saveProgress:(float)progress forKey:(NSString *)key;
- (float)getProgressForKey:(NSString *)key;
- (void)clearProgressForKey:(NSString *)key;
- (void)saveDownloadTask:(id)task forKey:(NSString *)key;
- (id)getDownloadTaskForKey:(NSString *)key;
- (void)clearDownloadTaskForKey:(NSString *)key;
@end

@implementation DDProgressCacheManager {
    NSMutableDictionary *_progressCache;
    NSMutableDictionary *_downloadTaskCache;
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
        _downloadTaskCache = [NSMutableDictionary dictionary];
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

- (void)saveDownloadTask:(id)task forKey:(NSString *)key {
    _downloadTaskCache[key] = task;
}

- (id)getDownloadTaskForKey:(NSString *)key {
    return _downloadTaskCache[key];
}

- (void)clearDownloadTaskForKey:(NSString *)key {
    [_downloadTaskCache removeObjectForKey:key];
}

@end

// 插件配置类
@interface DDTimelineForwardConfig : NSObject
@property (class, nonatomic, assign, getter=isTimelineForwardEnabled) BOOL timelineForwardEnabled;
@property (class, nonatomic, assign, getter=isAutoDownloadMedia) BOOL autoDownloadMedia;
+ (void)setupDefaults;
@end

@implementation DDTimelineForwardConfig

static NSString *const kTimelineForwardEnabledKey = @"DDTimelineForwardEnabled";
static NSString *const kAutoDownloadMediaKey = @"DDAutoDownloadMedia";

+ (BOOL)isTimelineForwardEnabled {
    return [[NSUserDefaults standardUserDefaults] boolForKey:kTimelineForwardEnabledKey];
}

+ (void)setTimelineForwardEnabled:(BOOL)enabled {
    [[NSUserDefaults standardUserDefaults] setBool:enabled forKey:kTimelineForwardEnabledKey];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

+ (BOOL)isAutoDownloadMedia {
    return [[NSUserDefaults standardUserDefaults] boolForKey:kAutoDownloadMediaKey];
}

+ (void)setAutoDownloadMedia:(BOOL)enabled {
    [[NSUserDefaults standardUserDefaults] setBool:enabled forKey:kAutoDownloadMediaKey];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

+ (void)setupDefaults {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    if (![defaults objectForKey:kTimelineForwardEnabledKey]) {
        [defaults setBool:YES forKey:kTimelineForwardEnabledKey];
    }
    if (![defaults objectForKey:kAutoDownloadMediaKey]) {
        [defaults setBool:YES forKey:kAutoDownloadMediaKey];
    }
    [defaults synchronize];
}

@end

// 进度显示窗口（转圈+百分比效果）
@interface DDProgressWindow : UIWindow
@property (nonatomic, strong) WCMediaDownloader *downloader;
- (instancetype)initWithFrame:(CGRect)frame username:(NSString *)username;
- (void)updateProgress:(float)progress;
- (void)startDownloadWithMediaItem:(WCMediaItem *)mediaItem dataItem:(WCDataItem *)dataItem;
- (void)show;
- (void)hide;
@end

@implementation DDProgressWindow {
    UIActivityIndicatorView *_activityIndicator;
    UILabel *_titleLabel;
    UILabel *_percentLabel;
    UILabel *_statusLabel;
    UIButton *_cancelButton;
    NSString *_username;
    UIVisualEffectView *_blurView;
    NSTimer *_progressTimer;
    float _currentProgress;
}

- (instancetype)initWithFrame:(CGRect)frame username:(NSString *)username {
    self = [super initWithFrame:frame];
    if (self) {
        _username = username;
        _currentProgress = 0.0f;
        self.windowLevel = UIWindowLevelAlert + 1;
        
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
    // 标题
    _titleLabel = [[UILabel alloc] init];
    _titleLabel.text = @"正在准备转发";
    _titleLabel.font = [UIFont systemFontOfSize:18 weight:UIFontWeightSemibold];
    _titleLabel.textColor = [UIColor labelColor];
    _titleLabel.textAlignment = NSTextAlignmentCenter;
    _titleLabel.numberOfLines = 0;
    _titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    
    // 活动指示器（转圈）
    _activityIndicator = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleLarge];
    _activityIndicator.color = [UIColor labelColor];
    _activityIndicator.translatesAutoresizingMaskIntoConstraints = NO;
    [_activityIndicator startAnimating];
    
    // 百分比标签
    _percentLabel = [[UILabel alloc] init];
    _percentLabel.text = @"0%";
    _percentLabel.font = [UIFont monospacedDigitSystemFontOfSize:24 weight:UIFontWeightMedium];
    _percentLabel.textColor = [UIColor labelColor];
    _percentLabel.textAlignment = NSTextAlignmentCenter;
    _percentLabel.translatesAutoresizingMaskIntoConstraints = NO;
    
    // 状态标签
    _statusLabel = [[UILabel alloc] init];
    _statusLabel.text = @"正在检查媒体文件...";
    _statusLabel.font = [UIFont systemFontOfSize:14];
    _statusLabel.textColor = [UIColor secondaryLabelColor];
    _statusLabel.textAlignment = NSTextAlignmentCenter;
    _statusLabel.numberOfLines = 0;
    _statusLabel.translatesAutoresizingMaskIntoConstraints = NO;
    
    // 取消按钮
    _cancelButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [_cancelButton setTitle:@"取消" forState:UIControlStateNormal];
    [_cancelButton setTitleColor:[UIColor systemRedColor] forState:UIControlStateNormal];
    _cancelButton.titleLabel.font = [UIFont systemFontOfSize:18 weight:UIFontWeightRegular];
    _cancelButton.translatesAutoresizingMaskIntoConstraints = NO;
    [_cancelButton addTarget:self action:@selector(cancelButtonPressed) forControlEvents:UIControlEventTouchUpInside];
    
    // 内容视图
    UIView *contentView = [[UIView alloc] init];
    if (@available(iOS 13.0, *)) {
        contentView.backgroundColor = [[UIColor secondarySystemBackgroundColor] colorWithAlphaComponent:0.85];
    } else {
        contentView.backgroundColor = [[UIColor colorWithRed:0.95 green:0.95 blue:0.97 alpha:1.0] colorWithAlphaComponent:0.85];
    }
    contentView.layer.cornerRadius = 16.0;
    contentView.layer.borderWidth = 0.5;
    contentView.layer.borderColor = [UIColor separatorColor].CGColor;
    contentView.translatesAutoresizingMaskIntoConstraints = NO;
    
    [contentView addSubview:_titleLabel];
    [contentView addSubview:_activityIndicator];
    [contentView addSubview:_percentLabel];
    [contentView addSubview:_statusLabel];
    [contentView addSubview:_cancelButton];
    
    [self addSubview:contentView];
    
    // 布局约束
    [NSLayoutConstraint activateConstraints:@[
        [contentView.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
        [contentView.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
        [contentView.widthAnchor constraintEqualToConstant:280],
        [contentView.heightAnchor constraintEqualToConstant:280],
        
        [_titleLabel.topAnchor constraintEqualToAnchor:contentView.topAnchor constant:25],
        [_titleLabel.leadingAnchor constraintEqualToAnchor:contentView.leadingAnchor constant:20],
        [_titleLabel.trailingAnchor constraintEqualToAnchor:contentView.trailingAnchor constant:-20],
        
        [_activityIndicator.topAnchor constraintEqualToAnchor:_titleLabel.bottomAnchor constant:20],
        [_activityIndicator.centerXAnchor constraintEqualToAnchor:contentView.centerXAnchor],
        [_activityIndicator.widthAnchor constraintEqualToConstant:50],
        [_activityIndicator.heightAnchor constraintEqualToConstant:50],
        
        [_percentLabel.topAnchor constraintEqualToAnchor:_activityIndicator.bottomAnchor constant:15],
        [_percentLabel.centerXAnchor constraintEqualToAnchor:contentView.centerXAnchor],
        
        [_statusLabel.topAnchor constraintEqualToAnchor:_percentLabel.bottomAnchor constant:10],
        [_statusLabel.leadingAnchor constraintEqualToAnchor:contentView.leadingAnchor constant:20],
        [_statusLabel.trailingAnchor constraintEqualToAnchor:contentView.trailingAnchor constant:-20],
        
        [_cancelButton.topAnchor constraintEqualToAnchor:_statusLabel.bottomAnchor constant:20],
        [_cancelButton.centerXAnchor constraintEqualToAnchor:contentView.centerXAnchor],
        [_cancelButton.bottomAnchor constraintLessThanOrEqualToAnchor:contentView.bottomAnchor constant:-20]
    ]];
}

- (void)updateProgress:(float)progress status:(NSString *)status {
    dispatch_async(dispatch_get_main_queue(), ^{
        _currentProgress = progress;
        int percent = (int)(progress * 100);
        _percentLabel.text = [NSString stringWithFormat:@"%d%%", percent];
        
        if (status) {
            _statusLabel.text = status;
        }
        
        // 保存进度到缓存
        NSString *cacheKey = [NSString stringWithFormat:@"forward_progress_%@", _username];
        [[DDProgressCacheManager sharedInstance] saveProgress:progress forKey:cacheKey];
        
        // 完成时改变颜色和文本
        if (progress >= 1.0) {
            _percentLabel.textColor = [UIColor systemGreenColor];
            _statusLabel.text = @"媒体文件准备完成！";
            [_activityIndicator stopAnimating];
        }
    });
}

- (void)startDownloadWithMediaItem:(WCMediaItem *)mediaItem dataItem:(WCDataItem *)dataItem {
    if (!mediaItem || ![DDTimelineForwardConfig isAutoDownloadMedia]) {
        [self updateProgress:1.0 status:@"跳过媒体下载"];
        [self performSelector:@selector(proceedToForward) withObject:nil afterDelay:1.0];
        return;
    }
    
    // 检查是否已经下载
    if ([mediaItem hasData]) {
        [self updateProgress:1.0 status:@"媒体文件已存在"];
        [self performSelector:@selector(proceedToForward) withObject:nil afterDelay:1.0];
        return;
    }
    
    [self updateProgress:0.1 status:@"开始下载媒体文件..."];
    
    // 创建下载器
    self.downloader = [[objc_getClass("WCMediaDownloader") alloc] initWithDataItem:dataItem mediaItem:mediaItem];
    if (self.downloader) {
        // 保存下载器引用
        NSString *cacheKey = [NSString stringWithFormat:@"forward_downloader_%@", _username];
        [[DDProgressCacheManager sharedInstance] saveDownloadTask:self.downloader forKey:cacheKey];
        
        // 开始下载
        [self.downloader startDownloadWithCompletionHandler:^(BOOL success) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (success) {
                    [self updateProgress:1.0 status:@"下载完成！"];
                    [self performSelector:@selector(proceedToForward) withObject:nil afterDelay:1.0];
                } else {
                    [self updateProgress:0.0 status:@"下载失败，将尝试转发原链接"];
                    [self performSelector:@selector(proceedToForward) withObject:nil afterDelay:2.0];
                }
            });
        }];
        
        // 启动进度更新定时器
        _progressTimer = [NSTimer scheduledTimerWithTimeInterval:0.5 
                                                         target:self 
                                                       selector:@selector(updateDownloadProgress) 
                                                       userInfo:nil 
                                                        repeats:YES];
    } else {
        [self updateProgress:1.0 status:@"无法创建下载器"];
        [self performSelector:@selector(proceedToForward) withObject:nil afterDelay:1.0];
    }
}

- (void)updateDownloadProgress {
    // 这里可以根据实际情况获取下载进度
    // 由于WCMediaDownloader没有提供进度回调，我们使用模拟进度
    // 实际项目中可以替换为真实的进度获取逻辑
    if (_currentProgress < 0.9) {
        _currentProgress += 0.1;
        [self updateProgress:_currentProgress status:@"正在下载媒体文件..."];
    }
}

- (void)proceedToForward {
    [self hide];
    
    // 清理定时器
    [_progressTimer invalidate];
    _progressTimer = nil;
    
    // 执行转发操作
    if (self.onCompletion) {
        self.onCompletion();
    }
}

- (void)cancelButtonPressed {
    [self hide];
    
    // 清理定时器
    [_progressTimer invalidate];
    _progressTimer = nil;
    
    // 取消下载
    if (self.downloader) {
        // 这里可以调用取消下载的方法（如果存在）
        NSString *cacheKey = [NSString stringWithFormat:@"forward_downloader_%@", _username];
        [[DDProgressCacheManager sharedInstance] clearDownloadTaskForKey:cacheKey];
    }
    
    // 清理进度缓存
    NSString *progressKey = [NSString stringWithFormat:@"forward_progress_%@", _username];
    [[DDProgressCacheManager sharedInstance] clearProgressForKey:progressKey];
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

// 添加完成回调属性
@property (nonatomic, copy) void (^onCompletion)(void);

@end

// 设置界面控制器
@interface DDTimelineForwardSettingsController : UIViewController
@property (nonatomic, strong) UISwitch *forwardSwitch;
@property (nonatomic, strong) UISwitch *autoDownloadSwitch;
@end

@implementation DDTimelineForwardSettingsController

- (void)viewDidLoad {
    [super viewDidLoad];
    
    self.title = @"朋友圈转发设置";
    self.view.backgroundColor = [UIColor systemBackgroundColor];
    
    // 配置iOS 15+模态样式
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
    UIScrollView *scrollView = [[UIScrollView alloc] init];
    scrollView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:scrollView];
    
    UIStackView *mainStack = [[UIStackView alloc] init];
    mainStack.axis = UILayoutConstraintAxisVertical;
    mainStack.spacing = 24;
    mainStack.alignment = UIStackViewAlignmentFill;
    mainStack.translatesAutoresizingMaskIntoConstraints = NO;
    [scrollView addSubview:mainStack];
    
    // 启用转发功能开关
    UIView *switchContainer1 = [self createSwitchContainerWithTitle:@"启用朋友圈转发" 
                                                           switchOn:[DDTimelineForwardConfig isTimelineForwardEnabled] 
                                                              tag:0];
    [mainStack addArrangedSubview:switchContainer1];
    
    // 自动下载媒体开关
    UIView *switchContainer2 = [self createSwitchContainerWithTitle:@"自动下载媒体文件" 
                                                           switchOn:[DDTimelineForwardConfig isAutoDownloadMedia] 
                                                              tag:1];
    [mainStack addArrangedSubview:switchContainer2];
    
    // 说明文字
    UILabel *descriptionLabel = [[UILabel alloc] init];
    descriptionLabel.text = @"启用后将在朋友圈菜单中添加「转发」按钮，点击后可快速转发朋友圈内容。自动下载媒体文件会预先缓存图片和视频。";
    descriptionLabel.font = [UIFont systemFontOfSize:14];
    descriptionLabel.textColor = [UIColor secondaryLabelColor];
    descriptionLabel.numberOfLines = 0;
    descriptionLabel.textAlignment = NSTextAlignmentLeft;
    [mainStack addArrangedSubview:descriptionLabel];
    
    // 布局约束
    [NSLayoutConstraint activateConstraints:@[
        [scrollView.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [scrollView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [scrollView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [scrollView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        
        [mainStack.topAnchor constraintEqualToAnchor:scrollView.topAnchor constant:20],
        [mainStack.leadingAnchor constraintEqualToAnchor:scrollView.leadingAnchor constant:20],
        [mainStack.trailingAnchor constraintEqualToAnchor:scrollView.trailingAnchor constant:-20],
        [mainStack.bottomAnchor constraintEqualToAnchor:scrollView.bottomAnchor constant:-20],
        [mainStack.widthAnchor constraintEqualToAnchor:scrollView.widthAnchor constant:-40]
    ]];
}

- (UIView *)createSwitchContainerWithTitle:(NSString *)title switchOn:(BOOL)on tag:(NSInteger)tag {
    UIView *container = [[UIView alloc] init];
    container.translatesAutoresizingMaskIntoConstraints = NO;
    
    UILabel *titleLabel = [[UILabel alloc] init];
    titleLabel.text = title;
    titleLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightMedium];
    titleLabel.textColor = [UIColor labelColor];
    titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [container addSubview:titleLabel];
    
    UISwitch *switchControl = [[UISwitch alloc] init];
    [switchControl setOn:on];
    switchControl.tag = tag;
    [switchControl addTarget:self action:@selector(switchChanged:) forControlEvents:UIControlEventValueChanged];
    switchControl.translatesAutoresizingMaskIntoConstraints = NO;
    [container addSubview:switchControl];
    
    [NSLayoutConstraint activateConstraints:@[
        [titleLabel.leadingAnchor constraintEqualToAnchor:container.leadingAnchor],
        [titleLabel.centerYAnchor constraintEqualToAnchor:container.centerYAnchor],
        [switchControl.trailingAnchor constraintEqualToAnchor:container.trailingAnchor],
        [switchControl.centerYAnchor constraintEqualToAnchor:container.centerYAnchor],
        [container.heightAnchor constraintEqualToConstant:44]
    ]];
    
    if (tag == 1) {
        self.autoDownloadSwitch = switchControl;
    } else {
        self.forwardSwitch = switchControl;
    }
    
    return container;
}

- (void)switchChanged:(UISwitch *)sender {
    if (sender.tag == 0) {
        [DDTimelineForwardConfig setTimelineForwardEnabled:sender.isOn];
    } else if (sender.tag == 1) {
        [DDTimelineForwardConfig setAutoDownloadMedia:sender.isOn];
    }
}

@end

// Hook实现
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
- (WCMediaItem *)dd_getFirstMediaItem {
    // 从WCDataItem中获取第一个媒体项
    if (!self.m_item) return nil;
    
    // 尝试通过不同的方法获取媒体项
    SEL selector = NSSelectorFromString(@"firstMediaItem");
    if ([self.m_item respondsToSelector:selector]) {
        return [self.m_item performSelector:selector];
    }
    
    // 尝试获取contentObj
    if ([self.m_item respondsToSelector:@selector(contentObj)]) {
        id contentObj = [self.m_item contentObj];
        if (contentObj) {
            // 尝试从contentObj中获取媒体列表
            SEL mediaListSelector = NSSelectorFromString(@"mediaList");
            if ([contentObj respondsToSelector:mediaListSelector]) {
                NSArray *mediaList = [contentObj performSelector:mediaListSelector];
                if (mediaList && [mediaList count] > 0) {
                    return mediaList[0];
                }
            }
        }
    }
    
    return nil;
}

%new
- (void)dd_forwardTimeline:(UIButton *)sender {
    __weak typeof(self) weakSelf = self;
    NSString *username = self.m_item.username ?: @"unknown";
    
    // 创建进度窗口
    CGRect screenBounds = [UIScreen mainScreen].bounds;
    DDProgressWindow *progressWindow = [[DDProgressWindow alloc] initWithFrame:screenBounds username:username];
    
    // 获取媒体项
    WCMediaItem *mediaItem = [self dd_getFirstMediaItem];
    
    // 设置完成回调
    progressWindow.onCompletion = ^{
        // 进入转发界面
        WCForwardViewController *forwardVC = [[objc_getClass("WCForwardViewController") alloc] initWithDataItem:weakSelf.m_item];
        if (weakSelf.navigationController) {
            [weakSelf.navigationController pushViewController:forwardVC animated:YES];
        }
    };
    
    [progressWindow show];
    [progressWindow startDownloadWithMediaItem:mediaItem dataItem:self.m_item];
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
        
        NSLog(@"DD朋友圈转发插件已加载 v1.5.0 - 使用WCMediaDownloader修复媒体缓存");
    }
}