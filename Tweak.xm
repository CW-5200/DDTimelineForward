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
@property(retain, nonatomic) id contentObj;
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

@interface WCDownloadMgr : NSObject
- (void)forceDownloadMedia:(id)arg1 downloadType:(long long)arg2;
- (void)downloadMedia:(id)arg1 downloadType:(long long)arg2;
- (BOOL)isDownloadingSnsImageForUrl:(id)arg1;
@end

@interface WCFacade : NSObject
+ (instancetype)sharedInstance;
@property(readonly, nonatomic) WCDownloadMgr *downloadMgr;
@end

@interface WCMediaItem : NSObject
@property(retain, nonatomic) NSString *mid;
@property(retain, nonatomic) NSString *tid;
- (BOOL)hasData;
- (BOOL)hasPreview;
- (BOOL)isValid;
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

// 媒体下载管理器
@interface DDMediaDownloadManager : NSObject
+ (instancetype)sharedInstance;
- (NSArray *)getMediaItemsFromDataItem:(WCDataItem *)dataItem;
- (void)downloadMediaItems:(NSArray *)mediaItems progressHandler:(void(^)(float progress, NSUInteger completed, NSUInteger total))progressHandler completion:(void(^)(BOOL success, NSError *error))completion;
- (BOOL)isMediaItemDownloaded:(WCMediaItem *)mediaItem;
@end

@implementation DDMediaDownloadManager {
    NSMutableDictionary *_downloadObservers;
    NSMutableDictionary *_downloadProgress;
}

+ (instancetype)sharedInstance {
    static DDMediaDownloadManager *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[self alloc] init];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _downloadObservers = [NSMutableDictionary dictionary];
        _downloadProgress = [NSMutableDictionary dictionary];
    }
    return self;
}

- (NSArray *)getMediaItemsFromDataItem:(WCDataItem *)dataItem {
    NSMutableArray *mediaItems = [NSMutableArray array];
    
    // 使用运行时获取媒体列表
    @try {
        if (dataItem.contentObj) {
            // 方法1: 尝试通过contentObj获取媒体列表
            if ([dataItem.contentObj respondsToSelector:@selector(media)]) {
                NSArray *mediaList = [dataItem.contentObj performSelector:@selector(media)];
                if ([mediaList isKindOfClass:[NSArray class]]) {
                    [mediaItems addObjectsFromArray:mediaList];
                }
            }
            
            // 方法2: 尝试通过KVC获取
            if (mediaItems.count == 0) {
                @try {
                    id mediaList = [dataItem.contentObj valueForKey:@"media"];
                    if ([mediaList isKindOfClass:[NSArray class]]) {
                        [mediaItems addObjectsFromArray:mediaList];
                    }
                } @catch (NSException *exception) {
                    NSLog(@"KVC获取media失败: %@", exception);
                }
            }
        }
    } @catch (NSException *exception) {
        NSLog(@"获取媒体列表失败: %@", exception);
    }
    
    // 过滤无效的媒体项
    NSMutableArray *validMediaItems = [NSMutableArray array];
    for (id item in mediaItems) {
        if ([item isKindOfClass:objc_getClass("WCMediaItem")] && [item isValid]) {
            [validMediaItems addObject:item];
        }
    }
    
    return validMediaItems;
}

- (BOOL)isMediaItemDownloaded:(WCMediaItem *)mediaItem {
    if (!mediaItem) return NO;
    
    @try {
        // 检查媒体文件是否已下载
        if ([mediaItem respondsToSelector:@selector(hasData)]) {
            return [mediaItem hasData];
        }
        if ([mediaItem respondsToSelector:@selector(hasPreview)]) {
            return [mediaItem hasPreview];
        }
        
        // 检查文件是否存在
        if ([mediaItem respondsToSelector:@selector(pathForData)]) {
            NSString *path = [mediaItem pathForData];
            if (path && [[NSFileManager defaultManager] fileExistsAtPath:path]) {
                return YES;
            }
        }
        
        if ([mediaItem respondsToSelector:@selector(pathForPreview)]) {
            NSString *path = [mediaItem pathForPreview];
            if (path && [[NSFileManager defaultManager] fileExistsAtPath:path]) {
                return YES;
            }
        }
    } @catch (NSException *exception) {
        NSLog(@"检查媒体文件下载状态失败: %@", exception);
    }
    
    return NO;
}

