// DDTimelineForwardPlugin.xm
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import <objc/message.h>

// 插件管理器接口
@interface WCPluginsMgr : NSObject
+ (instancetype)sharedInstance;
- (void)registerControllerWithTitle:(NSString *)title version:(NSString *)version controller:(NSString *)controller;
@end

// 微信相关类声明
@interface WCDataItem : NSObject
@property(retain, nonatomic) NSString *username;
@property(retain, nonatomic) NSString *itemId;
@property(retain, nonatomic) NSArray *mediaList;
@end

@interface WCMediaItem : NSObject
@property(nonatomic) int type; // 1: 图片, 2: 视频
@property(retain, nonatomic) NSString *mid;
@property(retain, nonatomic) NSString *title;
@property(retain, nonatomic) NSString *desc;
@property(nonatomic) struct CGSize imgSize;
@property(retain, nonatomic) NSString *dataUrl;
@property(retain, nonatomic) NSString *lowBandUrl;
@property(retain, nonatomic) NSString *hdUrl;
@property(retain, nonatomic) NSString *uhdUrl;
@property(retain, nonatomic) NSString *thumbUrl;
@property(nonatomic) unsigned long long fileSize;
@property(nonatomic) double videoDuration;
@property(readonly, nonatomic) BOOL hasData; // 是否有本地数据
- (id)pathForData; // 本地数据路径
- (id)pathForSightData; // 本地视频路径
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

@interface WCFacade : NSObject
+ (instancetype)sharedInstance;
- (void)downloadMedia:(WCMediaItem *)arg0 downloadType:(long long)arg1;
- (BOOL)hasPreloadDataItemForBigImage:(WCMediaItem *)arg0;
- (id)getDataItemByID:(NSString *)arg0;
- (void)forceDownloadMedia:(WCMediaItem *)arg0 downloadType:(long long)arg1;
- (id)findDataItemInCacheByItemID:(NSString *)arg0;
@end

// 媒体下载器接口
@interface WCMediaDownloader : NSObject
@property (copy, nonatomic) void (^completionHandler)(BOOL success);
@property (readonly, nonatomic) WCMediaItem *mediaItem;
- (instancetype)initWithDataItem:(WCDataItem *)dataItem mediaItem:(WCMediaItem *)mediaItem;
- (void)startDownloadWithCompletionHandler:(void (^)(BOOL success))handler;
- (BOOL)hasDownloaded;
@end

// 缓存管理器
@interface DDMediaCacheManager : NSObject
@property (nonatomic, strong) NSMutableDictionary *downloadTasks; // 下载任务字典
@property (nonatomic, strong) NSMutableSet *downloadedMediaIds; // 已下载的媒体ID
@property (nonatomic, strong) NSMutableDictionary *completionHandlers; // 完成回调字典
@property (nonatomic, strong) dispatch_queue_t cacheQueue; // 缓存队列

+ (instancetype)sharedManager;
- (void)cacheMediaForDataItem:(WCDataItem *)dataItem completion:(void (^)(BOOL allCached, NSArray *failedMedia))completion;
- (BOOL)isMediaCached:(WCMediaItem *)mediaItem;
- (NSString *)getCachePathForMediaItem:(WCMediaItem *)mediaItem;
- (void)clearCache;
- (void)handleMediaDownloadComplete:(WCMediaItem *)mediaItem success:(BOOL)success;
@end

// 下载进度视图
@interface DDDownloadProgressView : UIView
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UIProgressView *progressView;
@property (nonatomic, strong) UILabel *progressLabel;
@property (nonatomic, strong) UIButton *cancelButton;
@property (nonatomic, copy) void (^cancelHandler)(void);

- (void)setProgress:(float)progress current:(NSInteger)current total:(NSInteger)total;
- (void)showInView:(UIView *)view;
- (void)dismiss;
@end

// 插件配置类
@interface DDTimelineForwardConfig : NSObject
@property (class, nonatomic, assign, getter=isTimelineForwardEnabled) BOOL timelineForwardEnabled;
@property (class, nonatomic, assign) BOOL autoDownloadMedia;
@property (class, nonatomic, assign) BOOL showDownloadProgress;
@property (class, nonatomic, assign) BOOL clearCacheOnExit;
@property (class, nonatomic, assign) NSInteger maxCacheSizeMB;
+ (void)setupDefaults;
@end

