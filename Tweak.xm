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
@end

@implementation DDTimelineForwardSettingsController

- (void)viewDidLoad {
    [super viewDidLoad];
    
    self.title = @"朋友圈转发设置";
    self.view.backgroundColor = [UIColor systemBackgroundColor];
    
    // 配置iOS 15+模态样式
    UISheetPresentationController *sheet = self.sheetPresentationController;
    if (sheet) {
        sheet.detents = @[UISheetPresentationControllerDetent.mediumDetent];
        sheet.prefersGrabberVisible = YES;
        sheet.preferredCornerRadius = 20.0;
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
        [switchContainer.heightAnchor constraintEqualToConstant:44]
    ]];
}

- (void)switchChanged:(UISwitch *)sender {
    [DDTimelineForwardConfig setTimelineForwardEnabled:sender.isOn];
}

@end

// 自定义图标绘制类
@interface DDForwardIconGenerator : NSObject
+ (UIImage *)generateForwardIconWithColor:(UIColor *)color size:(CGSize)size;
@end

@implementation DDForwardIconGenerator

+ (UIImage *)generateForwardIconWithColor:(UIColor *)color size:(CGSize)size {
    UIGraphicsBeginImageContextWithOptions(size, NO, 0.0);
    CGContextRef context = UIGraphicsGetCurrentContext();
    
    // 设置图标颜色
    [color setFill];
    [color setStroke];
    
    // 绘制转发图标（类似微信的转发图标）
    CGFloat lineWidth = 1.5;
    CGContextSetLineWidth(context, lineWidth);
    
    // 计算图标绘制区域，留出边距
    CGFloat margin = 2.0;
    CGRect drawRect = CGRectMake(margin, margin, size.width - 2*margin, size.height - 2*margin);
    
    // 绘制一个向右的箭头和一个文档形状
    CGFloat arrowWidth = drawRect.size.width * 0.4;
    CGFloat arrowHeight = drawRect.size.height * 0.5;
    CGFloat docWidth = drawRect.size.width * 0.4;
    CGFloat docHeight = drawRect.size.height * 0.6;
    
    // 绘制文档形状（矩形）
    CGRect docRect = CGRectMake(drawRect.origin.x, 
                               drawRect.origin.y + (drawRect.size.height - docHeight)/2,
                               docWidth, 
                               docHeight);
    
    // 文档矩形（带圆角）
    CGFloat cornerRadius = 1.5;
    UIBezierPath *docPath = [UIBezierPath bezierPathWithRoundedRect:docRect cornerRadius:cornerRadius];
    docPath.lineWidth = lineWidth;
    [docPath stroke];
    
    // 在文档上添加两条短横线（模拟文档内容）
    CGFloat lineSpacing = 3.0;
    CGFloat lineY = docRect.origin.y + lineSpacing * 2;
    
    for (int i = 0; i < 3; i++) {
        CGFloat lineX = docRect.origin.x + 3.0;
        CGFloat lineLength = docRect.size.width - 6.0;
        
        UIBezierPath *linePath = [UIBezierPath bezierPath];
        [linePath moveToPoint:CGPointMake(lineX, lineY)];
        [linePath addLineToPoint:CGPointMake(lineX + lineLength, lineY)];
        linePath.lineWidth = lineWidth;
        [linePath stroke];
        
        lineY += lineSpacing;
    }
    
    // 绘制箭头（从文档右侧延伸到边缘）
    CGFloat arrowStartX = CGRectGetMaxX(docRect) + 3.0;
    CGFloat arrowCenterY = CGRectGetMidY(docRect);
    
    UIBezierPath *arrowPath = [UIBezierPath bezierPath];
    
    // 箭头主体（向右的线）
    [arrowPath moveToPoint:CGPointMake(arrowStartX, arrowCenterY)];
    [arrowPath addLineToPoint:CGPointMake(drawRect.origin.x + drawRect.size.width - margin, arrowCenterY)];
    
    // 箭头头部（三角形）
    CGFloat arrowHeadSize = 3.5;
    [arrowPath moveToPoint:CGPointMake(drawRect.origin.x + drawRect.size.width - margin - arrowHeadSize, 
                                      arrowCenterY - arrowHeadSize)];
    [arrowPath addLineToPoint:CGPointMake(drawRect.origin.x + drawRect.size.width - margin, arrowCenterY)];
    [arrowPath addLineToPoint:CGPointMake(drawRect.origin.x + drawRect.size.width - margin - arrowHeadSize, 
                                      arrowCenterY + arrowHeadSize)];
    
    arrowPath.lineWidth = lineWidth;
    arrowPath.lineCapStyle = kCGLineCapRound;
    arrowPath.lineJoinStyle = kCGLineJoinRound;
    [arrowPath stroke];
    
    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    
    return [image imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
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
        CGFloat buttonSpacing = 15.0; // 固定间距
        
        // 创建转发按钮
        UIButton *forwardButton = [UIButton buttonWithType:UIButtonTypeCustom];
        forwardButton.frame = CGRectMake(0, 0, buttonWidth, likeBtn.frame.size.height);
        
        // 创建自定义转发图标
        UIImage *forwardIcon = [DDForwardIconGenerator generateForwardIconWithColor:likeBtn.currentTitleColor 
                                                                               size:CGSizeMake(16, 16)];
        
        // 创建图标视图
        UIImageView *iconView = [[UIImageView alloc] initWithImage:forwardIcon];
        iconView.tintColor = likeBtn.currentTitleColor;
        iconView.frame = CGRectMake(10, (forwardButton.frame.size.height - 16)/2, 16, 16);
        iconView.contentMode = UIViewContentModeScaleAspectFit;
        [forwardButton addSubview:iconView];
        
        // 创建标题标签 - 使用系统细体
        UILabel *titleLabel = [[UILabel alloc] init];
        titleLabel.text = @"转发";
        titleLabel.font = [UIFont systemFontOfSize:likeBtn.titleLabel.font.pointSize weight:UIFontWeightLight]; // 细体
        titleLabel.textColor = likeBtn.currentTitleColor;
        titleLabel.textAlignment = NSTextAlignmentLeft;
        titleLabel.frame = CGRectMake(30, 0, buttonWidth - 30, forwardButton.frame.size.height);
        [forwardButton addSubview:titleLabel];
        
        [forwardButton addTarget:self action:@selector(dd_forwardTimeline:) forControlEvents:UIControlEventTouchUpInside];
        
        // 获取按钮容器
        UIView *buttonContainer = likeBtn.superview;
        
        // 设置按钮位置（顺序：点赞 -> 评论 -> | -> 转发）
        CGFloat currentX = 0;
        
        // 点赞按钮位置（保持不变）
        likeBtn.frame = CGRectMake(currentX, likeBtn.frame.origin.y, buttonWidth, likeBtn.frame.size.height);
        currentX += buttonWidth + buttonSpacing;
        
        // 评论按钮位置（在点赞按钮右侧）
        if (commentBtn) {
            commentBtn.frame = CGRectMake(currentX, commentBtn.frame.origin.y, buttonWidth, commentBtn.frame.size.height);
            currentX += buttonWidth;
            
            // 创建自定义分隔线
            UIView *separator = [[UIView alloc] init];
            
            // 根据系统主题设置分隔线颜色
            separator.backgroundColor = [UIColor colorWithDynamicProvider:^UIColor * _Nonnull(UITraitCollection * _Nonnull traitCollection) {
                if (traitCollection.userInterfaceStyle == UIUserInterfaceStyleDark) {
                    // 深色模式：浅白色，alpha 0.2
                    return [UIColor colorWithWhite:0.9 alpha:0.2];
                } else {
                    // 浅色模式：黑色，alpha 0.1
                    return [UIColor colorWithWhite:0.0 alpha:0.1];
                }
            }];
            
            // 设置分隔符位置和尺寸
            CGFloat separatorHeight = forwardButton.frame.size.height * 0.6;
            CGFloat separatorY = (forwardButton.frame.size.height - separatorHeight) / 2;
            separator.frame = CGRectMake(currentX, separatorY, 0.5, separatorHeight);
            separator.layer.cornerRadius = 0.25; // 半圆角，宽度的一半
            
            [buttonContainer addSubview:separator];
            currentX += 0.5 + buttonSpacing; // 分隔符宽度+间距
        } else {
            // 如果没有评论按钮，直接添加间距
            currentX += buttonSpacing;
        }
        
        // 转发按钮位置（在评论按钮右侧或点赞按钮右侧）
        forwardButton.frame = CGRectMake(currentX, likeBtn.frame.origin.y, buttonWidth, likeBtn.frame.size.height);
        currentX += buttonWidth;
        
        // 将转发按钮添加到容器
        [buttonContainer addSubview:forwardButton];
        
        // 计算总宽度
        CGFloat totalWidth = currentX;
        
        // 精确设置容器宽度（匹配按钮组总宽度）
        CGRect containerFrame = buttonContainer.frame;
        containerFrame.size.width = totalWidth;
        buttonContainer.frame = containerFrame;
        
        // 精确设置浮窗宽度（匹配容器宽度）
        CGRect selfFrame = self.frame;
        selfFrame.size.width = totalWidth;
        selfFrame.origin.x -= 90; // 整体向左移动
        self.frame = selfFrame;
    }
}

