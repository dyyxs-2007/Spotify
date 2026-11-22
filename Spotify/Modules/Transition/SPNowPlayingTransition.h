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

@end

NS_ASSUME_NONNULL_END