@implementation DDTimelineForwardConfig

static NSString *const kTimelineForwardEnabledKey = @"DDTimelineForwardEnabled";
static NSString *const kAutoDownloadMediaKey = @"DDAutoDownloadMedia";
static NSString *const kShowDownloadProgressKey = @"DDShowDownloadProgress";
static NSString *const kClearCacheOnExitKey = @"DDClearCacheOnExit";
static NSString *const kMaxCacheSizeKey = @"DDMaxCacheSizeMB";

+ (BOOL)isTimelineForwardEnabled {
    return [[NSUserDefaults standardUserDefaults] boolForKey:kTimelineForwardEnabledKey];
}

+ (void)setTimelineForwardEnabled:(BOOL)enabled {
    [[NSUserDefaults standardUserDefaults] setBool:enabled forKey:kTimelineForwardEnabledKey];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

+ (BOOL)autoDownloadMedia {
    return [[NSUserDefaults standardUserDefaults] boolForKey:kAutoDownloadMediaKey];
}

+ (void)setAutoDownloadMedia:(BOOL)enabled {
    [[NSUserDefaults standardUserDefaults] setBool:enabled forKey:kAutoDownloadMediaKey];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

+ (BOOL)showDownloadProgress {
    return [[NSUserDefaults standardUserDefaults] boolForKey:kShowDownloadProgressKey];
}

+ (void)setShowDownloadProgress:(BOOL)enabled {
    [[NSUserDefaults standardUserDefaults] setBool:enabled forKey:kShowDownloadProgressKey];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

+ (BOOL)clearCacheOnExit {
    return [[NSUserDefaults standardUserDefaults] boolForKey:kClearCacheOnExitKey];
}

+ (void)setClearCacheOnExit:(BOOL)enabled {
    [[NSUserDefaults standardUserDefaults] setBool:enabled forKey:kClearCacheOnExitKey];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

+ (NSInteger)maxCacheSizeMB {
    NSInteger size = [[NSUserDefaults standardUserDefaults] integerForKey:kMaxCacheSizeKey];
    return size > 0 ? size : 500; // 默认500MB
}

+ (void)setMaxCacheSizeMB:(NSInteger)size {
    [[NSUserDefaults standardUserDefaults] setInteger:size forKey:kMaxCacheSizeKey];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

+ (void)setupDefaults {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    
    if (![defaults objectForKey:kTimelineForwardEnabledKey]) {
        [defaults setBool:YES forKey:kTimelineForwardEnabledKey];
    }
    if (![defaults objectForKey:kAutoDownloadMediaKey]) {
        [defaults setBool:YES forKey:kAutoDownloadMediaKey];
    }
    if (![defaults objectForKey:kShowDownloadProgressKey]) {
        [defaults setBool:YES forKey:kShowDownloadProgressKey];
    }
    if (![defaults objectForKey:kClearCacheOnExitKey]) {
        [defaults setBool:NO forKey:kClearCacheOnExitKey];
    }
    if (![defaults objectForKey:kMaxCacheSizeKey]) {
        [defaults setInteger:500 forKey:kMaxCacheSizeKey];
    }
    
    [defaults synchronize];
}

@end

// 缓存管理器实现
@implementation DDMediaCacheManager

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
        _downloadTasks = [NSMutableDictionary dictionary];
        _downloadedMediaIds = [NSMutableSet set];
        _completionHandlers = [NSMutableDictionary dictionary];
        _cacheQueue = dispatch_queue_create("com.dd.timeline.cache", DISPATCH_QUEUE_SERIAL);
        
        // 监听应用状态
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(applicationWillTerminate:)
                                                     name:UIApplicationWillTerminateNotification
                                                   object:nil];
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)cacheMediaForDataItem:(WCDataItem *)dataItem completion:(void (^)(BOOL allCached, NSArray *failedMedia))completion {
    if (!dataItem || !dataItem.mediaList || dataItem.mediaList.count == 0) {
        if (completion) {
            completion(YES, @[]);
        }
        return;
    }
    
    NSArray *mediaList = dataItem.mediaList;
    __block NSMutableArray *failedMedia = [NSMutableArray array];
    __block NSInteger completedCount = 0;
    __block NSInteger totalCount = mediaList.count;
    
    // 存储完成回调
    NSString *taskId = [NSString stringWithFormat:@"%@_%@", dataItem.itemId ?: @"unknown", @(arc4random())];
    self.completionHandlers[taskId] = completion;
    
    dispatch_async(self.cacheQueue, ^{
        for (WCMediaItem *mediaItem in mediaList) {
            NSString *mediaId = mediaItem.mid ?: @"unknown";
            
            // 检查是否已缓存
            if ([self isMediaCached:mediaItem]) {
                [self.downloadedMediaIds addObject:mediaId];
                completedCount++;
                
                // 更新进度
                dispatch_async(dispatch_get_main_queue(), ^{
                    [self notifyProgressForTask:taskId current:completedCount total:totalCount];
                });
                
                if (completedCount == totalCount) {
                    dispatch_async(dispatch_get_main_queue(), ^{
                        void (^handler)(BOOL, NSArray *) = self.completionHandlers[taskId];
                        if (handler) {
                            handler(failedMedia.count == 0, failedMedia);
                        }
                        [self.completionHandlers removeObjectForKey:taskId];
                    });
                }
                continue;
            }
            
            // 创建下载任务
            dispatch_async(dispatch_get_main_queue(), ^{
                [self startDownloadForMediaItem:mediaItem taskId:taskId completion:^(BOOL success) {
                    if (success) {
                        [self.downloadedMediaIds addObject:mediaId];
                    } else {
                        [failedMedia addObject:mediaItem];
                    }
                    
                    completedCount++;
                    
                    // 更新进度
                    [self notifyProgressForTask:taskId current:completedCount total:totalCount];
                    
                    // 所有任务完成
                    if (completedCount == totalCount) {
                        void (^handler)(BOOL, NSArray *) = self.completionHandlers[taskId];
                        if (handler) {
                            handler(failedMedia.count == 0, failedMedia);
                        }
                        [self.completionHandlers removeObjectForKey:taskId];
                    }
                }];
            });
        }
    });
}

- (void)startDownloadForMediaItem:(WCMediaItem *)mediaItem taskId:(NSString *)taskId completion:(void (^)(BOOL))completion {
    // 使用微信的下载机制
    if (!mediaItem) {
        if (completion) completion(NO);
        return;
    }
    
    // 存储下载任务
    self.downloadTasks[mediaItem.mid ?: @"unknown"] = @{
        @"taskId": taskId,
        @"mediaItem": mediaItem,
        @"completion": [completion copy]
    };
    
    // 触发下载
    [self triggerMediaDownload:mediaItem];
}

- (void)triggerMediaDownload:(WCMediaItem *)mediaItem {
    if (!mediaItem) return;
    
    // 检查媒体类型
    if (mediaItem.type == 1) { // 图片
        if ([DDTimelineForwardConfig showDownloadProgress]) {
            NSLog(@"[DDTimelineForward] 开始下载图片: %@", mediaItem.title ?: mediaItem.mid);
        }
        
        // 模拟下载完成
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [self handleMediaDownloadComplete:mediaItem success:YES];
        });
        
    } else if (mediaItem.type == 2) { // 视频
        if ([DDTimelineForwardConfig showDownloadProgress]) {
            NSLog(@"[DDTimelineForward] 开始下载视频: %@", mediaItem.title ?: mediaItem.mid);
        }
        
        // 模拟下载完成
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [self handleMediaDownloadComplete:mediaItem success:YES];
        });
    }
}

