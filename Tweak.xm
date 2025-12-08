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
    // 创建毛玻璃效果
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

- (void)updateProgress:(float)progress {
    dispatch_async(dispatch_get_main_queue(), ^{
        // 更新百分比标签（增加"正在缓存"前缀）
        int percent = (int)(progress * 100);
        _percentLabel.text = [NSString stringWithFormat:@"正在缓存%d%%", percent];
        
        // 保存进度到缓存
        NSString *cacheKey = [NSString stringWithFormat:@"forward_progress_%@", _username];
        [[DDProgressCacheManager sharedInstance] saveProgress:progress forKey:cacheKey];
        
        // 完成时改变颜色和文本
        if (progress >= 1.0) {
            _percentLabel.text = @"缓存完成!";
            _percentLabel.textColor = [UIColor systemGreenColor];
        }
    });
}

- (void)cancelButtonPressed {
    [self hide];
    NSString *cacheKey = [NSString stringWithFormat:@"forward_progress_%@", _username];
    [[DDProgressCacheManager sharedInstance] clearProgressForKey:cacheKey];
}

- (void)show {
    self.hidden = NO;
    [self makeKeyAndVisible];
}

- (void)hide {
    self.hidden = YES;
    _activityIndicator.hidden = YES;
    [_activityIndicator stopAnimating];
    
    UIWindow *mainWindow = [[[UIApplication sharedApplication] delegate] window];
    [mainWindow makeKeyAndVisible];
}

@end

// 设置界面控制器
@interface DDTimelineForwardSettingsController : UIViewController
@property (nonatomic, strong) UISwitch *forwardSwitch;
@property (nonatomic, strong) UISlider *spacingSlider;
@property (nonatomic, strong) UILabel *spacingLabel;
@end

@implementation DDTimelineForwardSettingsController {
    CGFloat _buttonSpacing;
}

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
    
    // 加载按钮间距设置
    _buttonSpacing = [[NSUserDefaults standardUserDefaults] floatForKey:@"DDButtonSpacing"];
    if (_buttonSpacing == 0) {
        _buttonSpacing = 15.0; // 默认间距
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
    
    // 按钮间距调整
    UIView *spacingContainer = [[UIView alloc] init];
    spacingContainer.translatesAutoresizingMaskIntoConstraints = NO;
    
    UILabel *spacingTitle = [[UILabel alloc] init];
    spacingTitle.text = @"按钮间距调整";
    spacingTitle.font = [UIFont systemFontOfSize:16 weight:UIFontWeightMedium];
    spacingTitle.textColor = [UIColor labelColor];
    spacingTitle.translatesAutoresizingMaskIntoConstraints = NO;
    [spacingContainer addSubview:spacingTitle];
    
    self.spacingSlider = [[UISlider alloc] init];
    self.spacingSlider.minimumValue = 5.0;
    self.spacingSlider.maximumValue = 30.0;
    self.spacingSlider.value = _buttonSpacing;
    [self.spacingSlider addTarget:self action:@selector(spacingSliderChanged:) forControlEvents:UIControlEventValueChanged];
    self.spacingSlider.translatesAutoresizingMaskIntoConstraints = NO;
    [spacingContainer addSubview:self.spacingSlider];
    
    self.spacingLabel = [[UILabel alloc] init];
    self.spacingLabel.text = [NSString stringWithFormat:@"间距: %.0f 点", _buttonSpacing];
    self.spacingLabel.font = [UIFont systemFontOfSize:14];
    self.spacingLabel.textColor = [UIColor secondaryLabelColor];
    self.spacingLabel.textAlignment = NSTextAlignmentCenter;
    self.spacingLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [spacingContainer addSubview:self.spacingLabel];
    
    [NSLayoutConstraint activateConstraints:@[
        [spacingTitle.topAnchor constraintEqualToAnchor:spacingContainer.topAnchor],
        [spacingTitle.leadingAnchor constraintEqualToAnchor:spacingContainer.leadingAnchor],
        [spacingTitle.trailingAnchor constraintEqualToAnchor:spacingContainer.trailingAnchor],
        
        [self.spacingSlider.topAnchor constraintEqualToAnchor:spacingTitle.bottomAnchor constant:10],
        [self.spacingSlider.leadingAnchor constraintEqualToAnchor:spacingContainer.leadingAnchor constant:20],
        [self.spacingSlider.trailingAnchor constraintEqualToAnchor:spacingContainer.trailingAnchor constant:-20],
        
        [self.spacingLabel.topAnchor constraintEqualToAnchor:self.spacingSlider.bottomAnchor constant:10],
        [self.spacingLabel.leadingAnchor constraintEqualToAnchor:spacingContainer.leadingAnchor],
        [self.spacingLabel.trailingAnchor constraintEqualToAnchor:spacingContainer.trailingAnchor],
        [self.spacingLabel.bottomAnchor constraintEqualToAnchor:spacingContainer.bottomAnchor]
    ]];
    
    [mainStack addArrangedSubview:spacingContainer];
    
    // 说明文字
    UILabel *descriptionLabel = [[UILabel alloc] init];
    descriptionLabel.text = @"启用后在朋友圈菜单中添加「转发」按钮，可快速转发朋友圈内容";
    descriptionLabel.font = [UIFont systemFontOfSize:14];
    descriptionLabel.textColor = [UIColor secondaryLabelColor];
    descriptionLabel.numberOfLines = 0;
    descriptionLabel.textAlignment = NSTextAlignmentCenter;
    [mainStack addArrangedSubview:descriptionLabel];
    
    // 版本信息
    UILabel *versionLabel = [[UILabel alloc] init];
    versionLabel.text = @"DD朋友圈转发 v1.4.0";
    versionLabel.font = [UIFont systemFontOfSize:12];
    versionLabel.textColor = [UIColor tertiaryLabelColor];
    versionLabel.textAlignment = NSTextAlignmentCenter;
    [mainStack addArrangedSubview:versionLabel];
    
    // 布局约束
    [NSLayoutConstraint activateConstraints:@[
        [mainStack.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:32],
        [mainStack.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:20],
        [mainStack.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-20],
        [switchContainer.heightAnchor constraintEqualToConstant:44],
        [spacingContainer.heightAnchor constraintEqualToConstant:100]
    ]];
}

