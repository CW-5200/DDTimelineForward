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
    
    UILabel *titleLabel = [[UILabel alloc] init];
    titleLabel.text = @"启用朋友圈转发";
    titleLabel.font = [UIFont systemFontOfSize:17 weight:UIFontWeightSemibold];
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
    versionLabel.text = @"DD朋友圈转发 v1.0.0";
    versionLabel.font = [UIFont systemFontOfSize:12];
    versionLabel.textColor = [UIColor tertiaryLabelColor];
    versionLabel.textAlignment = NSTextAlignmentCenter;
    [mainStack addArrangedSubview:versionLabel];
    
    // 布局约束
    [NSLayoutConstraint activateConstraints:@[
        [mainStack.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:32],
        [mainStack.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:20],
        [mainStack.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-20]
    ]];
}

- (void)switchChanged:(UISwitch *)sender {
    [DDTimelineForwardConfig setTimelineForwardEnabled:sender.isOn];
}

@end

// Hook实现
%hook WCOperateFloatView

- (void)showWithItemData:(id)arg1 tipPoint:(struct CGPoint)arg2 {
    %orig(arg1, arg2);
    
    if (![DDTimelineForwardConfig isTimelineForwardEnabled]) {
        return;
    }
    
    // 获取点赞按钮的宽度作为标准宽度
    UIButton *likeButton = self.m_likeBtn;
    CGFloat buttonWidth = CGRectGetWidth(likeButton.frame);
    
    // 获取按钮容器（猜测是m_clipView）
    UIView *clipView = nil;
    for (UIView *subview in self.subviews) {
        if ([subview.subviews containsObject:likeButton] && subview != likeButton) {
            clipView = subview;
            break;
        }
    }
    
    if (!clipView) {
        clipView = likeButton.superview;
    }
    
    if (!clipView) {
        return;
    }
    
    // 获取评论按钮
    UIButton *commentButton = self.m_commentBtn;
    
    // 创建转发按钮
    UIButton *forwardButton = [UIButton buttonWithType:UIButtonTypeCustom];
    [forwardButton setTitle:@"转发" forState:UIControlStateNormal];
    [forwardButton setTitleColor:likeButton.currentTitleColor forState:UIControlStateNormal];
    forwardButton.titleLabel.font = likeButton.titleLabel.font;
    [forwardButton addTarget:self action:@selector(dd_forwardTimeline:) forControlEvents:UIControlEventTouchUpInside];
    
    // 设置按钮框架
    CGFloat buttonHeight = CGRectGetHeight(likeButton.frame);
    CGFloat spacing = 0;
    
    // 计算间距（点赞和评论按钮之间的间距）
    if (CGRectGetMaxX(likeButton.frame) < CGRectGetMinX(commentButton.frame)) {
        spacing = CGRectGetMinX(commentButton.frame) - CGRectGetMaxX(likeButton.frame);
    } else {
        spacing = 5; // 默认间距
    }
    
    // 重新布局所有按钮
    CGFloat totalWidth = buttonWidth * 3 + spacing * 2;
    
    // 调整容器和视图大小
    CGRect clipFrame = clipView.frame;
    clipFrame.size.width = totalWidth;
    clipView.frame = clipFrame;
    
    CGRect selfFrame = self.frame;
    selfFrame.size.width = totalWidth;
    self.frame = selfFrame;
    
    // 重新设置按钮位置
    likeButton.frame = CGRectMake(0, 0, buttonWidth, buttonHeight);
    commentButton.frame = CGRectMake(buttonWidth + spacing, 0, buttonWidth, buttonHeight);
    forwardButton.frame = CGRectMake((buttonWidth + spacing) * 2, 0, buttonWidth, buttonHeight);
    
    // 添加到视图
    [clipView addSubview:forwardButton];
    
    // 重新定位整个视图使其居中显示
    [self adjustPositionForTipPoint:arg2];
}

%new
- (void)dd_forwardTimeline:(UIButton *)sender {
    if (self.navigationController) {
        Class WCForwardViewControllerClass = objc_getClass("WCForwardViewController");
        if (WCForwardViewControllerClass) {
            WCForwardViewController *forwardVC = [[WCForwardViewControllerClass alloc] initWithDataItem:self.m_item];
            [self.navigationController pushViewController:forwardVC animated:YES];
        }
    }
}

%new
- (void)adjustPositionForTipPoint:(CGPoint)tipPoint {
    // 调整视图位置，使其相对于tipPoint居中
    CGRect frame = self.frame;
    frame.origin.x = tipPoint.x - frame.size.width / 2;
    
    // 确保不会超出屏幕边界
    UIWindow *window = [UIApplication sharedApplication].keyWindow;
    CGFloat screenWidth = CGRectGetWidth(window.bounds);
    
    if (frame.origin.x < 0) {
        frame.origin.x = 10;
    } else if (CGRectGetMaxX(frame) > screenWidth) {
        frame.origin.x = screenWidth - frame.size.width - 10;
    }
    
    self.frame = frame;
}

%end

// 插件初始化
%ctor {
    @autoreleasepool {
        [DDTimelineForwardConfig setupDefaults];
        
        if (NSClassFromString(@"WCPluginsMgr")) {
            [[objc_getClass("WCPluginsMgr") sharedInstance] 
                registerControllerWithTitle:@"DD朋友圈转发" 
                                   version:@"1.0.0" 
                               controller:@"DDTimelineForwardSettingsController"];
        }
        
        NSLog(@"DD朋友圈转发插件已加载");
    }
}