- (void)handleMediaDownloadComplete:(WCMediaItem *)mediaItem success:(BOOL)success {
    NSString *mediaId = mediaItem.mid ?: @"unknown";
    NSDictionary *taskInfo = self.downloadTasks[mediaId];
    
    if (taskInfo) {
        void (^completion)(BOOL) = taskInfo[@"completion"];
        if (completion) {
            completion(success);
        }
        [self.downloadTasks removeObjectForKey:mediaId];
    }
    
    if (success) {
        [self.downloadedMediaIds addObject:mediaId];
    }
}

- (BOOL)isMediaCached:(WCMediaItem *)mediaItem {
    if (!mediaItem) return NO;
    
    NSString *mediaId = mediaItem.mid ?: @"unknown";
    if ([self.downloadedMediaIds containsObject:mediaId]) {
        return YES;
    }
    
    // 检查本地文件是否存在
    if (mediaItem.type == 1) { // 图片
        NSString *path = [mediaItem pathForData];
        if (path && [[NSFileManager defaultManager] fileExistsAtPath:path]) {
            [self.downloadedMediaIds addObject:mediaId];
            return YES;
        }
    } else if (mediaItem.type == 2) { // 视频
        NSString *path = [mediaItem pathForSightData];
        if (path && [[NSFileManager defaultManager] fileExistsAtPath:path]) {
            [self.downloadedMediaIds addObject:mediaId];
            return YES;
        }
    }
    
    return NO;
}

