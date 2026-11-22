//
//  SPSkeletonView.h
//  Spotify
//
//  Shimmer 微光骨架屏组件及首页/详情页预设布局。
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface SPSkeletonBlockView : UIView
- (instancetype)initWithCornerRadius:(CGFloat)cornerRadius;
@end

@interface SPSkeletonView : UIView

+ (instancetype)homeSkeletonView;
+ (instancetype)detailSkeletonView;

- (void)dismissAnimated:(BOOL)animated;

@end

NS_ASSUME_NONNULL_END