%new
- (void)dd_forwardTimeline:(UIButton *)sender {
    __weak typeof(self) weakSelf = self;
    NSString *username = self.m_item.username ?: @"未知用户";
    NSString *cacheKey = [NSString stringWithFormat:@"forward_progress_%@", username];
    float savedProgress = [[DDProgressCacheManager sharedInstance] getProgressForKey:cacheKey];
    
    // 创建进度窗口（转圈+百分比效果）
    CGRect screenBounds = [UIScreen mainScreen].bounds;
    DDProgressWindow *progressWindow = [[DDProgressWindow alloc] initWithFrame:screenBounds username:username];
    [progressWindow updateProgress:savedProgress];
    [progressWindow show];
    
    // 模拟转发过程（实际项目中应替换为真实转发逻辑）
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        float progress = savedProgress;
        while (progress < 1.0) {
            progress += 0.01;
            if (progress > 1.0) progress = 1.0;
            
            [progressWindow updateProgress:progress];
            
            // 模拟网络延迟
            [NSThread sleepForTimeInterval:0.05];
        }
        
        // 转发完成
        dispatch_async(dispatch_get_main_queue(), ^{
            [progressWindow hide];
            [[DDProgressCacheManager sharedInstance] clearProgressForKey:cacheKey];
            
            // 进入转发界面
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