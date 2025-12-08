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
@property(retain, nonatomic) NSArray *mediaList;
@end

@interface WCMediaItem : NSObject
@property (retain, nonatomic) NSString *mid;
@property (nonatomic) int type; // 媒体类型
@property (retain, nonatomic) NSString *dataUrl; // 实际是WCUrl对象，这里简化
- (BOOL)hasData; // 检查是否已下载
- (BOOL)hasSight; // 检查视频是否已下载
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

// 媒体下载管理器
@interface WCMediaDownloader : NSObject
@property (copy, nonatomic) id /* block */ completionHandler;
- (id)initWithDataItem:(WCDataItem *)arg0 mediaItem:(WCMediaItem *)arg1;
- (void)startDownloadWithCompletionHandler:(id /* block */)arg0;
@end

// 插件配置类
@interface DDTimelineForwardConfig : NSObject
@property (class, nonatomic, assign, getter=isTimelineForwardEnabled) BOOL timelineForwardEnabled;
@property (class, nonatomic, assign, getter=isAutoDownloadEnabled) BOOL autoDownloadEnabled;
+ (void)setupDefaults;
@end

@implementation DDTimelineForwardConfig

static NSString *const kTimelineForwardEnabledKey = @"DDTimelineForwardEnabled";
static NSString *const kAutoDownloadEnabledKey = @"DDAutoDownloadEnabled";

+ (BOOL)isTimelineForwardEnabled {
    return [[NSUserDefaults standardUserDefaults] boolForKey:kTimelineForwardEnabledKey];
}

+ (void)setTimelineForwardEnabled:(BOOL)enabled {
    [[NSUserDefaults standardUserDefaults] setBool:enabled forKey:kTimelineForwardEnabledKey];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

+ (BOOL)isAutoDownloadEnabled {
    return [[NSUserDefaults standardUserDefaults] boolForKey:kAutoDownloadEnabledKey];
}

+ (void)setAutoDownloadEnabled:(BOOL)enabled {
    [[NSUserDefaults standardUserDefaults] setBool:enabled forKey:kAutoDownloadEnabledKey];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

+ (void)setupDefaults {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    if (![defaults objectForKey:kTimelineForwardEnabledKey]) {
        [defaults setBool:YES forKey:kTimelineForwardEnabledKey];
        [defaults setBool:YES forKey:kAutoDownloadEnabledKey];
        [defaults synchronize];
    }
}

@end

// 媒体下载器管理器
@interface DDMediaDownloadManager : NSObject
+ (instancetype)sharedManager;
- (void)downloadMediaForDataItem:(WCDataItem *)dataItem completion:(void(^)(BOOL success, NSError *error))completion;
@end

@implementation DDMediaDownloadManager

+ (instancetype)sharedManager {
    static DDMediaDownloadManager *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[self alloc] init];
    });
    return sharedInstance;
}

// 检查媒体是否已下载
- (BOOL)checkMediaDownloadStatus:(WCDataItem *)dataItem {
    if (!dataItem.mediaList || dataItem.mediaList.count == 0) {
        return YES; // 没有媒体，不需要下载
    }
    
    for (WCMediaItem *mediaItem in dataItem.mediaList) {
        // 根据媒体类型检查是否已下载
        if (mediaItem.type == 2) { // 视频类型
            if (![mediaItem hasSight]) {
                return NO;
            }
        } else { // 图片类型
            if (![mediaItem hasData]) {
                return NO;
            }
        }
    }
    return YES;
}

