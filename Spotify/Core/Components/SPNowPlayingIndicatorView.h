//
//  SPNowPlayingIndicatorView.h
//  Spotify
//
//  Core Animation 实现的三柱动态音浪指示器，用于标注列表中的正在播放曲目。
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface SPNowPlayingIndicatorView : UIView

@property (nonatomic, assign, getter=isAnimating) BOOL animating;

@end

NS_ASSUME_NONNULL_END
