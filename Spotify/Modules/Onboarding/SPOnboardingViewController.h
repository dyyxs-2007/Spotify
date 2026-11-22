//
//  SPOnboardingViewController.h
//  Spotify
//
//  首次启动全屏横滑大图引导页：4 张氛围大图、视差滚动、伸缩小绿药丸指示器；
//  滑至末页或点击按钮可直接平滑过渡到登录/注册欢迎页。
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface SPOnboardingViewController : UIViewController

/// YES：从设置页"重新查看新手引导"进入，完成后 pop 返回设置页；NO：首次启动流程，push 进入登录注册欢迎页
@property (nonatomic, assign) BOOL replayMode;
@property (nonatomic, assign, readonly) NSInteger slideCount;
@property (nonatomic, assign, readonly) NSInteger currentPage;

@end

NS_ASSUME_NONNULL_END