- (void)downloadMediaItems:(NSArray *)mediaItems progressHandler:(void(^)(float progress, NSUInteger completed, NSUInteger total))progressHandler completion:(void(^)(BOOL success, NSError *error))completion {
    
    if (mediaItems.count == 0) {
        if (completion) {
            completion(YES, nil);
        }
        return;
    }
    
    __block NSUInteger totalCount = mediaItems.count;
    __block NSUInteger completedCount = 0;
    __block BOOL hasError = NO;
    __block NSError *lastError = nil;
    
    // 重置进度
    [_downloadProgress removeAllObjects];
    for (WCMediaItem *mediaItem in mediaItems) {
        NSString *itemKey = [self keyForMediaItem:mediaItem];
        _downloadProgress[itemKey] = @0.0f;
    }
    
    // 下载完成检查块
    void (^checkCompletion)(void) = ^{
        if (completedCount + (hasError ? 1 : 0) >= totalCount) {
            // 所有项目完成或出错
            BOOL success = !hasError && (completedCount == totalCount);
            if (completion) {
                completion(success, lastError);
            }
            
            // 清理观察者
            for (NSString *key in [_downloadObservers allKeys]) {
                [[NSNotificationCenter defaultCenter] removeObserver:_downloadObservers[key]];
            }
            [_downloadObservers removeAllObjects];
            [_downloadProgress removeAllObjects];
        }
    };
    
    // 进度更新块
    void (^updateProgress)(void) = ^{
        float totalProgress = 0.0f;
        for (NSNumber *progress in [_downloadProgress allValues]) {
            totalProgress += [progress floatValue];
        }
        totalProgress /= totalCount;
        
        if (progressHandler) {
            progressHandler(totalProgress, completedCount, totalCount);
        }
    };
    
    for (WCMediaItem *mediaItem in mediaItems) {
        // 检查是否已下载
        if ([self isMediaItemDownloaded:mediaItem]) {
            completedCount++;
            _downloadProgress[[self keyForMediaItem:mediaItem]] = @1.0f;
            updateProgress();
            checkCompletion();
            continue;
        }
        
        // 开始下载
        NSString *itemKey = [self keyForMediaItem:mediaItem];
        
        // 创建下载观察者
        id observer = [[NSNotificationCenter defaultCenter] addObserverForName:@"DDMediaDownloadProgressNotification" 
                                                                        object:mediaItem 
                                                                         queue:[NSOperationQueue mainQueue] 
                                                                    usingBlock:^(NSNotification *note) {
            float progress = [note.userInfo[@"progress"] floatValue];
            BOOL finished = [note.userInfo[@"finished"] boolValue];
            BOOL failed = [note.userInfo[@"failed"] boolValue];
            
            if (failed) {
                hasError = YES;
                lastError = note.userInfo[@"error"];
                completedCount++;
            } else if (finished) {
                completedCount++;
                _downloadProgress[itemKey] = @1.0f;
            } else {
                _downloadProgress[itemKey] = @(progress);
            }
            
            updateProgress();
            checkCompletion();
        }];
        
        _downloadObservers[itemKey] = observer;
        
        // 使用微信下载管理器开始下载
        WCDownloadMgr *downloadMgr = [[objc_getClass("WCFacade") sharedInstance] downloadMgr];
        if (downloadMgr) {
            [downloadMgr forceDownloadMedia:mediaItem downloadType:0];
        }
    }
}

