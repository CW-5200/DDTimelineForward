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

@interface MMUIButton : UIButton
@property(nonatomic) struct UIEdgeInsets touchInsets;
@property(nonatomic) long long expandHitWidth;
@property(nonatomic) long long expandHitHeight;
@property(nonatomic) _Bool autoExpandHitArea;
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
    
    if ([DDTimelineForwardConfig isTimelineForwardEnabled]) {
        // 获取点赞按钮的样式作为参考
        UIButton *likeButton = self.m_likeBtn;
        CGFloat buttonWidth = [self buttonWidth:likeButton];
        
        // 创建转发按钮
        MMUIButton *forwardButton = [MMUIButton buttonWithType:UIButtonTypeCustom];
        
        // 使用 UIButtonConfiguration（iOS 15+）
        UIButtonConfiguration *config = [UIButtonConfiguration plainButtonConfiguration];
        config.title = @"转发";
        config.image = [UIImage systemImageNamed:@"arrowshape.turn.up.right.fill"];
        config.imagePlacement = NSDirectionalRectEdgeLeading;
        config.imagePadding = 5;
        config.baseForegroundColor = [likeButton titleColorForState:UIControlStateNormal];
        
        // 设置字体
        UIFont *font = likeButton.titleLabel.font;
        if (font) {
            NSMutableAttributedString *attributedTitle = [[NSMutableAttributedString alloc] initWithString:@"转发"];
            [attributedTitle addAttribute:NSFontAttributeName value:font range:NSMakeRange(0, attributedTitle.length)];
            config.attributedTitle = attributedTitle;
        }
        
        forwardButton.configuration = config;
        
        // 添加点击事件
        [forwardButton addTarget:self action:@selector(dd_forwardTimeline:) forControlEvents:UIControlEventTouchUpInside];
        
        // 设置点击区域扩展（与微信按钮保持一致）
        forwardButton.touchInsets = UIEdgeInsetsMake(-10, -10, -10, -10);
        forwardButton.autoExpandHitArea = YES;
        
        // 获取评论按钮的位置
        CGRect commentBtnFrame = self.m_commentBtn.frame;
        
        // 计算转发按钮位置
        CGFloat forwardButtonX = CGRectGetMaxX(commentBtnFrame);
        forwardButton.frame = CGRectMake(
            forwardButtonX,
            commentBtnFrame.origin.y,
            buttonWidth,
            commentBtnFrame.size.height
        );
        
        [self addSubview:forwardButton];
        
        // 调整容器视图
        UIView *containerView = likeButton.superview;
        if (containerView) {
            CGRect containerFrame = containerView.frame;
            containerFrame.size.width += buttonWidth;
            containerView.frame = containerFrame;
        }
        
        // 调整自身视图宽度
        CGRect selfFrame = self.frame;
        selfFrame.size.width += buttonWidth;
        self.frame = selfFrame;
        
        // 调整背景图片视图宽度
        for (UIView *subview in self.subviews) {
            if ([subview isKindOfClass:[UIImageView class]] && subview.frame.size.width > 100) {
                // 可能是背景图片视图
                CGRect bkgFrame = subview.frame;
                bkgFrame.size.width = selfFrame.size.width;
                subview.frame = bkgFrame;
            }
        }
    }
}

%new
- (void)dd_forwardTimeline:(UIButton *)sender {
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