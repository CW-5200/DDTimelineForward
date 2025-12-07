#import <UIKit/UIKit.h>
#import <objc/runtime.h>

// MARK: - 插件管理器接口
@interface WCPluginsMgr : NSObject
+ (instancetype)sharedInstance;
- (void)registerControllerWithTitle:(NSString *)title version:(NSString *)version controller:(NSString *)controller;
@end

// MARK: - 微信相关类声明
@interface WCDataItem : NSObject
@property(retain, nonatomic) NSString *username;
@end

@interface WCOperateFloatView : UIView
@property(readonly, nonatomic) UIButton *m_likeBtn;
@property(readonly, nonatomic) WCDataItem *m_item;
@property(nonatomic) __weak UINavigationController *navigationController;
- (void)showWithItemData:(id)arg1 tipPoint:(struct CGPoint)arg2;
- (double)buttonWidth:(id)arg1;
- (void)layoutSubviews;
@end

@interface WCForwardViewController : UIViewController
- (id)initWithDataItem:(WCDataItem *)arg1;
@end

// MARK: - 插件配置类
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

// MARK: - 设置界面控制器
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
    descriptionLabel.text = @"启用后在朋友圈长按菜单中添加「转发」按钮，可快速转发朋友圈内容";
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

// MARK: - Hook实现
%hook WCOperateFloatView

- (void)showWithItemData:(id)arg1 tipPoint:(struct CGPoint)arg2 {
    // 先调用原始方法，确保基础布局完成
    %orig(arg1, arg2);
    
    // 添加转发按钮
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        // 延迟一点确保布局完成
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.05 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [self addForwardButtonIfNeeded];
        });
    });
}

- (void)layoutSubviews {
    %orig;
    [self addForwardButtonIfNeeded];
}

%new
- (void)addForwardButtonIfNeeded {
    if (![DDTimelineForwardConfig isTimelineForwardEnabled]) {
        // 如果已存在转发按钮，移除它
        for (UIView *subview in self.subviews) {
            if ([subview isKindOfClass:[UIButton class]] && 
                ((UIButton *)subview).tag == 9999) {
                [subview removeFromSuperview];
            }
        }
        return;
    }
    
    // 检查是否已添加转发按钮
    BOOL hasForwardButton = NO;
    for (UIView *subview in self.subviews) {
        if ([subview isKindOfClass:[UIButton class]] && 
            ((UIButton *)subview).tag == 9999) {
            hasForwardButton = YES;
            break;
        }
    }
    
    if (hasForwardButton) return;
    
    // 获取微信分享图标（尝试多种方法）
    UIImage *shareIcon = nil;
    
    // 方法1：尝试从系统资源获取分享图标
    if (@available(iOS 13.0, *)) {
        // iOS 13+ 系统分享图标
        shareIcon = [UIImage systemImageNamed:@"square.and.arrow.up"];
    }
    
    // 方法2：创建自定义分享图标
    if (!shareIcon) {
        UIGraphicsBeginImageContextWithOptions(CGSizeMake(24, 24), NO, 0.0);
        
        // 绘制分享箭头图标
        UIBezierPath *path = [UIBezierPath bezierPath];
        [path moveToPoint:CGPointMake(6, 12)];
        [path addLineToPoint:CGPointMake(18, 12)];
        [path moveToPoint:CGPointMake(15, 9)];
        [path addLineToPoint:CGPointMake(18, 12)];
        [path addLineToPoint:CGPointMake(15, 15)];
        [path moveToPoint:CGPointMake(18, 8)];
        [path addLineToPoint:CGPointMake(18, 16)];
        [path addLineToPoint:CGPointMake(12, 16)];
        [path addLineToPoint:CGPointMake(12, 8)];
        [path addLineToPoint:CGPointMake(18, 8)];
        
        path.lineWidth = 1.5;
        path.lineCapStyle = kCGLineCapRound;
        path.lineJoinStyle = kCGLineJoinRound;
        
        // 使用微信按钮的蓝色
        [[UIColor colorWithRed:0.0 green:0.478 blue:1.0 alpha:1.0] setStroke];
        [path stroke];
        
        shareIcon = UIGraphicsGetImageFromCurrentImageContext();
        UIGraphicsEndImageContext();
    }
    
    // 创建转发按钮
    UIButton *forwardButton = [UIButton buttonWithType:UIButtonTypeCustom];
    forwardButton.tag = 9999; // 用于标识我们的按钮
    
    // 设置按钮样式，匹配微信原生按钮
    if (shareIcon) {
        [forwardButton setImage:[shareIcon imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate] 
                       forState:UIControlStateNormal];
        forwardButton.tintColor = self.m_likeBtn.tintColor ?: [UIColor colorWithRed:0.0 green:0.478 blue:1.0 alpha:1.0];
    } else {
        [forwardButton setTitle:@"转发" forState:UIControlStateNormal];
        [forwardButton setTitleColor:self.m_likeBtn.currentTitleColor forState:UIControlStateNormal];
    }
    
    forwardButton.titleLabel.font = self.m_likeBtn.titleLabel.font;
    [forwardButton addTarget:self action:@selector(dd_forwardTimeline:) forControlEvents:UIControlEventTouchUpInside];
    
    // 计算按钮位置，放在点赞按钮右边
    CGFloat buttonWidth = [self buttonWidth:self.m_likeBtn];
    CGRect likeBtnFrame = self.m_likeBtn.frame;
    
    // 调整按钮位置，避免整体偏移
    forwardButton.frame = CGRectMake(
        CGRectGetMaxX(likeBtnFrame),
        likeBtnFrame.origin.y,
        buttonWidth,
        likeBtnFrame.size.height
    );
    
    [self addSubview:forwardButton];
    
    // 调整容器宽度和位置，保持居中显示
    [self adjustContainerForForwardButton:buttonWidth];
}