- (NSString *)keyForMediaItem:(WCMediaItem *)mediaItem {
    if (mediaItem.mid) {
        return [NSString stringWithFormat:@"media_%@", mediaItem.mid];
    }
    if (mediaItem.tid) {
        return [NSString stringWithFormat:@"media_%@", mediaItem.tid];
    }
    return [NSString stringWithFormat:@"media_%p", mediaItem];
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
    if ( {
        [defaults setBool:YES forKey:kTimelineForwardEnabledKey];
        [defaults synchronize];
    }
}

@end

// 进度显示窗口
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
        [self setupBlurBackground];
        [self setupUI];
    }
    return self;
}

- (void)setupBlurBackground {
    UIBlurEffect *blurEffect;
    if (@available(iOS 13.0, *)) {
        blurEffect = [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemUltraThinMaterial];
    } else {
        blurEffect = [UIBlurEffect effectWithStyle:UIBlurEffectStyleLight];
    }
    
    _blurView = [[UIVisualEffectView alloc] initWithEffect:blurEffect];
    _blurView.frame = self.bounds;
    _blurView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _blurView.alpha = 0.95;
    
    UIView *overlayView = [[UIView alloc] initWithFrame:_blurView.bounds];
    overlayView.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.2];
    overlayView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [_blurView.contentView addSubview:overlayView];
    
    [self addSubview:_blurView];
}

