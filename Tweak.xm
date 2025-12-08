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
@property(retain, nonatomic) id mediaList; // MediaList类型
@end

@interface MediaList : NSObject
@property(retain, nonatomic) NSMutableArray *media; // WCMediaItem数组
@end

@interface WCMediaItem : NSObject
@property(retain, nonatomic) NSString *tid;
@property(retain, nonatomic) NSString *mid;
@property(nonatomic) int type;
@property(retain, nonatomic) NSString *title;
@property(retain, nonatomic) NSString *desc;
@property(retain, nonatomic) NSMutableArray *previewUrls;
@property(retain, nonatomic) id dataUrl;
@property(retain, nonatomic) id lowBandUrl;
// ... 其他属性
- (BOOL)hasData; // 根据头文件，有这个方法
- (BOOL)hasSight;
- (BOOL)hasAttachVideo;
@end

@interface WCMediaDownloader : NSObject
@property(readonly, nonatomic) WCDataItem *dataItem;
@property(readonly, nonatomic) WCMediaItem *mediaItem;
@property(copy, nonatomic) void (^completionHandler)(NSError *error);
- (id)initWithDataItem:(WCDataItem *)dataItem mediaItem:(WCMediaItem *)mediaItem;
- (void)startDownloadWithCompletionHandler:(void (^)(NSError *error))handler;
- (BOOL)hasDownloaded; // 这个方法在WCMediaDownloader中
- (BOOL)Image_hasDownloaded;
- (BOOL)Video_hasDownloaded;
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
    }
    if (![defaults objectForKey:kAutoDownloadEnabledKey]) {
        [defaults setBool:YES forKey:kAutoDownloadEnabledKey];
    }
    [defaults synchronize];
}

@end

// 下载管理器
@interface DDMediaDownloadManager : NSObject
+ (instancetype)sharedManager;
- (void)downloadMediaForDataItem:(WCDataItem *)dataItem
              inViewController:(UIViewController *)viewController
                    completion:(void (^)(BOOL success, NSError *error))completion;
@end

@implementation DDMediaDownloadManager {
    NSMutableArray *_downloadingItems;
    NSMutableDictionary *_downloaders;
    NSInteger _successCount;
    NSInteger _failCount;
    NSInteger _totalCount;
    void (^_completion)(BOOL success, NSError *error);
    UIView *_loadingView;
}

+ (instancetype)sharedManager {
    static DDMediaDownloadManager *instance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[DDMediaDownloadManager alloc] init];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _downloadingItems = [NSMutableArray array];
        _downloaders = [NSMutableDictionary dictionary];
    }
    return self;
}

- (void)showLoadingInView:(UIView *)view {
    if (_loadingView) {
        [_loadingView removeFromSuperview];
    }
    
    _loadingView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 120, 120)];
    _loadingView.backgroundColor = [UIColor colorWithWhite:0 alpha:0.7];
    _loadingView.layer.cornerRadius = 10;
    _loadingView.center = CGPointMake(view.bounds.size.width/2, view.bounds.size.height/2);
    _loadingView.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleRightMargin | UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleBottomMargin;
    
    // 使用新的ActivityIndicatorView样式
    UIActivityIndicatorView *indicator = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleLarge];
    indicator.color = [UIColor whiteColor];
    indicator.center = CGPointMake(60, 50);
    [indicator startAnimating];
    [_loadingView addSubview:indicator];
    
    UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(0, 80, 120, 30)];
    label.text = @"下载媒体中...";
    label.textColor = [UIColor whiteColor];
    label.textAlignment = NSTextAlignmentCenter;
    label.font = [UIFont systemFontOfSize:14];
    [_loadingView addSubview:label];
    
    [view addSubview:_loadingView];
}

- (void)hideLoading {
    if (_loadingView) {
        [_loadingView removeFromSuperview];
        _loadingView = nil;
    }
}