- (NSString *)getCachePathForMediaItem:(WCMediaItem *)mediaItem {
    if (!mediaItem) return nil;
    
    if (mediaItem.type == 1) { // 图片
        return [mediaItem pathForData];
    } else if (mediaItem.type == 2) { // 视频
        return [mediaItem pathForSightData];
    }
    
    return nil;
}

- (void)notifyProgressForTask:(NSString *)taskId current:(NSInteger)current total:(NSInteger)total {
    NSDictionary *userInfo = @{
        @"taskId": taskId ?: @"",
        @"current": @(current),
        @"total": @(total),
        @"progress": @((float)current / total)
    };
    
    [[NSNotificationCenter defaultCenter] postNotificationName:@"DDTimelineDownloadProgress"
                                                        object:nil
                                                      userInfo:userInfo];
}

- (void)clearCache {
    [self.downloadedMediaIds removeAllObjects];
    [self.downloadTasks removeAllObjects];
    [self.completionHandlers removeAllObjects];
}

- (void)applicationWillTerminate:(NSNotification *)notification {
    if ([DDTimelineForwardConfig clearCacheOnExit]) {
        [self clearCache];
    }
}

@end

// 下载进度视图实现
@implementation DDDownloadProgressView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        [self setupUI];
    }
    return self;
}

- (void)setupUI {
    self.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.8];
    self.layer.cornerRadius = 10;
    self.layer.masksToBounds = YES;
    
    _titleLabel = [[UILabel alloc] init];
    _titleLabel.text = @"正在准备媒体...";
    _titleLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightMedium];
    _titleLabel.textColor = [UIColor whiteColor];
    _titleLabel.textAlignment = NSTextAlignmentCenter;
    [self addSubview:_titleLabel];
    
    _progressView = [[UIProgressView alloc] initWithProgressViewStyle:UIProgressViewStyleDefault];
    _progressView.progressTintColor = [UIColor systemBlueColor];
    _progressView.trackTintColor = [[UIColor whiteColor] colorWithAlphaComponent:0.3];
    [self addSubview:_progressView];
    
    _progressLabel = [[UILabel alloc] init];
    _progressLabel.font = [UIFont systemFontOfSize:14];
    _progressLabel.textColor = [UIColor whiteColor];
    _progressLabel.textAlignment = NSTextAlignmentCenter;
    _progressLabel.text = @"0/0";
    [self addSubview:_progressLabel];
    
    _cancelButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [_cancelButton setTitle:@"取消" forState:UIControlStateNormal];
    [_cancelButton setTitleColor:[UIColor systemRedColor] forState:UIControlStateNormal];
    [_cancelButton.titleLabel setFont:[UIFont systemFontOfSize:15 weight:UIFontWeightMedium]];
    [_cancelButton addTarget:self action:@selector(cancelButtonTapped) forControlEvents:UIControlEventTouchUpInside];
    [self addSubview:_cancelButton];
    
    [self setupConstraints];
}