// 下载媒体
- (void)downloadMediaForDataItem:(WCDataItem *)dataItem completion:(void(^)(BOOL success, NSError *error))completion {
    if (!dataItem.mediaList || dataItem.mediaList.count == 0) {
        if (completion) completion(YES, nil);
        return;
    }
    
    __block NSInteger downloadCount = 0;
    __block NSInteger totalCount = dataItem.mediaList.count;
    __block BOOL hasError = NO;
    __block NSError *lastError = nil;
    
    for (WCMediaItem *mediaItem in dataItem.mediaList) {
        @autoreleasepool {
            // 检查是否已下载
            BOOL isDownloaded = NO;
            if (mediaItem.type == 2) {
                isDownloaded = [mediaItem hasSight];
            } else {
                isDownloaded = [mediaItem hasData];
            }
            
            if (isDownloaded) {
                downloadCount++;
                if (downloadCount == totalCount) {
                    if (completion) completion(!hasError, lastError);
                }
                continue;
            }
            
            // 创建下载器
            WCMediaDownloader *downloader = [[objc_getClass("WCMediaDownloader") alloc] initWithDataItem:dataItem mediaItem:mediaItem];
            if (downloader) {
                [downloader startDownloadWithCompletionHandler:^(NSError *error) {
                    downloadCount++;
                    
                    if (error) {
                        hasError = YES;
                        lastError = error;
                        NSLog(@"[DDTimelineForward] 媒体下载失败: %@", error);
                    }
                    
                    // 所有媒体下载完成
                    if (downloadCount == totalCount) {
                        if (completion) {
                            completion(!hasError, lastError);
                        }
                    }
                }];
            } else {
                downloadCount++;
                if (downloadCount == totalCount) {
                    if (completion) completion(!hasError, lastError);
                }
            }
        }
    }
}

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
    UISheetPresentationController *sheet = self.sheetPresentationController;
    if (sheet) {
        sheet.detents = @[UISheetPresentationControllerDetent.mediumDetent];
        sheet.prefersGrabberVisible = YES;
        sheet.preferredCornerRadius = 20.0;
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
    
    // 开关控件 - 启用转发
    UIView *switchContainer1 = [[UIView alloc] init];
    
    UILabel *titleLabel1 = [[UILabel alloc] init];
    titleLabel1.text = @"启用朋友圈转发";
    titleLabel1.font = [UIFont systemFontOfSize:17 weight:UIFontWeightSemibold];
    titleLabel1.translatesAutoresizingMaskIntoConstraints = NO;
    [switchContainer1 addSubview:titleLabel1];
    
    self.forwardSwitch = [[UISwitch alloc] init];
    [self.forwardSwitch setOn:[DDTimelineForwardConfig isTimelineForwardEnabled]];
    [self.forwardSwitch addTarget:self action:@selector(forwardSwitchChanged:) forControlEvents:UIControlEventValueChanged];
    self.forwardSwitch.translatesAutoresizingMaskIntoConstraints = NO;
    [switchContainer1 addSubview:self.forwardSwitch];
    
    [NSLayoutConstraint activateConstraints:@[
        [titleLabel1.leadingAnchor constraintEqualToAnchor:switchContainer1.leadingAnchor],
        [titleLabel1.centerYAnchor constraintEqualToAnchor:switchContainer1.centerYAnchor],
        [self.forwardSwitch.trailingAnchor constraintEqualToAnchor:switchContainer1.trailingAnchor],
        [self.forwardSwitch.centerYAnchor constraintEqualToAnchor:switchContainer1.centerYAnchor]
    ]];
    
    [mainStack addArrangedSubview:switchContainer1];
    
    // 开关控件 - 自动下载媒体
    UIView *switchContainer2 = [[UIView alloc] init];
    
    UILabel *titleLabel2 = [[UILabel alloc] init];
    titleLabel2.text = @"自动下载媒体";
    titleLabel2.font = [UIFont systemFontOfSize:17 weight:UIFontWeightSemibold];
    titleLabel2.translatesAutoresizingMaskIntoConstraints = NO;
    [switchContainer2 addSubview:titleLabel2];
    
    self.autoDownloadSwitch = [[UISwitch alloc] init];
    [self.autoDownloadSwitch setOn:[DDTimelineForwardConfig isAutoDownloadEnabled]];
    [self.autoDownloadSwitch addTarget:self action:@selector(autoDownloadSwitchChanged:) forControlEvents:UIControlEventValueChanged];
    self.autoDownloadSwitch.translatesAutoresizingMaskIntoConstraints = NO;
    [switchContainer2 addSubview:self.autoDownloadSwitch];
    
    [NSLayoutConstraint activateConstraints:@[
        [titleLabel2.leadingAnchor constraintEqualToAnchor:switchContainer2.leadingAnchor],
        [titleLabel2.centerYAnchor constraintEqualToAnchor:switchContainer2.centerYAnchor],
        [self.autoDownloadSwitch.trailingAnchor constraintEqualToAnchor:switchContainer2.trailingAnchor],
        [self.autoDownloadSwitch.centerYAnchor constraintEqualToAnchor:switchContainer2.centerYAnchor]
    ]];
    
    UILabel *downloadDescLabel = [[UILabel alloc] init];
    downloadDescLabel.text = @"转发前自动下载图片/视频，确保转发成功";
    downloadDescLabel.font = [UIFont systemFontOfSize:12];
    downloadDescLabel.textColor = [UIColor secondaryLabelColor];
    downloadDescLabel.numberOfLines = 0;
    [mainStack addArrangedSubview:downloadDescLabel];
    
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
    versionLabel.text = @"DD朋友圈转发 v1.1.0";
    versionLabel.font = [UIFont systemFontOfSize:12];
    versionLabel.textColor = [UIColor tertiaryLabelColor];
    versionLabel.textAlignment = NSTextAlignmentCenter;
    [mainStack addArrangedSubview:versionLabel];
    
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

- (void)forwardSwitchChanged:(UISwitch *)sender {
    [DDTimelineForwardConfig setTimelineForwardEnabled:sender.isOn];
}

- (void)autoDownloadSwitchChanged:(UISwitch *)sender {
    [DDTimelineForwardConfig setAutoDownloadEnabled:sender.isOn];
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
- (void)dd_forwardTimeline:(UIButton *)sender {
    if (!self.m_item) {
        return;
    }
    
    // 检查是否需要自动下载媒体
    if ([DDTimelineForwardConfig isAutoDownloadEnabled]) {
        // 检查媒体下载状态
        BOOL mediaDownloaded = [[DDMediaDownloadManager sharedManager] checkMediaDownloadStatus:self.m_item];
        
        if (!mediaDownloaded) {
            // 显示下载提示
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"下载媒体" 
                                                                           message:@"正在下载媒体文件，请稍候..." 
                                                                    preferredStyle:UIAlertControllerStyleAlert];
            [self.window.rootViewController presentViewController:alert animated:YES completion:nil];
            
            // 开始下载媒体
            [[DDMediaDownloadManager sharedManager] downloadMediaForDataItem:self.m_item completion:^(BOOL success, NSError *error) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    [alert dismissViewControllerAnimated:YES completion:^{
                        if (success) {
                            // 下载成功，跳转到转发界面
                            [self showForwardViewController];
                        } else {
                            // 下载失败，询问用户是否继续
                            UIAlertController *errorAlert = [UIAlertController alertControllerWithTitle:@"下载失败" 
                                                                                               message:@"媒体下载失败，可能无法转发图片/视频，是否继续？" 
                                                                                        preferredStyle:UIAlertControllerStyleAlert];
                            [errorAlert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
                            [errorAlert addAction:[UIAlertAction actionWithTitle:@"继续转发" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
                                [self showForwardViewController];
                            }]];
                            [self.window.rootViewController presentViewController:errorAlert animated:YES completion:nil];
                        }
                    }];
                });
            }];
        } else {
            // 媒体已下载，直接跳转
            [self showForwardViewController];
        }
    } else {
        // 不自动下载，直接跳转
        [self showForwardViewController];
    }
}

