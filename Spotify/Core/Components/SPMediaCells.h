//
//  SPMediaCells.h
//  Spotify
//
//  可复用的媒体 Cell：
//  - SPMediaRowCell            表格行（歌曲/专辑/歌单/艺人），可选"更多"按钮
//  - SPMediaRowCollectionCell  集合视图中的列表行（音乐库列表模式）
//  - SPMediaCardCell           方形/圆形封面卡片（首页横滑、音乐库网格模式）
//

#import <UIKit/UIKit.h>
#import "SPMediaItem.h"
#import "SPMediaRowView.h"

NS_ASSUME_NONNULL_BEGIN

@interface SPMediaRowCell : UITableViewCell
@property (nonatomic, strong, readonly) SPMediaRowView *rowView;
@property (nonatomic, strong, readonly) UIButton *moreButton;
@property (nonatomic, assign) BOOL showsMoreButton;
@property (nonatomic, copy, nullable) void (^moreHandler)(void);
+ (NSString *)reuseId;
@end

@interface SPMediaRowCollectionCell : UICollectionViewCell
@property (nonatomic, strong, readonly) SPMediaRowView *rowView;
+ (NSString *)reuseId;
@end

@interface SPMediaCardCell : UICollectionViewCell
@property (nonatomic, strong, readonly) UIImageView *coverView;
- (void)configureWithItem:(id<SPMediaItem>)item;
+ (NSString *)reuseId;
@end

NS_ASSUME_NONNULL_END
