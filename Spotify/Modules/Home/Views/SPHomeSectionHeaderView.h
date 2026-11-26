//
//  SPHomeSectionHeaderView.h
//  Spotify
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface SPHomeSectionHeaderView : UICollectionReusableView

+ (NSString *)reuseId;
@property (nonatomic, strong, readonly) UILabel *titleLabel;
/// 左右内边距（首页 CompositionalLayout 自带 section.contentInsets 默认 0；搜索页 FlowLayout 设为 SPMarginHorizontal）
@property (nonatomic, assign) CGFloat horizontalInset;

@end

NS_ASSUME_NONNULL_END
