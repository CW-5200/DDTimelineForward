
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

// Hook实现 - 修复版
%hook WCOperateFloatView

// 使用关联对象避免重复添加按钮
static void *forwardButtonKey = &forwardButtonKey;

- (void)showWithItemData:(id)arg1 tipPoint:(struct CGPoint)arg2 {
    %orig(arg1, arg2);
    
    if ([DDTimelineForwardConfig isTimelineForwardEnabled]) {
        // 检查是否已存在转发按钮
        UIButton *existingForwardButton = objc_getAssociatedObject(self, forwardButtonKey);
        if (existingForwardButton) {
            [existingForwardButton removeFromSuperview];
        }
        
        // 创建转发按钮
        UIButton *forwardButton = [UIButton buttonWithType:UIButtonTypeCustom];
        
        // 添加图标
        if (@available(iOS 13.0, *)) {
            // 使用系统图标
            UIImage *forwardImage = [UIImage systemImageNamed:@"paperplane.fill"];
            if (forwardImage) {
                [forwardButton setImage:forwardImage forState:UIControlStateNormal];
                
                // 调整图标大小
                CGSize imageSize = CGSizeMake(22, 22);
                UIGraphicsBeginImageContextWithOptions(imageSize, NO, 0.0);
                [forwardImage drawInRect:CGRectMake(0, 0, imageSize.width, imageSize.height)];
                UIImage *resizedImage = UIGraphicsGetImageFromCurrentImageContext();
                UIGraphicsEndImageContext();
                
                [forwardButton setImage:resizedImage forState:UIControlStateNormal];
                
                // 设置图标颜色与点赞按钮一致
                UIColor *tintColor = self.m_likeBtn.currentTitleColor;
                [forwardButton setTintColor:tintColor];
                
                // 调整图片位置
                forwardButton.imageEdgeInsets = UIEdgeInsetsMake(0, -5, 0, 5);
            } else {
                // 如果系统图标不可用，使用文本
                [forwardButton setTitle:@"转发" forState:UIControlStateNormal];
                [forwardButton setTitleColor:self.m_likeBtn.currentTitleColor forState:UIControlStateNormal];
            }
        } else {
            // iOS 13以下使用文本
            [forwardButton setTitle:@"转发" forState:UIControlStateNormal];
            [forwardButton setTitleColor:self.m_likeBtn.currentTitleColor forState:UIControlStateNormal];
        }
        
        forwardButton.titleLabel.font = self.m_likeBtn.titleLabel.font;
        [forwardButton addTarget:self action:@selector(dd_forwardTimeline:) forControlEvents:UIControlEventTouchUpInside];
        
        // 动态获取按钮宽度
        CGFloat buttonWidth = [self buttonWidth:self.m_likeBtn];
        
        // 获取点赞按钮的frame，确保获取的是正确的值
        CGRect likeBtnFrame = self.m_likeBtn.frame;
        
        // 调试信息
        NSLog(@"[DD] 点赞按钮frame: %@", NSStringFromCGRect(likeBtnFrame));
        NSLog(@"[DD] 按钮宽度: %.2f", buttonWidth);
        NSLog(@"[DD] 容器宽度: %.2f", CGRectGetWidth(self.frame));
        
        // 设置转发按钮frame - 修复偏移问题
        // 使用相对布局，确保在点赞按钮右侧正确位置
        forwardButton.frame = CGRectMake(
            CGRectGetMaxX(likeBtnFrame),  // 直接从点赞按钮右边开始
            likeBtnFrame.origin.y,
            buttonWidth,
            likeBtnFrame.size.height
        );
        
        // 添加到视图
        [self addSubview:forwardButton];
        
        // 使用关联对象存储按钮引用
        objc_setAssociatedObject(self, forwardButtonKey, forwardButton, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        
        // 调整父容器宽度（可选，根据实际布局决定）
        UIView *containerView = self.m_likeBtn.superview;
        if (containerView) {
            CGRect containerFrame = containerView.frame;
            
            // 计算新的宽度：原来的宽度 + 转发按钮的宽度 + 可能需要的间距
            CGFloat originalWidth = CGRectGetWidth(containerFrame);
            CGFloat newWidth = originalWidth + buttonWidth;
            
            containerFrame.size.width = newWidth;
            containerView.frame = containerFrame;
            
            NSLog(@"[DD] 容器宽度从 %.2f 调整到 %.2f", originalWidth, newWidth);
        }
        
        // 调整自身宽度
        CGRect selfFrame = self.frame;
        selfFrame.size.width += buttonWidth;
        self.frame = selfFrame;
        
        // 重新布局以确保按钮正确显示
        [self setNeedsLayout];
        [self layoutIfNeeded];
    }
}

%new
- (void)dd_forwardTimeline:(UIButton *)sender {
    if (!self.m_item || !self.navigationController) {
        NSLog(@"[DD] 转发失败: 缺少必要数据");
        return;
    }
    
    Class WCForwardViewControllerClass = objc_getClass("WCForwardViewController");
    if (!WCForwardViewControllerClass) {
        NSLog(@"[DD] 转发失败: 未找到 WCForwardViewController 类");
        return;
    }
    
    // 使用安全的方式创建转发控制器
    @try {
        WCForwardViewController *forwardVC = [[WCForwardViewControllerClass alloc] initWithDataItem:self.m_item];
        if (forwardVC && self.navigationController) {
            [self.navigationController pushViewController:forwardVC animated:YES];
            NSLog(@"[DD] 跳转到转发页面");
        }
    } @catch (NSException *exception) {
        NSLog(@"[DD] 转发异常: %@", exception);
    }
}

// 确保在视图更新时重新布局
- (void)layoutSubviews {
    %orig;
    
    // 更新转发按钮位置
    UIButton *forwardButton = objc_getAssociatedObject(self, forwardButtonKey);
    if (forwardButton && [DDTimelineForwardConfig isTimelineForwardEnabled]) {
        CGRect likeBtnFrame = self.m_likeBtn.frame;
        CGFloat buttonWidth = [self buttonWidth:self.m_likeBtn];
        
        forwardButton.frame = CGRectMake(
            CGRectGetMaxX(likeBtnFrame),
            likeBtnFrame.origin.y,
            buttonWidth,
            likeBtnFrame.size.height
        );
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
        
        NSLog(@"[DD] 朋友圈转发插件已加载");
    }
}
