#import <UIKit/UIKit.h>
#import <objc/runtime.h>

// 微信相关类声明
@interface WCDataItem : NSObject
@property(retain, nonatomic) NSString *username;
@property(retain, nonatomic) id mediaList; // MediaList类型
@end

@interface MediaList : NSObject
@property(retain, nonatomic) NSMutableArray *media; // WCMediaItem数组
@end

@interface WCMediaItem : NSObject
@property(retain, nonatomic) NSString *mid;
@property(nonatomic) int type;
- (BOOL)hasData;
- (BOOL)hasSight;
- (BOOL)hasAttachVideo;
@end

@interface WCMediaDownloader : NSObject
@property(readonly, nonatomic) WCDataItem *dataItem;
@property(readonly, nonatomic) WCMediaItem *mediaItem;
@property(copy, nonatomic) void (^completionHandler)(NSError *error);
- (id)initWithDataItem:(WCDataItem *)dataItem mediaItem:(WCMediaItem *)mediaItem;
- (void)startDownloadWithCompletionHandler:(void (^)(NSError *error))handler;
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

// 插件管理器接口
@interface WCPluginsMgr : NSObject
+ (instancetype)sharedInstance;
- (void)registerControllerWithTitle:(NSString *)title version:(NSString *)version controller:(NSString *)controller;
@end

// 下载管理器
@interface DDMediaDownloadManager : NSObject
+ (instancetype)sharedManager;
- (void)downloadMediaForDataItem:(WCDataItem *)dataItem
              inViewController:(UIViewController *)viewController
                    completion:(void (^)(BOOL success))completion;
@end

@implementation DDMediaDownloadManager {
    NSMutableDictionary *_downloaders;
    NSInteger _pendingDownloads;
    NSInteger _completedDownloads;
    void (^_completion)(BOOL success);
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
    @try {
        if (mediaItem.type == 2 || mediaItem.type == 6) {
            return [mediaItem hasSight] || [mediaItem hasAttachVideo];
        } else {
            return [mediaItem hasData];
        }
    } @catch (NSException *exception) {
        return NO;
    }
}

- (void)downloadMediaForDataItem:(WCDataItem *)dataItem
              inViewController:(UIViewController *)viewController
                    completion:(void (^)(BOOL success))completion {
    
    // 获取媒体列表
    MediaList *mediaList = nil;
    @try {
        mediaList = [dataItem valueForKey:@"mediaList"];
    } @catch (NSException *exception) {
        NSLog(@"DDTimeline: 无法获取mediaList");
        if (completion) completion(NO);
        return;
    }
    
    NSArray *mediaItems = mediaList.media;
    if (!mediaItems || mediaItems.count == 0) {
        if (completion) completion(YES);
        return;
    }
    
    // 过滤需要下载的媒体
    NSMutableArray *needDownloadItems = [NSMutableArray array];
    for (WCMediaItem *mediaItem in mediaItems) {
        if (![self isMediaItemDownloaded:mediaItem]) {
            [needDownloadItems addObject:mediaItem];
        }
    }
    
    if (needDownloadItems.count == 0) {
        if (completion) completion(YES);
        return;
    }
    
    // 显示加载视图
    [self showLoadingInView:viewController.view];
    
    // 初始化状态
    _pendingDownloads = needDownloadItems.count;
    _completedDownloads = 0;
    _completion = completion;
    
    // 开始下载每个媒体
    for (WCMediaItem *mediaItem in needDownloadItems) {
        [self downloadSingleMedia:mediaItem forDataItem:dataItem];
    }
}

- (void)downloadSingleMedia:(WCMediaItem *)mediaItem forDataItem:(WCDataItem *)dataItem {
    @try {
        WCMediaDownloader *downloader = [[objc_getClass("WCMediaDownloader") alloc] initWithDataItem:dataItem mediaItem:mediaItem];
        
        NSString *key = [NSString stringWithFormat:@"%@_%@", dataItem.username, mediaItem.mid ?: @""];
        _downloaders[key] = downloader;
        
        [downloader startDownloadWithCompletionHandler:^(NSError *error) {
            dispatch_async(dispatch_get_main_queue(), ^{
                NSString *key = [NSString stringWithFormat:@"%@_%@", dataItem.username, mediaItem.mid ?: @""];
                [self->_downloaders removeObjectForKey:key];
                
                self->_completedDownloads++;
                
                if (self->_completedDownloads >= self->_pendingDownloads) {
                    [self downloadCompleted];
                }
            });
        }];
    } @catch (NSException *exception) {
        _completedDownloads++;
        if (_completedDownloads >= _pendingDownloads) {
            [self downloadCompleted];
        }
    }
}

- (void)downloadCompleted {
    [self hideLoading];
    if (_completion) {
        _completion(YES);
    }
    [_downloaders removeAllObjects];
}

@end

// 设置界面控制器（简化版）
@interface DDTimelineForwardSettingsController : UIViewController
@end

@implementation DDTimelineForwardSettingsController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"朋友圈转发设置";
    self.view.backgroundColor = [UIColor systemBackgroundColor];
    
    if (@available(iOS 15.0, *)) {
        UISheetPresentationController *sheet = self.sheetPresentationController;
        if (sheet) {
            sheet.detents = @[UISheetPresentationControllerDetent.mediumDetent];
            sheet.prefersGrabberVisible = YES;
        }
    }
    
    UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(20, 100, 200, 30)];
    label.text = @"已启用朋友圈转发功能";
    label.textAlignment = NSTextAlignmentCenter;
    label.center = CGPointMake(self.view.bounds.size.width/2, self.view.bounds.size.height/2);
    [self.view addSubview:label];
}

@end

// Hook实现
%hook WCOperateFloatView

- (void)showWithItemData:(id)arg1 tipPoint:(struct CGPoint)arg2 {
    %orig(arg1, arg2);
    
    // 直接添加转发按钮，不提供开关控制
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

%new
- (void)dd_forwardTimeline:(UIButton *)sender {
    sender.enabled = NO;
    
    UIViewController *currentVC = nil;
    if (self.navigationController) {
        currentVC = self.navigationController;
    } else {
        UIResponder *responder = self;
        while (![responder isKindOfClass:[UIViewController class]]) {
            responder = responder.nextResponder;
        }
        currentVC = (UIViewController *)responder;
    }
    
    if (!currentVC) {
        sender.enabled = YES;
        return;
    }
    
    // 先下载媒体，再跳转
    [[DDMediaDownloadManager sharedManager] downloadMediaForDataItem:self.m_item
                                                  inViewController:currentVC
                                                        completion:^(BOOL success) {
        dispatch_async(dispatch_get_main_queue(), ^{
            sender.enabled = YES;
            
            // 无论下载成功与否都跳转，让转发界面处理
            WCForwardViewController *forwardVC = [[objc_getClass("WCForwardViewController") alloc] initWithDataItem:self.m_item];
            if (self.navigationController) {
                [self.navigationController pushViewController:forwardVC animated:YES];
            } else if (currentVC.navigationController) {
                [currentVC.navigationController pushViewController:forwardVC animated:YES];
            } else {
                [currentVC presentViewController:forwardVC animated:YES completion:nil];
            }
        });
    }];
}

%end

// 插件初始化
%ctor {
    @autoreleasepool {
        if (NSClassFromString(@"WCPluginsMgr")) {
            [[objc_getClass("WCPluginsMgr") sharedInstance] 
                registerControllerWithTitle:@"朋友圈转发" 
                                   version:@"1.0" 
                               controller:@"DDTimelineForwardSettingsController"];
        }
        
        NSLog(@"朋友圈转发插件已加载");
    }
}