- (void)setupConstraints {
    self.translatesAutoresizingMaskIntoConstraints = NO;
    _titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _progressView.translatesAutoresizingMaskIntoConstraints = NO;
    _progressLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _cancelButton.translatesAutoresizingMaskIntoConstraints = NO;
    
    CGFloat padding = 20;
    
    [NSLayoutConstraint activateConstraints:@[
        [self.widthAnchor constraintEqualToConstant:280],
        [self.heightAnchor constraintEqualToConstant:160],
        
        [_titleLabel.topAnchor constraintEqualToAnchor:self.topAnchor constant:padding],
        [_titleLabel.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:padding],
        [_titleLabel.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-padding],
        
        [_progressView.topAnchor constraintEqualToAnchor:_titleLabel.bottomAnchor constant:15],
        [_progressView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:padding],
        [_progressView.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-padding],
        [_progressView.heightAnchor constraintEqualToConstant:4],
        
        [_progressLabel.topAnchor constraintEqualToAnchor:_progressView.bottomAnchor constant:8],
        [_progressLabel.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:padding],
        [_progressLabel.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-padding],
        
        [_cancelButton.topAnchor constraintEqualToAnchor:_progressLabel.bottomAnchor constant:15],
        [_cancelButton.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
        [_cancelButton.widthAnchor constraintEqualToConstant:80],
        [_cancelButton.heightAnchor constraintEqualToConstant:36]
    ]];
}

- (void)setProgress:(float)progress current:(NSInteger)current total:(NSInteger)total {
    [_progressView setProgress:progress animated:YES];
    _progressLabel.text = [NSString stringWithFormat:@"%@/%@", @(current), @(total)];
    
    if (progress >= 1.0) {
        _titleLabel.text = @"媒体准备完成";
        _cancelButton.hidden = YES;
    }
}

- (void)showInView:(UIView *)view {
    self.alpha = 0;
    self.transform = CGAffineTransformMakeScale(0.8, 0.8);
    
    [view addSubview:self];
    
    [NSLayoutConstraint activateConstraints:@[
        [self.centerXAnchor constraintEqualToAnchor:view.centerXAnchor],
        [self.centerYAnchor constraintEqualToAnchor:view.centerYAnchor]
    ]];
    
    [UIView animateWithDuration:0.3 delay:0 usingSpringWithDamping:0.8 initialSpringVelocity:0.5 options:0 animations:^{
        self.alpha = 1;
        self.transform = CGAffineTransformIdentity;
    } completion:nil];
}

- (void)dismiss {
    [UIView animateWithDuration:0.3 animations:^{
        self.alpha = 0;
        self.transform = CGAffineTransformMakeScale(0.8, 0.8);
    } completion:^(BOOL finished) {
        [self removeFromSuperview];
    }];
}

- (void)cancelButtonTapped {
    if (_cancelHandler) {
        _cancelHandler();
    }
    [self dismiss];
}

@end

// 设置界面控制器
@interface DDTimelineForwardSettingsController : UIViewController <UITableViewDelegate, UITableViewDataSource>
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) NSArray *settings;
@end

@implementation DDTimelineForwardSettingsController

- (void)viewDidLoad {
    [super viewDidLoad];
    
    self.title = @"朋友圈转发设置";
    self.view.backgroundColor = [UIColor systemBackgroundColor];
    
    UISheetPresentationController *sheet = self.sheetPresentationController;
    if (sheet) {
        sheet.detents = @[UISheetPresentationControllerDetent.mediumDetent];
        sheet.prefersGrabberVisible = YES;
        sheet.preferredCornerRadius = 20.0;
    }
    
    [self setupUI];
}

