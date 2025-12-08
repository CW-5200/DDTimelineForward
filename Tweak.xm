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
@property(retain, nonatomic) NSMutableArray *mediaList; // 媒体列表
- (id)mediaAtIndex:(unsigned int)index;
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

@interface MediaList : NSObject
@property (retain, nonatomic) NSMutableArray *media;
@end

@interface WCMediaItem : NSObject
@property (nonatomic) int type; // 1:图片 15:视频
@property (retain, nonatomic) NSString *mid;
@property (retain, nonatomic) NSString *title;
@property (retain, nonatomic) NSString *desc;
@property (retain, nonatomic) NSMutableArray *previewUrls;
@property (retain, nonatomic) id dataUrl;
@property (retain, nonatomic) id lowBandUrl;
@property (nonatomic) struct CGSize { double width; double height; } imgSize;
@property (nonatomic) double videoDuration;
@property (readonly, nonatomic) BOOL hasData;
@property (readonly, nonatomic) BOOL hasSight;
- (id)pathForData;
- (id)pathForSightData;
- (id)tempPathForSightData;
@end

@interface WCMediaDownloader : NSObject
@property (retain, nonatomic) WCMediaDownloader *retainedSelf;
@property (copy, nonatomic) id /* block */ completionHandler;
@property (readonly, nonatomic) WCDataItem *dataItem;
@property (readonly, nonatomic) WCMediaItem *mediaItem;
- (id)initWithDataItem:(id)a0 mediaItem:(id)a1;
- (BOOL)hasDownloaded;
- (void)startDownloadWithCompletionHandler:(id /* block */)a0;
- (void)Image_startDownload;
- (void)Video_startDownload;
@end

// 媒体缓存管理器
@interface DDMediaCacheManager : NSObject
+ (instancetype)sharedManager;
- (void)cacheMediaForDataItem:(WCDataItem *)dataItem completion:(void (^)(BOOL success))completion;
- (BOOL)isAllMediaCachedForDataItem:(WCDataItem *)dataItem;
@end

@implementation DDMediaCacheManager {
    NSMutableDictionary *_cachingItems;
}

+ (instancetype)sharedManager {
    static DDMediaCacheManager *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[DDMediaCacheManager alloc] init];
    });
    return sharedInstance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _cachingItems = [NSMutableDictionary dictionary];
    }
    return self;
}

- (BOOL)isAllMediaCachedForDataItem:(WCDataItem *)dataItem {
    if (!dataItem || ![dataItem respondsToSelector:@selector(mediaList)]) {
        return YES;
    }
    
    NSMutableArray *mediaList = [dataItem valueForKey:@"mediaList"];
    if (!mediaList || mediaList.count == 0) {
        return YES;
    }
    
    for (WCMediaItem *mediaItem in mediaList) {
        if (mediaItem.type == 1) { // 图片
            if (!mediaItem.hasData) {
                return NO;
            }
        } else if (mediaItem.type == 15) { // 视频
            if (!mediaItem.hasSight) {
                return NO;
            }
        }
    }
    
    return YES;
}

- (void)cacheMediaForDataItem:(WCDataItem *)dataItem completion:(void (^)(BOOL success))completion {
    if (!dataItem || ![dataItem respondsToSelector:@selector(mediaList)]) {
        if (completion) completion(YES);
        return;
    }
    
    NSMutableArray *mediaList = [dataItem valueForKey:@"mediaList"];
    if (!mediaList || mediaList.count == 0) {
        if (completion) completion(YES);
        return;
    }
    
    __block NSInteger pendingDownloads = mediaList.count;
    __block BOOL hasError = NO;
    
    for (WCMediaItem *mediaItem in mediaList) {
        NSString *itemKey = [NSString stringWithFormat:@"%@_%@", dataItem.username, mediaItem.mid ?: @""];
        
        // 检查是否已经在下载
        if (_cachingItems[itemKey]) {
            pendingDownloads--;
            if (pendingDownloads <= 0) {
                if (completion) completion(!hasError);
            }
            continue;
        }
        
        // 检查是否已下载
        BOOL isDownloaded = NO;
        if (mediaItem.type == 1) { // 图片
            isDownloaded = mediaItem.hasData;
        } else if (mediaItem.type == 15) { // 视频
            isDownloaded = mediaItem.hasSight;
        } else {
            pendingDownloads--;
            if (pendingDownloads <= 0) {
                if (completion) completion(!hasError);
            }
            continue;
        }
        
        if (isDownloaded) {
            pendingDownloads--;
            if (pendingDownloads <= 0) {
                if (completion) completion(!hasError);
            }
            continue;
        }
        
        // 开始下载
        _cachingItems[itemKey] = mediaItem;
        WCMediaDownloader *downloader = [[objc_getClass("WCMediaDownloader") alloc] initWithDataItem:dataItem mediaItem:mediaItem];
        
        [downloader startDownloadWithCompletionHandler:^(NSError *error) {
            @synchronized (self) {
                [_cachingItems removeObjectForKey:itemKey];
                
                if (error) {
                    hasError = YES;
                    NSLog(@"DDMediaCacheManager: 下载失败 %@", error);
                } else {
                    NSLog(@"DDMediaCacheManager: 下载成功 %@", mediaItem.mid);
                }
                
                pendingDownloads--;
                if (pendingDownloads <= 0) {
                    if (completion) completion(!hasError);
                }
            }
        }];
    }
}