%new
- (void)showForwardViewController {
    dispatch_async(dispatch_get_main_queue(), ^{
        WCForwardViewController *forwardVC = [[objc_getClass("WCForwardViewController") alloc] initWithDataItem:self.m_item];
        if (self.navigationController) {
            [self.navigationController pushViewController:forwardVC animated:YES];
        } else {
            // 如果没有导航控制器，尝试模态展示
            UIViewController *rootVC = [UIApplication sharedApplication].keyWindow.rootViewController;
            UINavigationController *nav = [[objc_getClass("UINavigationController") alloc] initWithRootViewController:forwardVC];
            [rootVC presentViewController:nav animated:YES completion:nil];
        }
    });
}

%end

// 添加对WCDataItem的hook以确保可以获取mediaList
%hook WCDataItem

%new
- (NSArray *)mediaList {
    // 使用KVC获取媒体列表
    id mediaObj = [self valueForKey:@"media"];
    if (mediaObj) {
        if ([mediaObj isKindOfClass:[NSArray class]]) {
            return mediaObj;
        }
    }
    return @[];
}

%end

// 插件初始化
%ctor {
    @autoreleasepool {
        [DDTimelineForwardConfig setupDefaults];
        
        if (NSClassFromString(@"WCPluginsMgr")) {
            [[objc_getClass("WCPluginsMgr") sharedInstance] 
                registerControllerWithTitle:@"DD朋友圈转发" 
                                   version:@"1.1.0" 
                               controller:@"DDTimelineForwardSettingsController"];
        }
        
        NSLog(@"[DDTimelineForward] 插件已加载 v1.1.0");
    }
}