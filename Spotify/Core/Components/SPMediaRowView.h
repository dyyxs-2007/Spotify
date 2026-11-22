//
//  SPMediaRowView.h
//  Spotify
//
//  列表行内容视图：封面 + 标题（可选律动音浪）+ 副标题。被表格 cell、集合 cell 复用。
//

#import <UIKit/UIKit.h>
#import "SPMediaItem.h"

NS_ASSUME_NONNULL_BEGIN

@interface SPMediaRowView : UIView

@property (nonatomic, strong, readonly) UIImageView *coverView;
@property (nonatomic, strong, readonly) UILabel *titleLabel;
@property (nonatomic, strong, readonly) UILabel *subtitleLabel;

/// 封面边长，传 0 隐藏封面（专辑详情页里的歌曲行）
@property (nonatomic, assign) CGFloat coverSize;
/// 是否为当前播放项（标题变绿并显示音浪）
@property (nonatomic, assign, getter=isActive) BOOL active;

- (void)setActive:(BOOL)active isPlaying:(BOOL)isPlaying;
- (void)configureWithItem:(id<SPMediaItem>)item;

@end

NS_ASSUME_NONNULL_END
