// DDTimelineForwardWithCache.xm
#import <UIKit/UIKit.h>
#import <objc/runtime.h>

// 配置类
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

// 微信相关类声明
@interface WCDataItem : NSObject
@property(retain, nonatomic) NSString *username;
@property(retain, nonatomic) NSArray *mediaArray; // 媒体数组
@property(retain, nonatomic) id firstMediaItem;   // 第一个媒体
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

@interface WCMediaItem : NSObject
@property(retain, nonatomic) NSString *tid;
@property(retain, nonatomic) NSString *mid;
@property(retain, nonatomic) id dataUrl;
@property(retain, nonatomic) id lowBandUrl;
@property(retain, nonatomic) id attachUrl;
@property(nonatomic) int type;
@property(nonatomic) int subType;
@property(nonatomic) int totalSize;
@property(nonatomic) struct CGSize { double width; double height; } imgSize;
- (BOOL)hasDownloaded;
- (id)pathForData;
- (id)pathForSightData;
- (id)pathForPreview;
@end

@interface WCMediaDownloader : NSObject
@property(retain, nonatomic) id retainedSelf;
@property(copy, nonatomic) void (^completionHandler)(NSError *);
- (id)initWithDataItem:(id)arg1 mediaItem:(id)arg2;
- (void)startDownloadWithCompletionHandler:(void (^)(NSError *))arg1;
- (BOOL)hasDownloaded;
- (void)_retainSelf;
- (void)_releaseSelf;
@end

@interface WCFacade : NSObject
+ (id)sharedInstance;
- (void)downloadMediaForDataItem:(id)arg1 mediaItem:(id)arg2 shouldAutoDownload:(BOOL)arg3 completion:(void (^)(NSError *, NSString *))arg4;
@end

// 媒体下载管理器
@interface DDMediaCacheManager : NSObject
@property (nonatomic, strong) NSMutableDictionary *downloadTasks;
@property (nonatomic, strong) NSMutableDictionary *completionHandlers;
+ (instancetype)sharedManager;
- (void)downloadMediaForDataItem:(WCDataItem *)dataItem completion:(void (^)(BOOL success, NSError *error))completion;
- (void)showDownloadProgress;
- (void)hideDownloadProgress;
@end

@implementation DDMediaCacheManager {
    UIView *_progressView;
    UILabel *_progressLabel;
    UIProgressView *_progressBar;
    NSUInteger _totalMediaCount;
    NSUInteger _completedCount;
}

+ (instancetype)sharedManager {
    static DDMediaCacheManager *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[self alloc] init];
    });
    return sharedInstance;
}

- (instancetype)init {
    if (self = [super init]) {
        _downloadTasks = [NSMutableDictionary dictionary];
        _completionHandlers = [NSMutableDictionary dictionary];
    }
    return self;
}

- (void)showDownloadProgress {
    if (!_progressView) {
        _progressView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 200, 120)];
        _progressView.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.85];
        _progressView.layer.cornerRadius = 12;
        _progressView.layer.masksToBounds = YES;
        _progressView.center = [UIApplication sharedApplication].keyWindow.center;
        
        _progressLabel = [[UILabel alloc] initWithFrame:CGRectMake(20, 20, 160, 30)];
        _progressLabel.textColor = [UIColor whiteColor];
        _progressLabel.textAlignment = NSTextAlignmentCenter;
        _progressLabel.font = [UIFont systemFontOfSize:16];
        _progressLabel.text = @"正在准备媒体文件...";
        
        _progressBar = [[UIProgressView alloc] initWithFrame:CGRectMake(20, 70, 160, 2)];
        _progressBar.progressTintColor = [UIColor colorWithRed:0.0 green:0.5 blue:1.0 alpha:1.0];
        
        [_progressView addSubview:_progressLabel];
        [_progressView addSubview:_progressBar];
    }
    
    _progressBar.progress = 0;
    _completedCount = 0;
    [[UIApplication sharedApplication].keyWindow addSubview:_progressView];
}

- (void)updateProgress:(float)progress {
    _progressBar.progress = progress;
    _progressLabel.text = [NSString stringWithFormat:@"正在下载... %.0f%%", progress * 100];
}

- (void)hideDownloadProgress {
    [_progressView removeFromSuperview];
}