- (void)setupUI {
    _titleLabel = [[UILabel alloc] init];
    _titleLabel.text = @"正在转发朋友圈";
    _titleLabel.font = [UIFont systemFontOfSize:18 weight:UIFontWeightSemibold];
    _titleLabel.textColor = [UIColor labelColor];
    _titleLabel.textAlignment = NSTextAlignmentCenter;
    _titleLabel.numberOfLines = 0;
    _titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    
    _activityIndicator = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleLarge];
    _activityIndicator.color = [UIColor labelColor];
    _activityIndicator.translatesAutoresizingMaskIntoConstraints = NO;
    [_activityIndicator startAnimating];
    
    _percentLabel = [[UILabel alloc] init];
    _percentLabel.text = @"正在下载0%";
    _percentLabel.font = [UIFont monospacedDigitSystemFontOfSize:18 weight:UIFontWeightMedium];
    _percentLabel.textColor = [UIColor labelColor];
    _percentLabel.textAlignment = NSTextAlignmentCenter;
    _percentLabel.numberOfLines = 0;
    _percentLabel.adjustsFontSizeToFitWidth = YES;
    _percentLabel.minimumScaleFactor = 0.8;
    _percentLabel.translatesAutoresizingMaskIntoConstraints = NO;
    
    _cancelButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [_cancelButton setTitle:@"取消" forState:UIControlStateNormal];
    [_cancelButton setTitleColor:[UIColor systemRedColor] forState:UIControlStateNormal];
    _cancelButton.titleLabel.font = [UIFont systemFontOfSize:18 weight:UIFontWeightRegular];
    _cancelButton.translatesAutoresizingMaskIntoConstraints = NO;
    [_cancelButton addTarget:self action:@selector(cancelButtonPressed) forControlEvents:UIControlEventTouchUpInside];
    
    UIView *contentView = [[UIView alloc] init];
    if (@available(iOS 13.0, *)) {
        contentView.backgroundColor = [[UIColor secondarySystemBackgroundColor] colorWithAlphaComponent:0.85];
    } else {
        contentView.backgroundColor = [[UIColor colorWithRed:0.95 green:0.95 blue:0.97 alpha:1.0] colorWithAlphaComponent:0.85];
    }
    contentView.layer.cornerRadius = 16.0;
    contentView.layer.borderWidth = 0.5;
    contentView.layer.borderColor = [UIColor separatorColor].CGColor;
    contentView.translatesAutoresizingMaskIntoConstraints = NO;
    
    [contentView addSubview:_titleLabel];
    [contentView addSubview:_activityIndicator];
    [contentView addSubview:_percentLabel];
    [contentView addSubview:_cancelButton];
    
    [self addSubview:contentView];
    
    [NSLayoutConstraint activateConstraints:@[
        [contentView.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
        [contentView.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
        [contentView.widthAnchor constraintEqualToConstant:280],
        [contentView.heightAnchor constraintEqualToConstant:260],
        
        [_titleLabel.topAnchor constraintEqualToAnchor:contentView.topAnchor constant:25],
        [_titleLabel.leadingAnchor constraintEqualToAnchor:contentView.leadingAnchor constant:20],
        [_titleLabel.trailingAnchor constraintEqualToAnchor:contentView.trailingAnchor constant:-20],
        [_titleLabel.heightAnchor constraintGreaterThanOrEqualToConstant:25],
        
        [_activityIndicator.topAnchor constraintEqualToAnchor:_titleLabel.bottomAnchor constant:20],
        [_activityIndicator.centerXAnchor constraintEqualToAnchor:contentView.centerXAnchor],
        [_activityIndicator.widthAnchor constraintEqualToConstant:50],
        [_activityIndicator.heightAnchor constraintEqualToConstant:50],
        
        [_percentLabel.topAnchor constraintEqualToAnchor:_activityIndicator.bottomAnchor constant:20],
        [_percentLabel.leadingAnchor constraintEqualToAnchor:contentView.leadingAnchor constant:20],
        [_percentLabel.trailingAnchor constraintEqualToAnchor:contentView.trailingAnchor constant:-20],
        [_percentLabel.heightAnchor constraintGreaterThanOrEqualToConstant:30],
        
        [_cancelButton.topAnchor constraintEqualToAnchor:_percentLabel.bottomAnchor constant:50],
        [_cancelButton.centerXAnchor constraintEqualToAnchor:contentView.centerXAnchor],
        [_cancelButton.bottomAnchor constraintLessThanOrEqualToAnchor:contentView.bottomAnchor constant:-20]
    ]];
}

- (void)updateProgress:(float)progress {
    dispatch_async(dispatch_get_main_queue(), ^{
        int percent = (int)(progress * 100);
        _percentLabel.text = [NSString stringWithFormat:@"正在下载%d%%", percent];
        
        NSString *cacheKey = [NSString stringWithFormat:@"forward_progress_%@", _username];
        [[DDProgressCacheManager sharedInstance] saveProgress:progress forKey:cacheKey];
        
        if (progress >= 1.0) {
            _percentLabel.text = @"下载完成!";
            _percentLabel.textColor = [UIColor systemGreenColor];
        } else {
            _percentLabel.textColor = [UIColor labelColor];
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

// Hook WCDownloadMgr 来监控真实下载进度
%hook WCDownloadMgr

- (void)onDownloadFinish:(id)arg1 downloadType:(long long)arg2 {
    %orig(arg1, arg2);
    
    // 发送下载完成通知
    [[NSNotificationCenter defaultCenter] postNotificationName:@"DDMediaDownloadProgressNotification" 
                                                        object:arg1 
                                                      userInfo:@{@"progress": @1.0, @"finished": @YES}];
}

- (void)onDownloadFail:(id)arg1 downloadType:(long long)arg2 {
    %orig(arg1, arg2);
    
    // 发送下载失败通知
    NSError *error = [NSError errorWithDomain:@"DDMediaDownload" code:-1 userInfo:@{NSLocalizedDescriptionKey: @"下载失败"}];
    [[NSNotificationCenter defaultCenter] postNotificationName:@"DDMediaDownloadProgressNotification" 
                                                        object:arg1 
                                                      userInfo:@{@"progress": @0.0, @"failed": @YES, @"error": error}];
}

- (void)onDownloadMediaProcessChange:(id)arg1 downloadType:(long long)arg2 current:(int)arg3 total:(int)arg4 {
    %orig(arg1, arg2, arg3, arg4);
    
    if (total > 0) {
        float progress = (float)current / (float)total;
        [[NSNotificationCenter defaultCenter] postNotificationName:@"DDMediaDownloadProgressNotification" 
                                                            object:arg1 
                                                          userInfo:@{@"progress": @(progress), @"finished": @NO}];
    }
}

%end

// Hook WCOperateFloatView 实现真实的转发逻辑
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
    __weak typeof(self) weakSelf = self;
    NSString *username = self.m_item.username ?: @"未知用户";
    NSString *cacheKey = [NSString stringWithFormat:@"forward_progress_%@", username];
    float savedProgress = [[DDProgressCacheManager sharedInstance] getProgressForKey:cacheKey];
    
    // 创建进度窗口
    CGRect screenBounds = [UIScreen mainScreen].bounds;
    DDProgressWindow *progressWindow = [[DDProgressWindow alloc] initWithFrame:screenBounds username:username];
    [progressWindow updateProgress:savedProgress];
    [progressWindow show];
    
    // 获取需要下载的媒体文件
    NSArray *mediaItems = [[DDMediaDownloadManager sharedInstance] getMediaItemsFromDataItem:self.m_item];
    
    if (mediaItems.count == 0) {
        // 如果没有媒体文件，直接完成
        [progressWindow updateProgress:1.0];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [progressWindow hide];
            [[DDProgressCacheManager sharedInstance] clearProgressForKey:cacheKey];
            [weakSelf dd_navigateToForwardViewController];
        });
        return;
    }
    
    // 实际下载媒体文件
    [[DDMediaDownloadManager sharedInstance] downloadMediaItems:mediaItems progressHandler:^(float progress, NSUInteger completed, NSUInteger total) {
        [progressWindow updateProgress:progress];
        
        // 保存进度到缓存
        [[DDProgressCacheManager sharedInstance] saveProgress:progress forKey:cacheKey];
        
    } completion:^(BOOL success, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [progressWindow hide];
            [[DDProgressCacheManager sharedInstance] clearProgressForKey:cacheKey];
            
            if (success) {
                [weakSelf dd_navigateToForwardViewController];
            } else {
                [weakSelf dd_showDownloadErrorAlert:error];
            }
        });
    }];
}

