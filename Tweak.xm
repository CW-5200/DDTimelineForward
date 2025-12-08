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
@end

@interface WCOperateFloatView : UIView
@property(readonly, nonatomic) UIButton *m_likeBtn;
@property(readonly, nonatomic) UIButton *m_commentBtn;
@property(readonly, nonatomic) WCDataItem *m_item;
@property(nonatomic) __weak UINavigationController *navigationController;
- (void)showWithItemData:(id)arg1 tipPoint:(struct CGPoint)arg2;
- (double)buttonWidth:(id)arg1;
@end

@interface WCForwardViewController : UIViewController
- (id)initWithDataItem:(WCDataItem *)arg1;
@end

// 进度缓存管理器
@interface DDProgressCacheManager : NSObject
+ (instancetype)sharedInstance;
- (void)saveProgress:(float)progress forKey:(NSString *)key;
- (float)getProgressForKey:(NSString *)key;
- (void)clearProgressForKey:(NSString *)key;
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
- (instancetype)initWithFrame:(CGRect)frame username:(NSString *)username;
- (void)updateProgress:(float)progress;
- (void)show;
- (void)hide;
@end

@implementation DDProgressWindow {
    UIActivityIndicatorView *_activityIndicator;
    UILabel *_titleLabel;
    UILabel *_percentLabel;
    UIButton *_cancelButton;
    NSString *_username;
    UIVisualEffectView *_blurView;
}

- (instancetype)initWithFrame:(CGRect)frame username:(NSString *)username {
    self = [super initWithFrame:frame];
    if (self) {
        _username = username;
        self.windowLevel = UIWindowLevelAlert + 1;
        
        // 创建毛玻璃效果背景
        [self setupBlurBackground];
        
        [self setupUI];
    }
    return self;
}

- (void)setupBlurBackground {
    // 使用最新的系统毛玻璃效果
    UIBlurEffect *blurEffect = [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemUltraThinMaterial];
    
    _blurView = [[UIVisualEffectView alloc] initWithEffect:blurEffect];
    _blurView.frame = self.bounds;
    _blurView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _blurView.alpha = 0.95;
    
    // 添加半透明覆盖层增强效果
    UIView *overlayView = [[UIView alloc] initWithFrame:_blurView.bounds];
    overlayView.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.2];
    overlayView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [_blurView.contentView addSubview:overlayView];
    
    [self addSubview:_blurView];
}

- (void)setupUI {
    // 标题
    _titleLabel = [[UILabel alloc] init];
    _titleLabel.text = @"正在转发朋友圈";
    _titleLabel.font = [UIFont systemFontOfSize:18 weight:UIFontWeightSemibold];
    _titleLabel.textColor = [UIColor labelColor];
    _titleLabel.textAlignment = NSTextAlignmentCenter;
    _titleLabel.numberOfLines = 0;
    _titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    
    // 活动指示器（转圈）- 使用大号样式
    _activityIndicator = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleLarge];
    _activityIndicator.color = [UIColor labelColor];
    _activityIndicator.translatesAutoresizingMaskIntoConstraints = NO;
    [_activityIndicator startAnimating];
    
    // 百分比标签（增加"正在缓存"前缀）
    _percentLabel = [[UILabel alloc] init];
    _percentLabel.text = @"正在缓存0%";
    _percentLabel.font = [UIFont monospacedDigitSystemFontOfSize:18 weight:UIFontWeightMedium];
    _percentLabel.textColor = [UIColor labelColor];
    _percentLabel.textAlignment = NSTextAlignmentCenter;
    _percentLabel.numberOfLines = 0;
    _percentLabel.adjustsFontSizeToFitWidth = YES;
    _percentLabel.minimumScaleFactor = 0.8;
    _percentLabel.translatesAutoresizingMaskIntoConstraints = NO;
    
    // 取消按钮
    _cancelButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [_cancelButton setTitle:@"取消" forState:UIControlStateNormal];
    [_cancelButton setTitleColor:[UIColor systemRedColor] forState:UIControlStateNormal];
    _cancelButton.titleLabel.font = [UIFont systemFontOfSize:18 weight:UIFontWeightRegular];
    _cancelButton.translatesAutoresizingMaskIntoConstraints = NO;
    [_cancelButton addTarget:self action:@selector(cancelButtonPressed) forControlEvents:UIControlEventTouchUpInside];
    
    // 内容视图（带半透明背景）
    UIView *contentView = [[UIView alloc] init];
    contentView.backgroundColor = [[UIColor secondarySystemBackgroundColor] colorWithAlphaComponent:0.85];
    contentView.layer.cornerRadius = 16.0;
    contentView.layer.borderWidth = 0.5;
    contentView.layer.borderColor = [UIColor separatorColor].CGColor;
    contentView.translatesAutoresizingMaskIntoConstraints = NO;
    
    [contentView addSubview:_titleLabel];
    [contentView addSubview:_activityIndicator];
    [contentView addSubview:_percentLabel];
    [contentView addSubview:_cancelButton];
    
    [self addSubview:contentView];
    
    // 布局约束
    [NSLayoutConstraint activateConstraints:@[
        // 内容视图（居中显示）
        [contentView.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
        [contentView.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
        [contentView.widthAnchor constraintEqualToConstant:280],
        [contentView.heightAnchor constraintEqualToConstant:260],
        
        // 标题
        [_titleLabel.topAnchor constraintEqualToAnchor:contentView.topAnchor constant:25],
        [_titleLabel.leadingAnchor constraintEqualToAnchor:contentView.leadingAnchor constant:20],
        [_titleLabel.trailingAnchor constraintEqualToAnchor:contentView.trailingAnchor constant:-20],
        [_titleLabel.heightAnchor constraintGreaterThanOrEqualToConstant:25],
        
        // 活动指示器（转圈）
        [_activityIndicator.topAnchor constraintEqualToAnchor:_titleLabel.bottomAnchor constant:20],
        [_activityIndicator.centerXAnchor constraintEqualToAnchor:contentView.centerXAnchor],
        [_activityIndicator.widthAnchor constraintEqualToConstant:50],
        [_activityIndicator.heightAnchor constraintEqualToConstant:50],
        
        // 百分比标签
        [_percentLabel.topAnchor constraintEqualToAnchor:_activityIndicator.bottomAnchor constant:20],
        [_percentLabel.leadingAnchor constraintEqualToAnchor:contentView.leadingAnchor constant:20],
        [_percentLabel.trailingAnchor constraintEqualToAnchor:contentView.trailingAnchor constant:-20],
        [_percentLabel.heightAnchor constraintGreaterThanOrEqualToConstant:30],
        
        // 取消按钮
        [_cancelButton.topAnchor constraintEqualToAnchor:_percentLabel.bottomAnchor constant:25],
        [_cancelButton.centerXAnchor constraintEqualToAnchor:contentView.centerXAnchor],
        [_cancelButton.bottomAnchor constraintLessThanOrEqualToAnchor:contentView.bottomAnchor constant:-20]
    ]];
}

-## 更新了 Tweak.xm 中的分隔线颜色设置：浅色模式使用深黑色 (alpha 0.2)，深色模式使用白色 (alpha 0.3)。
 同时，转发按钮的图标和文字已设置为白色。

 请将以上代码复制到你的 Tweak.xm 文件中进行编译测试。