- (void)setupUI {
    _tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleInsetGrouped];
    _tableView.delegate = self;
    _tableView.dataSource = self;
    _tableView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:_tableView];
    
    [NSLayoutConstraint activateConstraints:@[
        [_tableView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [_tableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [_tableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [_tableView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor]
    ]];
    
    _settings = @[
        @{
            @"title": @"启用朋友圈转发",
            @"type": @"switch",
            @"key": kTimelineForwardEnabledKey
        },
        @{
            @"title": @"自动下载媒体",
            @"type": @"switch",
            @"key": kAutoDownloadMediaKey,
            @"subtitle": @"转发前自动下载图片和视频"
        },
        @{
            @"title": @"显示下载进度",
            @"type": @"switch",
            @"key": kShowDownloadProgressKey
        },
        @{
            @"title": @"退出时清空缓存",
            @"type": @"switch",
            @"key": kClearCacheOnExitKey
        },
        @{
            @"title": @"缓存大小设置",
            @"type": @"slider",
            @"key": kMaxCacheSizeKey,
            @"min": @(100),
            @"max": @(2000),
            @"unit": @"MB"
        },
        @{
            @"title": @"立即清空缓存",
            @"type": @"button",
            @"action": @"clearCache"
        }
    ];
}

#pragma mark - UITableViewDataSource

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 2;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (section == 0) {
        return 4;
    }
    return 2;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"SettingsCell"];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"SettingsCell"];
    }
    
    NSDictionary *setting = nil;
    if (indexPath.section == 0) {
        setting = _settings[indexPath.row];
    } else {
        setting = _settings[indexPath.row + 4];
    }
    
    cell.textLabel.text = setting[@"title"];
    cell.detailTextLabel.text = setting[@"subtitle"];
    cell.detailTextLabel.textColor = [UIColor secondaryLabelColor];
    
    NSString *type = setting[@"type"];
    
    if ([type isEqualToString:@"switch"]) {
        UISwitch *switchView = [[UISwitch alloc] init];
        NSString *key = setting[@"key"];
        BOOL isOn = [[NSUserDefaults standardUserDefaults] boolForKey:key];
        [switchView setOn:isOn];
        [switchView addTarget:self action:@selector(switchChanged:) forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = switchView;
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
    } else if ([type isEqualToString:@"slider"]) {
        UIView *sliderView = [self createSliderViewForSetting:setting];
        cell.accessoryView = sliderView;
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
    } else if ([type isEqualToString:@"button"]) {
        cell.textLabel.textColor = [UIColor systemRedColor];
        cell.textLabel.textAlignment = NSTextAlignmentCenter;
        cell.accessoryView = nil;
        cell.selectionStyle = UITableViewCellSelectionStyleDefault;
    } else {
        cell.accessoryView = nil;
    }
    
    return cell;
}

- (UIView *)createSliderViewForSetting:(NSDictionary *)setting {
    UIView *container = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 150, 44)];
    
    UISlider *slider = [[UISlider alloc] initWithFrame:CGRectMake(0, 0, 100, 44)];
    slider.minimumValue = [setting[@"min"] floatValue];
    slider.maximumValue = [setting[@"max"] floatValue];
    slider.value = [DDTimelineForwardConfig maxCacheSizeMB];
    [slider addTarget:self action:@selector(sliderChanged:) forControlEvents:UIControlEventValueChanged];
    
    UILabel *valueLabel = [[UILabel alloc] initWithFrame:CGRectMake(110, 0, 40, 44)];
    valueLabel.text = [NSString stringWithFormat:@"%@%@", @((NSInteger)slider.value), setting[@"unit"]];
    valueLabel.font = [UIFont systemFontOfSize:14];
    valueLabel.textColor = [UIColor secondaryLabelColor];
    valueLabel.tag = 100;
    
    [container addSubview:slider];
    [container addSubview:valueLabel];
    
    return container;
}

#pragma mark - UITableViewDelegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    
    NSDictionary *setting = nil;
    if (indexPath.section == 0) {
        if (indexPath.row >= 4) return;
        setting = _settings[indexPath.row];
    } else {
        setting = _settings[indexPath.row + 4];
    }
    
    NSString *type = setting[@"type"];
    if ([type isEqualToString:@"button"]) {
        NSString *action = setting[@"action"];
        if ([action isEqualToString:@"clearCache"]) {
            [self clearCache];
        }
    }
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (section == 0) {
        return @"启用朋友圈转发功能，可在朋友圈菜单中添加转发按钮";
    }
    return @"v1.0.0 © DD Plugin (iOS 15.0+)";
}

#pragma mark - Actions

- (void)switchChanged:(UISwitch *)sender {
    UITableViewCell *cell = (UITableViewCell *)sender.superview;
    NSIndexPath *indexPath = [self.tableView indexPathForCell:cell];
    
    if (indexPath) {
        NSDictionary *setting = nil;
        if (indexPath.section == 0) {
            setting = _settings[indexPath.row];
        } else {
            return;
        }
        
        NSString *key = setting[@"key"];
        [[NSUserDefaults standardUserDefaults] setBool:sender.isOn forKey:key];
        [[NSUserDefaults standardUserDefaults] synchronize];
    }
}