%new
- (void)dd_navigateToForwardViewController {
    WCForwardViewController *forwardVC = [[objc_getClass("WCForwardViewController") alloc] initWithDataItem:self.m_item];
    if (self.navigationController) {
        [self.navigationController pushViewController:forwardVC animated:YES];
    }
}

%new
- (void)dd_showDownloadErrorAlert:(NSError *)error {
    NSString *errorMessage = error.localizedDescription ?: @"媒体文件下载失败，请检查网络后重试";
    
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"下载失败" 
                                                                   message:errorMessage
                                                            preferredStyle:UIAlertControllerStyleAlert];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"重试" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        [self dd_forwardTimeline:nil];
    }]];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    
    UIViewController *topVC = [self dd_getTopViewController];
    [topVC presentViewController:alert animated:YES completion:nil];
}

%new
- (UIViewController *)dd_getTopViewController {
    UIWindow *window = [[UIApplication sharedApplication] keyWindow];
    UIViewController *rootVC = window.rootViewController;
    while (rootVC.presentedViewController) {
        rootVC = rootVC.presentedViewController;
    }
    return rootVC;
}

%end

// 插件初始化
%ctor {
    @autoreleasepool {
        [DDProgressCacheManager sharedInstance];
        [DDMediaDownloadManager sharedInstance];
        [DDTimelineForwardConfig setupDefaults];
        
        if (NSClassFromString(@"WCPluginsMgr")) {
            [[objc_getClass("WCPluginsMgr") sharedInstance] 
                registerControllerWithTitle:@"DD朋友圈转发" 
                                   version:@"1.4.1" 
                               controller:@"DDTimelineForwardSettingsController"];
        }
        
        NSLog(@"DD朋友圈转发插件已加载 v1.4.1 - 真实下载版");
    }
}
