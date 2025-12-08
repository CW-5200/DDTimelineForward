#import <UIKit/UIKit.h>
#import <objc/runtime.h>

// 微信私有类声明
@interface WCMediaItem : NSObject
@property (nonatomic, readonly) NSString *mid;
@property (nonatomic, readonly) int type;
@property (nonatomic, readonly) int totalSize;
@end

@interface WCDataItem : NSObject
@property (nonatomic, retain) NSArray *mediaList;
@property (nonatomic, retain) NSString *username;
@end

@interface WCOperateFloatView : UIView
@property (nonatomic, retain) WCDataItem *m_item;
- (void)showWithItemData:(id)arg1 tipPoint:(struct CGPoint)arg2;
@end

// 进度窗口实现
@interface DDProgressWindow : UIWindow
@property (nonatomic, retain) NSString *username;
@property (nonatomic, assign) float currentProgress;
@end

@implementation DDProgressWindow {
    UIProgressView *_progressBar;
    UILabel *_statusLabel;
}

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.windowLevel = UIWindowLevelAlert + 1;
        self.backgroundColor = [UIColor clearColor];
        
        _progressBar = [[UIProgressView alloc] initWithProgressViewStyle:UIProgressViewStyleDefault];
        _progressBar.frame = CGRectMake(20, 100, frame.size.width - 40, 20);
        [self addSubview:_progressBar];
        
        _statusLabel = [[UILabel alloc] initWithFrame:CGRectMake(20, 130, frame.size.width - 40, 20)];
        _statusLabel.textColor = [UIColor whiteColor];
        _statusLabel.textAlignment = NSTextAlignmentCenter;
        [self addSubview:_statusLabel];
    }
    return self;
}

- (void)show {
    self.hidden = NO;
    [self makeKeyAndVisible];
}

- (void)hide {
    self.hidden = YES;
    [self resignKeyWindow];
}

- (void)updateProgress:(float)progress {
    _currentProgress = progress;
    dispatch_async(dispatch_get_main_queue(), ^{
        _progressBar.progress = progress;
        _statusLabel.text = [NSString stringWithFormat:@"正在下载 %.1f%%", progress * 100];
    });
}

@end

// 插件主逻辑
%hook WCOperateFloatView

- (void)showWithItemData:(id)arg1 tipPoint:(struct CGPoint)arg2 {
    %orig;
    
    // 检查转发权限
    if ( return;
    
    // 获取当前数据项
    WCDataItem *dataItem = self.m_item;
    if (!dataItem || !dataItem.mediaList.count) return;
    
    // 创建进度窗口
    DDProgressWindow *progressWindow = [[DDProgressWindow alloc] initWithFrame:CGRectMake(0, 0, 280, 160)];
    progressWindow.username = dataItem.username;
    [progressWindow show];
    
    // 获取第一个媒体项
    WCMediaItem *mediaItem = dataItem.mediaList.firstObject;
    if (!mediaItem) {
        [progressWindow hide];
        return;
    }
    
    // 设置下载进度回调
    [WCDownloadMgr sharedInstance].downloadProgressHandler = ^(WCMediaItem *item, float progress) {
        if (item.mid == mediaItem.mid) {
            [progressWindow updateProgress:progress];
            if (progress >= 1.0) {
                [progressWindow hide];
                [self performForward:mediaItem];
            }
        }
    };
    
    // 开始下载
    [[WCDownloadMgr sharedInstance] startDownloadMedia:mediaItem downloadType:WCMediaDownloadTypeThumb];
}

%new
- (void)performForward:(WCMediaItem *)mediaItem {
    // 构造转发参数
    WCForwardViewController *forwardVC = [[objc_getClass("WCForwardViewController") alloc] initWithDataItem:self.m_item];
    objc_setAssociatedObject(forwardVC, @selector(navigationController), self.navigationController, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    
    // 执行跳转
    UINavigationController *nav = objc_getAssociatedObject(self, @selector(navigationController));
    if (nav) {
        [nav pushViewController:forwardVC animated:YES];
    }
}

%end

// 配置管理
@interface DDTimelineForwardConfig : NSObject
@property (class, assign, getter=isTimelineForwardEnabled) BOOL timelineForwardEnabled;
+ (void)setupDefaults;
@end

@implementation DDTimelineForwardConfig

static NSString *const kEnableKey = @"timeline_forward_enabled";

+ (BOOL)isTimelineForwardEnabled {
    return [[NSUserDefaults standardUserDefaults] boolForKey:kEnableKey];
}

+ (void)setTimelineForwardEnabled:(BOOL)enabled {
    [[NSUserDefaults standardUserDefaults] setBool:enabled forKey:kEnableKey];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

+ (void)setupDefaults {
    if ( {
        [self setTimelineForwardEnabled:YES];
    }
}

@end

// 初始化插件
%ctor {
    // 注册设置界面
    if (NSClassFromString(@"WCPluginsMgr")) {
        [[WCPluginsMgr sharedInstance] registerControllerWithTitle:@"朋友圈转发"
                                                         version:@"1.0.1"
                                                     controller:@"DDTimelineForwardSettingsController"];
    }
    
    // 初始化配置
    [DDTimelineForwardConfig setupDefaults];
    
    NSLog(@"[TimelineForward] Plugin initialized (v1.0.1)");
}

// 设置界面（示例）
@interface DDTimelineForwardSettingsController : UIViewController
@property (nonatomic, retain) UISwitch *enableSwitch;
@end

@implementation DDTimelineForwardSettingsController

- (void)viewDidLoad {
    [super viewDidLoad];
    
    self.view.backgroundColor = [UIColor whiteColor];
    self.title = @"朋友圈转发设置";
    
    UISwitch *switchCtrl = [[UISwitch alloc] initWithFrame:CGRectMake(20, 100, 0, 0)];
    [switchCtrl addTarget:self action:@selector(switchChanged:) forControlEvents:UIControlEventValueChanged];
    switchCtrl.on = [DDTimelineForwardConfig isTimelineForwardEnabled];
    self.enableSwitch = switchCtrl;
    [self.view addSubview:switchCtrl];
    
    UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(backgroundTap:)];
    [self.view addGestureRecognizer:tap];
}

- (void)switchChanged:(UISwitch *)sender {
    [DDTimelineForwardConfig setTimelineForwardEnabled:sender.isOn];
}

- (void)backgroundTap:(UITapGestureRecognizer *)sender {
    [self.view endEditing:YES];
}

@end
