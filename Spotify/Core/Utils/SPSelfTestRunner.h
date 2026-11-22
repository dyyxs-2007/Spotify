//
//  SPSelfTestRunner.h
//  Spotify
//
//  内置自动化自检套件：验证 LRU 缓存算法、播放队列、上下首预加载、切上一首秒播、
//  L3 数据缓存与 UI 页面流转无异常，可由启动参数 -SPSelfTest 或设置菜单触发。
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@class SPRootViewController;

@interface SPSelfTestRunner : NSObject

+ (void)runWithRootViewController:(SPRootViewController *)rootVC
                       completion:(nullable void (^)(BOOL allPassed, NSString *report))completion;

@end

NS_ASSUME_NONNULL_END
