//
//  SPBrandMarkView.h
//  Spotify
//
//  矢量绘制的高精度 Spotify 风格圆形声波徽章。
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface SPBrandMarkView : UIView

@property (nonatomic, strong) UIColor *circleColor;
@property (nonatomic, strong) UIColor *waveColor;

- (instancetype)initWithCircleColor:(UIColor *)circleColor waveColor:(UIColor *)waveColor;

@end

NS_ASSUME_NONNULL_END