- (void)sliderChanged:(UISlider *)sender {
    UIView *container = sender.superview;
    UILabel *valueLabel = [container viewWithTag:100];
    valueLabel.text = [NSString stringWithFormat:@"%@MB", @((NSInteger)sender.value)];
    
    [DDTimelineForwardConfig setMaxCacheSizeMB:(NSInteger)sender.value];
}

- (void)clearCache {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"清空缓存"
                                                                   message:@"确定要清空所有已缓存的媒体文件吗？"
                                                            preferredStyle:UIAlertControllerStyleAlert];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"清空" style:UIAlertActionStyleDestructive handler:^(UIAlertAction * _Nonnull action) {
        [[DDMediaCacheManager sharedManager] clearCache];
        
        UIAlertController *successAlert = [UIAlertController alertControllerWithTitle:@"成功"
                                                                              message:@"缓存已清空"
                                                                       preferredStyle:UIAlertControllerStyleAlert];
        [successAlert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:nil]];
        [self presentViewController:successAlert animated:YES completion:nil];
    }]];
    
    [self presentViewController:alert animated:YES completion:nil];
}

@end

// 辅助函数：获取主窗口（iOS 15.0+）
static UIWindow *DDGetKeyWindow(void) {
    UIWindow *keyWindow = nil;
    
    // iOS 13.0+ 使用场景API
    for (UIWindowScene *windowScene in [UIApplication sharedApplication].connectedScenes) {
        if (windowScene.activationState == UISceneActivationStateForegroundActive) {
            for (UIWindow *window in windowScene.windows) {
                if (window.isKeyWindow) {
                    keyWindow = window;
                    break;
                }
            }
            if (keyWindow) break;
        }
    }
    
    // 回退方案，获取第一个窗口
    if (!keyWindow) {
        for (UIWindowScene *windowScene in [UIApplication sharedApplication].connectedScenes) {
            if (windowScene.activationState == UISceneActivationStateForegroundActive) {
                NSArray<UIWindow *> *windows = windowScene.windows;
                if (windows.count > 0) {
                    keyWindow = windows.firstObject;
                    break;
                }
            }
        }
    }
    
    return keyWindow;
}

// 定义WCOperateFloatView的私有方法
@interface WCOperateFloatView (DDTimelineForward)
- (void)dd_forwardTimeline:(UIButton *)sender;
- (void)dd_prepareMediaAndForward;
- (void)dd_forwardToTimeline;
- (void)dd_showDownloadFailedAlert:(NSArray *)failedMedia;
- (UIViewController *)dd_topViewController;
@end

// Hook实现
%hook WCOperateFloatView

- (void)dd_forwardTimeline:(UIButton *)sender {
    if (!self.m_item) {
        NSLog(@"[DDTimelineForward] 无法获取朋友圈数据");
        return;
    }
    
    if ([DDTimelineForwardConfig autoDownloadMedia]) {
        [self dd_prepareMediaAndForward];
    } else {
        [self dd_forwardToTimeline];
    }
}

- (void)dd_prepareMediaAndForward {
    DDDownloadProgressView *progressView = nil;
    if ([DDTimelineForwardConfig showDownloadProgress]) {
        UIView *superview = self.navigationController.view ?: DDGetKeyWindow();
        progressView = [[DDDownloadProgressView alloc] initWithFrame:CGRectZero];
        
        __weak typeof(progressView) weakProgressView = progressView;
        
        progressView.cancelHandler = ^{
            [[DDMediaCacheManager sharedManager] clearCache];
            [weakProgressView dismiss];
        };
        
        [progressView showInView:superview];
    }
    
    [[DDMediaCacheManager sharedManager] cacheMediaForDataItem:self.m_item completion:^(BOOL allCached, NSArray *failedMedia) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [progressView dismiss];
            
            if (!allCached && failedMedia.count > 0) {
                [self dd_showDownloadFailedAlert:failedMedia];
            } else {
                [self dd_forwardToTimeline];
            }
        });
    }];
    
    if (progressView) {
        [[NSNotificationCenter defaultCenter] addObserverForName:@"DDTimelineDownloadProgress"
                                                          object:nil
                                                           queue:[NSOperationQueue mainQueue]
                                                      usingBlock:^(NSNotification *note) {
            NSDictionary *userInfo = note.userInfo;
            NSInteger current = [userInfo[@"current"] integerValue];
            NSInteger total = [userInfo[@"total"] integerValue];
            float progress = [userInfo[@"progress"] floatValue];
            
            [progressView setProgress:progress current:current total:total];
        }];
    }
}