- (void)downloadMediaForDataItem:(WCDataItem *)dataItem completion:(void (^)(BOOL success, NSError *error))completion {
    if (!dataItem) {
        if (completion) completion(NO, [NSError errorWithDomain:@"DDTimelineForward" code:-1 userInfo:@{NSLocalizedDescriptionKey: @"数据项为空"}]);
        return;
    }
    
    // 获取媒体数组
    NSArray *mediaArray = nil;
    if ([dataItem respondsToSelector:@selector(mediaArray)]) {
        mediaArray = [dataItem mediaArray];
    } else if ([dataItem respondsToSelector:@selector(firstMediaItem)]) {
        id mediaItem = [dataItem firstMediaItem];
        if (mediaItem) mediaArray = @[mediaItem];
    }
    
    if (!mediaArray || mediaArray.count == 0) {
        // 没有媒体，直接完成
        if (completion) completion(YES, nil);
        return;
    }
    
    _totalMediaCount = mediaArray.count;
    _completedCount = 0;
    [self showDownloadProgress];
    
    __block NSError *lastError = nil;
    __block NSUInteger successCount = 0;
    dispatch_group_t group = dispatch_group_create();
    
    for (id mediaItem in mediaArray) {
        if (![mediaItem isKindOfClass:objc_getClass("WCMediaItem")]) continue;
        
        dispatch_group_enter(group);
        
        // 检查是否已下载
        if ([mediaItem respondsToSelector:@selector(hasDownloaded)] && [mediaItem hasDownloaded]) {
            _completedCount++;
            [self updateProgress:(float)_completedCount / _totalMediaCount];
            successCount++;
            dispatch_group_leave(group);
            continue;
        }
        
        // 使用微信的下载机制
        NSString *key = [NSString stringWithFormat:@"%p_%p", dataItem, mediaItem];
        
        WCFacade *facade = [objc_getClass("WCFacade") sharedInstance];
        if (facade && [facade respondsToSelector:@selector(downloadMediaForDataItem:mediaItem:shouldAutoDownload:completion:)]) {
            [facade downloadMediaForDataItem:dataItem 
                                   mediaItem:mediaItem 
                         shouldAutoDownload:YES 
                                 completion:^(NSError *error, NSString *path) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    self->_completedCount++;
                    [self updateProgress:(float)self->_completedCount / self->_totalMediaCount];
                    
                    if (!error && path) {
                        successCount++;
                    } else {
                        lastError = error;
                        NSLog(@"DDTimelineForward: 下载失败: %@", error);
                    }
                    
                    dispatch_group_leave(group);
                });
            }];
        } else {
            // 备用方法：直接使用WCMediaDownloader
            WCMediaDownloader *downloader = [[objc_getClass("WCMediaDownloader") alloc] initWithDataItem:dataItem mediaItem:mediaItem];
            if (downloader) {
                [self.downloadTasks setObject:downloader forKey:key];
                
                [downloader startDownloadWithCompletionHandler:^(NSError *error) {
                    dispatch_async(dispatch_get_main_queue(), ^{
                        [self.downloadTasks removeObjectForKey:key];
                        
                        self->_completedCount++;
                        [self updateProgress:(float)self->_completedCount / self->_totalMediaCount];
                        
                        if (!error) {
                            successCount++;
                        } else {
                            lastError = error;
                            NSLog(@"DDTimelineForward: 下载失败: %@", error);
                        }
                        
                        dispatch_group_leave(group);
                    });
                }];
            } else {
                dispatch_group_leave(group);
            }
        }
    }
    
    dispatch_group_notify(group, dispatch_get_main_queue(), ^{
        [self hideDownloadProgress];
        
        BOOL success = (successCount > 0) || (mediaArray.count == 0);
        if (completion) {
            completion(success, lastError);
        }
    });
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
    descriptionLabel.text = @"启用后在朋友圈菜单中添加「转发」按钮，转发前会自动缓存媒体文件";
    descriptionLabel.font = [UIFont systemFontOfSize:14];
    descriptionLabel.textColor = [UIColor secondaryLabelColor];
    descriptionLabel.numberOfLines = 0;
    descriptionLabel.textAlignment = NSTextAlignmentCenter;
    [mainStack addArrangedSubview:descriptionLabel];
    
    // 版本信息
    UILabel *versionLabel = [[UILabel alloc] init];
    versionLabel.text = @"DD朋友圈转发 v1.1.0 (带缓存)";
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
    if (!self.m_item) return;
    
    // 先缓存媒体文件
    [[DDMediaCacheManager sharedManager] downloadMediaForDataItem:self.m_item completion:^(BOOL success, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (success) {
                // 下载成功，跳转到转发界面
                Class WCForwardViewControllerClass = objc_getClass("WCForwardViewController");
                if (WCForwardViewControllerClass) {
                    WCForwardViewController *forwardVC = [[WCForwardViewControllerClass alloc] initWithDataItem:self.m_item];
                    if (self.navigationController) {
                        [self.navigationController pushViewController:forwardVC animated:YES];
                    }
                }
            } else {
                // 下载失败，显示提示
                UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"转发失败" 
                                                                               message:error.localizedDescription ?: @"媒体文件下载失败，无法转发"
                                                                        preferredStyle:UIAlertControllerStyleAlert];
                [alert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:nil]];
                
                UIViewController *topVC = [UIApplication sharedApplication].keyWindow.rootViewController;
                while (topVC.presentedViewController) {
                    topVC = topVC.presentedViewController;
                }
                [topVC presentViewController:alert animated:YES completion:nil];
            }
        });
    }];
}

%end

// 插件管理器接口
@interface WCPluginsMgr : NSObject
+ (instancetype)sharedInstance;
- (void)registerControllerWithTitle:(NSString *)title version:(NSString *)version controller:(NSString *)controller;
@end

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
        
        NSLog(@"DD朋友圈转发插件已加载 (带媒体缓存功能)");
    }
}