@end

// 插件配置类
@interface DDTimelineForwardConfig : NSObject
@property (class, nonatomic, assign, getter=isTimelineForwardEnabled) BOOL timelineForwardEnabled;
@property (class, nonatomic, assign, getter=isAutoCacheEnabled) BOOL autoCacheEnabled;
+ (void)setupDefaults;
@end

@implementation DDTimelineForwardConfig

static NSString *const kTimelineForwardEnabledKey = @"DDTimelineForwardEnabled";
static NSString *const kAutoCacheEnabledKey = @"DDAutoCacheEnabled";

+ (BOOL)isTimelineForwardEnabled {
    return [[NSUserDefaults standardUserDefaults] boolForKey:kTimelineForwardEnabledKey];
}

+ (void)setTimelineForwardEnabled:(BOOL)enabled {
    [[NSUserDefaults standardUserDefaults] setBool:enabled forKey:kTimelineForwardEnabledKey];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

+ (BOOL)isAutoCacheEnabled {
    return [[NSUserDefaults standardUserDefaults] boolForKey:kAutoCacheEnabledKey];
}

+ (void)setAutoCacheEnabled:(BOOL)enabled {
    [[NSUserDefaults standardUserDefaults] setBool:enabled forKey:kAutoCacheEnabledKey];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

+ (void)setupDefaults {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    if (![defaults objectForKey:kTimelineForwardEnabledKey]) {
        [defaults setBool:YES forKey:kTimelineForwardEnabledKey];
    }
    if (![defaults objectForKey:kAutoCacheEnabledKey]) {
        [defaults setBool:YES forKey:kAutoCacheEnabledKey];
    }
    [defaults synchronize];
}

@end

// 设置界面控制器
@interface DDTimelineForwardSettingsController : UIViewController
@property (nonatomic, strong) UISwitch *forwardSwitch;
@property (nonatomic, strong) UISwitch *autoCacheSwitch;
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
    
    // 开关控件2: 自动缓存
    UIView *switchContainer2 = [[UIView alloc] init];
    
    UILabel *titleLabel2 = [[UILabel alloc] init];
    titleLabel2.text = @"自动缓存媒体";
    titleLabel2.font = [UIFont systemFontOfSize:17 weight:UIFontWeightSemibold];
    titleLabel2.translatesAutoresizingMaskIntoConstraints = NO;
    [switchContainer2 addSubview:titleLabel2];
    
    UILabel *subLabel2 = [[UILabel alloc] init];
    subLabel2.text = @"(转发前自动下载图片/视频)";
    subLabel2.font = [UIFont systemFontOfSize:12];
    subLabel2.textColor = [UIColor secondaryLabelColor];
    subLabel2.translatesAutoresizingMaskIntoConstraints = NO;
    [switchContainer2 addSubview:subLabel2];
    
    self.autoCacheSwitch = [[UISwitch alloc] init];
    [self.autoCacheSwitch setOn:[DDTimelineForwardConfig isAutoCacheEnabled]];
    [self.autoCacheSwitch addTarget:self action:@selector(autoCacheSwitchChanged:) forControlEvents:UIControlEventValueChanged];
    self.autoCacheSwitch.translatesAutoresizingMaskIntoConstraints = NO;
    [switchContainer2 addSubview:self.autoCacheSwitch];
    
    [NSLayoutConstraint activateConstraints:@[
        [titleLabel2.leadingAnchor constraintEqualToAnchor:switchContainer2.leadingAnchor],
        [titleLabel2.topAnchor constraintEqualToAnchor:switchContainer2.topAnchor],
        [subLabel2.leadingAnchor constraintEqualToAnchor:switchContainer2.leadingAnchor],
        [subLabel2.topAnchor constraintEqualToAnchor:titleLabel2.bottomAnchor constant:4],
        [self.autoCacheSwitch.trailingAnchor constraintEqualToAnchor:switchContainer2.trailingAnchor],
        [self.autoCacheSwitch.centerYAnchor constraintEqualToAnchor:switchContainer2.centerYAnchor]
    ]];
    
    [mainStack addArrangedSubview:switchContainer2];
    
    // 说明文字
    UILabel *descriptionLabel = [[UILabel alloc] init];
    descriptionLabel.text = @"启用后在朋友圈菜单中添加「转发」按钮，自动缓存媒体文件确保转发成功";
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

- (void)autoCacheSwitchChanged:(UISwitch *)sender {
    [DDTimelineForwardConfig setAutoCacheEnabled:sender.isOn];
}

@end

// Hook实现
%hook WCOperateFloatView

- (void)showWithItemData:(id)arg1 tipPoint:(struct CGPoint)arg2 {
    %orig(arg1, arg2);
    
    if ([DDTimelineForwardConfig isTimelineForwardEnabled] && self.m_item) {
        // 提前开始缓存媒体文件
        if ([DDTimelineForwardConfig isAutoCacheEnabled]) {
            [[DDMediaCacheManager sharedManager] cacheMediaForDataItem:self.m_item completion:nil];
        }
        
        // 避免重复添加按钮
        if (![self viewWithTag:10086]) {
            UIButton *forwardButton = [UIButton buttonWithType:UIButtonTypeCustom];
            forwardButton.tag = 10086;
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
}

%new
- (void)dd_forwardTimeline:(UIButton *)sender {
    if (!self.m_item) {
        return;
    }
    
    // 检查媒体是否已缓存
    BOOL allCached = [[DDMediaCacheManager sharedManager] isAllMediaCachedForDataItem:self.m_item];
    
    if (!allCached && [DDTimelineForwardConfig isAutoCacheEnabled]) {
        // 显示加载提示
        UIView *loadingView = [[UIView alloc] initWithFrame:self.window.bounds];
        loadingView.backgroundColor = [UIColor colorWithWhite:0 alpha:0.7];
        loadingView.tag = 10087;
        
        UIActivityIndicatorView *indicator = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhiteLarge];
        indicator.center = loadingView.center;
        [indicator startAnimating];
        [loadingView addSubview:indicator];
        
        UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(0, indicator.frame.origin.y + 60, loadingView.frame.size.width, 30)];
        label.text = @"正在缓存媒体文件...";
        label.textColor = [UIColor whiteColor];
        label.textAlignment = NSTextAlignmentCenter;
        [loadingView addSubview:label];
        
        [self.window addSubview:loadingView];
        
        // 开始缓存
        [[DDMediaCacheManager sharedManager] cacheMediaForDataItem:self.m_item completion:^(BOOL success) {
            [loadingView removeFromSuperview];
            
            if (success) {
                // 缓存成功，打开转发界面
                [self openForwardViewController];
            } else {
                // 缓存失败，显示提示
                UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"缓存失败" 
                    message:@"媒体文件下载失败，可能无法正常转发" 
                    preferredStyle:UIAlertControllerStyleAlert];
                [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
                [alert addAction:[UIAlertAction actionWithTitle:@"继续转发" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
                    [self openForwardViewController];
                }]];
                
                if (self.navigationController) {
                    [self.navigationController presentViewController:alert animated:YES completion:nil];
                }
            }
        }];
    } else {
        // 直接打开转发界面
        [self openForwardViewController];
    }
}

%new
- (void)openForwardViewController {
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
                                   version:@"1.1.0" 
                               controller:@"DDTimelineForwardSettingsController"];
        }
        
        NSLog(@"DD朋友圈转发插件已加载 v1.1.0");
    }
}