//
//  SPGradientView.h
//  Spotify
//
//  以 CAGradientLayer 作为 backing layer 的视图，自动跟随 bounds，适合做渐变背景。
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface SPGradientView : UIView

@property (nonatomic, readonly) CAGradientLayer *gradientLayer;
@property (nonatomic, copy, nullable) NSArray<UIColor *> *colors;
@property (nonatomic, copy, nullable) NSArray<NSNumber *> *locations;

/// 默认从上到下
- (void)setStartPoint:(CGPoint)start endPoint:(CGPoint)end;
/// 带隐式动画地切换颜色
- (void)setColors:(NSArray<UIColor *> *)colors animated:(BOOL)animated;

@end

NS_ASSUME_NONNULL_END