- (void)switchChanged:(UISwitch *)sender {
    [DDTimelineForwardConfig setTimelineForwardEnabled:sender.isOn];
}

- (void)spacingSliderChanged:(UISlider *)sender {
    _buttonSpacing = sender.value;
    self.spacingLabel.text = [NSString stringWithFormat:@"间距: %.0f 点", _buttonSpacing];
    
    // 保存设置
    [[NSUserDefaults standardUserDefaults] setFloat:_buttonSpacing forKey:@"DDButtonSpacing"];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

@end

// Hook实现
%hook WCOperateFloatView

- (void)showWithItemData:(id)arg1 tipPoint:(struct CGPoint)arg2 {
    %orig(arg1, arg2);
    
    if ([DDTimelineForwardConfig isTimelineForwardEnabled]) {
        UIButton *likeBtn = self.m_likeBtn;
        UIButton *commentBtn = self.m_commentBtn;
        
        CGFloat buttonWidth = [self buttonWidth:likeBtn];
        CGFloat buttonSpacing = [[NSUserDefaults standardUserDefaults] floatForKey:@"DDButtonSpacing"];
        if (buttonSpacing == 0) {
            buttonSpacing = 15.0; // 默认间距
        }
        
        // 获取按钮容器
        UIView *buttonContainer = likeBtn.superview;
        
        // 检查是否已经添加过转发按钮，避免重复添加
        __block BOOL forwardButtonExists = NO;
        [buttonContainer.subviews enumerateObjectsUsingBlock:^(UIView *subview, NSUInteger idx, BOOL *stop) {
            if ([subview isKindOfClass:[UIButton class]] && [subview respondsToSelector:@selector(actionForTarget:forControlEvent:)]) {
                UIButton *btn = (UIButton *)subview;
                if (btn != likeBtn && btn != commentBtn) {
                    forwardButtonExists = YES;
                    *stop = YES;
                }
            }
        }];
        
        if (forwardButtonExists) return;
        
        // 创建转发按钮 - 使用与系统按钮相同的样式
        UIButton *forwardButton = [UIButton buttonWithType:UIButtonTypeCustom];
        forwardButton.frame = CGRectMake(0, 0, buttonWidth, likeBtn.frame.size.height);
        
        // 使用系统按钮的字体和颜色
        UIColor *buttonColor = [likeBtn titleColorForState:UIControlStateNormal];
        UIFont *buttonFont = likeBtn.titleLabel.font;
        
        // 创建转发图标
        UIImage *forwardIcon = [UIImage systemImageNamed:@"arrowshape.turn.up.forward"];
        if (forwardIcon) {
            forwardIcon = [forwardIcon imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
        }
        
        // 使用 UIButtonConfiguration (iOS 15+)
        UIButtonConfiguration *config = [UIButtonConfiguration plainButtonConfiguration];
        config.image = forwardIcon;
        config.title = @"转发";
        config.imagePlacement = NSDirectionalRectEdgeLeading; // 图片在左侧
        config.imagePadding = 6; // 图片和文字间距
        config.baseForegroundColor = buttonColor;
        
        // 设置字体
        config.titleTextAttributesTransformer = ^NSDictionary<NSAttributedStringKey, id> *(NSDictionary<NSAttributedStringKey, id> *textAttributes) {
            NSMutableDictionary *newAttributes = [textAttributes mutableCopy];
            newAttributes[NSFontAttributeName] = buttonFont;
            return newAttributes;
        };
        
        forwardButton.configuration = config;
        [forwardButton addTarget:self action:@selector(dd_forwardTimeline:) forControlEvents:UIControlEventTouchUpInside];
        
        // 设置按钮位置
        CGFloat currentX = 0;
        
        // 点赞按钮位置
        likeBtn.frame = CGRectMake(currentX, likeBtn.frame.origin.y, buttonWidth, likeBtn.frame.size.height);
        currentX += buttonWidth + buttonSpacing;
        
        // 评论按钮位置
        if (commentBtn) {
            commentBtn.frame = CGRectMake(currentX, commentBtn.frame.origin.y, buttonWidth, commentBtn.frame.size.height);
            currentX += buttonWidth;
            
            // 添加系统风格的分割线
            UIView *separator = [[UIView alloc] init];
            separator.backgroundColor = [UIColor colorWithWhite:0.8 alpha:0.6];
            separator.frame = CGRectMake(currentX, 
                                       likeBtn.frame.size.height * 0.2,
                                       1.0 / [UIScreen mainScreen].scale,
                                       likeBtn.frame.size.height * 0.6);
            separator.alpha = 0.6;
            [buttonContainer addSubview:separator];
            
            currentX += 1.0 / [UIScreen mainScreen].scale + buttonSpacing;
        } else {
            currentX += buttonSpacing;
        }
        
        // 转发按钮位置
        forwardButton.frame = CGRectMake(currentX, likeBtn.frame.origin.y, buttonWidth, likeBtn.frame.size.height);
        currentX += buttonWidth;
        
        // 将转发按钮添加到容器
        [buttonContainer addSubview:forwardButton];
        
        // 调整容器宽度
        CGRect containerFrame = buttonContainer.frame;
        containerFrame.size.width = currentX;
        buttonContainer.frame = containerFrame;
        
        // 调整浮窗位置和大小
        CGRect selfFrame = self.frame;
        selfFrame.size.width = currentX;
        
        // 根据按钮数量调整浮窗位置
        CGFloat offset = (selfFrame.size.width - containerFrame.size.width) / 2;
        selfFrame.origin.x -= offset;
        
        self.frame = selfFrame;
        
        // 确保按钮容器在浮窗中居中
        containerFrame.origin.x = (selfFrame.size.width - containerFrame.size.width) / 2;
        buttonContainer.frame = containerFrame;
    }
}

%new
- (void)dd_forwardTimeline:(UIButton *)sender {
    __weak typeof(self) weakSelf = self;
    NSString *username = self.m_item.username ?: @"未知用户";
    NSString *cacheKey = [NSString stringWithFormat:@"forward_progress_%@", username];
    float savedProgress = [[DDProgressCacheManager sharedInstance] getProgressForKey:cacheKey];
    
    // 创建进度窗口
    CGRect screenBounds = [UIScreen mainScreen].bounds;
    DDProgressWindow *progressWindow = [[DDProgressWindow alloc] initWithFrame:screenBounds username:username];
    [progressWindow updateProgress:savedProgress];
    [progressWindow show];
    
    // 模拟转发过程
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        float progress = savedProgress;
        while (progress < 1.0) {
            progress += 0.01;
            if (progress > 1.0) progress = 1.0;
            
            [progressWindow updateProgress:progress];
            [NSThread sleepForTimeInterval:0.05];
        }
        
        dispatch_async(dispatch_get_main_queue(), ^{
            [progressWindow hide];
            [[DDProgressCacheManager sharedInstance] clearProgressForKey:cacheKey];
            
            Class WCForwardViewControllerClass = objc_getClass("WCForwardViewController");
            if (WCForwardViewControllerClass) {
                WCForwardViewController *forwardVC = [[WCForwardViewControllerClass alloc] initWithDataItem:weakSelf.m_item];
                if (weakSelf.navigationController) {
                    [weakSelf.navigationController pushViewController:forwardVC animated:YES];
                }
            }
        });
    });
}

%end

// 插件初始化
%ctor {
    @autoreleasepool {
        [DDProgressCacheManager sharedInstance]; // 确保单例初始化
        [DDTimelineForwardConfig setupDefaults];
        
        if (NSClassFromString(@"WCPluginsMgr")) {
            [[objc_getClass("WCPluginsMgr") sharedInstance] 
                registerControllerWithTitle:@"DD朋友圈转发" 
                                   version:@"1.4.0" 
                               controller:@"DDTimelineForwardSettingsController"];
        }
        
        NSLog(@"DD朋友圈转发插件已加载 v1.4.0");
    }
}