- (BOOL)isMediaItemDownloaded:(WCMediaItem *)mediaItem {
    // 根据WCMediaItem.h中的方法，检查是否已下载
    @try {
        // 根据类型检查不同的下载状态
        if (mediaItem.type == 2 || mediaItem.type == 6) { // 视频类型
            if ([mediaItem respondsToSelector:@selector(hasSight)]) {
                return [mediaItem hasSight];
            }
            if ([mediaItem respondsToSelector:@selector(hasAttachVideo)]) {
                return [mediaItem hasAttachVideo];
            }
        } else { // 图片类型
            if ([mediaItem respondsToSelector:@selector(hasData)]) {
                return [mediaItem hasData];
            }
        }
        
        // 检查媒体ID是否在已下载列表中
        NSString *mediaID = mediaItem.mid;
        if (!mediaID) return NO;
        
        // 检查本地文件是否存在
        NSString *documentsPath = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
        NSString *snsPath = [documentsPath stringByAppendingPathComponent:@"Sns"];
        
        // 检查多种可能的文件路径
        NSFileManager *fileManager = [NSFileManager defaultManager];
        
        // 检查是否有对应的缓存文件
        NSString *midHash = [self md5Hash:mediaID];
        NSString *cachePath1 = [snsPath stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.mp4", midHash]];
        NSString *cachePath2 = [snsPath stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.jpg", midHash]];
        NSString *cachePath3 = [snsPath stringByAppendingPathComponent:[NSString stringWithFormat:@"%@.png", midHash]];
        
        if ([fileManager fileExistsAtPath:cachePath1] || 
            [fileManager fileExistsAtPath:cachePath2] || 
            [fileManager fileExistsAtPath:cachePath3]) {
            return YES;
        }
        
    } @catch (NSException *exception) {
        NSLog(@"DDTimeline: 检查下载状态异常: %@", exception);
    }
    
    return NO;
}

- (NSString *)md5Hash:(NSString *)string {
    // 简单的哈希函数，用于生成文件名
    __block NSString *hash = @"";
    
    // 简化版本，实际应该使用更安全的哈希
    @autoreleasepool {
        NSData *data = [string dataUsingEncoding:NSUTF8StringEncoding];
        if (data.length > 0) {
            hash = [NSString stringWithFormat:@"%08lx", (unsigned long)[data hash]];
        }
    }
    
    return hash;
}

- (void)downloadMediaForDataItem:(WCDataItem *)dataItem
              inViewController:(UIViewController *)viewController
                    completion:(void (^)(BOOL success, NSError *error))completion {
    
    if (![DDTimelineForwardConfig isAutoDownloadEnabled]) {
        if (completion) {
            completion(YES, nil);
        }
        return;
    }
    
    // 获取媒体列表
    MediaList *mediaList = nil;
    @try {
        mediaList = [dataItem valueForKey:@"mediaList"];
    } @catch (NSException *exception) {
        NSLog(@"DDTimeline: 无法获取mediaList: %@", exception);
        if (completion) {
            completion(NO, [NSError errorWithDomain:@"DDTimelineForward" code:-1 userInfo:@{NSLocalizedDescriptionKey: @"无法获取媒体列表"}]);
        }
        return;
    }
    
    NSArray *mediaItems = mediaList.media;
    if (!mediaItems || mediaItems.count == 0) {
        NSLog(@"DDTimeline: 没有媒体需要下载");
        if (completion) {
            completion(YES, nil);
        }
        return;
    }
    
    NSLog(@"DDTimeline: 发现 %lu 个媒体文件", (unsigned long)mediaItems.count);
    
    // 检查哪些需要下载
    NSMutableArray *needDownloadItems = [NSMutableArray array];
    for (WCMediaItem *mediaItem in mediaItems) {
        if (![self isMediaItemDownloaded:mediaItem]) {
            [needDownloadItems addObject:mediaItem];
        } else {
            NSLog(@"DDTimeline: 媒体已下载: %@", mediaItem.mid);
        }
    }
    
    if (needDownloadItems.count == 0) {
        NSLog(@"DDTimeline: 所有媒体都已下载");
        if (completion) {
            completion(YES, nil);
        }
        return;
    }
    
    NSLog(@"DDTimeline: 需要下载 %lu 个媒体文件", (unsigned long)needDownloadItems.count);
    
    // 显示加载视图
    [self showLoadingInView:viewController.view];
    
    // 保存回调
    _completion = completion;
    _successCount = 0;
    _failCount = 0;
    _totalCount = needDownloadItems.count;
    
    // 开始下载每个媒体
    for (WCMediaItem *mediaItem in needDownloadItems) {
        [self downloadSingleMedia:mediaItem forDataItem:dataItem];
    }
}

- (void)downloadSingleMedia:(WCMediaItem *)mediaItem forDataItem:(WCDataItem *)dataItem {
    @try {
        // 创建下载器
        WCMediaDownloader *downloader = [[objc_getClass("WCMediaDownloader") alloc] initWithDataItem:dataItem mediaItem:mediaItem];
        
        NSString *key = [NSString stringWithFormat:@"%@_%@", dataItem.username, mediaItem.mid ?: @""];
        _downloaders[key] = downloader;
        
        // 开始下载
        [downloader startDownloadWithCompletionHandler:^(NSError *error) {
            dispatch_async(dispatch_get_main_queue(), ^{
                NSString *key = [NSString stringWithFormat:@"%@_%@", dataItem.username, mediaItem.mid ?: @""];
                [self->_downloaders removeObjectForKey:key];
                
                if (error) {
                    NSLog(@"DDTimeline: 下载失败: %@, error: %@", mediaItem.mid, error);
                    self->_failCount++;
                } else {
                    NSLog(@"DDTimeline: 下载成功: %@", mediaItem.mid);
                    self->_successCount++;
                }
                
                // 检查是否全部完成
                if (self->_successCount + self->_failCount >= self->_totalCount) {
                    [self downloadCompleted];
                }
            });
        }];
        
    } @catch (NSException *exception) {
        NSLog(@"DDTimeline: 创建下载器异常: %@", exception);
        _failCount++;
        
        if (_successCount + _failCount >= _totalCount) {
            [self downloadCompleted];
        }
    }
}

- (void)downloadCompleted {
    [self hideLoading];
    
    BOOL success = _failCount == 0;
    NSError *error = nil;
    
    if (_failCount > 0) {
        NSString *errorMsg = [NSString stringWithFormat:@"成功下载 %ld 个，失败 %ld 个", (long)_successCount, (long)_failCount];
        error = [NSError errorWithDomain:@"DDTimelineForward" 
                                    code:-1 
                                userInfo:@{NSLocalizedDescriptionKey: errorMsg}];
        NSLog(@"DDTimeline: %@", errorMsg);
    } else {
        NSLog(@"DDTimeline: 所有媒体下载完成");
    }
    
    if (_completion) {
        _completion(success, error);
    }
    
    // 清理
    _completion = nil;
    [_downloaders removeAllObjects];
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
    if (@available(iOS 15.0, *)) {
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
    UIStackView *mainStack = [[UIStackView alloc] init];
    mainStack.axis = UILayoutConstraintAxisVertical;
    mainStack.spacing = 24;
    mainStack.alignment = UIStackViewAlignmentFill;
    mainStack.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:mainStack];
    
    // 开关控件1: 启用转发
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
    
    // 开关控件2: 自动下载媒体
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
    
    [mainStack addArrangedSubview:switchContainer2];
    
    // 说明文字
    UILabel *descriptionLabel = [[UILabel alloc] init];
    descriptionLabel.text = @"自动下载功能会在转发前下载所有媒体文件，避免转发失败";
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
        [mainStack.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:32],
        [mainStack.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:20],
        [mainStack.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-20]
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
    // 禁用按钮，防止重复点击
    sender.enabled = NO;
    
    // 获取当前视图控制器
    UIViewController *currentVC = nil;
    if (self.navigationController) {
        currentVC = self.navigationController;
    } else {
        // 查找父视图控制器
        UIResponder *responder = self;
        while (![responder isKindOfClass:[UIViewController class]]) {
            responder = responder.nextResponder;
        }
        currentVC = (UIViewController *)responder;
    }
    
    if (!currentVC) {
        NSLog(@"DDTimeline: 无法找到当前视图控制器");
        sender.enabled = YES;
        return;
    }
    
    // 下载媒体文件
    [[DDMediaDownloadManager sharedManager] downloadMediaForDataItem:self.m_item
                                                  inViewController:currentVC
                                                        completion:^(BOOL success, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            sender.enabled = YES;
            
            if (success || error) {
                // 即使有部分失败也跳转，让转发界面处理
                WCForwardViewController *forwardVC = [[objc_getClass("WCForwardViewController") alloc] initWithDataItem:self.m_item];
                if (self.navigationController) {
                    [self.navigationController pushViewController:forwardVC animated:YES];
                } else if (currentVC.navigationController) {
                    [currentVC.navigationController pushViewController:forwardVC animated:YES];
                } else {
                    [currentVC presentViewController:forwardVC animated:YES completion:nil];
                }
            }
            
            // 如果下载失败，显示提示（可选）
            if (error) {
                UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"提示"
                                                                               message:error.localizedDescription
                                                                        preferredStyle:UIAlertControllerStyleAlert];
                [alert addAction:[UIAlertAction actionWithTitle:@"确定" 
                                                         style:UIAlertActionStyleDefault 
                                                       handler:nil]];
                [currentVC presentViewController:alert animated:YES completion:nil];
            }
        });
    }];
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
        
        NSLog(@"DD朋友圈转发插件 v1.1.0 已加载");
    }
}