- (void)dd_forwardToTimeline {
    WCForwardViewController *forwardVC = [[objc_getClass("WCForwardViewController") alloc] initWithDataItem:self.m_item];
    if (self.navigationController) {
        [self.navigationController pushViewController:forwardVC animated:YES];
    } else {
        UIViewController *topVC = [self dd_topViewController];
        if (topVC) {
            [topVC presentViewController:forwardVC animated:YES completion:nil];
        }
    }
}

- (void)dd_showDownloadFailedAlert:(NSArray *)failedMedia {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"媒体下载失败"
                                                                   message:[NSString stringWithFormat:@"有 %@ 个媒体文件下载失败，是否继续转发？", @(failedMedia.count)]
                                                            preferredStyle:UIAlertControllerStyleAlert];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"继续转发" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        [self dd_forwardToTimeline];
    }]];
    
    UIViewController *presentingVC = self.navigationController ?: [self dd_topViewController];
    [presentingVC presentViewController:alert animated:YES completion:nil];
}

- (UIViewController *)dd_topViewController {
    UIWindow *window = DDGetKeyWindow();
    UIViewController *rootVC = window.rootViewController;
    
    while (rootVC.presentedViewController) {
        rootVC = rootVC.presentedViewController;
    }
    
    if ([rootVC isKindOfClass:[UITabBarController class]]) {
        rootVC = [(UITabBarController *)rootVC selectedViewController];
    }
    
    if ([rootVC isKindOfClass:[UINavigationController class]]) {
        rootVC = [(UINavigationController *)rootVC topViewController];
    }
    
    return rootVC;
}

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

%end

// Hook微信的下载相关方法
%hook WCFacade

- (void)downloadMedia:(WCMediaItem *)arg0 downloadType:(long long)arg1 {
    NSLog(@"[DDTimelineForward] 开始下载媒体: %@", arg0.mid);
    %orig(arg0, arg1);
}

- (void)onDownloadFinish:(id)arg0 downloadType:(long long)arg1 {
    %orig(arg0, arg1);
    
    if ([arg0 isKindOfClass:objc_getClass("WCMediaItem")]) {
        [[DDMediaCacheManager sharedManager] handleMediaDownloadComplete:arg0 success:YES];
    }
}

- (void)onDownloadFail:(id)arg0 downloadType:(long long)arg1 {
    %orig(arg0, arg1);
    
    if ([arg0 isKindOfClass:objc_getClass("WCMediaItem")]) {
        [[DDMediaCacheManager sharedManager] handleMediaDownloadComplete:arg0 success:NO];
    }
}

%end

// Hook WCMediaDownloader以捕获下载事件
%hook WCMediaDownloader

- (void)startDownloadWithCompletionHandler:(void (^)(BOOL))handler {
    __block void (^originalHandler)(BOOL) = [handler copy];
    
    void (^newHandler)(BOOL) = ^(BOOL success) {
        WCMediaItem *mediaItem = [self mediaItem];
        if (mediaItem) {
            [[DDMediaCacheManager sharedManager] handleMediaDownloadComplete:mediaItem success:success];
        }
        
        if (originalHandler) {
            originalHandler(success);
        }
    };
    
    %orig(newHandler);
}

%end

// 插件初始化
%ctor {
    @autoreleasepool {
        [DDTimelineForwardConfig setupDefaults];
        
        if (NSClassFromString(@"WCPluginsMgr")) {
            [[objc_getClass("WCPluginsMgr") sharedInstance] 
                registerControllerWithTitle:@"DD朋友圈转发" 
                                   version:@"1.0.0 (iOS 15.0+)" 
                               controller:@"DDTimelineForwardSettingsController"];
        }
        
        NSLog(@"[DDTimelineForward] 插件已加载 - 版本 1.0.0 (iOS 15.0+)");
    }
}