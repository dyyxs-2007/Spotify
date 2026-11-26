//
//  SPNowPlayingTransition.h
//  Spotify
//
//  迷你播放条 ↔ 全屏播放页的自定义 Hero 封面飞跃转场。
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface SPNowPlayingTransition : NSObject <UIViewControllerTransitioningDelegate>

- (instancetype)initWithMiniPlayerView:(UIView *)miniPlayerView
                   sourceCoverProvider:(UIView *(^)(void))sourceCoverProvider;

/// 在交互下拉退出过程中同步更新底层半透明背板透明度
- (void)updateBackdropForDismissProgress:(CGFloat)progress;

@end

NS_ASSUME_NONNULL_END
