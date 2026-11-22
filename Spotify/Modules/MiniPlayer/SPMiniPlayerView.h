//
//  SPMiniPlayerView.h
//  Spotify
//
//  悬浮在 TabBar 上方的迷你播放条。自己订阅 SPPlayerService，外部只需要处理点击。
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface SPMiniPlayerView : UIView

@property (nonatomic, copy, nullable) void (^tapHandler)(void);
@property (nonatomic, strong, readonly) UIImageView *coverView;

@end

NS_ASSUME_NONNULL_END