%new
- (void)adjustContainerForForwardButton:(CGFloat)buttonWidth {
    // 获取按钮容器（通常是所有按钮的父视图）
    UIView *buttonContainer = self.m_likeBtn.superview;
    if (!buttonContainer) return;
    
    // 保存原始中心点，以便保持居中
    CGPoint originalCenter = buttonContainer.center;
    
    // 扩展容器宽度，为转发按钮腾出空间
    CGRect containerFrame = buttonContainer.frame;
    containerFrame.size.width += buttonWidth;
    buttonContainer.frame = containerFrame;
    
    // 调整整个浮窗的宽度
    CGRect selfFrame = self.frame;
    selfFrame.size.width += buttonWidth;
    self.frame = selfFrame;
    
    // 重新计算所有按钮的位置，避免偏移
    [self repositionButtonsInContainer:buttonContainer];
    
    // 保持容器居中
    buttonContainer.center = originalCenter;
    
    // 调整浮窗位置，避免超出屏幕
    [self adjustPopupPosition];
}

%new
- (void)repositionButtonsInContainer:(UIView *)container {
    // 获取容器中所有按钮
    NSMutableArray *buttons = [NSMutableArray array];
    for (UIView *subview in container.subviews) {
        if ([subview isKindOfClass:[UIButton class]]) {
            [buttons addObject:subview];
        }
    }
    
    // 按x坐标排序
    [buttons sortUsingComparator:^NSComparisonResult(UIButton *btn1, UIButton *btn2) {
        return btn1.frame.origin.x > btn2.frame.origin.x ? NSOrderedDescending : NSOrderedAscending;
    }];
    
    // 重新布局按钮，等间距排列
    CGFloat totalWidth = 0;
    for (UIButton *button in buttons) {
        totalWidth += button.frame.size.width;
    }
    
    CGFloat spacing = (container.frame.size.width - totalWidth) / (buttons.count + 1);
    CGFloat currentX = spacing;
    
    for (UIButton *button in buttons) {
        CGRect buttonFrame = button.frame;
        buttonFrame.origin.x = currentX;
        button.frame = buttonFrame;
        currentX += buttonFrame.size.width + spacing;
    }
}

%new
- (void)adjustPopupPosition {
    // 确保浮窗不会超出屏幕边界
    CGRect screenBounds = [UIScreen mainScreen].bounds;
    CGFloat screenWidth = screenBounds.size.width;
    
    CGRect selfFrame = self.frame;
    
    // 检查是否超出右边屏幕边界
    if (CGRectGetMaxX(selfFrame) > screenWidth - 10) {
        selfFrame.origin.x = screenWidth - selfFrame.size.width - 10;
        self.frame = selfFrame;
    }
    
    // 检查是否超出左边屏幕边界
    if (selfFrame.origin.x < 10) {
        selfFrame.origin.x = 10;
        self.frame = selfFrame;
    }
}

%new
- (void)dd_forwardTimeline:(UIButton *)sender {
    WCForwardViewController *forwardVC = [[objc_getClass("WCForwardViewController") alloc] initWithDataItem:self.m_item];
    if (self.navigationController) {
        [self.navigationController pushViewController:forwardVC animated:YES];
    }
    
    // 隐藏浮窗
    [self removeFromSuperview];
}

%end

// MARK: - 插件初始化
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