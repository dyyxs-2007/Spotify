//
//  SPRootViewController.h
//  Spotify
//
//  根容器：左侧滑入叠加抽屉 + 静止主 TabBar 容器 + 跨 Tab 常驻迷你播放条。
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface SPRootViewController : UIViewController

@property (nonatomic, strong, readonly) UIView *contentContainer;
@property (nonatomic, strong, readonly) UITabBarController *tabController;
@property (nonatomic, assign, readonly, getter=isDrawerOpen) BOOL drawerOpen;

- (void)presentNowPlaying;
- (void)presentAuthFlow;
- (void)openSideDrawer;
- (void)closeSideDrawerAnimated:(BOOL)animated completion:(nullable void (^)(void))completion;
- (void)pushOnCurrentTab:(UIViewController *)vc;

@end

NS_ASSUME_NONNULL_END
