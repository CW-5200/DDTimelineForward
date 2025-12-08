#import <UIKit/UIKit.h>
#import <objc/runtime.h>

// 微信相关类声明
@interface WCDataItem : NSObject
@property(retain, nonatomic) NSString *username;
@property(retain, nonatomic) NSArray *mediaList;
@end

@interface WCMediaItem : NSObject
@property(nonatomic) int type; // 1=图片, 2=视频
@property(retain, nonatomic) NSString *dataUrl;
@property(retain, nonatomic) NSString *thumbUrl;
@end

@interface WCMediaDownloader : NSObject
- (id)initWithDataItem:(WCDataItem *)dataItem mediaItem:(WCMediaItem *)mediaItem;
- (void)startDownloadWithCompletionHandler:(void (^)(NSError *error))completionHandler;
- (BOOL)hasDownloaded;
@end

@interface WCOperateFloatView : UIView
@property(readonly, nonatomic) WCDataItem *m_item;
@property(nonatomic) __weak UINavigationController *navigationController;
@end

@interface WCForwardViewController : UIViewController
- (id)initWithDataItem:(WCDataItem *)arg1;
@end

// 简化的媒体下载管理器
@interface DDMediaDownloadManager : NSObject
+ (instancetype)sharedManager;
- (void)downloadMediaForDataItem:(WCDataItem *)dataItem completion:(void (^)(BOOL success))completion;
@end

@implementation DDMediaDownloadManager

+ (instancetype)sharedManager {
    static DDMediaDownloadManager *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[self alloc] init];
    });
    return instance;
}

- (void)downloadMediaForDataItem:(WCDataItem *)dataItem completion:(void (^)(BOOL success))completion {
    if (!dataItem.mediaList || dataItem.mediaList.count == 0) {
        // 没有媒体文件，直接完成
        completion(YES);
        return;
    }
    
    __block NSInteger downloadCount = 0;
    __block NSInteger totalCount = dataItem.mediaList.count;
    __block BOOL hasError = NO;
    
    for (WCMediaItem *mediaItem in dataItem.mediaList) {
        WCMediaDownloader *downloader = [[objc_getClass("WCMediaDownloader") alloc] 
                                        initWithDataItem:dataItem mediaItem:mediaItem];
        
        if ([downloader hasDownloaded]) {
            downloadCount++;
            if (downloadCount == totalCount) {
                completion(YES);
            }
            continue;
        }
        
        [downloader startDownloadWithCompletionHandler:^(NSError *error) {
            downloadCount++;
            
            if (error) {
                hasError = YES;
                NSLog(@"媒体下载失败: %@", error);
            }
            
            if (downloadCount == totalCount) {
                completion(!hasError);
            }
        }];
    }
}

@end

// Hook实现 - 保持转发按钮不变
%hook WCOperateFloatView

- (void)showWithItemData:(id)arg1 tipPoint:(struct CGPoint)arg2 {
    %orig(arg1, arg2);
    
    // 不修改按钮布局，只添加转发功能
    UIButton *likeBtn = self.m_likeBtn;
    
    if (likeBtn) {
        // 创建转发按钮，保持与原有按钮一致的样式
        UIButton *forwardButton = [UIButton buttonWithType:UIButtonTypeCustom];
        forwardButton.frame = likeBtn.frame;
        
        // 使用系统转发图标
        UIImage *forwardIcon = [UIImage systemImageNamed:@"arrowshape.turn.up.right.fill"];
        if (forwardIcon) {
            forwardIcon = [forwardIcon imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
            [forwardButton setImage:forwardIcon forState:UIControlStateNormal];
            forwardButton.tintColor = likeBtn.currentTitleColor;
        }
        
        [forwardButton addTarget:self action:@selector(dd_forwardTimeline:) forControlEvents:UIControlEventTouchUpInside];
        
        // 将转发按钮添加到容器
        [likeBtn.superview addSubview:forwardButton];
    }
}

%new
- (void)dd_forwardTimeline:(UIButton *)sender {
    WCDataItem *dataItem = self.m_item;
    
    // 创建简单的加载提示
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:nil 
                                                                   message:@"准备转发内容..." 
                                                            preferredStyle:UIAlertControllerStyleAlert];
    
    UIActivityIndicatorView *indicator = [[UIActivityIndicatorView alloc] 
                                         initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    [indicator startAnimating];
    
    [alert.view addSubview:indicator];
    
    // 居中显示指示器
    indicator.translatesAutoresizingMaskIntoConstraints = NO;
    [indicator.centerXAnchor constraintEqualToAnchor:alert.view.centerXAnchor].active = YES;
    [indicator.centerYAnchor constraintEqualToAnchor:alert.view.centerYAnchor constant:10].active = YES;
    
    UIViewController *topVC = [self _topViewController];
    [topVC presentViewController:alert animated:YES completion:nil];
    
    // 使用微信原生下载器下载媒体文件
    [[DDMediaDownloadManager sharedManager] downloadMediaForDataItem:dataItem completion:^(BOOL success) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [alert dismissViewControllerAnimated:YES completion:^{
                if (success) {
                    // 媒体下载完成，进入转发界面
                    Class WCForwardViewControllerClass = objc_getClass("WCForwardViewController");
                    if (WCForwardViewControllerClass) {
                        WCForwardViewController *forwardVC = [[WCForwardViewControllerClass alloc] initWithDataItem:dataItem];
                        if (self.navigationController) {
                            [self.navigationController pushViewController:forwardVC animated:YES];
                        }
                    }
                } else {
                    // 下载失败提示
                    UIAlertController *errorAlert = [UIAlertController alertControllerWithTitle:@"转发失败" 
                                                                                       message:@"媒体文件下载失败，请重试" 
                                                                                preferredStyle:UIAlertControllerStyleAlert];
                    [errorAlert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:nil]];
                    [topVC presentViewController:errorAlert animated:YES completion:nil];
                }
            }];
        });
    }];
}

%new
- (UIViewController *)_topViewController {
    UIWindow *window = [[UIApplication sharedApplication] keyWindow];
    UIViewController *topViewController = window.rootViewController;
    
    while (topViewController.presentedViewController) {
        topViewController = topViewController.presentedViewController;
    }
    
    return topViewController;
}

%end

// 插件初始化
%ctor {
    @autoreleasepool {
        NSLog(@"朋友圈媒体转发修复插件已加载 - 自动修复预览限制");
    }
}
