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
@property(readonly, nonatomic) UIButton *m_commentBtn; // 添加评论按钮属性
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
    
    // 检查是否已启用转发功能
    if (![DDTimelineForwardConfig isTimelineForwardEnabled]) {
        return;
    }
    
    // 检查是否已存在转发按钮（避免重复添加）
    static NSInteger forwardButtonTag = 1001;
    UIButton *existingForwardButton = [self viewWithTag:forwardButtonTag];
    if (existingForwardButton) {
        return;
    }
    
    // 获取点赞按钮和评论按钮的frame
    CGRect likeBtnFrame = self.m_likeBtn.frame;
    CGRect commentBtnFrame = self.m_commentBtn.frame;
    
    // 计算转发按钮宽度（与点赞按钮相同）
    CGFloat buttonWidth = [self buttonWidth:self.m_likeBtn];
    
    // 获取按钮容器（假设点赞和评论按钮在同一个容器中）
    UIView *buttonsContainer = self.m_likeBtn.superview;
    if (!buttonsContainer) {
        buttonsContainer = self;
    }
    
    // 计算按钮之间的间距
    CGFloat spacing = 0;
    if (CGRectGetMaxX(likeBtnFrame) <= CGRectGetMinX(commentBtnFrame)) {
        spacing = CGRectGetMinX(commentBtnFrame) - CGRectGetMaxX(likeBtnFrame);
    } else {
        // 如果按钮重叠或没有间距，使用默认间距
        spacing = 8.0; // 默认间距
    }
    
    // 创建转发按钮
    UIButton *forwardButton = [UIButton buttonWithType:UIButtonTypeCustom];
    forwardButton.tag = forwardButtonTag;
    [forwardButton setTitle:@"转发" forState:UIControlStateNormal];
    [forwardButton setTitleColor:self.m_likeBtn.currentTitleColor forState:UIControlStateNormal];
    forwardButton.titleLabel.font = self.m_likeBtn.titleLabel.font;
    [forwardButton addTarget:self action:@selector(dd_forwardTimeline:) forControlEvents:UIControlEventTouchUpInside];
    
    // 设置转发按钮frame
    CGFloat forwardButtonX = CGRectGetMaxX(commentBtnFrame) + spacing;
    forwardButton.frame = CGRectMake(
        forwardButtonX,
        likeBtnFrame.origin.y,
        buttonWidth,
        likeBtnFrame.size.height
    );
    
    // 添加转发按钮到容器
    [buttonsContainer addSubview:forwardButton];
    
    // 调整容器宽度以容纳转发按钮
    CGRect containerFrame = buttonsContainer.frame;
    CGFloat oldContainerWidth = containerFrame.size.width;
    CGFloat newContainerWidth = CGRectGetMaxX(forwardButton.frame);
    
    if (newContainerWidth > oldContainerWidth) {
        containerFrame.size.width = newContainerWidth;
        buttonsContainer.frame = containerFrame;
        
        // 调整整个视图的宽度
        CGRect selfFrame = self.frame;
        CGFloat widthIncrease = newContainerWidth - oldContainerWidth;
        selfFrame.size.width += widthIncrease;
        self.frame = selfFrame;
    }
}

%new
- (void)dd_forwardTimeline:(UIButton *)sender {
    // 获取转发视图控制器并显示
    WCForwardViewController *forwardVC = [[objc_getClass("WCForwardViewController") alloc] initWithDataItem:self.m_item];
    if (self.navigationController) {
        [self.navigationController pushViewController:forwardVC animated:YES];
    }
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